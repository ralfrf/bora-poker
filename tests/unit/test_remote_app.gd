extends "res://tests/test_case.gd"
## À distância, parte do app (SPEC 9.3): senha da sala e limite de tentativas, lista de
## salas, pergunta da lotação (GET /lotacao) e a sessão do app que entra, cai e volta.

const Room := preload("res://server/room.gd")
const Server := preload("res://server/server.gd")
const Clock := preload("res://server/clock.gd")
const Protocol := preload("res://server/protocol.gd")
const Codec := preload("res://net/codec.gd")
const LocalTransport := preload("res://net/local_transport.gd")
const RemoteHost := preload("res://net/remote_host.gd")
const LoadProbe := preload("res://net/load_probe.gd")
const PasswordGuard := preload("res://server/password_guard.gd")
const RemoteGame := preload("res://ui/app/remote_game.gd")

const FAST: Dictionary = {"hand_gap_ms": 0, "showdown_gap_ms": 0, "bot_min_ms": 0, "bot_max_ms": 0,
	"bot_evaluations": 120}


func _spin(step: Callable, done: Callable, ms: int = 4000) -> bool:
	var until: int = Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < until:
		step.call()
		if done.call():
			return true
		OS.delay_msec(2)
	return false


func _hello(client: LocalTransport.Endpoint, nick: String, device: String) -> void:
	client.send({"t": Protocol.HELLO, "v": Protocol.VERSION, "nick": nick, "avatar": 0, "device": device})


func _errors(client: LocalTransport.Endpoint) -> Array:
	return client.poll().filter(func(m: Dictionary) -> bool: return m["t"] == Protocol.ERROR)


func _try(server: Server, client: LocalTransport.Endpoint, room_id: String, password: String) -> Dictionary:
	client.poll()
	client.send({"t": Protocol.JOIN_ROOM, "room": room_id, "spectate": false, "password": password})
	server.tick()
	for message: Dictionary in client.poll():
		if message["t"] in [Protocol.ERROR, Protocol.JOINED]:
			return message
	return {}


func test_password_option_never_leaves_the_server() -> void:
	assert_false(Room.normalize_options({"password": "12a4"})["ok"], "só números")
	assert_false(Room.normalize_options({"password": "123"})["ok"], "4 números")
	assert_false(Room.normalize_options({"password": 1234})["ok"], "texto, não número")
	assert_true(Room.normalize_options({"password": ""})["ok"], "sem senha")
	var clock: Clock = Clock.new(true)
	var transport: LocalTransport = LocalTransport.new()
	var server: Server = Server.new(transport, clock, {"room": FAST})
	var ana: LocalTransport.Endpoint = transport.connect_client()
	_hello(ana, "Ana", "dev-ana")
	ana.send({"t": Protocol.CREATE_ROOM, "options": {"seats": 3, "password": "8642"}})
	server.tick()
	var room: Room = server.rooms.values()[0]
	assert_false(room.options.has("password"), "a senha não fica nas opções")
	assert_true(room.has_password())
	var bia: LocalTransport.Endpoint = transport.connect_client()
	_hello(bia, "Bia", "dev-bia")
	bia.send({"t": Protocol.LIST_ROOMS})
	server.tick()
	assert_eq(_try(server, bia, room.id, "8642")["t"], Protocol.JOINED, "entrou com a senha")
	ana.send({"t": Protocol.START})
	for _i in 30:
		server.tick()
	var seen: String = ""
	for client: LocalTransport.Endpoint in [ana, bia]:
		for message: Dictionary in client.poll():
			seen += Codec.encode(message)
	seen += Codec.encode(room.snapshot())
	assert_true(seen.length() > 1000, "houve mensagens para conferir")
	assert_false(seen.contains("8642"), "a senha nunca vai aos aparelhos nem ao retrato")


