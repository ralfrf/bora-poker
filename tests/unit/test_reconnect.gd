extends "res://tests/test_case.gd"
## Quedas e voltas na sala (SPEC 6.1 a 6.3): lugar guardado por 60 s, fichas guardadas
## por 10 minutos com a escolha na volta, a mesma pessoa por outra conexão, o torneio e
## o mano a mano com ausente. Relógio manual e sementes fixas.

const Room := preload("res://server/room.gd")
const Clock := preload("res://server/clock.gd")
const Protocol := preload("res://server/protocol.gd")
const Table := preload("res://engine/table.gd")
const Hand := preload("res://engine/hand.gd")

const FAST: Dictionary = {"hand_gap_ms": 0, "showdown_gap_ms": 0, "bot_min_ms": 0,
	"bot_max_ms": 0, "bot_evaluations": 120}

var _inbox: Dictionary = {}
var _clock: Clock = null
var _seed: int = 0


func _room(raw: Dictionary, config: Dictionary = {}) -> Room:
	var normalized: Dictionary = Room.normalize_options(raw)
	_inbox = {}
	_clock = Clock.new(true)
	_seed = 3000
	var merged: Dictionary = FAST.duplicate()
	merged.merge(config, true)
	return Room.new("ABCD", normalized["options"], _clock, _collect, merged, _next_seed)


func _collect(id: String, message: Dictionary) -> void:
	if not _inbox.has(id):
		_inbox[id] = []
	_inbox[id].append(message)


func _next_seed() -> int:
	_seed += 1
	return _seed


func _join(room: Room, nick: String, device: String) -> Dictionary:
	var result: Dictionary = room.join({"nick": nick, "avatar": 0, "device": device})
	room.announce()
	return result


func _last_state(id: String) -> Dictionary:
	var list: Array = _inbox.get(id, [])
	for i in range(list.size() - 1, -1, -1):
		if list[i]["t"] == Protocol.STATE:
			return list[i]
	return {}


func _member_info(id: String, of: String) -> Dictionary:
	for member: Dictionary in _last_state(id).get("room", {}).get("members", []):
		if member["id"] == of:
			return member
	return {}


## Quem está na vez desiste, até a mão acabar (ou o limite).
func _fold_until(room: Room, done: Callable) -> void:
	for _i in 60:
		room.tick()
		if done.call():
			return
		if room.table.hand_in_progress():
			var seat: int = room.table.hand.to_act
			var member: Room.Member = room.member_at(seat)
			var seq: int = int(_last_state(member.id)["table"]["seq"])
			room.handle(member.id, {"t": Protocol.ACT, "seq": seq, "action": Hand.FOLD, "amount": 0})


func _three(raw: Dictionary) -> Array:
	var room: Room = _room(raw)
	var a: String = _join(room, "Ana", "dev-a")["id"]
	var b: String = _join(room, "Bia", "dev-b")["id"]
	var c: String = _join(room, "Caio", "dev-c")["id"]
	room.handle(a, {"t": Protocol.START})
	return [room, a, b, c]


func test_drop_keeps_seat_and_returns_within_60s() -> void:
	var parts: Array = _three({"turn_seconds": 0})
	var room: Room = parts[0]
	var c: String = parts[3]
	var seat: int = room.members[c].seat
	room.drop_connection(c)
	assert_true(room.members.has(c), "continua na sala")
	assert_eq(room.members[c].seat, seat, "o lugar fica guardado")
	assert_eq(_member_info(parts[1], c).get("connected"), false, "os outros veem reconectando")
	_clock.advance(59000)
	room.tick()
	assert_eq(room.members[c].seat, seat, "ainda dentro dos 60 s")
	var back: Dictionary = _join(room, "Caio", "dev-c")
	assert_eq(back["id"], c, "volta como o mesmo participante")
	assert_eq(back["resumed"], true)
	assert_eq(room.members[c].seat, seat)
	assert_eq(_member_info(parts[1], c).get("connected"), true)


func test_wrong_device_is_not_the_same_person() -> void:
	var parts: Array = _three({"turn_seconds": 0})
	var room: Room = parts[0]
	var c: String = parts[3]
	room.drop_connection(c)
	var other: Dictionary = _join(room, "Caio", "dev-x")
	assert_true(other["id"] != c, "só o apelido não basta (SPEC 6.1)")
	assert_eq(other["resumed"], false)


