extends "res://tests/test_case.gd"
## Rede do Wi-Fi (SPEC 9.2): código da sala, mux, WebSocket de verdade nesta máquina
## (127.0.0.1), batimento, descoberta por UDP e uma partida com anfitrião e dois
## convidados, com queda e volta.

const RoomCode := preload("res://net/room_code.gd")
const Mux := preload("res://net/mux.gd")
const LocalTransport := preload("res://net/local_transport.gd")
const WsServer := preload("res://net/ws_server.gd")
const WsClient := preload("res://net/ws_client.gd")
const Discovery := preload("res://net/discovery.gd")
const WifiGame := preload("res://ui/app/wifi_game.gd")
const Clock := preload("res://server/clock.gd")
const Protocol := preload("res://server/protocol.gd")
const Wire := preload("res://server/wire.gd")

const FAST: Dictionary = {"hand_gap_ms": 0, "showdown_gap_ms": 0, "bot_min_ms": 0,
	"bot_max_ms": 0, "bot_evaluations": 120}
const TEST_UDP_PORT: int = 47891

var _seed: int = 0


func _next_seed() -> int:
	_seed += 1
	return _seed


## Faz as pontas andarem por até ms, ou até done() ficar verdadeiro.
func _spin(step: Callable, done: Callable, ms: int = 3000) -> bool:
	var until: int = Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < until:
		step.call()
		if done.call():
			return true
		OS.delay_msec(2)
	return false


func test_room_code_round_trip() -> void:
	for ip: String in ["192.168.0.1", "192.168.43.1", "10.0.255.254", "172.20.10.2",
			"192.168.1.0", "10.1.0.0"]:
		var code: String = RoomCode.encode(ip)
		assert_eq(code.length(), 4, "4 caracteres para " + ip)
		var parts: PackedStringArray = ip.split(".")
		var own: String = "%s.%s.77.88" % [parts[0], parts[1]]
		assert_eq(RoomCode.decode(code, own), ip, "volta ao IP " + ip)
		assert_eq(RoomCode.decode(code.to_lower(), own), ip, "aceita minúsculas")
		assert_eq(RoomCode.decode(RoomCode.pretty(code), own), ip, "aceita o espaço")
	assert_eq(RoomCode.encode("abc"), "", "IP inválido")
	assert_eq(RoomCode.decode("K7M", "192.168.0.5"), "", "curto demais")
	assert_eq(RoomCode.decode("K0MP", "192.168.0.5"), "", "caractere fora do alfabeto")
	# Trocar um caractere quase sempre é pego pela conferência.
	var code: String = RoomCode.encode("192.168.1.37")
	var caught: int = 0
	var tried: int = 0
	for i in 4:
		for ch: String in RoomCode.CHARS:
			if ch == code[i]:
				continue
			tried += 1
			var typo: String = code.left(i) + ch + code.substr(i + 1)
			if RoomCode.decode(typo, "192.168.1.2") == "":
				caught += 1
	assert_true(caught * 100 >= tried * 90, "erros de digitação pegos: %d de %d" % [caught, tried])


func test_local_ip_prefers_wifi() -> void:
	assert_eq(RoomCode.score_address("127.0.0.1", "lo"), 0)
	assert_eq(RoomCode.score_address("8.8.8.8", "wlan0"), 0, "endereço público não serve")
	assert_eq(RoomCode.score_address("fe80::1", "wlan0"), 0, "IPv6 não serve")
	assert_true(RoomCode.score_address("10.20.30.40", "wlan0")
		> RoomCode.score_address("10.1.2.3", "rmnet_data0"), "Wi-Fi antes de dados móveis")
	assert_true(RoomCode.score_address("192.168.43.1", "ap0")
		> RoomCode.score_address("192.168.0.9", "eth9"), "ponto de acesso conta como Wi-Fi")
	assert_eq(RoomCode.broadcast_addresses("192.168.0.9"),
		["255.255.255.255", "192.168.0.255"] as Array[String])