func test_wrong_password_waits_longer_per_device() -> void:
	var clock: Clock = Clock.new(true)
	var transport: LocalTransport = LocalTransport.new()
	var server: Server = Server.new(transport, clock, {"room": FAST})
	var ana: LocalTransport.Endpoint = transport.connect_client()
	_hello(ana, "Ana", "dev-ana")
	ana.send({"t": Protocol.CREATE_ROOM, "options": {"seats": 4, "password": "2580"}})
	server.tick()
	var room_id: String = server.rooms.keys()[0]
	var caio: LocalTransport.Endpoint = transport.connect_client()
	_hello(caio, "Caio", "dev-caio")
	server.tick()
	var asked: Dictionary = _try(server, caio, room_id, "")
	assert_eq(asked.get("code"), Protocol.E_PASSWORD, "sem senha: o servidor pede")
	assert_eq(asked.get("text"), "esta sala tem senha")
	assert_eq(int(asked.get("wait_ms", -1)), 0, "pedir não conta como errada")
	for i in PasswordGuard.DEVICE_FREE - 1:
		var wrong: Dictionary = _try(server, caio, room_id, "1111")
		assert_eq(wrong.get("text"), "senha errada", "errada %d sem espera" % (i + 1))
	var third: Dictionary = _try(server, caio, room_id, "1112")
	assert_eq(int(third.get("wait_ms", -1)), 0, "a terceira ainda não espera")
	var fourth: Dictionary = _try(server, caio, room_id, "1113")
	assert_eq(int(fourth.get("wait_ms", 0)), PasswordGuard.DEVICE_BASE_MS, "a quarta: 5 s")
	assert_eq(fourth.get("text"), "senha errada; espere 5 s para tentar de novo")
	var blocked: Dictionary = _try(server, caio, room_id, "2580")
	assert_eq(blocked.get("code"), Protocol.E_PASSWORD, "durante a espera nem a certa entra")
	assert_true(str(blocked.get("text")).begins_with("muitas tentativas erradas"))
	clock.advance(PasswordGuard.DEVICE_BASE_MS)
	var fifth: Dictionary = _try(server, caio, room_id, "1114")
	assert_eq(int(fifth.get("wait_ms", 0)), PasswordGuard.DEVICE_BASE_MS * 2, "a espera dobra")
	clock.advance(PasswordGuard.DEVICE_BASE_MS * 2)
	assert_eq(_try(server, caio, room_id, "2580")["t"], Protocol.JOINED, "passada a espera, a certa entra")
	# Quem caiu volta sem digitar a senha de novo.
	var room: Room = server.rooms[room_id]
	caio.close()
	server.tick()
	var again: LocalTransport.Endpoint = transport.connect_client()
	_hello(again, "Caio", "dev-caio")
	server.tick()
	var back: Dictionary = _try(server, again, room_id, "")
	assert_eq(back["t"], Protocol.JOINED, "volta sem senha")
	assert_true(back.get("resumed", false), "mesmo lugar")
	assert_eq(room.members.size(), 2)


## Transporte local que diz o IP de cada conexão (como o do servidor à distância).
class IpTransport:
	extends "res://net/local_transport.gd"

	var ips: Dictionary = {}   ## peer -> IP

	func peer_ip(peer: int) -> String:
		return str(ips.get(peer, "198.51.100.1"))


func test_ip_limit_against_new_device_codes() -> void:
	var clock: Clock = Clock.new(true)
	var transport: IpTransport = IpTransport.new()
	var server: Server = Server.new(transport, clock, {"room": FAST})
	var ana: LocalTransport.Endpoint = transport.connect_client()
	_hello(ana, "Ana", "dev-ana")
	ana.send({"t": Protocol.CREATE_ROOM, "options": {"seats": 4, "password": "2580"}})
	server.tick()
	var room_id: String = server.rooms.keys()[0]
	var last: Dictionary = {}
	for i in PasswordGuard.IP_FREE + 1:
		var thief: LocalTransport.Endpoint = transport.connect_client()
		transport.ips[thief.peer] = "203.0.113.9"
		_hello(thief, "X", "falso-%d" % i)   # um código de aparelho novo a cada tentativa
		server.tick()
		last = _try(server, thief, room_id, "%04d" % i)
	assert_eq(int(last.get("wait_ms", 0)), PasswordGuard.IP_BASE_MS, "o IP passa a esperar")
	var same_ip: LocalTransport.Endpoint = transport.connect_client()
	transport.ips[same_ip.peer] = "203.0.113.9"
	_hello(same_ip, "Y", "falso-novo")
	server.tick()
	assert_eq(_try(server, same_ip, room_id, "2580").get("code"), Protocol.E_PASSWORD,
		"do mesmo IP, nem a certa entra durante a espera")
	var friend: LocalTransport.Endpoint = transport.connect_client()
	_hello(friend, "Bia", "dev-bia")
	server.tick()
	assert_eq(_try(server, friend, room_id, "2580")["t"], Protocol.JOINED,
		"de outro IP, a amiga entra: quem erra de propósito não tranca a sala")
	# A sala fecha: as contas dela somem.
	server.rooms[room_id].close(Protocol.R_OWNER)
	server.tick()
	assert_eq(server.get("_guard").wait_ms(room_id, "falso-0", "203.0.113.9"), 0)


