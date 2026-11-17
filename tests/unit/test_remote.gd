extends "res://tests/test_case.gd"
## Servidor à distância (SPEC 4.3, 6.5, 9.3): vagas de carga, lotação, teto de
## espectadores, sala sem humanos, limite de mensagens e o anfitrião com HTTP.

const Room := preload("res://server/room.gd")
const Server := preload("res://server/server.gd")
const Load := preload("res://server/load.gd")
const Clock := preload("res://server/clock.gd")
const Protocol := preload("res://server/protocol.gd")
const LocalTransport := preload("res://net/local_transport.gd")
const RemoteHost := preload("res://net/remote_host.gd")
const WsClient := preload("res://net/ws_client.gd")
const Hand := preload("res://engine/hand.gd")

const FAST: Dictionary = {"hand_gap_ms": 0, "showdown_gap_ms": 0, "bot_min_ms": 0, "bot_max_ms": 0,
	"bot_evaluations": 120}

var _seed: int = 0


func _next_seed() -> int:
	_seed += 1
	return _seed


func _spin(step: Callable, done: Callable, ms: int = 3000) -> bool:
	var until: int = Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < until:
		step.call()
		if done.call():
			return true
		OS.delay_msec(2)
	return false


func _room(raw: Dictionary, clock: Clock, config: Dictionary) -> Room:
	var merged: Dictionary = FAST.duplicate()
	merged.merge(config, true)
	return Room.new("ABCD", Room.normalize_options(raw)["options"], clock, Callable(), merged, _next_seed)


func _join(room: Room, nick: String, spectate: bool = false) -> Dictionary:
	var result: Dictionary = room.join({"nick": nick, "avatar": 0, "device": "dev-" + nick}, spectate)
	room.announce()
	return result


func test_load_weights_and_percent() -> void:
	assert_eq(Load.room_weight(6, 0), 100, "mesa de 6 = uma vaga")
	assert_eq(Load.room_weight(2, 0), 20)
	assert_eq(Load.room_weight(9, 3), 280, "9 lugares e 3 espectadores")
	var clock: Clock = Clock.new(true)
	var cpu: Array = [0]
	var load: Load = Load.new(1000, clock, func() -> int: return cpu[0], 0.1)
	load.sample()
	clock.advance(Load.SAMPLE_MS)
	cpu[0] = 1000000   # 1 s de CPU em 5 s com 0,1 núcleo = o dobro do que cabe
	load.sample()
	assert_eq(load.cpu_percent(), 100, "CPU limitada a 100%")
	clock.advance(Load.SAMPLE_MS)
	cpu[0] = 1100000   # mais 0,1 s em 5 s: no minuto, 1,1 s / (10 s * 0,1)
	load.sample()
	assert_eq(load.cpu_percent(), 100)
	for _i in 14:
		clock.advance(Load.SAMPLE_MS)
		cpu[0] += 100000   # 0,1 s a cada 5 s = 20% do que cabe
		load.sample()
	assert_eq(load.cpu_percent(), 20, "o pico antigo saiu da janela de 1 minuto")
	assert_eq(load.slots_percent(250), 25)
	assert_eq(load.percent(250), 25, "o maior entre CPU e vagas")
	assert_true(load.fits(900, 100))
	assert_false(load.fits(901, 100), "não cabe")
	assert_true(Load.new(0, clock).fits(100000, 220), "sem limite configurado")