func test_mux_routes_peers() -> void:
	var one: LocalTransport = LocalTransport.new()
	var two: LocalTransport = LocalTransport.new()
	var mux: Mux = Mux.new()
	mux.add(one)
	mux.add(two)
	var a: LocalTransport.Endpoint = one.connect_client()
	var b: LocalTransport.Endpoint = two.connect_client()
	b.send({"t": "x"})
	var events: Array[Dictionary] = mux.poll()
	assert_eq(events.size(), 3, "duas conexões e uma mensagem")
	var peers: Dictionary = {}
	for event: Dictionary in events:
		if event["type"] == "connect":
			peers[event["peer"]] = true
	assert_eq(peers.size(), 2, "números diferentes")
	var b_peer: int = events[2]["peer"]
	mux.send(b_peer, {"t": "y"})
	assert_eq(b.poll().size(), 1, "a resposta chega a quem mandou")
	assert_eq(a.poll().size(), 0)
	mux.drop(b_peer)
	assert_false(b.is_open())


func test_websocket_round_trip_and_heartbeat() -> void:
	var server: WsServer = WsServer.new()
	assert_eq(server.listen(0, "127.0.0.1"), OK, "abre a porta")
	var client: WsClient = WsClient.new()
	client.open("127.0.0.1", server.port)
	var events: Array = []
	var got: Array = []
	var step: Callable = func() -> void:
		events.append_array(server.poll())
		got.append_array(client.poll())
	assert_true(_spin(step, func() -> bool: return client.is_open() and not events.is_empty()),
		"conectou")
	assert_eq(events[0]["type"], "connect")
	var peer: int = events[0]["peer"]
	client.send({"t": "hello", "n": 7})
	assert_true(_spin(step, func() -> bool:
		return events.any(func(e: Dictionary) -> bool: return e["type"] == "message")), "mensagem chegou")
	var message: Dictionary = events.filter(func(e: Dictionary) -> bool:
		return e["type"] == "message")[0]["data"]
	assert_eq(message.get("n"), 7, "número volta inteiro")
	server.send(peer, {"t": "state", "v": [1, 2]})
	assert_true(_spin(step, func() -> bool: return not got.is_empty()), "resposta chegou")
	assert_eq(got[0].get("v"), [1, 2])
	# O app manda ping sozinho; o "pong" não chega a quem usa.
	assert_true(_spin(step, func() -> bool:
		return events.any(func(e: Dictionary) -> bool:
			return e["type"] == "message" and e["data"].get("t") == Protocol.PING), 3000),
		"batimento a cada 2 s")
	client.close()
	assert_true(_spin(step, func() -> bool:
		return events.any(func(e: Dictionary) -> bool: return e["type"] == "disconnect")),
		"o servidor percebe o fechamento")
	server.stop()


func test_server_drops_silent_peer() -> void:
	var clock: Clock = Clock.new(true)
	var server: WsServer = WsServer.new(clock)
	server.listen(0, "127.0.0.1")
	var client: WsClient = WsClient.new()
	client.open("127.0.0.1", server.port)
	var events: Array = []
	_spin(func() -> void:
		events.append_array(server.poll())
		client.poll(), func() -> bool: return not events.is_empty())
	# A partir daqui o app fica calado (não é mais consultado).
	for _i in 12:
		clock.advance(1000)
		events.append_array(server.poll())
	assert_true(events.any(func(e: Dictionary) -> bool: return e["type"] == "disconnect"),
		"10 s sem nada: caiu")
	# Servidor parado muito tempo (app suspenso) não derruba ninguém.
	var client2: WsClient = WsClient.new()
	client2.open("127.0.0.1", server.port)
	var events2: Array = []
	_spin(func() -> void:
		events2.append_array(server.poll())
		client2.poll(), func() -> bool: return not events2.is_empty())
	clock.advance(60000)
	events2.append_array(server.poll())
	assert_false(events2.any(func(e: Dictionary) -> bool: return e["type"] == "disconnect"),
		"a pausa do próprio servidor não conta")
	server.stop()


