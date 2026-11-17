extends RefCounted
## Transporte WebSocket do lado do servidor (SPEC 9.2 e 9.3). No Wi-Fi roda no celular
## do anfitrião; à distância, sem tela, no Render. Segue o mesmo contrato do transporte
## local:
##   poll() -> [{type: "connect" | "message" | "disconnect", peer, data}]
##   send(peer, mensagem), send_state(peer, mensagem, pacote), drop(peer)
##
## O aperto de mão e os quadros são feitos aqui sobre TCP, e não pelo WebSocketPeer do
## Godot, por dois motivos: a mesma porta também atende HTTP comum (o Render só expõe
## uma porta; /saude e a lotação vêm por ela), e um pedido que não é de jogo (o
## detector de portas do Render, robôs da internet) recebe uma resposta HTTP em vez de
## virar erro.
##
## Batimento: o app manda "ping" a cada 2 s. Uma conexão que fica SILENCE_MS sem mandar
## nada é dada como caída. Se o próprio servidor ficou parado (o Android suspendeu o
## app), a contagem recomeça: ninguém cai por culpa do anfitrião.

const Codec := preload("res://net/codec.gd")
const Clock := preload("res://server/clock.gd")
const Wire := preload("res://server/wire.gd")
const Protocol := preload("res://server/protocol.gd")

const PORT: int = 47820
const SILENCE_MS: int = 10000
const HANDSHAKE_MS: int = 5000
const PAUSE_GAP_MS: int = 3000
const MAX_PEERS: int = 32
const MAX_MESSAGE: int = 65536
const MAX_REQUEST: int = 8192
## Bytes esperando para sair. Passou disso, a conexão não está dando conta e cai.
const MAX_OUTBOX: int = 1 << 20
const WS_GUID: String = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
const STRAY_KEEP: int = 10
## O "pong" não sai se a conexão recebeu outra coisa há menos que isso: qualquer
## mensagem já mostra ao app que o servidor está vivo, e cada envio custa uns 80 bytes
## de cabeçalhos na banda do mês (SPEC 10).
const PONG_SKIP_MS: int = 1500
## Ao derrubar uma conexão, o quadro de fechamento espera isso depois da última
## mensagem sair: o cliente do Godot descarta as mensagens que chegam junto com o
## fechamento, e a expulsão ou o placar final se perderiam.
const CLOSE_DELAY_MS: int = 300


class Peer:
	extends RefCounted

	var id: int = 0
	var tcp: StreamPeerTCP = null
	var ip: String = ""
	var inbox: PackedByteArray = PackedByteArray()
	var outbox: Array[PackedByteArray] = []
	var out_offset: int = 0
	var out_bytes: int = 0
	var ws: bool = false        ## o aperto de mão do WebSocket terminou
	var open: bool = false      ## o servidor já soube da conexão e ainda não da queda
	var closing: bool = false   ## só falta terminar de enviar e fechar
	var close_heard: bool = false   ## o app respondeu ao nosso fechamento
	var close_sent: bool = false    ## o quadro de fechamento já saiu
	var close_at: int = 0           ## quando o quadro de fechamento pode sair
	var since: int = 0
	var last_ms: int = 0
	var last_out_ms: int = -1000000
	var room_json: String = ""  ## o último `room` que esta conexão recebeu (protocolo enxuto)


var port: int = 0
var max_peers: int = MAX_PEERS
## Atrás do repassador do Render o IP de quem conecta vem no X-Forwarded-For.
var trust_forwarded: bool = false
## Responde os pedidos HTTP que não são de jogo:
## func(pedido: {method, path, headers}) -> {status, type, body}. Sem ele, 404.
var http_handler: Callable = Callable()
## Primeira linha dos últimos pedidos que não eram de jogo (para o diagnóstico).
var stray: Array[String] = []
## Totais desde que abriu, para as medições e a lotação.
var bytes_out: int = 0
var bytes_in: int = 0

var _tcp: TCPServer = TCPServer.new()
var _clock: Clock = null
var _peers: Dictionary = {}     # id -> Peer
var _events: Array[Dictionary] = []
var _next_peer: int = 1
var _last_poll: int = -1


func _init(clock: Clock = null) -> void:
	_clock = clock if clock != null else Clock.new()


