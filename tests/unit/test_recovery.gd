extends "res://tests/test_case.gd"
## Recuperação depois de um reinício do servidor à distância (SPEC 9.4 e 6.6): o resumo
## assinado que vai aos celulares entre as mãos, a conferência dele (assinatura, prazo,
## quem apresenta) e a sala recriada com o resumo mais recente, com a mão cancelada.

const Room := preload("res://server/room.gd")
const Server := preload("res://server/server.gd")
const Clock := preload("res://server/clock.gd")
const Protocol := preload("res://server/protocol.gd")
const Summary := preload("res://server/summary.gd")
const Hand := preload("res://engine/hand.gd")
const LocalTransport := preload("res://net/local_transport.gd")
const RemoteHost := preload("res://net/remote_host.gd")
const RemoteGame := preload("res://ui/app/remote_game.gd")

const SECRET: String = "segredo-dos-testes"
const FAST: Dictionary = {"hand_gap_ms": 0, "showdown_gap_ms": 0, "bot_min_ms": 0, "bot_max_ms": 0,
	"bot_evaluations": 120}
const WAIT_MS: int = 6000

var _clock: Clock = null
var _seed: int = 0
## nick -> as mensagens que chegaram a esse celular
var _inbox: Dictionary = {}


class Phone:
	extends RefCounted
	var nick: String = ""
	var device: String = ""
	var end: LocalTransport.Endpoint = null


func _next_seed() -> int:
	_seed += 1
	return _seed


func _server(transport: LocalTransport) -> Server:
	return Server.new(transport, _clock, {"summary": Summary.new(SECRET), "room": FAST,
		"resume_wait_ms": WAIT_MS}, _next_seed)


func _phone(transport: LocalTransport, nick: String, device: String) -> Phone:
	var phone: Phone = Phone.new()
	phone.nick = nick
	phone.device = device
	phone.end = transport.connect_client()
	phone.end.send({"t": Protocol.HELLO, "v": Protocol.VERSION, "nick": nick, "avatar": 0,
		"device": device})
	return phone


func _read(phones: Array) -> void:
	for phone: Phone in phones:
		if not _inbox.has(phone.nick):
			_inbox[phone.nick] = []
		_inbox[phone.nick].append_array(phone.end.poll())


func _last(phone: Phone, type: String) -> Dictionary:
	var list: Array = _inbox.get(phone.nick, [])
	for i in range(list.size() - 1, -1, -1):
		if list[i]["t"] == type:
			return list[i]
	return {}


func _summaries(phone: Phone) -> Array:
	return _inbox.get(phone.nick, []).filter(
		func(m: Dictionary) -> bool: return m["t"] == Protocol.SUMMARY)


## O conteúdo do resumo (sem conferir a assinatura).
static func _body(token: String) -> Dictionary:
	return JSON.parse_string(_text(token))


static func _text(token: String) -> String:
	return Marshalls.base64_to_raw(token.split(".")[0]).decompress_dynamic(
		Summary.MAX_BODY, FileAccess.COMPRESSION_DEFLATE).get_string_from_utf8()


static func _stacks(saved_table: Dictionary) -> Dictionary:
	var stacks: Dictionary = {}
	for seat: Dictionary in saved_table["seats"]:
		if str(seat["state"]) != "out":
			stacks[str(seat["id"])] = int(seat["stack"])
	return stacks


static func _live_stacks(room: Room) -> Dictionary:
	return _stacks(JSON.parse_string(JSON.stringify(room.table.to_dict())))


## Sala de 3 com Ana (dona), Bia e Caio, partida começada, no servidor dado.
func _three(transport: LocalTransport, server: Server, password: String = "") -> Array:
	var ana: Phone = _phone(transport, "Ana", "dev-ana")
	var bia: Phone = _phone(transport, "Bia", "dev-bia")
	var caio: Phone = _phone(transport, "Caio", "dev-caio")
	server.tick()
	ana.end.send({"t": Protocol.CREATE_ROOM,
		"options": {"seats": 3, "turn_seconds": 0, "password": password}})
	server.tick()
	_read([ana, bia, caio])
	var room_id: String = str(_last(ana, Protocol.JOINED)["room"])
	for phone: Phone in [bia, caio]:
		phone.end.send({"t": Protocol.JOIN_ROOM, "room": room_id, "spectate": false,
			"password": password})
	server.tick()
	ana.end.send({"t": Protocol.START})
	server.tick()
	_read([ana, bia, caio])
	return [room_id, ana, bia, caio]