func test_client_detects_silent_server() -> void:
	var server: WsServer = WsServer.new()
	server.listen(0, "127.0.0.1")
	var clock: Clock = Clock.new(true)
	var client: WsClient = WsClient.new(clock)
	client.open("127.0.0.1", server.port)
	_spin(func() -> void:
		server.poll()
		client.poll(), func() -> bool: return client.is_open())
	# Ninguém responde aos pings (o servidor não é consultado).
	for _i in 8:
		clock.advance(1000)
		client.poll()
	assert_eq(client.status, WsClient.Status.LOST, "6 s sem ouvir nada: perdida")
	server.stop()


## Um pedido HTTP comum (o detector de portas do Render, um robô da internet) recebe
## resposta HTTP, sem erro, e a porta continua atendendo o jogo.
func test_stray_http_request_gets_plain_answer() -> void:
	var server: WsServer = WsServer.new()
	assert_eq(server.listen(0, "127.0.0.1"), OK)
	server.http_handler = func(request: Dictionary) -> Dictionary:
		if request["path"] == "/saude":
			return {"status": "200 OK", "type": "text/plain", "body": "ok"}
		return {"status": "404 Not Found", "type": "text/plain", "body": "não encontrado"}
	for case: Array in [["GET /saude HTTP/1.1\r\nHost: x\r\nUser-Agent: y\r\n\r\n", "200 OK", "ok"],
			["GET / HTTP/1.1\r\nHost: x\r\nUser-Agent: y\r\n\r\n", "404", "não encontrado"],
			["oi\r\n\r\n", "400", ""]]:
		var raw: StreamPeerTCP = StreamPeerTCP.new()
		raw.connect_to_host("127.0.0.1", server.port)
		var answer: PackedByteArray = PackedByteArray()
		var sent: Array = [false]
		_spin(func() -> void:
			server.poll()
			raw.poll()
			if raw.get_status() == StreamPeerTCP.STATUS_CONNECTED:
				if not sent[0]:
					raw.put_data((case[0] as String).to_utf8_buffer())
					sent[0] = true
				var available: int = raw.get_available_bytes()
				if available > 0:
					answer.append_array(raw.get_data(available)[1]),
			func() -> bool: return sent[0] and raw.get_status() != StreamPeerTCP.STATUS_CONNECTED)
		var text: String = answer.get_string_from_utf8()
		assert_true(text.begins_with("HTTP/1.1 " + case[1]), "resposta HTTP: " + text.left(40))
		assert_true(text.ends_with("\r\n\r\n" + case[2]), "corpo da resposta")
	assert_eq(server.stray, ["GET /", "(pedido inválido)"] as Array[String],
		"os pedidos ficam anotados para o diagnóstico, menos a verificação de saúde")
	# Depois disso, um app de verdade conecta e conversa.
	var client: WsClient = WsClient.new()
	client.open("127.0.0.1", server.port)
	var events: Array = []
	var got: Array = []
	var step: Callable = func() -> void:
		events.append_array(server.poll())
		got.append_array(client.poll())
	assert_true(_spin(step, func() -> bool: return client.is_open() and not events.is_empty()),
		"conectou depois dos pedidos estranhos")
	server.send(events[0]["peer"], {"t": "x", "v": 3})
	assert_true(_spin(step, func() -> bool: return not got.is_empty()), "mensagem chegou")
	assert_eq(got[0].get("v"), 3)
	assert_eq(server.peer_count(), 1, "só o app ficou conectado")
	server.stop()