## Abre a porta. bind_address "*" escuta em todas as redes do aparelho.
func listen(listen_port: int = PORT, bind_address: String = "*") -> Error:
	stop()
	var error: Error = _tcp.listen(listen_port, bind_address)
	if error == OK:
		port = _tcp.get_local_port()
	return error


func is_listening() -> bool:
	return _tcp.is_listening()


func stop() -> void:
	for peer: Peer in _peers.values():
		if peer.ws and not peer.closing:
			_queue(peer, _frame(8, _close_payload(1001)))
			_flush(peer)
		peer.tcp.disconnect_from_host()
	_peers.clear()
	_tcp.stop()


func poll() -> Array[Dictionary]:
	var now: int = _clock.now_ms()
	if _last_poll >= 0 and now - _last_poll > PAUSE_GAP_MS:
		for peer: Peer in _peers.values():
			peer.last_ms = now
			peer.since = now
	_last_poll = now
	while _tcp.is_listening() and _tcp.is_connection_available():
		var connection: StreamPeerTCP = _tcp.take_connection()
		if peer_count() >= max_peers:
			connection.disconnect_from_host()
			continue
		connection.set_no_delay(true)   # mensagens pequenas saem na hora
		var peer: Peer = Peer.new()
		peer.id = _next_peer
		_next_peer += 1
		peer.tcp = connection
		peer.ip = connection.get_connected_host()
		peer.since = now
		peer.last_ms = now
		_peers[peer.id] = peer
	for peer: Peer in _peers.values():
		_poll_peer(peer, now)
	var events: Array[Dictionary] = _events
	_events = []
	return events


func send(peer_id: int, message: Dictionary) -> void:
	var peer: Peer = _peers.get(peer_id)
	if peer == null or not peer.open:
		return
	if message.get("t") == Protocol.PONG and _clock.now_ms() - peer.last_out_ms < PONG_SKIP_MS:
		return
	if message.get("t") == Protocol.STATE:
		peer.room_json = ""   # o app trocou de room por fora do pacote: o próximo leva room
	var data: Variant = Wire.encode(message)
	if data is String:
		_queue(peer, _frame(1, (data as String).to_utf8_buffer()))
	else:
		_queue(peer, _frame(2, data))


## O `state` pelo protocolo enxuto: a parte pública já compactada e o `you` da pessoa.
func send_state(peer_id: int, message: Dictionary, pack: Wire.StatePack) -> void:
	var peer: Peer = _peers.get(peer_id)
	if peer == null or not peer.open:
		return
	var room_json: String = pack.room_json()
	var with_room: bool = peer.room_json != room_json
	peer.room_json = room_json
	_queue(peer, _frame(2, pack.frame(message.get("you", {}), with_room)))


## O servidor encerra a conexão (o que já foi enviado sai antes).
func drop(peer_id: int) -> void:
	var peer: Peer = _peers.get(peer_id)
	if peer == null or peer.closing:
		return
	_report_gone(peer)
	peer.closing = true
	peer.since = _clock.now_ms()
	peer.close_at = peer.since + CLOSE_DELAY_MS


## IP de onde a conexão veio ("" se não existe).
func peer_ip(peer_id: int) -> String:
	var peer: Peer = _peers.get(peer_id)
	return peer.ip if peer != null else ""


## Quantas conexões estão abertas ou se abrindo (para os testes e para o limite).
func peer_count() -> int:
	var count: int = 0
	for peer: Peer in _peers.values():
		if not peer.closing:
			count += 1
	return count


func _poll_peer(peer: Peer, now: int) -> void:
	peer.tcp.poll()
	if peer.tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED or not _flush(peer):
		_forget(peer)
		return
	var available: int = peer.tcp.get_available_bytes()
	if available > 0:
		var got: Array = peer.tcp.get_partial_data(available)
		if got[0] != OK:
			_forget(peer)
			return
		peer.inbox.append_array(got[1])
		bytes_in += (got[1] as PackedByteArray).size()
	if peer.closing:
		_finish_closing(peer, now)
		return
	if not peer.ws:
		if not _read_request(peer, now):
			return
	if not _read_frames(peer, now):
		_forget(peer)
		return
	if peer.open and now - peer.last_ms > SILENCE_MS:
		drop(peer.id)


