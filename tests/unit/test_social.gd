extends "res://tests/test_case.gd"
## Etapa 4, parte B, na sala: reações com limite de frequência (SPEC 11.2), espectador
## que senta quando abre vaga (SPEC 4.3), pausa no retrato da sala, placar dentro do
## state e o placar calculado quando o anfitrião some (SPEC 6.4).

const Room := preload("res://server/room.gd")
const Clock := preload("res://server/clock.gd")
const Protocol := preload("res://server/protocol.gd")
const Hand := preload("res://engine/hand.gd")
const HostLost := preload("res://net/host_lost.gd")
const Codec := preload("res://net/codec.gd")

const FAST: Dictionary = {"hand_gap_ms": 0, "showdown_gap_ms": 0, "bot_min_ms": 0,
	"bot_max_ms": 0, "bot_evaluations": 120}

var _inbox: Dictionary = {}
var _clock: Clock = null
var _seed: int = 0


func _room(raw: Dictionary, config: Dictionary = {}) -> Room:
	_inbox = {}
	_clock = Clock.new(true)
	_seed = 7000
	var merged: Dictionary = FAST.duplicate()
	merged.merge(config, true)
	return Room.new("ABCD", Room.normalize_options(raw)["options"], _clock, _collect, merged,
		_next_seed)


func _collect(id: String, message: Dictionary) -> void:
	if not _inbox.has(id):
		_inbox[id] = []
	_inbox[id].append(message)


func _next_seed() -> int:
	_seed += 1
	return _seed


func _join(room: Room, nick: String) -> String:
	var id: String = room.join({"nick": nick, "avatar": 0, "device": "dev-" + nick})["id"]
	room.announce()
	return id


func _last(id: String, type: String = Protocol.STATE) -> Dictionary:
	var list: Array = _inbox.get(id, [])
	for i in range(list.size() - 1, -1, -1):
		if list[i]["t"] == type:
			return list[i]
	return {}


func _count(id: String, type: String) -> int:
	return (_inbox.get(id, []) as Array).filter(func(m: Dictionary) -> bool:
		return m["t"] == type).size()


## Quem está na vez joga: passa se puder, senão paga.
func _play_turn(room: Room) -> void:
	var seat: int = room.table.hand.to_act
	var member: Room.Member = room.member_at(seat)
	var legal: Dictionary = room.table.hand.legal_actions()
	room.handle(member.id, {"t": Protocol.ACT, "seq": room._seq,
		"action": Hand.CHECK if legal["can_check"] else Hand.CALL, "amount": 0})


func test_reaction_reaches_everyone_with_rate_limit() -> void:
	var room: Room = _room({"turn_seconds": 0, "seats": 3})
	var a: String = _join(room, "Ana")
	var b: String = _join(room, "Bia")
	var c: String = _join(room, "Caio")
	room.handle(a, {"t": Protocol.REACT, "r": 6})
	for id: String in [a, b, c]:
		var got: Dictionary = _last(id, Protocol.REACTION)
		assert_eq(got.get("r"), 6, "todos recebem a reação")
		assert_eq(got.get("seat"), room.members[a].seat, "com o lugar de quem reagiu")
	room.handle(a, {"t": Protocol.REACT, "r": 0})
	assert_eq(_count(b, Protocol.REACTION), 1, "a segunda, logo em seguida, é ignorada")
	assert_eq(_count(a, Protocol.ERROR), 0, "sem mensagem de erro")
	_clock.advance(Protocol.REACTION_GAP_MS)
	room.handle(a, {"t": Protocol.REACT, "r": 0})
	assert_eq(_count(b, Protocol.REACTION), 2, "depois do intervalo, vale de novo")
	room.handle(b, {"t": Protocol.REACT, "r": Protocol.REACTIONS.size()})
	room.handle(b, {"t": Protocol.REACT, "r": "oi"})
	assert_eq(_count(c, Protocol.REACTION), 2, "índice inválido não passa: sem texto livre")
	# Sala cheia: quem chega assiste e não reage.
	var d: String = _join(room, "Dani")
	assert_eq(room.members[d].seat, -1)
	room.handle(d, {"t": Protocol.REACT, "r": 1})
	assert_eq(_count(c, Protocol.REACTION), 2, "espectador não reage")