func test_new_connection_takes_over_same_player() -> void:
	var parts: Array = _three({"turn_seconds": 0})
	var room: Room = parts[0]
	var again: Dictionary = _join(room, "Caio", "dev-c")
	assert_eq(again["id"], parts[3], "mesma pessoa por outra conexão")
	assert_eq(again["resumed"], true)


func test_after_60s_seat_is_freed_and_chips_held() -> void:
	var parts: Array = _three({"turn_seconds": 0})
	var room: Room = parts[0]
	var c: String = parts[3]
	_fold_until(room, func() -> bool: return room.table.hand_number >= 2)
	room.drop_connection(c)
	_clock.advance(60000)
	room.tick()
	_fold_until(room, func() -> bool: return not room.members.has(c))
	assert_false(room.members.has(c), "deixou a sala depois de 60 s")
	var held: int = room.table.cashbox.held(c)
	assert_true(held > 0, "fichas guardadas")
	assert_true(room.table.is_balanced())
	# Volta em 5 minutos: entra assistindo, com a oferta.
	_clock.advance(240000)
	var back: Dictionary = _join(room, "Caio", "dev-c")
	assert_eq(back["id"], c, "recupera o id das fichas guardadas")
	assert_eq(room.members[c].seat, -1, "espera a escolha")
	var offer: Dictionary = _last_state(c)["you"].get("return_offer", {})
	assert_eq(offer.get("before"), held, "oferta com as fichas de antes")
	assert_eq(offer.get("seat"), true)
	room.handle(c, {"t": Protocol.SIT})
	assert_eq(room.members[c].seat, -1, "sentar direto não vale: precisa escolher")
	room.handle(c, {"t": Protocol.RETURN_CHOICE, "keep": true})
	assert_true(room.members[c].seat >= 0, "voltou à mesa")
	assert_eq(room.table.seat_at(room.members[c].seat).stack, held, "com as fichas de antes")
	assert_eq(room.table.cashbox.held(c), 0)
	assert_false(_last_state(c)["you"].has("return_offer"))
	assert_true(room.table.is_balanced())


func test_return_with_initial_chips_counts_as_rebuy() -> void:
	var parts: Array = _three({"turn_seconds": 0, "rebuy_limit": 1, "starting_stack": 2000,
		"small_blind": 10, "big_blind": 20})
	var room: Room = parts[0]
	var c: String = parts[3]
	_fold_until(room, func() -> bool:
		return room.table.hand_number >= 1 and not room.table.hand_in_progress())
	room.leave(c)
	_fold_until(room, func() -> bool: return not room.members.has(c))
	var held: int = room.table.cashbox.held(c)
	assert_true(held > 0, "fichas guardadas (%d)" % held)
	_join(room, "Caio", "dev-c")
	assert_eq(_last_state(c)["you"]["return_offer"].get("can_initial"), true, "tem recompra")
	room.handle(c, {"t": Protocol.RETURN_CHOICE, "keep": false})
	assert_eq(room.table.seat_at(room.members[c].seat).stack, 2000, "as fichas iniciais")
	assert_eq(room.table.rebuys_of(c), 1 if held < 2000 else 0,
		"conta como recompra quando é mais do que ele tinha")
	assert_true(room.table.is_balanced())


func test_after_ten_minutes_comes_back_as_new_player() -> void:
	var parts: Array = _three({"turn_seconds": 0})
	var room: Room = parts[0]
	var c: String = parts[3]
	_fold_until(room, func() -> bool: return room.table.hand_number >= 2)
	room.drop_connection(c)
	_clock.advance(60000)
	room.tick()
	_fold_until(room, func() -> bool: return not room.members.has(c))
	_clock.advance(540000)   # 10 minutos desde a queda
	room.tick()
	assert_eq(room.table.cashbox.held(c), 0, "o prazo venceu")
	var back: Dictionary = _join(room, "Caio", "dev-c")
	assert_false(back["ok"], "é jogador novo, e a sala está fechada a novos")
	assert_eq(back["error"], "a partida já começou e a sala não aceita novos jogadores")
	assert_false(room.members.has(c))
	assert_true(room.table.is_balanced())


