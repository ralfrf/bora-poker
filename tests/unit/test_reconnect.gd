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
	# Volta dentro dos 5 minutos (4 desde a queda): entra assistindo, com a oferta.
	_clock.advance(180000)
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


func test_held_player_watches_full_room_until_a_seat_opens() -> void:
	var parts: Array = _three({"turn_seconds": 0, "seats": 3, "keep_open": true})
	var room: Room = parts[0]
	var c: String = parts[3]
	_fold_until(room, func() -> bool: return room.table.hand_number >= 2)
	room.drop_connection(c)
	_clock.advance(60000)
	room.tick()
	_fold_until(room, func() -> bool: return not room.members.has(c))
	var davi: Dictionary = _join(room, "Davi", "dev-d")
	assert_true(davi["ok"] and room.members[davi["id"]].seat >= 0, "Davi pega o lugar")
	assert_false(_join(room, "Eva", "dev-e")["ok"], "sala cheia: gente nova não entra")
	var back: Dictionary = _join(room, "Caio", "dev-c")
	assert_true(back["ok"], "quem caiu entra mesmo com a sala cheia")
	assert_eq(room.members[c].seat, -1, "assistindo")
	assert_eq(_last_state(c)["you"]["return_offer"].get("seat"), false, "sem lugar ainda")
	room.handle(c, {"t": Protocol.RETURN_CHOICE, "keep": true})
	assert_eq(room.members[c].seat, -1, "não volta sem lugar")
	room.leave(davi["id"])
	_fold_until(room, func() -> bool: return not room.members.has(davi["id"]))
	assert_eq(_last_state(c)["you"]["return_offer"].get("seat"), true, "abriu lugar")
	room.handle(c, {"t": Protocol.RETURN_CHOICE, "keep": true})
	assert_true(room.members[c].seat >= 0, "voltou à mesa")
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


func test_tournament_leave_has_two_minutes_to_return() -> void:
	# Saiu e voltou dentro dos 2 minutos: continua no torneio com o que sobrou.
	var parts: Array = _three({"format": Table.TOURNAMENT, "turn_seconds": 0})
	var room: Room = parts[0]
	var c: String = parts[3]
	var seat: int = room.members[c].seat
	room.leave(c)
	_clock.advance(90000)
	_fold_until(room, func() -> bool: return not room.table.hand_in_progress())
	room.tick()
	assert_true(room.members.has(c), "90 s: ainda no torneio, pagando os blinds")
	assert_eq(_join(room, "Caio", "dev-c")["id"], c, "voltou")
	assert_eq(room.members[c].seat, seat, "no mesmo lugar")
	_clock.advance(200000)
	room.tick()
	assert_true(room.members.has(c), "quem voltou não sai pelo prazo")
	# Saiu e não voltou: com 2 minutos, sai do torneio e as fichas vão para quem fica.
	var other: Array = _three({"format": Table.TOURNAMENT, "turn_seconds": 0})
	var t_room: Room = other[0]
	var t_c: String = other[3]
	t_room.leave(t_c)
	_clock.advance(119000)
	_fold_until(t_room, func() -> bool: return not t_room.table.hand_in_progress())
	t_room.tick()
	assert_true(t_room.members.has(t_c), "119 s: ainda não")
	var total: int = t_room.table.chips_on_seats() + t_room.table.chips_in_hand()
	_clock.advance(1000)
	_fold_until(t_room, func() -> bool: return not t_room.members.has(t_c))
	assert_false(t_room.members.has(t_c), "2 minutos: saiu do torneio")
	assert_false(t_room.is_closed(), "o torneio segue com os outros dois")
	assert_eq(t_room.table.participants().size(), 2)
	assert_eq(t_room.table.chips_on_seats() + t_room.table.chips_in_hand(), total, "nenhuma ficha some")
	assert_true(t_room.table.is_balanced())


