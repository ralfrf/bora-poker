extends "res://tests/test_case.gd"
## Servidor de salas com o transporte local (inclusive passando por JSON) e a visão por
## jogador: ninguém recebe o que não pode ver.

const Server := preload("res://server/server.gd")
const Room := preload("res://server/room.gd")
const Clock := preload("res://server/clock.gd")
const Protocol := preload("res://server/protocol.gd")
const View := preload("res://server/view.gd")
const LocalTransport := preload("res://net/local_transport.gd")
const Codec := preload("res://net/codec.gd")
const Table := preload("res://engine/table.gd")
const Hand := preload("res://engine/hand.gd")

const FAST: Dictionary = {"hand_gap_ms": 0, "showdown_gap_ms": 0, "bot_min_ms": 0, "bot_max_ms": 0,
	"bot_evaluations": 120}

var _seed: int = 0


func _next_seed() -> int:
	_seed += 1
	return _seed


func _server(transport: LocalTransport, config: Dictionary = {}) -> Server:
	_seed = 500
	var full: Dictionary = {"room": FAST}
	full.merge(config, true)
	return Server.new(transport, Clock.new(true), full, _next_seed)


func _hello(client: Object, nick: String, device: String = "") -> void:
	client.send({"t": Protocol.HELLO, "v": Protocol.VERSION, "nick": nick, "avatar": 1, "device": device})


func _last(messages: Array, type: String) -> Dictionary:
	for i in range(messages.size() - 1, -1, -1):
		if messages[i]["t"] == type:
			return messages[i]
	return {}


func _drain(server: Server, clients: Array, boxes: Array) -> void:
	server.tick()
	for i in clients.size():
		boxes[i].append_array(clients[i].poll())


# ---------------------------------------------------------------- servidor


func test_hello_is_required_and_version_checked() -> void:
	var transport: LocalTransport = LocalTransport.new()
	var server: Server = _server(transport)
	var client: Object = transport.connect_client()
	var box: Array = []
	client.send({"t": Protocol.LIST_ROOMS})
	client.send({"t": Protocol.PING})
	_drain(server, [client], [box])
	assert_eq(_last(box, Protocol.ERROR).get("code"), Protocol.E_NO_HELLO)
	assert_false(_last(box, Protocol.PONG).is_empty(), "ping responde sem apresentação")
	client.send({"t": Protocol.HELLO, "v": 99, "nick": "Ana"})
	_drain(server, [client], [box])
	assert_eq(_last(box, Protocol.ERROR).get("code"), Protocol.E_VERSION)
	assert_eq(_last(box, Protocol.ERROR).get("text"), "Atualize o app.")
	assert_false(client.is_open(), "versão errada: conexão encerrada")


func test_create_list_join_and_play_through_json() -> void:
	var transport: LocalTransport = LocalTransport.new()
	transport.use_json = true
	var server: Server = _server(transport)
	var a: Object = transport.connect_client()
	var b: Object = transport.connect_client()
	var boxes: Array = [[], []]
	_hello(a, "Ana", "dev-a")
	_hello(b, "  Bruno  ", "dev-b")
	_drain(server, [a, b], boxes)
	assert_eq(_last(boxes[1], Protocol.WELCOME).get("nick"), "Bruno", "apelido limpo")
	a.send({"t": Protocol.CREATE_ROOM, "options": {"seats": 3, "turn_seconds": 0, "bots": [2]}})
	_drain(server, [a, b], boxes)
	var room_id: String = str(_last(boxes[0], Protocol.JOINED).get("room", ""))
	assert_eq(room_id.length(), 4, "código de 4 caracteres")
	b.send({"t": Protocol.LIST_ROOMS})
	_drain(server, [a, b], boxes)
	var rooms: Array = _last(boxes[1], Protocol.ROOMS)["rooms"]
	assert_eq(rooms.size(), 1)
	assert_eq(int(rooms[0]["players"]), 2, "dono e bot")
	b.send({"t": Protocol.JOIN_ROOM, "room": room_id.to_lower()})
	_drain(server, [a, b], boxes)
	assert_false(_last(boxes[1], Protocol.JOINED).is_empty(), "entra pelo código, sem diferenciar maiúscula")
	a.send({"t": Protocol.START})
	_drain(server, [a, b], boxes)
	# Os dois humanos desistem sempre que é a vez deles; o bot joga sozinho.
	var room: Room = server.rooms[room_id]
	var seen_json_types: bool = true
	for _i in 300:
		if room.table.hand_number >= 5:
			break
		for k in 2:
			var state: Dictionary = _last(boxes[k], Protocol.STATE)
			var you: Dictionary = state.get("you", {})
			if you.has("legal"):
				seen_json_types = seen_json_types and typeof(state["table"]["seq"]) == TYPE_INT
				var legal: Dictionary = you["legal"]
				var action: String = Hand.CHECK if legal["can_check"] else Hand.FOLD
				[a, b][k].send({"t": Protocol.ACT, "seq": state["table"]["seq"], "action": action, "amount": 0})
		_drain(server, [a, b], boxes)
	assert_true(room.table.hand_number >= 5, "a partida anda pelo transporte")
	assert_true(seen_json_types, "inteiros continuam inteiros depois do JSON")
	assert_eq(room.bot_errors, 0)
	assert_true(_last(boxes[0], Protocol.ERROR).is_empty(), "nenhuma jogada recusada")