## Protocolo enxuto (SPEC 9.1): o `state` chega inteiro ao app pela rede, com `room` só
## quando muda, e as mensagens grandes chegam compactadas.
func test_lean_state_over_websocket() -> void:
	var server: WsServer = WsServer.new()
	server.listen(0, "127.0.0.1")
	var client: WsClient = WsClient.new()
	client.open("127.0.0.1", server.port)
	var events: Array = []
	var got: Array = []
	var step: Callable = func() -> void:
		events.append_array(server.poll())
		got.append_array(client.poll())
	_spin(step, func() -> bool: return client.is_open() and not events.is_empty())
	var peer: int = events[0]["peer"]
	var room: Dictionary = {"id": "ABCD", "members": [{"id": "m1", "nick": "Ana"}], "phase": "lobby"}
	var table: Dictionary = {"seq": 1, "seats": [{"seat": 0, "stack": 2000}]}
	var before: int = server.bytes_out
	server.send_state(peer, {"you": {"id": "m1", "cards": [3, 51]}},
		Wire.StatePack.new(room, table, [{"type": "deal"}]))
	var first_size: int = server.bytes_out - before
	before = server.bytes_out
	server.send_state(peer, {"you": {"id": "m1"}},
		Wire.StatePack.new(room.duplicate(true), {"seq": 2, "seats": []}, []))
	assert_true(server.bytes_out - before < first_size, "o segundo vai sem room")
	var history: Array = []
	for i in 60:
		history.append({"hand": i, "text": "mão de exemplo com bastante texto repetido"})
	before = server.bytes_out
	server.send(peer, {"t": "hands", "hands": history})
	assert_true(server.bytes_out - before < JSON.stringify(history).length() / 4,
		"mensagem grande vai compactada")
	assert_true(_spin(step, func() -> bool: return got.size() >= 3), "chegaram as três")
	assert_eq(got[0], {"t": "state", "room": room, "table": table,
		"you": {"id": "m1", "cards": [3, 51]}, "events": [{"type": "deal"}]}, "foto completa")
	assert_eq(got[1]["room"], room, "room remontado no app")
	assert_eq(got[1]["table"]["seq"], 2)
	assert_eq(got[2]["hands"].size(), 60)
	assert_eq(got[2]["hands"][59]["hand"], 59, "números voltam inteiros")
	server.stop()


## Expulso ou sala encerrada: a última mensagem chega antes de a conexão fechar.
func test_last_message_arrives_before_drop() -> void:
	var server: WsServer = WsServer.new()
	server.listen(0, "127.0.0.1")
	var client: WsClient = WsClient.new()
	client.open("127.0.0.1", server.port)
	var events: Array = []
	var got: Array = []
	var step: Callable = func() -> void:
		events.append_array(server.poll())
		got.append_array(client.poll())
	_spin(step, func() -> bool: return client.is_open() and not events.is_empty())
	client.send({"t": Protocol.PING})   # algo por ler no servidor na hora de fechar
	var big: Array = []
	for i in 400:
		big.append("linha %d de um placar comprido" % i)
	server.send(events[0]["peer"], {"t": Protocol.CLOSED, "reason": "x", "scoreboard": big})
	server.drop(events[0]["peer"])
	assert_true(_spin(step, func() -> bool: return client.status == WsClient.Status.LOST),
		"a conexão fecha")
	assert_eq(got.size(), 1, "a mensagem final chegou")
	assert_eq(got[0].get("scoreboard", []).size(), 400)
	assert_eq(server.peer_count(), 0)
	server.stop()


## O "pong" logo depois de outra mensagem não sai: ela já mostrou que o servidor vive.
func test_pong_skipped_right_after_other_message() -> void:
	var clock: Clock = Clock.new(true)
	var server: WsServer = WsServer.new(clock)
	server.listen(0, "127.0.0.1")
	var client: WsClient = WsClient.new()
	client.open("127.0.0.1", server.port)
	var events: Array = []
	_spin(func() -> void:
		events.append_array(server.poll())
		client.poll(), func() -> bool: return client.is_open() and not events.is_empty())
	var peer: int = events[0]["peer"]
	server.send(peer, {"t": "x"})
	var before: int = server.bytes_out
	clock.advance(WsServer.PONG_SKIP_MS - 1)
	server.send(peer, {"t": Protocol.PONG})
	assert_eq(server.bytes_out, before, "pong logo depois de outra mensagem fica de fora")
	clock.advance(1)
	server.send(peer, {"t": Protocol.PONG})
	assert_true(server.bytes_out > before, "sem nada recente, o pong sai")
	server.stop()