func test_spectator_drop() -> void:
	var room: Room = _room({"seats": 2, "turn_seconds": 0})
	var a: String = _join(room, "Ana", "dev-a")["id"]
	_join(room, "Bia", "dev-b")
	var spy: Dictionary = {"nick": "Saulo", "avatar": 0, "device": "dev-s"}
	var s: String = room.join(spy, true)["id"]
	assert_eq(room.members[s].seat, -1)
	room.drop_connection(s)
	assert_false(room.members.has(s), "na sala de espera, quem assistia sai na hora")
	s = room.join(spy, true)["id"]
	room.handle(a, {"t": Protocol.START})
	# Em partida, quem assiste não entraria de novo de fora: tem 60 s para voltar.
	room.drop_connection(s)
	_clock.advance(59000)
	room.tick()
	assert_true(room.members.has(s), "lugar de espectador guardado")
	var back: Dictionary = _join(room, "Saulo", "dev-s")
	assert_true(back["ok"] and back["resumed"] and back["id"] == s, "volta a assistir")
	room.drop_connection(s)
	_clock.advance(60000)
	room.tick()
	assert_false(room.members.has(s), "passados 60 s, sai")
	assert_false(_join(room, "Saulo", "dev-s")["ok"], "sala cheia: não entra mais")


func test_tournament_drop_keeps_seat_and_returns() -> void:
	var parts: Array = _three({"format": Table.TOURNAMENT, "turn_seconds": 0})
	var room: Room = parts[0]
	var c: String = parts[3]
	_fold_until(room, func() -> bool: return room.table.hand_number >= 2)
	room.drop_connection(c)
	_clock.advance(60000)
	room.tick()
	assert_true(room.members[c].gone, "depois de 60 s desiste sozinho a cada mão")
	var seat: int = room.members[c].seat
	_clock.advance(300000)
	var back: Dictionary = _join(room, "Caio", "dev-c")
	assert_eq(back["id"], c, "volta quando quiser")
	assert_false(room.members[c].gone)
	assert_eq(room.members[c].seat, seat, "no mesmo lugar")


func test_tournament_heads_up_with_absent_player_ends() -> void:
	var room: Room = _room({"format": Table.TOURNAMENT, "turn_seconds": 0})
	var a: String = _join(room, "Ana", "dev-a")["id"]
	var b: String = _join(room, "Bia", "dev-b")["id"]
	room.handle(a, {"t": Protocol.START})
	room.drop_connection(b)
	_clock.advance(30000)
	room.tick()
	assert_false(room.is_closed(), "30 s ainda não contam")
	_clock.advance(30000)
	_fold_until(room, func() -> bool: return room.is_closed())
	assert_true(room.is_closed(), "mano a mano com ausente há mais de 60 s: acabou")
	var podium: Array = room.final.get("podium", [])
	assert_eq(podium.size() > 0 and podium[0]["id"] == a, true, "quem ficou é o campeão")


func test_engine_concede() -> void:
	var table: Table = Table.new()
	table.configure({"format": Table.TOURNAMENT})
	table.add_player(0, "a")
	table.add_player(1, "b")
	table.add_player(2, "c")
	assert_eq(table.concede(1)["ok"], false, "só no mano a mano")
	var classic: Table = Table.new()
	classic.add_player(0, "a")
	classic.add_player(1, "b")
	assert_eq(classic.concede(1)["ok"], false, "só no torneio")
	var duel: Table = Table.new()
	duel.configure({"format": Table.TOURNAMENT})
	duel.add_player(0, "a")
	duel.add_player(1, "b")
	duel.start_hand({"seed": 1})
	assert_eq(duel.concede(1)["ok"], false, "não no meio da mão")
	duel.apply_action(duel.hand.to_act, Hand.FOLD)
	var total: int = duel.chips_on_seats()
	var response: Dictionary = duel.concede(1)
	assert_eq(response["ok"], true)
	assert_eq(duel.chips_on_seats(), total, "as fichas só mudam de lugar")
	assert_true(duel.is_over(), "o torneio acabou")
	assert_eq(duel.podium()[0]["id"], "a")
	assert_true(duel.is_balanced())


func test_avatar_changes_only_in_lobby() -> void:
	var room: Room = _room({"turn_seconds": 0})
	var a: String = _join(room, "Ana", "dev-a")["id"]
	var b: String = _join(room, "Bia", "dev-b")["id"]
	room.handle(b, {"t": Protocol.PROFILE, "avatar": 7})
	assert_eq(_member_info(a, b).get("avatar"), 7, "todos veem o avatar novo")
	room.handle(b, {"t": Protocol.PROFILE, "avatar": 99})
	assert_eq(room.members[b].avatar, 7, "avatar inexistente não vale")
	room.handle(a, {"t": Protocol.START})
	room.handle(b, {"t": Protocol.PROFILE, "avatar": 3})
	assert_eq(room.members[b].avatar, 7, "depois de começar, não muda")