func test_every_message_survives_json() -> void:
	var transport: LocalTransport = LocalTransport.new()
	var server: Server = _server(transport)
	var a: Object = transport.connect_client()
	var box: Array = []
	_hello(a, "Ana")
	a.send({"t": Protocol.CREATE_ROOM, "options": {"seats": 4, "bots": [1, 2, 3]}})
	_drain(server, [a], [box])
	var room: Room = server.rooms.values()[0]
	var broken: Array = []
	room.tap = func(_id: String, message: Dictionary) -> void:
		if Codec.decode(Codec.encode(message)) != message:
			broken.append(message["t"])
	a.send({"t": Protocol.START})
	for _i in 400:
		if room.is_closed() or room.table.hand_number >= 15:
			break
		var state: Dictionary = _last(box, Protocol.STATE)
		if state.get("you", {}).has("legal"):
			a.send({"t": Protocol.ACT, "seq": state["table"]["seq"], "action": Hand.FOLD, "amount": 0})
		_drain(server, [a], [box])
	a.send({"t": Protocol.OWNER, "cmd": Protocol.CMD_CLOSE})
	_drain(server, [a], [box])
	assert_eq(broken.size(), 0, "mensagens que mudam no JSON: " + str(broken))
	assert_false(_last(box, Protocol.CLOSED).is_empty(), "recebeu o placar final")
	assert_eq(server.rooms.size(), 0, "sala encerrada é apagada")


func test_refusals_and_leaving() -> void:
	var transport: LocalTransport = LocalTransport.new()
	var server: Server = _server(transport, {"max_rooms": 1})
	var a: Object = transport.connect_client()
	var b: Object = transport.connect_client()
	var boxes: Array = [[], []]
	_hello(a, "Ana")
	_hello(b, "Bia")
	b.send({"t": Protocol.JOIN_ROOM, "room": "ZZZZ"})
	b.send({"t": Protocol.START})
	a.send({"t": Protocol.CREATE_ROOM, "options": {"seats": 2, "bots": [1, 1]}})
	_drain(server, [a, b], boxes)
	assert_eq(_last(boxes[1], Protocol.ERROR).get("code"), Protocol.E_NO_ROOM)
	assert_eq(_last(boxes[0], Protocol.ERROR).get("text"), "deixe um lugar para você")
	a.send({"t": Protocol.CREATE_ROOM, "options": {"seats": 2}})
	b.send({"t": Protocol.CREATE_ROOM, "options": {}})
	_drain(server, [a, b], boxes)
	assert_eq(_last(boxes[1], Protocol.ERROR).get("text"), "o servidor está cheio; tente mais tarde")
	a.send({"t": Protocol.CREATE_ROOM, "options": {}})
	_drain(server, [a, b], boxes)
	assert_eq(_last(boxes[0], Protocol.ERROR).get("text"), "você já está em uma sala")
	a.send({"t": Protocol.LEAVE})
	_drain(server, [a, b], boxes)
	assert_eq(_last(boxes[0], Protocol.LEFT).get("reason"), Protocol.R_LEFT)
	assert_eq(server.rooms.size(), 0, "o único humano saiu: a sala fechou e foi apagada")


func test_kick_and_disconnect_through_server() -> void:
	var transport: LocalTransport = LocalTransport.new()
	var server: Server = _server(transport)
	var a: Object = transport.connect_client()
	var b: Object = transport.connect_client()
	var c: Object = transport.connect_client()
	var boxes: Array = [[], [], []]
	_hello(a, "Ana", "dev-a")
	_hello(b, "Bia", "dev-b")
	_hello(c, "Caio", "dev-c")
	a.send({"t": Protocol.CREATE_ROOM, "options": {"seats": 4}})
	_drain(server, [a, b, c], boxes)
	var room_id: String = _last(boxes[0], Protocol.JOINED)["room"]
	b.send({"t": Protocol.JOIN_ROOM, "room": room_id})
	c.send({"t": Protocol.JOIN_ROOM, "room": room_id, "spectate": true})
	_drain(server, [a, b, c], boxes)
	var room: Room = server.rooms[room_id]
	var b_id: String = _last(boxes[1], Protocol.JOINED)["you"]
	assert_eq(room.members[_last(boxes[2], Protocol.JOINED)["you"]].seat, -1, "entrou assistindo")
	a.send({"t": Protocol.OWNER, "cmd": Protocol.CMD_KICK, "id": b_id})
	_drain(server, [a, b, c], boxes)
	assert_eq(_last(boxes[1], Protocol.LEFT).get("reason"), Protocol.R_KICKED)
	b.send({"t": Protocol.JOIN_ROOM, "room": room_id})
	_drain(server, [a, b, c], boxes)
	assert_eq(_last(boxes[1], Protocol.ERROR).get("text"), "você foi expulso desta sala")
	b.send({"t": Protocol.CREATE_ROOM, "options": {}})
	_drain(server, [a, b, c], boxes)
	assert_eq(server.rooms.size(), 2, "o expulso fica livre para outra sala")
	var a_id: String = _last(boxes[0], Protocol.JOINED)["you"]
	a.close()
	_drain(server, [a, b, c], boxes)
	assert_eq(room.owner_id, a_id, "o dono caiu: o lugar fica guardado por 60 s")
	assert_true(room.members[a_id].offline_since >= 0, "marcado como desconectado")
	(server.get("_clock") as Clock).advance(60000)
	_drain(server, [a, b, c], boxes)
	assert_eq(room.owner_id, _last(boxes[2], Protocol.JOINED)["you"], "depois de 60 s a sala passa")