func test_remote_list_shows_only_open_rooms_with_details() -> void:
	var clock: Clock = Clock.new(true)
	var transport: LocalTransport = LocalTransport.new()
	var server: Server = Server.new(transport, clock, {"room": FAST, "list_open_only": true})
	var specs: Array = [
		{"seats": 3, "password": "1234", "small_blind": 25, "big_blind": 50},   # aguardando, com senha
		{"seats": 2, "keep_open": false, "bots": [1]},                          # em partida, sem vaga
		{"seats": 3, "keep_open": true, "bots": [1]},                           # em partida, com vaga
		{"seats": 2, "bots": [1]},                                              # cheia, aguardando
	]
	var owners: Array[LocalTransport.Endpoint] = []
	for i in specs.size():
		var client: LocalTransport.Endpoint = transport.connect_client()
		_hello(client, "Dono%d" % i, "dev-%d" % i)
		client.send({"t": Protocol.CREATE_ROOM, "options": specs[i]})
		server.tick()
		owners.append(client)
	for i in [1, 2]:
		owners[i].send({"t": Protocol.START})
	server.tick()
	var viewer: LocalTransport.Endpoint = transport.connect_client()
	_hello(viewer, "Eva", "dev-eva")
	viewer.send({"t": Protocol.LIST_ROOMS})
	server.tick()
	var rooms: Array = []
	for message: Dictionary in viewer.poll():
		if message["t"] == Protocol.ROOMS:
			rooms = message["rooms"]
	var owners_listed: Array = rooms.map(func(r: Dictionary) -> String: return r["owner"])
	owners_listed.sort()
	assert_eq(owners_listed, ["Dono0", "Dono2"], "só a que aguarda com vaga e a aberta em partida")
	for room: Dictionary in rooms:
		assert_false(room.has("password"), "a senha não vai na lista")
		if room["owner"] == "Dono0":
			assert_true(room["locked"], "cadeado")
			assert_eq([room["small_blind"], room["big_blind"]], [25, 50], "blinds")
			assert_eq(room["phase"], Protocol.LOBBY)
		else:
			assert_false(room["locked"])
			assert_eq(room["phase"], Protocol.PLAYING)


func test_load_probe_addresses() -> void:
	assert_eq(LoadProbe.normalize(""), LoadProbe.DEFAULT_URL, "vazio = o padrão")
	assert_eq(LoadProbe.normalize(" bora-poker.onrender.com/ "), "wss://bora-poker.onrender.com")
	assert_eq(LoadProbe.normalize("https://x.com"), "wss://x.com")
	assert_eq(LoadProbe.normalize("http://10.0.0.2:8090"), "ws://10.0.0.2:8090")
	assert_eq(LoadProbe.split("wss://bora-poker.onrender.com"),
		{"tls": true, "host": "bora-poker.onrender.com", "port": 443, "path": ""})
	assert_eq(LoadProbe.split("ws://127.0.0.1:8090/x"),
		{"tls": false, "host": "127.0.0.1", "port": 8090, "path": "/x"})
	assert_true(LoadProbe.is_valid("bora-poker.onrender.com"))
	assert_false(LoadProbe.is_valid("ws://com espaço"))
	assert_false(LoadProbe.is_valid("ws://h:99999"))


func test_load_probe_reads_remote_host() -> void:
	var host: RemoteHost = RemoteHost.new(null, {"slots": 500, "room": FAST})
	assert_eq(host.listen(0, "127.0.0.1"), OK)
	var probe: LoadProbe = LoadProbe.new("ws://127.0.0.1:%d" % host.ws.port)
	var states: Array = []
	assert_true(_spin(func() -> void:
		host.tick()
		probe.poll()
		states.append(probe.state),
		func() -> bool: return probe.state == LoadProbe.State.READY), "respondeu")
	assert_false(states.has(LoadProbe.State.WAKING),
		"servidor acordado: nunca mostra o aviso de espera")
	assert_eq(probe.pct, 0)
	assert_false(probe.full)
	probe.close()
	host.ws.stop()