func test_watcher_cap_counts_only_chosen_watchers() -> void:
	var clock: Clock = Clock.new(true)
	var room: Room = _room({"seats": 2, "turn_seconds": 0, "rebuy_limit": 0}, clock, {"watcher_cap": 3})
	var a: String = _join(room, "Ana")["id"]
	_join(room, "Bia")
	for nick: String in ["Caio", "Davi", "Eva"]:
		assert_true(_join(room, nick, true)["ok"], "assiste: " + nick)
	assert_eq(room.watchers(), 3)
	var refused: Dictionary = _join(room, "Fabi", true)
	assert_false(refused["ok"], "o quarto espectador fica de fora")
	assert_eq(refused["error"], "já há 3 pessoas assistindo")
	room.leave(room.members.values().filter(func(m: Room.Member) -> bool: return m.nick == "Eva")[0].id)
	assert_eq(room.watchers(), 2, "quem sai libera a vaga")
	assert_true(_join(room, "Fabi", true)["ok"])
	room.handle(a, {"t": Protocol.START})
	# Joga até alguém zerar (sem recompra): ele continua assistindo e não conta no teto.
	for _i in 400:
		if room.is_closed() or room.phase != Protocol.PLAYING:
			break
		if room.table.hand_in_progress():
			var seat: int = room.table.hand.to_act
			var legal: Dictionary = room.table.hand.legal_actions()
			var member: Room.Member = room.member_at(seat)
			var action: String = Hand.CALL if not legal["can_check"] else Hand.CHECK
			var amount: int = 0
			if legal["can_raise"]:
				action = Hand.BET if legal["is_bet"] else Hand.RAISE
				amount = int(legal["max_to"])
			room.handle(member.id, {"t": Protocol.ACT, "seq": room._seq, "action": action, "amount": amount})
		else:
			room.tick()
	var busted: Array = room.members.values().filter(func(m: Room.Member) -> bool:
		return m.nick in ["Ana", "Bia"] and m.seat < 0)
	assert_eq(busted.size(), 1, "alguém zerou e virou espectador")
	assert_false(busted[0].watcher, "quem zerou não conta")
	assert_eq(room.watchers(), 3, "o teto continua contando só os 3 que escolheram assistir")


func test_empty_playing_room_waits_ten_minutes() -> void:
	var clock: Clock = Clock.new(true)
	var room: Room = _room({"seats": 3, "turn_seconds": 15, "bots": [1]}, clock,
		{"empty_close_ms": 600000})
	var a: String = _join(room, "Ana")["id"]
	room.handle(a, {"t": Protocol.START})
	room.tick()
	room.drop_connection(a)
	for _i in 30:
		clock.advance(5000)
		room.tick()
	assert_false(room.is_closed(), "sem humanos, a partida espera")
	assert_eq(room.owner_id, "", "ninguém para ser dono")
	var hand: int = room.table.hand_number
	for _i in 80:   # 550 s desde a queda: as fichas guardadas valem 10 minutos
		clock.advance(5000)
		room.tick()
	assert_false(room.is_closed(), "ainda dentro dos 10 minutos")
	assert_eq(room.table.hand_number, hand, "sem humanos, não começa mão nova")
	var back: Dictionary = _join(room, "Ana")
	assert_true(back["ok"], "voltou: " + str(back["error"]))
	assert_eq(room.owner_id, back["id"], "quem volta vira dono")
	room.handle(back["id"], {"t": Protocol.RETURN_CHOICE, "keep": true})
	assert_true(room.members[back["id"]].seat >= 0, "voltou à mesa com as fichas de antes")
	clock.advance(600000)
	room.tick()
	assert_false(room.is_closed(), "com alguém de volta, não fecha")
	room.leave(back["id"])
	clock.advance(599000)
	room.tick()
	assert_false(room.is_closed())
	clock.advance(1000)
	room.tick()
	assert_true(room.is_closed(), "10 minutos sem humanos: fecha")
	assert_eq(room.final.get("reason"), Protocol.R_EMPTY)


func test_lobby_without_humans_closes_at_once() -> void:
	var clock: Clock = Clock.new(true)
	var room: Room = _room({"seats": 3}, clock, {"empty_close_ms": 600000})
	var a: String = _join(room, "Ana")["id"]
	room.leave(a)
	assert_true(room.is_closed(), "na sala de espera não há o que esperar")


func test_message_flood_disconnects() -> void:
	var transport: LocalTransport = LocalTransport.new()
	var server: Server = Server.new(transport, Clock.new(true), {"rate": 10})
	var client: LocalTransport.Endpoint = transport.connect_client()
	server.tick()
	for _i in Server.RATE_BURST:
		client.send({"t": Protocol.PING})
	server.tick()
	assert_true(client.is_open(), "até o limite de uma vez, tudo bem")
	client.send({"t": Protocol.PING})
	server.tick()
	assert_false(client.is_open(), "passou do limite: desconectado")