# ---------------------------------------------------------------- visão e sigilo


## Embaralha entre si as cartas que quem olha não pode ver (as fechadas dos outros e o
## resto do baralho), nos mesmos lugares de onde saíram. A visão não pode mudar.
func _scrambled(table: Table, viewer_seat: int, rng: RandomNumberGenerator) -> Table:
	var saved: Dictionary = table.to_dict()
	var hand: Dictionary = saved["hand"]
	var visible: Dictionary = {}
	for card: int in hand["board"]:
		visible[card] = true
	var shown: Dictionary = {}
	for entry: Dictionary in hand["result"].get("shown", []):
		shown[int(entry["seat"])] = true
	for player: Dictionary in hand["players"]:
		var seat: int = player["seat"]
		var open: bool = (hand["revealed"] and not player["folded"]) or shown.has(seat)
		if seat == viewer_seat or open:
			for card: int in player["cards"]:
				visible[card] = true
	var hidden: Array = []
	for card: int in 52:
		if not visible.has(card):
			hidden.append(card)
	var shuffled: Array = hidden.duplicate()
	for i in range(shuffled.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: Variant = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = swap
	var map: Dictionary = {}
	for i in hidden.size():
		map[hidden[i]] = shuffled[i]
	for player: Dictionary in hand["players"]:
		player["cards"] = (player["cards"] as Array).map(func(c: int) -> int: return map.get(c, c))
	hand["deck"] = (hand["deck"] as Array).map(func(c: int) -> int: return map.get(c, c))
	var copy: Table = Table.new()
	assert_true(copy.load_dict(saved), "cópia embaralhada carrega: " + copy.load_error)
	return copy


func test_view_does_not_depend_on_hidden_cards() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 77
	var compared: int = 0
	for round_number in 30:
		var table: Table = Table.new()
		table.configure({"format": Table.CLASSIC})
		var ids: Dictionary = {}
		for i in 4:
			table.add_player(i, "j%d" % i)
			ids[i] = "j%d" % i
		table.start_hand({"seed": 9000 + round_number})
		var guard: int = 0
		while guard < 60:
			guard += 1
			for viewer in 5:
				var seat: int = viewer if viewer < 4 else -1
				var id: String = ids.get(seat, "")
				var copy: Table = _scrambled(table, seat, rng)
				assert_eq(View.public(copy, ids), View.public(table, ids), "visão pública")
				assert_eq(View.own(copy, seat, id, ids), View.own(table, seat, id, ids), "visão própria")
				compared += 1
			if not table.hand_in_progress():
				break
			var legal: Dictionary = table.hand.legal_actions()
			var roll: float = rng.randf()
			var response: Dictionary
			if legal["can_raise"] and roll < 0.25:
				response = table.apply_action(table.hand.to_act, Hand.BET if legal["is_bet"] else Hand.RAISE,
					rng.randi_range(legal["min_to"], legal["max_to"]))
			elif roll < 0.85:
				response = table.apply_action(table.hand.to_act, Hand.CHECK if legal["can_check"] else Hand.CALL)
			else:
				response = table.apply_action(table.hand.to_act, Hand.FOLD)
			assert_true(response["ok"], str(response["error"]))
	assert_true(compared > 500, "comparações feitas: %d" % compared)


func test_view_never_carries_the_deck_or_other_cards() -> void:
	var table: Table = Table.new()
	table.configure({"format": Table.CLASSIC})
	var ids: Dictionary = {0: "a", 1: "b", 2: "c"}
	for i in 3:
		table.add_player(i, ids[i])
	table.start_hand({"seed": 4242})
	var public: Dictionary = View.public(table, ids)
	assert_false(JSON.stringify(public).contains("deck"), "nada de baralho")
	for entry: Dictionary in public["seats"]:
		assert_false(entry.has("cards"), "cartas fechadas não aparecem na parte pública")
	assert_eq(View.own(table, 1, "b", ids)["cards"], table.hand.player_at(1).cards)
	assert_true(View.own(table, -1, "", ids).is_empty(), "espectador não recebe nada particular")
	# Outra pessoa sentou no lugar 1 depois que a mão começou: não herda as cartas.
	assert_true(View.own(table, 1, "novo", ids).is_empty(), "lugar trocado não leva as cartas")