func test_wire_rejects_broken_frames() -> void:
	var cache: Dictionary = {}
	var frame: PackedByteArray = Wire.StatePack.new({"id": "A"}, {"seq": 1}, []).frame({}, false)
	assert_eq(Wire.decode(frame, cache), {}, "sem room guardado não monta a foto")
	var good: PackedByteArray = Wire.StatePack.new({"id": "A"}, {"seq": 1}, []).frame({}, true)
	assert_eq(Wire.decode(good, cache)["room"], {"id": "A"})
	assert_eq(Wire.decode(frame, cache)["room"], {"id": "A"}, "depois usa o guardado")
	for broken: PackedByteArray in [PackedByteArray(), PackedByteArray([9, 1, 2]),
			good.slice(0, 12), PackedByteArray([1, 255, 255, 255, 127, 0, 0, 0, 0])]:
		assert_eq(Wire.decode(broken, {}), {}, "quadro estragado é ignorado")


func test_discovery_announce_and_expire() -> void:
	var clock: Clock = Clock.new(true)
	var listener: Discovery.Listener = Discovery.Listener.new(clock)
	assert_eq(listener.listen(TEST_UDP_PORT), OK, "escuta a porta")
	var announcer: Discovery.Announcer = Discovery.Announcer.new(
		clock, ["127.0.0.1"] as Array[String], TEST_UDP_PORT)
	var info: Dictionary = {"name": "Sala de Ana", "format": "classic", "seats": 4,
		"players": 2, "phase": "lobby", "open": true, "port": 47820}
	announcer.poll(info)
	var seen: bool = _spin(func() -> void: listener.poll(),
		func() -> bool: return listener.rooms.size() == 1, 2000)
	assert_true(seen, "a sala aparece sozinha")
	if seen:
		var room: Dictionary = listener.list()[0]
		assert_eq(room["name"], "Sala de Ana")
		assert_eq(room["ip"], "127.0.0.1")
		assert_eq(room["port"], 47820)
	# Não manda de novo antes da hora.
	announcer.poll(info)
	OS.delay_msec(30)
	listener.poll()
	clock.advance(6000)
	listener.poll()
	assert_eq(listener.rooms.size(), 0, "some depois de alguns segundos sem anúncio")
	assert_eq(Discovery.Listener.parse("lixo".to_utf8_buffer(), "1.2.3.4"), {}, "pacote estranho")
	assert_eq(Discovery.Listener.parse(JSON.stringify({"app": "outro", "v": 1, "port": 1}).to_utf8_buffer(),
		"1.2.3.4"), {}, "outro app")
	announcer.close()
	listener.close()