## Quem está na vez desiste (ou passa), até done() ou o limite de passos.
func _play(server: Server, room: Room, phones: Array, done: Callable, check: bool = false) -> void:
	for _i in 400:
		server.tick()
		_read(phones)
		if done.call():
			return
		if room.table.hand_in_progress():
			var member: Room.Member = room.member_at(room.table.hand.to_act)
			var legal: Dictionary = room.table.hand.legal_actions()
			var action: String = Hand.FOLD
			if check and legal.get("can_check", false):
				action = Hand.CHECK
			elif check:
				action = Hand.CALL
			room.handle(member.id, {"t": Protocol.ACT, "seq": int(room.get("_seq")),
				"action": action, "amount": 0})
	fail("o jogo não chegou aonde devia")


## Joga algumas mãos e para no meio de uma (com apostas na mesa). Devolve a sala.
func _into_a_hand(server: Server, room_id: String, phones: Array, hands: int) -> Room:
	var room: Room = server.rooms[room_id]
	_play(server, room, phones, func() -> bool: return room.table.hand_number >= hands)
	# A mão seguinte começa; um lance de pagar deixa fichas no meio.
	_play(server, room, phones, func() -> bool:
		return room.table.hand_in_progress() and room.table.hand_number == hands + 1, true)
	return room


func _resume(phone: Phone, room_id: String, token: String, password: String = "") -> void:
	phone.end.send({"t": Protocol.RESUME_ROOM, "room": room_id, "summary": token,
		"password": password})


func _setup() -> void:
	_clock = Clock.new(true)
	_seed = 9000
	_inbox = {}


# ---------------------------------------------------------------- assinatura


func test_summary_signature_and_validity() -> void:
	var signer: Summary = Summary.new(SECRET)
	var now: int = 1_800_000_000
	var token: String = signer.sign({"id": "ABCD"}, 3, "", now)
	assert_true(signer.open(token, now)["ok"], "o próprio servidor confere")
	assert_true(Summary.new(SECRET).open(token, now + 30)["ok"], "o servidor reiniciado também")
	assert_eq(Summary.new("outro").open(token, now)["error"], "assinatura inválida")
	# Corpo trocado (mais fichas) com a assinatura antiga.
	var parts: PackedStringArray = token.split(".")
	var body: Dictionary = _body(token)
	body["rev"] = 99
	var forged: String = Marshalls.raw_to_base64(JSON.stringify(body).to_utf8_buffer()
		.compress(FileAccess.COMPRESSION_DEFLATE)) + "." + parts[1]
	assert_eq(signer.open(forged, now)["error"], "assinatura inválida")
	var flipped: String = parts[0] + "." + ("B" if parts[1][0] == "A" else "A") + parts[1].substr(1)
	assert_eq(signer.open(flipped, now)["error"], "assinatura inválida")
	for junk: String in ["", "abc", "a.b.c", "!!!!.????", "AAAA", "AAAA.", ".AAAA", "A=AA.AAAA"]:
		assert_false(signer.open(junk, now)["ok"], "lixo recusado sem erro: '%s'" % junk)
	assert_eq(signer.open(token, now + Summary.VALID_S + 1)["error"], "resumo vencido")
	assert_true(signer.open(token, now + Summary.VALID_S)["ok"], "no limite ainda vale")
	assert_eq(signer.open(token, now - Summary.SKEW_S - 1)["error"], "resumo com hora errada")
	assert_false(Summary.new(SECRET).boot == signer.boot, "cada servidor ligado tem o seu boot")


func test_device_tag_hides_the_device_code() -> void:
	var one: Summary = Summary.new(SECRET)
	var tag: String = one.device_tag("ABCD", "dev-ana")
	assert_eq(tag.length(), Summary.TAG_LENGTH)
	assert_eq(Summary.new(SECRET).device_tag("ABCD", "dev-ana"), tag, "igual depois do reinício")
	assert_false(one.device_tag("WXYZ", "dev-ana") == tag, "muda de sala para sala")
	assert_false(Summary.new("outro").device_tag("ABCD", "dev-ana") == tag, "muda com o segredo")
	assert_eq(one.device_tag("ABCD", ""), "", "sem código, sem marca")