## Fechando: o que chega é descartado (dado não lido faria o sistema cortar a conexão
## sem entregar o que já foi enviado). Fecha depois de tudo sair e, no WebSocket,
## depois de o app responder ao fechamento.
func _finish_closing(peer: Peer, now: int) -> void:
	if peer.ws and not peer.close_heard:
		_skim_close(peer)
	else:
		peer.inbox.clear()
	if peer.ws and not peer.close_sent and not peer.close_heard:
		if peer.out_bytes > 0:
			peer.close_at = now + CLOSE_DELAY_MS
		elif now >= peer.close_at:
			peer.close_sent = true
			_queue(peer, _frame(8, _close_payload(1000)))
	if (peer.out_bytes == 0 and (peer.close_heard or not peer.ws)) or now - peer.since > HANDSHAKE_MS:
		_forget(peer)


## Procura a resposta de fechamento do app entre os quadros que chegaram.
func _skim_close(peer: Peer) -> void:
	while peer.inbox.size() >= 2:
		var b: PackedByteArray = peer.inbox
		var length: int = b[1] & 0x7F
		var pos: int = 2 + (4 if (b[1] & 0x80) != 0 else 0)
		if length == 126:
			if b.size() < 4:
				return
			length = (b[2] << 8) | b[3]
			pos += 2
		elif length == 127:
			peer.close_heard = true   # não vem do nosso app; não vale esperar
			return
		if b.size() < pos + length:
			return
		if (b[0] & 0x0F) == 8:
			peer.close_heard = true
		peer.inbox = b.slice(pos + length)


## Espera o pedido HTTP inteiro. Verdadeiro: virou WebSocket e pode ler quadros.
func _read_request(peer: Peer, now: int) -> bool:
	var end: int = _header_end(peer.inbox)
	if end < 0:
		if peer.inbox.size() > MAX_REQUEST or now - peer.since > HANDSHAKE_MS:
			_forget(peer)
		return false
	var head: String = peer.inbox.slice(0, end).get_string_from_utf8()
	peer.inbox = peer.inbox.slice(end + 4)
	var lines: PackedStringArray = head.split("\r\n")
	var first: PackedStringArray = lines[0].split(" ")
	var headers: Dictionary = {}
	for i in range(1, lines.size()):
		var colon: int = lines[i].find(":")
		if colon > 0:
			headers[lines[i].left(colon).strip_edges().to_lower()] = lines[i].substr(colon + 1).strip_edges()
	var method: String = first[0] if first.size() == 3 else ""
	var path: String = first[1] if first.size() == 3 else ""
	if trust_forwarded and headers.has("x-forwarded-for"):
		# A última entrada é a que o repassador acrescentou; as outras vêm de quem pediu.
		var chain: PackedStringArray = str(headers["x-forwarded-for"]).split(",")
		peer.ip = chain[chain.size() - 1].strip_edges()
	if (method == "GET" and str(headers.get("upgrade", "")).to_lower() == "websocket"
			and headers.has("sec-websocket-key")):
		var accept: String = Marshalls.raw_to_base64(
			(str(headers["sec-websocket-key"]) + WS_GUID).sha1_buffer())
		_queue(peer, ("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n"
			+ "Connection: Upgrade\r\nSec-WebSocket-Accept: %s\r\n\r\n" % accept).to_utf8_buffer())
		peer.ws = true
		peer.open = true
		peer.last_ms = now
		_events.append({"type": "connect", "peer": peer.id, "data": {}})
		return true
	if path != "/saude":
		_note_stray(method, path)
	var answer: Dictionary = {"status": "404 Not Found", "type": "text/plain; charset=utf-8",
		"body": "não encontrado"}
	if method == "":
		answer = {"status": "400 Bad Request", "type": "text/plain; charset=utf-8", "body": ""}
	elif http_handler.is_valid():
		answer = http_handler.call({"method": method, "path": path, "headers": headers})
	_reply(peer, answer, method == "HEAD")
	peer.closing = true
	peer.since = now
	return false


## Posição do primeiro \r\n\r\n nos bytes, ou -1.
static func _header_end(data: PackedByteArray) -> int:
	var at: int = data.find(13)
	while at >= 0 and at + 3 < data.size():
		if data[at + 1] == 10 and data[at + 2] == 13 and data[at + 3] == 10:
			return at
		at = data.find(13, at + 1)
	return -1