func test_load_probe_wakes_then_gives_up() -> void:
	var clock: Clock = Clock.new(true)
	var silent: TCPServer = TCPServer.new()   # aceita a conexão e nunca responde
	silent.listen(0, "127.0.0.1")
	var probe: LoadProbe = LoadProbe.new("ws://127.0.0.1:%d" % silent.get_local_port(), clock)
	probe.poll()
	assert_eq(probe.state, LoadProbe.State.ASKING, "os primeiros 3 s: conectando")
	clock.advance(LoadProbe.WAKE_NOTICE_MS)
	probe.poll()
	assert_eq(probe.state, LoadProbe.State.WAKING, "sem resposta em 3 s: acordando")
	for _i in 200:
		clock.advance(1000)
		probe.poll()
		if probe.state == LoadProbe.State.DOWN:
			break
	assert_eq(probe.state, LoadProbe.State.DOWN, "2 minutos sem resposta: em manutenção")
	probe.close()
	silent.stop()


func test_remote_game_backoff_and_give_up() -> void:
	var clock: Clock = Clock.new(true)
	var silent: TCPServer = TCPServer.new()   # aceita a conexão e nunca responde
	silent.listen(0, "127.0.0.1")
	var game: RemoteGame = RemoteGame.new(clock)
	game.open("ws://127.0.0.1:%d" % silent.get_local_port(), "Ana", 0, "dev-ana")
	assert_eq(game.status_text(), "Conectando ao servidor…")
	var delays: Array[int] = []
	var scheduled: int = -1
	var woke: bool = false
	for _i in 4000:
		clock.advance(250)
		game.update()
		woke = woke or game.waking()
		var retry_at: int = int(game.get("_retry_at"))
		if retry_at >= 0 and retry_at != scheduled:
			delays.append(retry_at - clock.now_ms())
		scheduled = retry_at
		if game.failed():
			break
	assert_true(woke, "mostrou que o servidor está acordando")
	assert_true(game.failed(), "desistiu")
	assert_eq(game.error_text, "O servidor não respondeu. Tente de novo daqui a pouco.")
	assert_true(clock.now_ms() >= RemoteGame.GIVE_UP_MS, "depois de 2 minutos")
	assert_eq(delays.slice(0, 5), [1000, 2000, 4000, 8000, 10000] as Array[int],
		"espera crescente: 1, 2, 4, 8 e depois 10 s")
	silent.stop()


func test_remote_game_joins_with_password_and_comes_back() -> void:
	var host: RemoteHost = RemoteHost.new(null, {"room": FAST})
	assert_eq(host.listen(0, "127.0.0.1"), OK)
	var address: String = "ws://127.0.0.1:%d" % host.ws.port
	var ana: RemoteGame = RemoteGame.new()
	ana.open(address, "Ana", 1, "dev-ana")
	ana.create({"seats": 3}, "4321")
	var bia: RemoteGame = RemoteGame.new()
	bia.open(address, "Bia", 2, "dev-bia")
	var step: Callable = func() -> void:
		host.tick()
		ana.update()
		bia.update()
	assert_true(_spin(step, func() -> bool: return ana.room_id != "" and bia.rooms.size() == 1),
		"sala criada e listada")
	assert_true(bia.rooms[0]["locked"], "a lista mostra o cadeado")
	bia.join_room(ana.room_id, "0000")
	var got: Array = []
	assert_true(_spin(func() -> void:
		host.tick()
		ana.update()
		got.append_array(bia.update()),
		func() -> bool: return got.any(func(m: Dictionary) -> bool: return m["t"] == Protocol.ERROR)))
	assert_false(bia.failed(), "senha errada não derruba a sessão")
	assert_false(bia.joining())
	bia.join_room(ana.room_id, "4321")
	assert_true(_spin(step, func() -> bool: return bia.my_id != ""), "entrou")
	var first_id: String = bia.my_id
	# A conexão cai (troca do Wi-Fi para os dados móveis): o servidor só percebe depois.
	host.ws.drop((host.ws.get("_peers") as Dictionary).keys().max())
	assert_true(_spin(step, func() -> bool: return bia.link == RemoteGame.Link.RECONNECTING),
		"percebeu a queda")
	assert_eq(bia.status_text(), "Conexão perdida. Reconectando…")
	assert_true(bia.waiting_host(), "a mesa fica parada na tela")
	var back: Callable = func() -> bool:
		return bia.link == RemoteGame.Link.ONLINE and bia.reconnects == 1 and _connected(bia)
	assert_true(_spin(step, back, 5000), "voltou sozinho")
	assert_eq(bia.my_id, first_id, "mesmo participante")
	assert_eq(bia.room_id, ana.room_id)
	ana.shutdown()
	bia.shutdown()
	host.ws.stop()