func test_tournament_heads_up_with_absent_player_ends() -> void:
	var room: Room = _room({"format": Table.TOURNAMENT, "turn_seconds": 0})
	var a: String = _join(room, "Ana", "dev-a")["id"]
	var b: String = _join(room, "Bia", "dev-b")["id"]
	room.handle(a, {"t": Protocol.START})
	room.drop_connection(b)
	assert_eq(_member_info(a, b).get("remove_ms"), 120000, "caiu no torneio: 2 minutos")
	_clock.advance(90000)
	_fold_until(room, func() -> bool: return not room.table.hand_in_progress())
	room.tick()
	assert_false(room.is_closed(), "90 s ainda não contam")
	_clock.advance(30000)
	_fold_until(room, func() -> bool: return room.is_closed())
	assert_true(room.is_closed(), "mano a mano com ausente há 2 minutos: acabou")
	var podium: Array = room.final.get("podium", [])
	assert_eq(podium.size() > 0 and podium[0]["id"] == a, true, "quem ficou é o campeão")


func test_engine_concede() -> void:
	var table: Table = Table.new()
	table.configure({"format": Table.TOURNAMENT})
	table.add_player(0, "a")
	table.add_player(1, "b")
	table.add_player(2, "c")
	table.add_player(4, "d")
	table.start_hand({"seed": 1})
	while table.hand_in_progress():
		table.apply_action(table.hand.to_act, Hand.FOLD)
	var before: Dictionary = {}
	for index: int in [0, 2, 4]:
		before[index] = table.seat_at(index).stack
	var stack: int = table.seat_at(1).stack
	var total: int = table.chips_on_seats()
	var split: Dictionary = table.concede(1)
	assert_true(split["ok"], "com 4 também vale (quem saiu do torneio)")
	assert_eq(table.chips_on_seats(), total, "nenhuma ficha some")
	assert_true(table.is_balanced())
	var places: Array = split["events"].filter(func(e: Dictionary) -> bool:
		return e["type"] == "eliminated").map(func(e: Dictionary) -> int: return e["place"])
	assert_eq(places, [4], "a pior colocação de agora")
	# Partes iguais; a sobra vai, um centavo cada, a quem já tinha mais fichas (empate:
	# quem vem primeiro depois do lugar de quem saiu: 2, 4, 0).
	var richest: Array = [2, 4, 0]
	richest.sort_custom(func(x: int, y: int) -> bool:
		return before[x] > before[y] or (before[x] == before[y] and richest.find(x) < richest.find(y)))
	for rank in richest.size():
		var index: int = richest[rank]
		assert_eq(table.seat_at(index).stack - before[index], stack / 3 + (1 if rank < stack % 3 else 0),
			"lugar %d (%dº em fichas)" % [index, rank + 1])
	# Caso com sobra garantida: 100 centavos para 3 = 34, 33, 33; o 34 vai ao mais rico.
	var odd: Table = Table.new()
	odd.configure({"format": Table.TOURNAMENT, "starting_stack": 100, "small_blind": 1,
		"big_blind": 2})
	for index: int in [0, 1, 2, 3]:
		odd.add_player(index, "j%d" % index)
	odd.start_hand({"seed": 3})
	while odd.hand_in_progress():
		odd.apply_action(odd.hand.to_act, Hand.FOLD)
	var leaver: int = -1
	for index: int in [0, 1, 2, 3]:
		if odd.seat_at(index).stack == 100:
			leaver = index
			break
	var rest: Array = [0, 1, 2, 3].filter(func(i: int) -> bool: return i != leaver)
	var top: int = rest[0]
	for index: int in rest:
		if odd.seat_at(index).stack > odd.seat_at(top).stack:
			top = index
	var top_before: int = odd.seat_at(top).stack
	assert_true(odd.concede(leaver)["ok"])
	assert_eq(odd.seat_at(top).stack - top_before, 34, "a sobra fica com quem tem mais fichas")
	assert_true(odd.is_balanced())
	assert_false(table.is_over(), "o torneio continua com 3")
	assert_eq(table.concede(1)["ok"], false, "quem já saiu não entrega de novo")
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
	var duel_total: int = duel.chips_on_seats()
	var response: Dictionary = duel.concede(1)
	assert_eq(response["ok"], true)
	assert_eq(duel.chips_on_seats(), duel_total, "as fichas só mudam de lugar")
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