func test_watcher_needs_a_slot_too() -> void:
	var transport: LocalTransport = LocalTransport.new()
	var server: Server = Server.new(transport, Clock.new(true), {"slots": 110})
	var ana: LocalTransport.Endpoint = transport.connect_client()
	var caio: LocalTransport.Endpoint = transport.connect_client()
	ana.send({"t": Protocol.HELLO, "v": Protocol.VERSION, "nick": "Ana", "avatar": 0, "device": "a"})
	caio.send({"t": Protocol.HELLO, "v": Protocol.VERSION, "nick": "Caio", "avatar": 0, "device": "c"})
	ana.send({"t": Protocol.CREATE_ROOM, "options": {"seats": 6}})
	server.tick()
	var room_id: String = server.rooms.keys()[0]
	caio.send({"t": Protocol.JOIN_ROOM, "room": room_id, "spectate": true})
	server.tick()
	var answers: Array = caio.poll().filter(func(m: Dictionary) -> bool: return m["t"] == Protocol.ERROR)
	assert_eq(answers.size(), 1, "1 vaga + 0,2 do espectador passa de 1,1")
	assert_eq(answers[0].get("code"), Protocol.E_FULL)
	assert_eq(server.used_slots(), 100)


func _http_get(port: int, path: String) -> String:
	var raw: StreamPeerTCP = StreamPeerTCP.new()
	raw.connect_to_host("127.0.0.1", port)
	var answer: PackedByteArray = PackedByteArray()
	var sent: Array = [false]
	_spin(func() -> void:
		_host_ref.tick()
		raw.poll()
		if raw.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			if not sent[0]:
				raw.put_data(("GET %s HTTP/1.1\r\nHost: x\r\n\r\n" % path).to_utf8_buffer())
				sent[0] = true
			var available: int = raw.get_available_bytes()
			if available > 0:
				answer.append_array(raw.get_data(available)[1]),
		func() -> bool: return sent[0] and raw.get_status() != StreamPeerTCP.STATUS_CONNECTED)
	var text: String = answer.get_string_from_utf8()
	return text.substr(text.find("\r\n\r\n") + 4)


var _host_ref: RemoteHost = null


func _create(client: WsClient, seats: int) -> Dictionary:
	var got: Array = []
	client.send({"t": Protocol.CREATE_ROOM, "options": {"seats": seats}})
	_spin(func() -> void:
		_host_ref.tick()
		got.append_array(client.poll()),
		func() -> bool: return got.any(func(m: Dictionary) -> bool:
			return m["t"] in [Protocol.JOINED, Protocol.ERROR]))
	return got.filter(func(m: Dictionary) -> bool: return m["t"] in [Protocol.JOINED, Protocol.ERROR])[0]


func _greeted_client(nick: String) -> WsClient:
	var client: WsClient = WsClient.new()
	client.open("127.0.0.1", _host_ref.ws.port)
	var got: Array = []
	_spin(func() -> void:
		_host_ref.tick()
		if client.is_open() and got.is_empty():
			client.send({"t": Protocol.HELLO, "v": Protocol.VERSION, "nick": nick, "avatar": 1,
				"device": "dev-" + nick})
			got.append({})
		got.append_array(client.poll()),
		func() -> bool: return got.any(func(m: Dictionary) -> bool: return m.get("t") == Protocol.WELCOME))
	return client


func test_remote_host_slots_and_http() -> void:
	_host_ref = RemoteHost.new(null, {"slots": 150, "max_rooms": 10, "room": FAST})
	assert_eq(_host_ref.listen(0, "127.0.0.1"), OK)
	assert_eq(_http_get(_host_ref.ws.port, "/saude"), "ok")
	var load: Dictionary = JSON.parse_string(_http_get(_host_ref.ws.port, "/lotacao"))
	assert_eq(load, {"v": float(Protocol.VERSION), "pct": 0.0, "full": false}, "lotação vazia")
	var ana: WsClient = _greeted_client("Ana")
	assert_eq(_create(ana, 6)["t"], Protocol.JOINED, "mesa de 6 cabe")
	var bia: WsClient = _greeted_client("Bia")
	var refused: Dictionary = _create(bia, 6)
	assert_eq(refused.get("code"), Protocol.E_FULL, "outra de 6 não cabe nas 1,5 vaga")
	assert_eq(_create(bia, 2)["t"], Protocol.JOINED, "a de 2 cabe")
	load = JSON.parse_string(_http_get(_host_ref.ws.port, "/lotacao"))
	assert_eq(int(load["pct"]), 80, "1,2 de 1,5 vaga")
	assert_false(load["full"], "ainda cabe uma de 2")
	var status: Dictionary = JSON.parse_string(_http_get(_host_ref.ws.port, "/estado"))
	assert_eq(int(status["salas"]), 2)
	assert_eq(int(status["apresentadas"]), 2)
	assert_true(_http_get(_host_ref.ws.port, "/x").contains("não encontrado"))
	ana.close()
	bia.close()
	_host_ref.ws.stop()
	_host_ref = null