static func _connected(game: RemoteGame) -> bool:
	for member: Dictionary in game.last_state.get("room", {}).get("members", []):
		if member.get("id") == game.my_id:
			return bool(member.get("connected", false))
	return false


func test_remote_game_room_gone_on_return() -> void:
	var host: RemoteHost = RemoteHost.new(null, {"room": FAST})
	assert_eq(host.listen(0, "127.0.0.1"), OK)
	var ana: RemoteGame = RemoteGame.new()
	ana.open("ws://127.0.0.1:%d" % host.ws.port, "Ana", 1, "dev-ana")
	ana.create({"seats": 2})
	assert_true(_spin(func() -> void:
		host.tick()
		ana.update(), func() -> bool: return ana.room_id != ""))
	# O servidor reiniciou e perdeu a sala ainda na sala de espera: sem mão jogada, não
	# há resumo para recriá-la (SPEC 9.4; a recuperação está em test_recovery.gd).
	host.server.rooms.clear()
	host.ws.drop((host.ws.get("_peers") as Dictionary).keys().max())
	assert_true(_spin(func() -> void:
		host.tick()
		ana.update(), func() -> bool: return ana.failed(), 5000))
	assert_eq(ana.failure(), "A sala foi encerrada.")
	host.ws.stop()


func test_remote_game_does_not_create_twice() -> void:
	var host: RemoteHost = RemoteHost.new(null, {"room": FAST})
	assert_eq(host.listen(0, "127.0.0.1"), OK)
	var ana: RemoteGame = RemoteGame.new()
	ana.open("ws://127.0.0.1:%d" % host.ws.port, "Ana", 1, "dev-ana")
	var greeted: Callable = func() -> bool:
		return ana.link == RemoteGame.Link.ONLINE and bool(ana.get("_greeted"))
	assert_true(_spin(func() -> void:
		host.tick()
		ana.update(), greeted))
	ana.create({"seats": 2})
	# O pedido sai, mas a conexão cai antes de o "joined" chegar.
	ana.update()
	host.tick()
	host.ws.drop((host.ws.get("_peers") as Dictionary).keys().max())
	assert_true(_spin(func() -> void:
		host.tick()
		ana.update(), func() -> bool: return ana.failed() or ana.room_id != ""))
	if ana.room_id == "":
		assert_eq(ana.failure(), "A conexão caiu enquanto a sala era criada. Tente de novo.")
	assert_true(host.server.rooms.size() <= 1, "nunca duas salas")
	host.ws.stop()


func test_load_probe_offline_when_address_not_found() -> void:
	# .invalid nunca existe (RFC 2606): é o que o celular vê sem internet.
	var probe: LoadProbe = LoadProbe.new("wss://bora-poker-teste.invalid")
	assert_true(_spin(func() -> void: probe.poll(),
		func() -> bool: return probe.state == LoadProbe.State.OFFLINE, 15000),
		"endereço não encontrado: sem internet, sem esperar os 2 minutos")
	# A internet volta: a próxima tentativa encontra o servidor e mostra a lotação.
	var host: RemoteHost = RemoteHost.new(null, {"room": FAST})
	assert_eq(host.listen(0, "127.0.0.1"), OK)
	probe.set("_host", "127.0.0.1")
	probe.set("_port", host.ws.port)
	probe.set("_tls", false)
	assert_true(_spin(func() -> void:
		host.tick()
		probe.poll(), func() -> bool: return probe.state == LoadProbe.State.READY, 6000),
		"internet de volta: lotação")
	probe.close()
	host.ws.stop()