# ---------------------------------------------------------------- o que vai


func test_summary_after_each_hand_without_secrets() -> void:
	_setup()
	var transport: LocalTransport = LocalTransport.new()
	var server: Server = _server(transport)
	var parts: Array = _three(transport, server, "4321")
	var room_id: String = parts[0]
	var phones: Array = parts.slice(1)
	var room: Room = _into_a_hand(server, room_id, phones, 3)
	for phone: Phone in phones:
		assert_true(_summaries(phone).size() >= 3, "%s recebeu os resumos" % phone.nick)
	var ana: Phone = phones[0]
	var last: Dictionary = _summaries(ana).back()
	assert_eq(last["room"], room_id)
	var text: String = _text(str(last["s"]))
	var body: Dictionary = JSON.parse_string(text)
	assert_eq(body["room"]["table"]["hand"], null, "nenhuma carta nem o baralho")
	assert_false(text.contains("dev-ana") or text.contains("dev-bia"), "nenhum código de aparelho")
	assert_false(text.contains("4321") or text.contains("password"), "nem a senha")
	assert_eq(str(body["lock"]).length(), Summary.TAG_LENGTH, "só uma marca da senha")
	assert_eq(int(body["room"]["table"]["hand_number"]), 3, "o retrato do fim da última mão")
	assert_eq(int(body["rev"]), room.summary_rev)
	# Mão longa: o mesmo resumo sai de novo antes de vencer.
	var count: int = _summaries(ana).size()
	_clock.advance(Summary.REFRESH_S * 1000)
	server.tick()
	_read(phones)
	assert_eq(_summaries(ana).size(), count + 1, "emitido de novo numa mão longa")
	assert_eq(int(_body(str(_summaries(ana).back()["s"]))["rev"]), room.summary_rev, "mesmo conteúdo")
	assert_eq(str(_body(str(_summaries(ana).back()["s"]))["room"]["table"]), str(body["room"]["table"]))


func test_wifi_and_offline_send_no_summary() -> void:
	_setup()
	var transport: LocalTransport = LocalTransport.new()
	var server: Server = Server.new(transport, _clock, {"room": FAST}, _next_seed)
	var parts: Array = _three(transport, server)
	_into_a_hand(server, parts[0], parts.slice(1), 2)
	assert_eq(_summaries(parts[1]).size(), 0, "sem assinador, sem resumo")
	assert_false(server.rooms[parts[0]].summaries)


# ---------------------------------------------------------------- recuperação