func _reply(peer: Peer, answer: Dictionary, head_only: bool) -> void:
	var body: PackedByteArray = str(answer.get("body", "")).to_utf8_buffer()
	var head: String = ("HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\n"
		+ "Cache-Control: no-store\r\nConnection: close\r\n\r\n") % [
		answer.get("status", "200 OK"), answer.get("type", "text/plain"), body.size()]
	_queue(peer, head.to_utf8_buffer() if head_only else head.to_utf8_buffer() + body)


## Só o método e o caminho, sem a consulta: nada de quem pediu.
func _note_stray(method: String, path: String) -> void:
	stray.append(("%s %s" % [method, path.split("?")[0]]).left(80) if method != "" else "(pedido inválido)")
	if stray.size() > STRAY_KEEP:
		stray.pop_front()


## Lê os quadros que já chegaram inteiros. Falso: erro de protocolo, fechar.
func _read_frames(peer: Peer, now: int) -> bool:
	while peer.inbox.size() >= 2 and not peer.closing:
		var b: PackedByteArray = peer.inbox
		var final: bool = (b[0] & 0x80) != 0
		var opcode: int = b[0] & 0x0F
		var length: int = b[1] & 0x7F
		var pos: int = 2
		# Do app vem sempre mascarado, sem extensões e em quadros inteiros.
		if (b[1] & 0x80) == 0 or (b[0] & 0x70) != 0 or length == 127:
			return false
		if length == 126:
			if b.size() < 4:
				return true
			length = (b[2] << 8) | b[3]
			pos = 4
		if length > MAX_MESSAGE:
			return false
		if b.size() < pos + 4 + length:
			return true
		var mask: PackedByteArray = b.slice(pos, pos + 4)
		var payload: PackedByteArray = b.slice(pos + 4, pos + 4 + length)
		for i in length:
			payload[i] = payload[i] ^ mask[i & 3]
		peer.inbox = b.slice(pos + 4 + length)
		peer.last_ms = now
		match opcode:
			1:
				if not final:
					return false
				_events.append({"type": "message", "peer": peer.id,
					"data": Codec.decode(payload.get_string_from_utf8())})
			2:
				if not final:
					return false
			8:
				_report_gone(peer)
				_queue(peer, _frame(8, payload.slice(0, 2)))
				peer.closing = true
				peer.close_heard = true
				peer.close_sent = true
				peer.since = now
			9:
				_queue(peer, _frame(10, payload))
			10:
				pass
			_:
				return false
	return true


func _queue(peer: Peer, data: PackedByteArray) -> void:
	if peer.out_bytes + data.size() > MAX_OUTBOX:
		_forget(peer)
		return
	peer.outbox.append(data)
	peer.out_bytes += data.size()
	peer.last_out_ms = _clock.now_ms()
	bytes_out += data.size()
	_flush(peer)


## Manda o que couber agora, sem esperar. Falso: a conexão quebrou.
func _flush(peer: Peer) -> bool:
	while not peer.outbox.is_empty():
		var chunk: PackedByteArray = peer.outbox[0]
		var rest: PackedByteArray = chunk if peer.out_offset == 0 else chunk.slice(peer.out_offset)
		var result: Array = peer.tcp.put_partial_data(rest)
		if result[0] != OK:
			return false
		var sent: int = result[1]
		peer.out_bytes -= sent
		if sent < rest.size():
			peer.out_offset += sent
			return true
		peer.outbox.pop_front()
		peer.out_offset = 0
	return true


func _forget(peer: Peer) -> void:
	_report_gone(peer)
	peer.closing = true   # para de ler quadros desta conexão
	_peers.erase(peer.id)
	peer.tcp.disconnect_from_host()


func _report_gone(peer: Peer) -> void:
	if peer.open:
		peer.open = false
		_events.append({"type": "disconnect", "peer": peer.id, "data": {}})


static func _frame(opcode: int, payload: PackedByteArray) -> PackedByteArray:
	var head: PackedByteArray = PackedByteArray([0x80 | opcode])
	var size: int = payload.size()
	if size < 126:
		head.append(size)
	elif size < 65536:
		head.append_array(PackedByteArray([126, size >> 8, size & 0xFF]))
	else:
		head.append(127)
		for shift: int in [56, 48, 40, 32, 24, 16, 8, 0]:
			head.append((size >> shift) & 0xFF)
	return head + payload


static func _close_payload(code: int) -> PackedByteArray:
	return PackedByteArray([code >> 8, code & 0xFF])