func test_load_probe_back_to_waking_when_server_stops() -> void:
	var host: RemoteHost = RemoteHost.new(null, {"room": FAST})
	assert_eq(host.listen(0, "127.0.0.1"), OK)
	var clock: Clock = Clock.new(true)
	var probe: LoadProbe = LoadProbe.new("ws://127.0.0.1:%d" % host.ws.port, clock)
	assert_true(_spin(func() -> void:
		host.tick()
		probe.poll(), func() -> bool: return probe.state == LoadProbe.State.READY))
	host.ws.stop()
	clock.advance(LoadProbe.REFRESH_MS)
	assert_true(_spin(func() -> void:
		clock.advance(100)
		probe.poll(), func() -> bool: return probe.state != LoadProbe.State.READY))
	assert_eq(probe.state, LoadProbe.State.WAKING, "parou de responder: acordando de novo")
	probe.close()


func test_load_probe_once_asks_a_single_time() -> void:
	var clock: Clock = Clock.new(true)
	var silent: TCPServer = TCPServer.new()   # aceita a conexão e nunca responde
	silent.listen(0, "127.0.0.1")
	var probe: LoadProbe = LoadProbe.new("ws://127.0.0.1:%d" % silent.get_local_port(), clock)
	probe.once = true
	probe.poll()
	assert_false(probe.finished(), "perguntando")
	clock.advance(LoadProbe.ATTEMPT_MS + 1)
	probe.poll()
	assert_true(probe.finished(), "sem resposta: desiste sem insistir")
	clock.advance(LoadProbe.GIVE_UP_MS)
	probe.poll()
	assert_true(probe.finished(), "e não pergunta de novo")
	silent.stop()
	var host: RemoteHost = RemoteHost.new(null, {"room": FAST})
	assert_eq(host.listen(0, "127.0.0.1"), OK)
	var awake: LoadProbe = LoadProbe.new("ws://127.0.0.1:%d" % host.ws.port)
	awake.once = true
	assert_true(_spin(func() -> void:
		host.tick()
		awake.poll(), func() -> bool: return awake.finished()))
	assert_eq(awake.state, LoadProbe.State.READY, "respondeu uma vez e parou")
	host.ws.stop()


func test_list_shows_room_to_return_even_when_closed_to_new_people() -> void:
	var transport: LocalTransport = LocalTransport.new()
	var server: Server = Server.new(transport, Clock.new(true),
		{"room": FAST, "list_open_only": true})
	var ana: LocalTransport.Endpoint = transport.connect_client()
	var bia: LocalTransport.Endpoint = transport.connect_client()
	_hello(ana, "Ana", "dev-ana")
	_hello(bia, "Bia", "dev-bia")
	server.tick()
	ana.send({"t": Protocol.CREATE_ROOM, "options": {"seats": 3, "format": "tournament",
		"turn_seconds": 0}})
	server.tick()
	var room_id: String = server.rooms.keys()[0]
	bia.send({"t": Protocol.JOIN_ROOM, "room": room_id, "spectate": false})
	server.tick()
	var bia_id: String = ""
	for message: Dictionary in bia.poll():
		if message["t"] == Protocol.JOINED:
			bia_id = message["you"]
	ana.send({"t": Protocol.START})
	server.tick()
	# O app de Bia fecha; ela abre de novo e pede a lista.
	bia.close()
	server.tick()
	var again: LocalTransport.Endpoint = transport.connect_client()
	var caio: LocalTransport.Endpoint = transport.connect_client()
	_hello(again, "Bia", "dev-bia")
	_hello(caio, "Caio", "dev-caio")
	server.tick()
	again.poll()
	caio.poll()
	again.send({"t": Protocol.LIST_ROOMS})
	caio.send({"t": Protocol.LIST_ROOMS})
	server.tick()
	var lists: Array = []
	for end: LocalTransport.Endpoint in [again, caio]:
		for message: Dictionary in end.poll():
			if message["t"] == Protocol.ROOMS:
				lists.append(message["rooms"])
	assert_eq(lists[0].size(), 1, "Bia vê o torneio de onde caiu")
	assert_true(lists[0][0].get("back", false), "marcado para voltar")
	assert_eq(lists[1].size(), 0, "quem nunca esteve lá não vê o torneio em andamento")
	again.send({"t": Protocol.JOIN_ROOM, "room": room_id, "spectate": false})
	server.tick()
	var joined: Dictionary = {}
	for message: Dictionary in again.poll():
		if message["t"] == Protocol.JOINED:
			joined = message
	assert_eq(joined.get("you"), bia_id, "volta para o mesmo lugar")
	assert_true(joined.get("resumed", false))