func test_restart_restores_room_and_cancels_hand() -> void:
	_setup()
	var old_transport: LocalTransport = LocalTransport.new()
	var old_server: Server = _server(old_transport)
	var parts: Array = _three(old_transport, old_server)
	var room_id: String = parts[0]
	var old_room: Room = _into_a_hand(old_server, room_id, parts.slice(1), 3)
	var interrupted_button: int = old_room.table.button
	var interrupted_hand: int = old_room.table.hand_number
	var ids: Dictionary = {}
	for member: Room.Member in old_room.members.values():
		ids[member.nick] = member.id
	var tokens: Dictionary = {}
	for phone: Phone in parts.slice(1):
		tokens[phone.nick] = str(_summaries(phone).back()["s"])
	var expected: Dictionary = _stacks(_body(tokens["Ana"])["room"]["table"])
	assert_false(_live_stacks(old_room) == expected, "a mão interrompida tinha apostas")
	_inbox = {}
	# O servidor reinicia: memória vazia, outro boot, o mesmo segredo.
	_clock.advance(20000)
	var transport: LocalTransport = LocalTransport.new()
	var server: Server = _server(transport)
	var ana: Phone = _phone(transport, "Ana", "dev-ana")
	var bia: Phone = _phone(transport, "Bia", "dev-bia")
	var caio: Phone = _phone(transport, "Caio", "dev-caio")
	var phones: Array = [ana, bia, caio]
	server.tick()
	_resume(ana, room_id, tokens["Ana"])
	server.tick()
	_read(phones)
	assert_false(server.rooms.has(room_id), "espera os outros antes de recriar")
	assert_eq(_last(ana, Protocol.JOINED), {}, "Ana espera")
	_clock.advance(2000)
	_resume(bia, room_id, tokens["Bia"])
	server.tick()
	_clock.advance(WAIT_MS)
	server.tick()
	_read(phones)
	assert_true(server.rooms.has(room_id), "sala recriada com o mesmo código")
	var room: Room = server.rooms[room_id]
	for phone: Phone in [ana, bia]:
		var joined: Dictionary = _last(phone, Protocol.JOINED)
		assert_eq(joined.get("you"), ids[phone.nick], "%s volta como o mesmo participante" % phone.nick)
		assert_true(joined.get("resumed", false) and joined.get("restored", false))
	assert_eq(_live_stacks(room), expected, "a mão interrompida foi cancelada: fichas do resumo")
	assert_true(room.table.is_balanced(), "caixa de fichas fechada")
	assert_false(room.table.hand_in_progress())
	# Caio chega depois da espera: entra direto na sala recriada.
	_resume(caio, room_id, tokens["Caio"])
	server.tick()
	_read(phones)
	assert_eq(_last(caio, Protocol.JOINED).get("you"), ids["Caio"])
	assert_false(_last(caio, Protocol.JOINED).get("restored", false), "a sala já existia")
	# A mão seguinte repete as posições da interrompida.
	_play(server, room, phones, func() -> bool: return room.table.hand_in_progress())
	assert_eq(room.table.hand_number, interrupted_hand, "a mesma mão de novo")
	assert_eq(room.table.button, interrupted_button, "o botão volta para onde estava")
	assert_eq(room.owner_id, ids["Ana"], "o mesmo dono")
	# A sala recriada continua emitindo resumos, com a numeração adiante.
	var rev: int = int(_body(tokens["Ana"])["rev"])
	_play(server, room, phones, func() -> bool: return room.table.hand_number > interrupted_hand)
	_play(server, room, phones, func() -> bool: return _summaries(ana).size() > 0)
	assert_true(int(_body(str(_summaries(ana).back()["s"]))["rev"]) > rev, "rev continua subindo")


func test_restart_uses_newest_summary_presented() -> void:
	for old_first: bool in [true, false]:
		_setup()
		var old_transport: LocalTransport = LocalTransport.new()
		var old_server: Server = _server(old_transport)
		var parts: Array = _three(old_transport, old_server)
		var room_id: String = parts[0]
		var ana_old: Phone = parts[1]
		_into_a_hand(old_server, room_id, parts.slice(1), 2)
		var stale: String = str(_summaries(ana_old)[0]["s"])
		var fresh: String = str(_summaries(ana_old).back()["s"])
		assert_true(int(_body(stale)["rev"]) < int(_body(fresh)["rev"]))
		_inbox = {}
		_clock.advance(5000)
		var transport: LocalTransport = LocalTransport.new()
		var server: Server = _server(transport)
		var ana: Phone = _phone(transport, "Ana", "dev-ana")
		var bia: Phone = _phone(transport, "Bia", "dev-bia")
		server.tick()
		# Ana guarda um resumo antigo (de quando tinha outras fichas); Bia, o atual.
		_resume(ana if old_first else bia, room_id, stale if old_first else fresh)
		server.tick()
		_resume(bia if old_first else ana, room_id, fresh if old_first else stale)
		server.tick()
		_clock.advance(WAIT_MS)
		server.tick()
		_read([ana, bia])
		var room: Room = server.rooms[room_id]
		assert_eq(_live_stacks(room), _stacks(_body(fresh)["room"]["table"]),
			"vale o resumo mais recente (antigo %s)" % ("primeiro" if old_first else "depois"))
		assert_true(_last(ana, Protocol.JOINED).get("restored", false))