## O retrato leva a sala para outro servidor (Wi-Fi: o anfitrião saiu) e a partida segue.
func test_snapshot_restores_room_elsewhere() -> void:
	# Com espera entre mãos (e o relógio parado), dá para pegar a sala entre uma e outra.
	var room: Room = _room({"turn_seconds": 0}, {"hand_gap_ms": 1000, "showdown_gap_ms": 1000})
	var a: String = _join(room, "Ana", "dev-a")["id"]
	var b: String = _join(room, "Bia", "dev-b")["id"]
	var c: String = _join(room, "Caio", "dev-c")["id"]
	var parts: Array = [room, a, b, c]
	room.handle(a, {"t": Protocol.OWNER, "cmd": Protocol.CMD_ADD_BOT, "level": 1})
	room.handle(a, {"t": Protocol.START})
	assert_true(room.table.hand_in_progress())
	assert_eq(room.snapshot(), {}, "no meio da mão não há retrato")
	while room.table.hand_number < 3 or room.table.hand_in_progress():
		if room.table.hand_in_progress():
			var member: Room.Member = room.member_at(room.table.hand.to_act)
			if not member.is_bot:
				room.handle(member.id, {"t": Protocol.ACT, "action": Hand.FOLD, "amount": 0,
					"seq": int(_last_state(member.id)["table"]["seq"])})
		elif room.table.hand_number < 3:
			_clock.advance(1000)
		room.tick()
		_clock.advance(10)
	room.leave(c)
	var held: int = room.table.cashbox.held(c)
	var saved: Dictionary = room.snapshot()
	assert_false(saved.is_empty())
	assert_eq(saved["table"]["hand"], null, "sem as cartas da última mão")
	# O retrato viaja como JSON.
	var text: String = JSON.stringify(saved)
	var back: Dictionary = preload("res://net/codec.gd").decode(text)
	var other_clock: Clock = Clock.new(true)
	other_clock.advance(5_000_000)   # outro aparelho, outro relógio
	var inbox: Dictionary = {}
	var collect: Callable = func(id: String, message: Dictionary) -> void:
		if not inbox.has(id):
			inbox[id] = []
		inbox[id].append(message)
	var raw: Dictionary = back["options"].duplicate()
	raw["bots"] = []
	var copy: Room = Room.new("ABCD", Room.normalize_options(raw)["options"], other_clock,
		collect, FAST, _next_seed)
	assert_eq(copy.restore(back), "", "restaurou")
	assert_eq(copy.table.chips_on_seats(), room.table.chips_on_seats(), "mesmas fichas")
	assert_true(copy.table.is_balanced())
	assert_eq(copy.members.size(), room.members.size(), "mesmos participantes")
	assert_eq(copy.owner_id, room.owner_id, "mesmo dono")
	assert_eq(copy.table.cashbox.held(c), held, "as fichas guardadas vão junto")
	var a_back: Dictionary = copy.join({"nick": "Ana", "avatar": 0, "device": "dev-a"})
	assert_eq(a_back["id"], parts[1], "Ana reconecta como ela mesma")
	assert_eq(a_back["resumed"], true)
	var b_back: Dictionary = copy.join({"nick": "Bia", "avatar": 0, "device": "dev-b"})
	assert_eq(b_back["id"], parts[2])
	var c_back: Dictionary = copy.join({"nick": "Caio", "avatar": 0, "device": "dev-c"})
	assert_eq(c_back["id"], c, "Caio volta com as fichas guardadas")
	assert_true(copy.members[c].return_offer)
	var hands: int = copy.table.hand_number
	for _i in 200:
		other_clock.advance(500)
		copy.tick()
		if copy.table.hand_in_progress():
			var member: Room.Member = copy.member_at(copy.table.hand.to_act)
			if member.is_bot:
				continue
			var list: Array = inbox.get(member.id, [])
			var seq: int = int(list[-1]["table"]["seq"]) if not list.is_empty() else -1
			copy.handle(member.id, {"t": Protocol.ACT, "seq": seq, "action": Hand.FOLD, "amount": 0})
		if copy.table.hand_number >= hands + 3:
			break
	assert_true(copy.table.hand_number >= hands + 3, "a partida segue no outro servidor")
	assert_true(copy.table.is_balanced())
	assert_eq(copy.bot_errors, 0)