## Anfitrião e dois convidados por WebSocket nesta máquina: entram, jogam mãos
## inteiras, um convidado cai e volta para o mesmo lugar.
func test_wifi_match_with_two_guests() -> void:
	_seed = 4000
	var host: WifiGame = WifiGame.new()
	var options: Dictionary = {"format": "classic", "seats": 4, "turn_seconds": 0, "bots": []}
	var ok: bool = host.host("Ana", 1, "dev-a", options, FAST, _next_seed,
		["127.0.0.1"] as Array[String], 0, TEST_UDP_PORT + 1)
	assert_true(ok, "abriu a sala: " + host.error_text)
	if not ok:
		return
	var bia: WifiGame = WifiGame.new()
	var caio: WifiGame = WifiGame.new()
	bia.join("127.0.0.1", host.port, "Bia", 2, "dev-b")
	caio.join("127.0.0.1", host.port, "Caio", 3, "dev-c")
	var games: Array = [host, bia, caio]
	var hands: Array = [0]
	var errors: Array = []
	var step: Callable = func() -> void:
		for game: WifiGame in games:
			for message: Dictionary in game.update():
				if message["t"] == Protocol.ERROR:
					errors.append(message["text"])
				if message["t"] != Protocol.STATE:
					continue
				if game == host:
					for event: Dictionary in message["events"]:
						if event["type"] == "end":
							hands[0] += 1
				var you: Dictionary = message["you"]
				if you.has("legal"):
					game.act("check" if you["legal"]["can_check"] else "call", 0)
	var all_in: Callable = func() -> bool:
		var members: Array = host.last_state.get("room", {}).get("members", [])
		return members.size() == 3 and bia.my_id != "" and caio.my_id != ""
	assert_true(_spin(step, all_in, 4000), "os dois convidados entraram")
	assert_eq(bia.link, WifiGame.Link.ONLINE)
	host.start()
	assert_true(_spin(step, func() -> bool: return hands[0] >= 3, 8000),
		"jogaram mãos inteiras (%d)" % hands[0])
	assert_eq(errors, [], "nenhuma jogada recusada")
	# Caio cai (a conexão some) e volta com o mesmo aparelho.
	var caio_id: String = caio.my_id
	var caio_seat: int = int(caio.last_state["you"]["seat"])
	caio.shutdown()
	var offline: Callable = func() -> bool:
		for member: Dictionary in host.last_state["room"]["members"]:
			if member["id"] == caio_id:
				return not member["connected"]
		return false
	assert_true(_spin(step, offline, 4000), "o anfitrião vê Caio reconectando")
	var caio2: WifiGame = WifiGame.new()
	caio2.join("127.0.0.1", host.port, "Caio", 3, "dev-c")
	games[2] = caio2
	assert_true(_spin(step, func() -> bool: return caio2.my_id != "", 4000), "voltou")
	assert_eq(caio2.my_id, caio_id, "como o mesmo participante")
	assert_eq(int(caio2.last_state.get("you", {}).get("seat", -1)), caio_seat, "no mesmo lugar")
	var before: int = hands[0]
	assert_true(_spin(step, func() -> bool: return hands[0] >= before + 2, 8000),
		"a partida segue com ele")
	# Bia sai pelo botão; o anfitrião encerra e todos recebem o placar.
	bia.leave()
	bia.shutdown()
	games.erase(bia)
	host.owner(Protocol.CMD_CLOSE)
	_spin(step, func() -> bool: return not host.final.is_empty(), 2000)
	var final: Dictionary = host.final
	assert_eq(final.get("t"), Protocol.CLOSED, "o anfitrião encerra com placar")
	assert_true(_spin(step, func() -> bool: return not caio2.final.is_empty(), 3000),
		"o convidado recebe o placar")
	host.shutdown()
	caio2.shutdown()


## Partida em andamento: com vaga, o app pergunta antes de sentar; cheia, a entrada é
## recusada (só assiste quem já estava na sala).
func test_join_in_progress_asks_first() -> void:
	_seed = 4500
	var host: WifiGame = WifiGame.new()
	var options: Dictionary = {"format": "classic", "seats": 3, "turn_seconds": 0, "bots": [],
		"keep_open": true}
	var ok: bool = host.host("Ana", 1, "dev-a", options, FAST, _next_seed,
		["127.0.0.1"] as Array[String], 0, TEST_UDP_PORT + 3)
	assert_true(ok, "abriu a sala: " + host.error_text)
	if not ok:
		return
	var bia: WifiGame = WifiGame.new()
	bia.join("127.0.0.1", host.port, "Bia", 2, "dev-b")
	var games: Array = [host, bia]
	var step: Callable = func() -> void:
		for game: WifiGame in games:
			game.update()
	assert_true(_spin(step, func() -> bool: return bia.my_id != "", 4000), "Bia entrou")
	host.start()
	_spin(step, func() -> bool: return bia.last_state.get("room", {}).get("phase") == "playing", 2000)
	var davi: WifiGame = WifiGame.new()
	davi.join("127.0.0.1", host.port, "Davi", 3, "dev-d")
	games.append(davi)
	assert_true(_spin(step, func() -> bool: return davi.confirm_seat, 4000), "o app pergunta")
	_spin(step, func() -> bool: return false, 300)
	assert_eq(davi.my_id, "", "sem resposta, não entra")
	davi.confirm_join()
	assert_true(_spin(step, func() -> bool: return davi.my_id != "", 4000), "Davi entrou")
	assert_true(int(davi.last_state.get("you", {}).get("seat", -1)) >= 0, "sentado")
	var eva: WifiGame = WifiGame.new()
	eva.join("127.0.0.1", host.port, "Eva", 4, "dev-e")
	games.append(eva)
	assert_true(_spin(step, func() -> bool: return eva.link == WifiGame.Link.FAILED, 4000),
		"sala cheia: não entra")
	assert_false(eva.confirm_seat, "sem vaga, nem pergunta")
	assert_eq(eva.error_text, "A sala está cheia.")
	for game: WifiGame in games:
		game.shutdown()