func test_spectator_sits_when_a_seat_opens() -> void:
	var room: Room = _room({"turn_seconds": 0, "seats": 2})
	var a: String = _join(room, "Ana")
	var b: String = _join(room, "Bia")
	var c: String = _join(room, "Caio")
	assert_eq(room.members[c].seat, -1, "sala cheia: entra assistindo")
	assert_eq(_last(c)["you"].get("can_sit"), false)
	room.leave(b)
	assert_eq(_last(c)["you"].get("can_sit"), true, "abriu vaga na sala de espera")
	room.handle(c, {"t": Protocol.SIT, "seat": 1})
	assert_eq(room.members[c].seat, 1, "sentou no lugar livre")
	assert_false(_last(c)["you"].has("can_sit"), "quem está sentado não recebe can_sit")
	room.handle(a, {"t": Protocol.START})
	# Em partida, sala fechada a novos: quem chega só assiste, mesmo com vaga.
	var room2: Room = _room({"turn_seconds": 0, "seats": 3})
	var a2: String = _join(room2, "Ana")
	_join(room2, "Bia")
	room2.handle(a2, {"t": Protocol.START})
	var d: String = room2.join({"nick": "Dani", "avatar": 0, "device": "dev-d"}, true)["id"]
	room2.announce()
	assert_eq(_last(d)["you"].get("can_sit"), false, "sala não aceita novos jogadores")
	var room3: Room = _room({"turn_seconds": 0, "seats": 3, "keep_open": true})
	var a3: String = _join(room3, "Ana")
	_join(room3, "Bia")
	room3.handle(a3, {"t": Protocol.START})
	var e: String = room3.join({"nick": "Eva", "avatar": 0, "device": "dev-e"}, true)["id"]
	room3.announce()
	assert_eq(_last(e)["you"].get("can_sit"), true, "\"manter sala aberta\": pode sentar")
	assert_eq(_last(e)["you"].get("sit_rebuy"), false, "gente nova não gasta recompra")
	room3.handle(e, {"t": Protocol.SIT})
	assert_true(room3.members[e].seat >= 0, "sentou com a partida em andamento")


func test_forfeit_hand_folds_when_turn_comes() -> void:
	var room: Room = _room({"turn_seconds": 0, "seats": 4})
	var ids: Array[String] = [_join(room, "Ana"), _join(room, "Bia"), _join(room, "Caio")]
	room.handle(ids[0], {"t": Protocol.START})
	assert_true(room.table.hand_in_progress())
	var to_act: Room.Member = room.member_at(room.table.hand.to_act)
	var other: Room.Member = null
	for id: String in ids:
		if id != to_act.id:
			other = room.members[id]
			break
	room.forfeit_hand(other.id)
	assert_false(room.table.hand.player_at(other.seat).folded, "fora da vez, ainda não desistiu")
	for _i in 6:
		if not room.table.hand_in_progress() or room.table.hand.player_at(other.seat).folded:
			break
		_play_turn(room)
	assert_true(not room.table.hand_in_progress() or room.table.hand.player_at(other.seat).folded,
		"desistiu quando a vez chegou")
	# Na vez dele: desiste na hora. A mão seguinte não é afetada.
	_clock.advance(10)
	room.tick()
	if not room.table.hand_in_progress():
		return
	var now_member: Room.Member = room.member_at(room.table.hand.to_act)
	var hand: int = room.table.hand_number
	room.forfeit_hand(now_member.id)
	assert_true(room.table.hand_number != hand
		or room.table.hand.player_at(now_member.seat).folded, "desistiu na hora")
	assert_true(room.table.is_balanced())


