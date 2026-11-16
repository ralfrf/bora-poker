extends RefCounted
## Transporte WebSocket do lado do servidor (SPEC 9.2). No Wi-Fi roda no celular do
## anfitrião; na etapa 5, sem tela, no Render. Segue o mesmo contrato do transporte
## local:
##   poll() -> [{type: "connect" | "message" | "disconnect", peer, data}]
##   send(peer, mensagem), drop(peer)
##
## Batimento: o app manda "ping" a cada 2 s. Uma conexão que fica SILENCE_MS sem mandar
## nada é dada como caída. Se o próprio servidor ficou parado (o Android suspendeu o
## app), a contagem recomeça: ninguém cai por culpa do anfitrião.

const Codec := preload("res://net/codec.gd")
const Clock := preload("res://server/clock.gd")

const PORT: int = 47820
const SILENCE_MS: int = 10000
const HANDSHAKE_MS: int = 5000
const PAUSE_GAP_MS: int = 3000
const MAX_PEERS: int = 32
const MAX_MESSAGE: int = 65536


class Peer:
	extends RefCounted

	var id: int = 0
	var ws: WebSocketPeer = WebSocketPeer.new()
	var open: bool = false      ## o aperto de mão terminou e o servidor já soube
	var since: int = 0
	var last_ms: int = 0


var port: int = 0

var _tcp: TCPServer = TCPServer.new()
var _clock: Clock = null
var _peers: Dictionary = {}     # id -> Peer
var _closing: Array[Peer] = []  # encerradas por nós, terminando o fechamento
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
		peer.ws.close(1001, "servidor encerrado")
	_peers.clear()
	_closing.clear()
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
		if _peers.size() >= MAX_PEERS:
			connection.disconnect_from_host()
			continue
		var peer: Peer = Peer.new()
		peer.id = _next_peer
		_next_peer += 1
		peer.since = now
		peer.last_ms = now
		peer.ws.inbound_buffer_size = MAX_MESSAGE
		peer.ws.outbound_buffer_size = MAX_MESSAGE * 4
		peer.ws.accept_stream(connection)
		_peers[peer.id] = peer
	for peer: Peer in _peers.values():
		_poll_peer(peer, now)
	for peer: Peer in _closing.duplicate():
		peer.ws.poll()
		if peer.ws.get_ready_state() == WebSocketPeer.STATE_CLOSED or now - peer.since > HANDSHAKE_MS:
			_closing.erase(peer)
	var events: Array[Dictionary] = _events
	_events = []
	return events


func send(peer_id: int, message: Dictionary) -> void:
	var peer: Peer = _peers.get(peer_id)
	if peer != null and peer.open and peer.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		peer.ws.send_text(Codec.encode(message))


## O servidor encerra a conexão (o que já foi enviado sai antes).
func drop(peer_id: int) -> void:
	var peer: Peer = _peers.get(peer_id)
	if peer == null:
		return
	_peers.erase(peer_id)
	peer.ws.close(1000, "")
	peer.since = _clock.now_ms()
	_closing.append(peer)
	if peer.open:
		_events.append({"type": "disconnect", "peer": peer_id, "data": {}})


## IP de onde a conexão veio ("" se não existe).
func peer_ip(peer_id: int) -> String:
	var peer: Peer = _peers.get(peer_id)
	return peer.ws.get_connected_host() if peer != null else ""


## Quantas conexões estão abertas (para os testes e para o limite).
func peer_count() -> int:
	return _peers.size()


func _poll_peer(peer: Peer, now: int) -> void:
	peer.ws.poll()
	var state: int = peer.ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not peer.open:
			peer.open = true
			peer.last_ms = now
			_events.append({"type": "connect", "peer": peer.id, "data": {}})
		while peer.ws.get_available_packet_count() > 0:
			var packet: PackedByteArray = peer.ws.get_packet()
			peer.last_ms = now
			if peer.ws.was_string_packet():
				_events.append({"type": "message", "peer": peer.id,
					"data": Codec.decode(packet.get_string_from_utf8())})
		if now - peer.last_ms > SILENCE_MS:
			drop(peer.id)
	elif state == WebSocketPeer.STATE_CONNECTING:
		if now - peer.since > HANDSHAKE_MS:
			_peers.erase(peer.id)
			peer.ws.close()
	elif state == WebSocketPeer.STATE_CLOSED:
		_peers.erase(peer.id)
		if peer.open:
			_events.append({"type": "disconnect", "peer": peer.id, "data": {}})