## O anfitrião sai no meio da partida: a sala passa para o convidado mais antigo, o outro
## reconecta nele e a partida segue.
func test_host_leaves_and_room_moves() -> void:
	_seed = 5000
	var host: WifiGame = WifiGame.new()
	var options: Dictionary = {"format": "classic", "seats": 4, "turn_seconds": 0, "bots": [1]}
	var ok: bool = host.host("Ana", 1, "dev-a", options, FAST, _next_seed,
		["127.0.0.1"] as Array[String], 0, TEST_UDP_PORT + 2)
	assert_true(ok, "abriu a sala")
	if not ok:
		return
	var bia: WifiGame = WifiGame.new()
	var caio: WifiGame = WifiGame.new()
	for guest: WifiGame in [bia, caio]:
		guest.takeover = {"room_config": FAST, "seed_source": _next_seed,
			"announce_to": ["127.0.0.1"], "announce_port": TEST_UDP_PORT + 3}
	bia.join("127.0.0.1", host.port, "Bia", 2, "dev-b")
	var games: Array = [host, bia]
	var hands: Array = [0]
	var step: Callable = func() -> void:
		for game: WifiGame in games:
			for message: Dictionary in game.update():
				if message["t"] != Protocol.STATE:
					continue
				for event: Dictionary in message["events"]:
					if event["type"] == "end" and game == games[0]:
						hands[0] += 1
				var you: Dictionary = message["you"]
				if you.has("legal"):
					game.act("check" if you["legal"]["can_check"] else "call", 0)
				elif you.has("rebuy_ms"):
					game.rebuy(true)
	assert_true(_spin(step, func() -> bool: return bia.my_id != "", 4000), "Bia entrou")
	caio.join("127.0.0.1", host.port, "Caio", 3, "dev-c")
	games.append(caio)
	assert_true(_spin(step, func() -> bool: return caio.my_id != "", 4000), "Caio entrou")
	host.start()
	assert_true(_spin(step, func() -> bool: return hands[0] >= 2, 8000), "jogaram")
	var bia_id: String = bia.my_id
	var caio_id: String = caio.my_id
	var final: Dictionary = host.leave()
	assert_eq(final, {}, "sem placar: a sala continua")
	assert_true(_spin(step, func() -> bool: return not host.pending_exit(), 8000),
		"a mão acabou e a sala passou")
	assert_true(host.failure().contains("Bia"), "o anfitrião sabe para quem foi: " + host.failure())
	host.shutdown()
	games.erase(host)
	assert_true(_spin(step, func() -> bool:
		return bia.is_host and caio.link == WifiGame.Link.ONLINE and caio.my_id == caio_id 			and bia.my_id == bia_id and not caio.last_state.is_empty() 			and int(caio.last_state["table"].get("seq", 0)) > 0, 6000),
		"Bia virou anfitriã e Caio reconectou nela")
	assert_eq(bia.is_owner(), true, "Bia é a dona")
	hands[0] = 0
	hands[0] = 0
	assert_true(_spin(step, func() -> bool: return hands[0] >= 2, 10000),
		"a partida segue no celular da Bia (%d mãos)" % hands[0])
	bia.leave()
	bia.shutdown()
	caio.shutdown()