func test_resume_refusals() -> void:
	_setup()
	var old_transport: LocalTransport = LocalTransport.new()
	var old_server: Server = _server(old_transport)
	var parts: Array = _three(old_transport, old_server)
	var room_id: String = parts[0]
	_into_a_hand(old_server, room_id, parts.slice(1), 1)
	var token: String = str(_summaries(parts[1]).back()["s"])
	_inbox = {}
	# No próprio servidor que emitiu: a sala sumiu sem reinício (acabou de verdade).
	old_server.rooms.clear()
	var same: Phone = _phone(old_transport, "Ana", "dev-ana")
	old_server.tick()
	_resume(same, room_id, token)
	old_server.tick()
	_read([same])
	assert_eq(_last(same, Protocol.ERROR).get("text"), "sala não encontrada", "mesmo boot")
	# Depois de um reinício.
	var transport: LocalTransport = LocalTransport.new()
	var server: Server = _server(transport)
	var cases: Array = [
		["Ana", "dev-ana", room_id, token.left(token.length() - 6) + "AAAAA=", "assinatura inválida"],
		["Duda", "dev-duda", room_id, token, "você não consta nesta sala"],
		["Ana", "dev-bia", room_id, token, "você não consta nesta sala"],
		["Ana", "dev-ana", "ZZZZ", token, "o resumo é de outra sala"],
		["Ana", "dev-ana", room_id, "lixo", "resumo malformado"],
	]
	for item: Array in cases:
		_inbox = {}
		var phone: Phone = _phone(transport, item[0], item[1])
		server.tick()
		_resume(phone, item[2], item[3])
		server.tick()
		_read([phone])
		var error: Dictionary = _last(phone, Protocol.ERROR)
		assert_eq(error.get("code"), Protocol.E_NO_ROOM, item[4])
		assert_eq(error.get("text"), item[4])
	_clock.advance(WAIT_MS * 2)
	server.tick()
	assert_eq(server.rooms.size(), 0, "nada recriado")
	# Resumo velho demais.
	_clock.advance(Summary.VALID_S * 1000)
	var late: Phone = _phone(transport, "Ana", "dev-ana")
	server.tick()
	_resume(late, room_id, token)
	server.tick()
	_read([late])
	assert_eq(_last(late, Protocol.ERROR).get("text"), "resumo vencido")


func test_restored_room_keeps_password_locked() -> void:
	for known: String in ["4321", "", "9999"]:
		_setup()
		var old_transport: LocalTransport = LocalTransport.new()
		var old_server: Server = _server(old_transport)
		var parts: Array = _three(old_transport, old_server, "4321")
		var room_id: String = parts[0]
		_into_a_hand(old_server, room_id, parts.slice(1), 1)
		var token: String = str(_summaries(parts[2]).back()["s"])
		_inbox = {}
		var transport: LocalTransport = LocalTransport.new()
		var server: Server = _server(transport)
		var bia: Phone = _phone(transport, "Bia", "dev-bia")
		server.tick()
		_resume(bia, room_id, token, known)
		server.tick()
		_clock.advance(WAIT_MS)
		server.tick()
		var room: Room = server.rooms[room_id]
		assert_true(room.has_password(), "continua com cadeado")
		assert_eq(room.password_matches("4321"), known == "4321", "senha devolvida: '%s'" % known)
		assert_false(room.password_matches("9999"), "senha inventada não vale")
		assert_false(room.password_matches(Room.LOCKED), "a trava não é senha")
		assert_true(room.needs_password(Summary.new(SECRET).device_tag(room_id, "dev-duda"), "Duda"))
		# O próximo resumo continua trancado, mesmo sem a sala saber a senha.
		server.tick()
		_read([bia])
		var next: Dictionary = _body(str(_last(bia, Protocol.SUMMARY)["s"]))
		assert_eq(next["lock"], _body(token)["lock"], "a marca da senha segue")
		assert_true(int(next["at"]) >= int(_body(token)["at"]), "assinado de novo ao voltar")


func test_room_ended_after_restart_does_not_come_back() -> void:
	_setup()
	var old_transport: LocalTransport = LocalTransport.new()
	var old_server: Server = _server(old_transport)
	var parts: Array = _three(old_transport, old_server)
	var room_id: String = parts[0]
	_into_a_hand(old_server, room_id, parts.slice(1), 1)
	var token: String = str(_summaries(parts[1]).back()["s"])
	var caio_token: String = str(_summaries(parts[3]).back()["s"])
	_inbox = {}
	var transport: LocalTransport = LocalTransport.new()
	var server: Server = _server(transport)
	var ana: Phone = _phone(transport, "Ana", "dev-ana")
	server.tick()
	_resume(ana, room_id, token)
	server.tick()
	_clock.advance(WAIT_MS)
	server.tick()
	assert_true(server.rooms.has(room_id))
	# A sala recriada acaba de verdade (o dono encerra).
	server.rooms[room_id].close(Protocol.R_OWNER)
	server.tick()
	assert_false(server.rooms.has(room_id))
	var caio: Phone = _phone(transport, "Caio", "dev-caio")
	server.tick()
	_resume(caio, room_id, caio_token)
	server.tick()
	_clock.advance(WAIT_MS)
	server.tick()
	_read([caio])
	assert_eq(_last(caio, Protocol.ERROR).get("text"), "sala não encontrada",
		"resumo de antes do reinício não traz de volta a sala encerrada")
	assert_false(server.rooms.has(room_id))