func test_leave_button_shows_left_not_reconnecting() -> void:
	# Clássico, no meio da mão: o lugar espera a mão acabar, mas quem tocou em "Sair" saiu.
	var parts: Array = _three({"turn_seconds": 0})
	var room: Room = parts[0]
	var a: String = parts[1]
	var b: String = parts[2]
	var c: String = parts[3]
	assert_true(room.table.hand_in_progress())
	room.leave(c)
	assert_true(_member_info(a, c).get("left", false), "os outros veem que saiu")
	assert_false(_member_info(a, c).get("connected", true))
	# Quem só caiu continua "reconectando".
	room.drop_connection(b)
	assert_false(_member_info(a, b).get("left", false), "queda não é saída")
	assert_eq(_member_info(a, b).get("remove_ms"), 60000, "a contagem da queda no clássico")
	assert_false(_member_info(a, c).has("remove_ms"), "saiu no meio da mão: some quando ela acabar")
	# Torneio: o lugar fica guardado (SPEC 6.3), mas aparece como quem saiu.
	var tour: Array = _three({"format": "tournament", "turn_seconds": 0})
	var t_room: Room = tour[0]
	t_room.leave(tour[3])
	assert_true(_member_info(tour[1], tour[3]).get("left", false), "torneio: saiu")
	assert_eq(_member_info(tour[1], tour[3]).get("remove_ms"), 120000, "2 minutos para voltar")
	_clock.advance(30000)
	t_room.announce()
	assert_eq(_member_info(tour[1], tour[3]).get("remove_ms"), 90000, "a contagem anda")
	# Voltou: deixa de aparecer como quem saiu.
	_join(t_room, "Caio", "dev-c")
	assert_false(_member_info(tour[1], tour[3]).get("left", false), "voltou")


func _three_online(raw: Dictionary) -> Array:
	var room: Room = _room(raw, {"away_ms": 120000})
	var a: String = _join(room, "Ana", "dev-a")["id"]
	var b: String = _join(room, "Bia", "dev-b")["id"]
	var c: String = _join(room, "Caio", "dev-c")["id"]
	room.handle(a, {"t": Protocol.START})
	return [room, a, b, c]


func test_away_has_two_minutes_online_only() -> void:
	# Mesma rede e offline (sem prazo): o ausente fica, pagando os blinds.
	var lan: Array = _three({"turn_seconds": 0})
	lan[0].handle(lan[3], {"t": Protocol.AWAY, "on": true})
	assert_false(_member_info(lan[1], lan[3]).has("remove_ms"), "sem contagem fora do Online")
	_clock.advance(600000)
	lan[0].tick()
	assert_true(lan[0].members.has(lan[3]), "continua na sala")
	# Online, clássico: "Voltei" antes dos 2 minutos mantém o lugar.
	var parts: Array = _three_online({"turn_seconds": 0})
	var room: Room = parts[0]
	var a: String = parts[1]
	var c: String = parts[3]
	room.handle(c, {"t": Protocol.AWAY, "on": true})
	assert_eq(_member_info(a, c).get("remove_ms"), 120000, "ausente: 2 minutos")
	_clock.advance(100000)
	room.tick()
	room.handle(c, {"t": Protocol.AWAY, "on": false})
	assert_false(_member_info(a, c).has("remove_ms"), "voltou: sem contagem")
	_clock.advance(60000)
	room.tick()
	assert_true(room.members.has(c), "quem voltou não sai")
	# Ausente de novo e não volta: sai da sala, com as fichas guardadas.
	room.handle(c, {"t": Protocol.AWAY, "on": true})
	_clock.advance(120000)
	_fold_until(room, func() -> bool: return not room.members.has(c))
	assert_false(room.members.has(c), "2 minutos ausente: saiu da sala")
	var left: Array = _inbox.get(c, []).filter(func(m: Dictionary) -> bool:
		return m["t"] == Protocol.LEFT)
	assert_eq(left.back().get("reason") if not left.is_empty() else "", Protocol.R_AWAY,
		"o aparelho dele fica sabendo por quê")
	assert_true(room.table.cashbox.held(c) > 0, "as fichas ficam guardadas, como no Sair")
	assert_true(room.table.is_balanced())
	# Torneio: sai entre as mãos e as fichas vão para quem fica.
	var tour: Array = _three_online({"format": Table.TOURNAMENT, "turn_seconds": 0})
	var t_room: Room = tour[0]
	t_room.handle(tour[3], {"t": Protocol.AWAY, "on": true})
	_clock.advance(120000)
	_fold_until(t_room, func() -> bool: return not t_room.members.has(tour[3]))
	assert_false(t_room.members.has(tour[3]), "torneio: saiu")
	assert_eq(t_room.table.participants().size(), 2)
	assert_true(t_room.table.is_balanced())