func test_snapshot_with_hand_continues_the_same_hand() -> void:
	var room: Room = _room({"turn_seconds": 30, "seats": 4})
	var a: String = _join(room, "Ana")
	_join(room, "Bia")
	_join(room, "Caio")
	room.handle(a, {"t": Protocol.START})
	_play_turn(room)
	_clock.advance(4000)
	room.handle(a, {"t": Protocol.OWNER, "cmd": Protocol.CMD_PAUSE})
	var saved: Dictionary = Codec.decode(Codec.encode(room.snapshot(true)))
	assert_false(saved.is_empty(), "com a mão, o retrato sai no meio dela")
	assert_true(saved["table"]["hand"] != null, "leva a mão")
	assert_eq(int(saved["turn_ms"]), 26000, "e o que faltava da vez")
	var other_clock: Clock = Clock.new(true)
	other_clock.advance(9_000_000)
	var raw: Dictionary = saved["options"].duplicate()
	raw["bots"] = []
	var copy: Room = Room.new("ABCD", Room.normalize_options(raw)["options"], other_clock,
		func(_id: String, _m: Dictionary) -> void: pass, FAST, _next_seed)
	assert_eq(copy.restore(saved), "", "restaurou")
	assert_true(copy.paused, "continua pausada")
	assert_true(copy.table.hand_in_progress(), "a mão continua")
	assert_eq(copy.table.hand.to_act, room.table.hand.to_act)
	assert_eq(copy._turn_deadline - copy._now(), 26000, "a vez continua com o tempo que faltava")
	room.handle(a, {"t": Protocol.OWNER, "cmd": Protocol.CMD_RESUME})
	copy.handle(a, {"t": Protocol.OWNER, "cmd": Protocol.CMD_RESUME})
	# As duas salas jogam igual até o fim da mão: mesmo baralho, mesmo resultado.
	var number: int = room.table.hand_number
	for _i in 30:
		if room.table.hand_number != number or not room.table.hand_in_progress():
			break
		_play_turn(room)
		_play_turn(copy)
	assert_eq(copy.table.hand.board, room.table.hand.board, "mesmas cartas na mesa")
	assert_eq(copy.table.hand.result.get("payouts"), room.table.hand.result.get("payouts"),
		"mesmo resultado")
	assert_true(copy.table.is_balanced())


func test_host_lost_score_splits_host_bets() -> void:
	var room: Room = _room({"turn_seconds": 0, "seats": 4})
	var a: String = _join(room, "Ana")
	var b: String = _join(room, "Bia")
	var c: String = _join(room, "Caio")
	room.handle(a, {"t": Protocol.START})
	assert_eq(_last(a)["room"]["score"].size(), 3, "o placar vai no state")
	# Todos pagam o pré-flop; no flop, Ana aposta, Bia paga e Caio desiste.
	var guard: int = 0
	while room.table.hand_in_progress() and room.table.hand.street == Hand.PREFLOP and guard < 8:
		guard += 1
		_play_turn(room)
	while room.table.hand_in_progress() and room.table.hand.street == 1 and guard < 16:
		guard += 1
		var member: Room.Member = room.member_at(room.table.hand.to_act)
		var legal: Dictionary = room.table.hand.legal_actions()
		var action: Dictionary = {"t": Protocol.ACT, "seq": room._seq, "amount": 0}
		if member.id == a and legal["can_check"]:
			action["action"] = Hand.BET
			action["amount"] = int(legal["min_to"])
		elif member.id == c:
			action["action"] = Hand.FOLD
		else:
			action["action"] = Hand.CHECK if legal["can_check"] else Hand.CALL
		room.handle(member.id, action)
	assert_true(room.table.hand_in_progress(), "a mão segue")
	var state: Dictionary = _last(b)
	var totals: Dictionary = {}
	for entry: Dictionary in state["table"]["seats"]:
		totals[entry["id"]] = int(entry["total"])
	var before: Dictionary = {}
	for row: Dictionary in state["room"]["score"]:
		before[row["id"]] = int(row["net"])
	var final: Dictionary = HostLost.final_from(state, a)
	assert_eq(final.get("t"), Protocol.CLOSED)
	assert_eq(final.get("reason"), Protocol.R_HOST_GONE)
	var after: Dictionary = {}
	var sum: int = 0
	for row: Dictionary in final["scoreboard"]:
		after[row["id"]] = int(row["net"])
		sum += int(row["net"]) - int(before[row["id"]])
	assert_true(totals[a] > 0, "Ana tinha fichas na mão")
	assert_eq(after[a], before[a] - totals[a], "o anfitrião perde o que apostou")
	var folded_c: bool = room.table.hand.player_at(room.members[c].seat).folded
	if folded_c:
		assert_eq(after[b], before[b] + totals[a], "fica com quem ainda estava na mão")
		assert_eq(after[c], before[c], "quem desistiu recebe a aposta de volta")
	assert_eq(sum, 0, "nenhuma ficha some nem aparece")
	assert_eq(HostLost.final_from({}, a), {}, "sem state, sem placar")