func test_wait_ends_without_anyone_left() -> void:
	_setup()
	var old_transport: LocalTransport = LocalTransport.new()
	var old_server: Server = _server(old_transport)
	var parts: Array = _three(old_transport, old_server)
	_into_a_hand(old_server, parts[0], parts.slice(1), 1)
	var token: String = str(_summaries(parts[1]).back()["s"])
	var transport: LocalTransport = LocalTransport.new()
	var server: Server = _server(transport)
	var ana: Phone = _phone(transport, "Ana", "dev-ana")
	server.tick()
	_resume(ana, parts[0], token)
	server.tick()
	ana.end.close()
	_clock.advance(WAIT_MS)
	server.tick()
	server.tick()
	assert_eq(server.rooms.size(), 0, "ninguém esperando: a sala não volta")


# ---------------------------------------------------------------- o app


func test_app_returns_after_server_restart() -> void:
	var host: RemoteHost = RemoteHost.new(null, {"room": FAST, "summary_secret": SECRET})
	assert_eq(host.listen(0, "127.0.0.1"), OK)
	var ana: RemoteGame = RemoteGame.new()
	ana.open("ws://127.0.0.1:%d" % host.ws.port, "Ana", 1, "dev-ana")
	ana.create({"seats": 3, "turn_seconds": 0})
	var bia: RemoteGame = RemoteGame.new()
	bia.open("ws://127.0.0.1:%d" % host.ws.port, "Bia", 2, "dev-bia")
	var games: Array = [ana, bia]
	var step: Callable = func() -> void:
		host.tick()
		for game: RemoteGame in games:
			game.update()
	assert_true(_spin(step, func() -> bool: return ana.room_id != "" and bia.rooms.size() == 1))
	bia.join_room(ana.room_id)
	assert_true(_spin(step, func() -> bool: return bia.my_id != ""))
	ana.start()
	var room: Room = host.server.rooms[ana.room_id]
	var folds: Callable = func() -> void:
		step.call()
		if room.table.hand_in_progress():
			var member: Room.Member = room.member_at(room.table.hand.to_act)
			room.handle(member.id, {"t": Protocol.ACT, "seq": int(room.get("_seq")),
				"action": Hand.FOLD, "amount": 0})
	var have_summary: Callable = func() -> bool:
		return room.table.hand_number >= 2 and bia.get("_summary") != "" and ana.get("_summary") != ""
	assert_true(_spin(folds, have_summary), "os dois celulares têm o resumo")
	var ids: Array = [ana.my_id, bia.my_id]
	# O serviço reinicia (deploy): outro processo, o mesmo segredo.
	host.ws.stop()
	var again: RemoteHost = RemoteHost.new(null,
		{"room": FAST, "summary_secret": SECRET, "resume_wait_ms": 300})
	assert_eq(again.listen(0, "127.0.0.1"), OK)
	for game: RemoteGame in games:
		game.url = "ws://127.0.0.1:%d" % again.ws.port
	var step_again: Callable = func() -> void:
		again.tick()
		for game: RemoteGame in games:
			game.update()
	var both_back: Callable = func() -> bool:
		return (ana.status_text() == RemoteGame.RESTORED_NOTICE
			and bia.status_text() == RemoteGame.RESTORED_NOTICE)
	assert_true(_spin(step_again, both_back, 15000), "a mesa volta nos dois")
	assert_eq([ana.my_id, bia.my_id], ids, "os mesmos lugares")
	assert_false(ana.failed() or bia.failed())
	assert_true(again.server.rooms.has(ana.room_id))
	for game: RemoteGame in games:
		game.shutdown()
	again.ws.stop()


func _spin(step: Callable, done: Callable, ms: int = 4000) -> bool:
	var until: int = Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < until:
		step.call()
		if done.call():
			return true
		OS.delay_msec(2)
	return false
