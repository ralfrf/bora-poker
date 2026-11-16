extends "res://tests/test_case.gd"
## Sala do servidor (server/room.gd): começar, vez, estouros, ausência, pausa, recompra,
## expulsão, bots, dono, encerramento e torneio. Relógio manual e sementes fixas.

const Room := preload("res://server/room.gd")
const Clock := preload("res://server/clock.gd")
const Protocol := preload("res://server/protocol.gd")
const Table := preload("res://engine/table.gd")
const Hand := preload("res://engine/hand.gd")

## Sem esperas: as mãos seguem uma atrás da outra.
const FAST: Dictionary = {"hand_gap_ms": 0, "showdown_gap_ms": 0, "bot_min_ms": 0, "bot_max_ms": 0,
	"bot_evaluations": 120}

var _inbox: Dictionary = {}
var _clock: Clock = null
var _seed: int = 0


func _room(raw: Dictionary, config: Dictionary = {}) -> Room:
	var normalized: Dictionary = Room.normalize_options(raw)
	assert_true(normalized["ok"], "opções: " + str(normalized["error"]))
	_inbox = {}
	_clock = Clock.new(true)
	_seed = 1000
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


func _join(room: Room, nick: String, device: String = "") -> String:
	var result: Dictionary = room.join({"nick": nick, "avatar": 0, "device": device})
	assert_true(result["ok"], "entrar: " + str(result["error"]))
	room.announce()
	return result["id"]


func _last(id: String, type: String) -> Dictionary:
	var list: Array = _inbox.get(id, [])
	for i in range(list.size() - 1, -1, -1):
		if list[i]["t"] == type:
			return list[i]
	return {}


func _count(id: String, type: String) -> int:
	return _inbox.get(id, []).filter(func(m: Dictionary) -> bool: return m["t"] == type).size()


func _to_act(room: Room) -> String:
	if not room.table.hand_in_progress():
		return ""
	return room.member_at(room.table.hand.to_act).id


func _act(room: Room, id: String, action: String, amount: int = 0) -> void:
	room.handle(id, {"t": Protocol.ACT, "seq": int(_last(id, Protocol.STATE)["table"]["seq"]),
		"action": action, "amount": amount})


## Quem está na vez vai all-in (ou paga o all-in de outro).
func _shove(room: Room) -> void:
	var id: String = _to_act(room)
	var legal: Dictionary = room.table.hand.legal_actions()
	if legal["can_raise"]:
		_act(room, id, Hand.BET if legal["is_bet"] else Hand.RAISE, int(legal["max_to"]))
	elif legal["can_check"]:
		_act(room, id, Hand.CHECK)
	else:
		_act(room, id, Hand.CALL)


## Joga all-in até alguém zerar. Devolve o id de quem zerou.
func _bust_someone(room: Room) -> String:
	for _i in 400:
		for member: Room.Member in room.members.values():
			if member.rebuy_offer or (member.seat < 0 and not member.is_bot and room.table.knows(member.id)):
				return member.id
		if room.is_closed():
			return ""
		if room.table.hand_in_progress():
			_shove(room)
		else:
			room.tick()
	return ""


func _classic_pair(extra: Dictionary = {}) -> Array:
	var raw: Dictionary = {"format": Table.CLASSIC, "seats": 4}
	raw.merge(extra, true)
	var room: Room = _room(raw)
	var a: String = _join(room, "Ana", "dev-a")
	var b: String = _join(room, "Bruno", "dev-b")
	return [room, a, b]


func _total_chips(room: Room) -> int:
	return room.table.chips_on_seats() + room.table.chips_in_hand()


# ---------------------------------------------------------------- opções e entrada


func test_options_defaults_and_refusals() -> void:
	var ok: Dictionary = Room.normalize_options({})
	assert_true(ok["ok"])
	assert_eq(ok["options"]["seats"], 4)
	assert_eq(ok["options"]["turn_seconds"], 30)
	assert_eq(ok["options"]["starting_stack"], 2000)
	assert_false(Room.normalize_options({"seats": 1})["ok"], "1 lugar")
	assert_false(Room.normalize_options({"seats": 10})["ok"], "10 lugares")
	assert_true(Room.normalize_options({"seats": 9})["ok"], "9 lugares (mesa cheia)")
	assert_false(Room.normalize_options({"turn_seconds": 20})["ok"], "tempo fora da lista")
	assert_false(Room.normalize_options({"format": "x"})["ok"], "formato")
	assert_false(Room.normalize_options({"bots": [4]})["ok"], "nível de bot")
	assert_false(Room.normalize_options({"seats": 2, "bots": [1, 1, 1]})["ok"], "bots demais")
	assert_false(Room.normalize_options({"big_blind": 5000})["ok"], "blind maior que as fichas")
	assert_false(Room.normalize_options("x")["ok"], "não é dicionário")
	var tour: Dictionary = Room.normalize_options({"format": Table.TOURNAMENT, "keep_open": true})
	assert_false(tour["options"]["keep_open"], "torneio nunca fica aberto")


func test_nick_cleanup_and_duplicates() -> void:
	assert_eq(Room.clean_nick("  Zé\n "), "Zé")
	assert_eq(Room.clean_nick(""), "Jogador")
	assert_eq(Room.clean_nick("abcdefghijklmnopqrstuvwxyz").length(), 16)
	var room: Room = _room({})
	var a: String = _join(room, "Ana")
	var b: String = _join(room, "Ana")
	var c: String = _join(room, "Ana")
	assert_eq(room.members[a].nick, "Ana")
	assert_eq(room.members[b].nick, "Ana 2")
	assert_eq(room.members[c].nick, "Ana 3")
	assert_eq(room.owner_id, a, "o primeiro é o dono")
	assert_eq(room.name, "Sala de Ana")


func test_full_room_seats_as_spectator() -> void:
	var room: Room = _room({"seats": 2})
	var a: String = _join(room, "A")
	var b: String = _join(room, "B")
	var c: String = _join(room, "C")
	assert_eq(room.members[a].seat, 0)
	assert_eq(room.members[b].seat, 1)
	assert_eq(room.members[c].seat, -1, "sem lugar, assiste")


# ---------------------------------------------------------------- começar e vez


func test_start_needs_owner_and_two_players() -> void:
	var room: Room = _room({})
	var a: String = _join(room, "Ana")
	room.handle(a, {"t": Protocol.START})
	assert_eq(_last(a, Protocol.ERROR).get("code"), Protocol.E_REFUSED, "sozinho não começa")
	var b: String = _join(room, "Bruno")
	room.handle(b, {"t": Protocol.START})
	assert_eq(room.phase, Protocol.LOBBY, "só o dono começa")
	room.handle(a, {"t": Protocol.START})
	assert_eq(room.phase, Protocol.PLAYING)
	assert_true(room.table.hand_in_progress(), "a primeira mão começou")
	var who: String = _to_act(room)
	assert_true(_last(who, Protocol.STATE)["you"].has("legal"), "quem está na vez recebe as ações")
	var other: String = b if who == a else a
	assert_false(_last(other, Protocol.STATE)["you"].has("legal"), "o outro não recebe")
	assert_eq(_last(other, Protocol.STATE)["you"]["cards"].size(), 2, "cada um vê as próprias cartas")


func test_turn_order_and_stale_seq() -> void:
	var pair: Array = _classic_pair()
	var room: Room = pair[0]
	room.handle(pair[1], {"t": Protocol.START})
	var who: String = _to_act(room)
	var other: String = pair[2] if who == pair[1] else pair[1]
	_act(room, other, Hand.CALL)
	assert_eq(_last(other, Protocol.ERROR).get("text"), "não é a sua vez")
	var old_seq: int = int(_last(who, Protocol.STATE)["table"]["seq"])
	_act(room, who, Hand.CALL)
	assert_eq(_to_act(room), other, "a vez passou")
	room.handle(other, {"t": Protocol.ACT, "seq": old_seq, "action": Hand.CHECK, "amount": 0})
	assert_eq(_last(other, Protocol.ERROR).get("text"), "essa jogada chegou atrasada")
	room.handle(other, {"t": Protocol.ACT, "seq": "1", "action": Hand.CHECK})
	assert_eq(_last(other, Protocol.ERROR).get("text"), "jogada malformada")
	room.handle(other, {"t": "dance"})
	assert_eq(_last(other, Protocol.ERROR).get("code"), Protocol.E_BAD_MESSAGE)


# ---------------------------------------------------------------- tempo e ausência


func test_timeout_checks_or_folds_and_two_make_away() -> void:
	var pair: Array = _classic_pair()
	var room: Room = pair[0]
	room.handle(pair[1], {"t": Protocol.START})
	var who: String = _to_act(room)
	var hand_before: int = room.table.hand_number
	_clock.advance(29999)
	room.tick()
	assert_eq(_to_act(room), who, "antes do prazo nada muda")
	_clock.advance(1)
	room.tick()
	# Pré-flop, o small blind não pode passar: desiste e a mão acaba.
	assert_eq(room.table.hand_number, hand_before + 1, "desistiu e começou outra mão")
	assert_eq(room.members[who].timeouts, 1)
	assert_false(room.members[who].away, "um estouro ainda não é ausência")
	var timeout_seen: bool = _inbox[who].any(func(m: Dictionary) -> bool:
		return m["t"] == Protocol.STATE and m["events"].any(func(e: Dictionary) -> bool:
			return e["type"] == "timeout"))
	assert_true(timeout_seen, "evento de estouro")
	for _i in 10:
		if room.members[who].away:
			break
		_clock.advance(30000)
		room.tick()
	assert_true(room.members[who].away, "dois estouros seguidos: ausente")
	assert_true(room.table.seat_at(room.members[who].seat).away, "a mesa sabe")
	room.handle(who, {"t": Protocol.AWAY, "on": false})
	assert_false(room.members[who].away, "Voltei")
	assert_eq(room.members[who].timeouts, 0)
	assert_false(room.table.seat_at(room.members[who].seat).away)


func test_away_player_sits_out_of_hands() -> void:
	var room: Room = _room({"turn_seconds": 0})
	var a: String = _join(room, "A")
	var b: String = _join(room, "B")
	var c: String = _join(room, "C")
	room.handle(c, {"t": Protocol.AWAY, "on": true})
	room.handle(a, {"t": Protocol.START})
	assert_true(room.table.hand_in_progress())
	assert_true(room.table.hand.player_at(room.members[c].seat) == null, "ausente fica fora da mão")
	assert_true(room.table.hand.player_at(room.members[b].seat) != null)
	room.handle(c, {"t": Protocol.AWAY, "on": false})
	# Termina a mão: na próxima, C volta a receber cartas.
	var guard: int = 0
	var number: int = room.table.hand_number
	while room.table.hand_number == number and guard < 20:
		_act(room, _to_act(room), Hand.FOLD)
		guard += 1
	assert_true(room.table.hand.player_at(room.members[c].seat) != null, "depois do Voltei joga de novo")


func test_human_action_resets_timeouts() -> void:
	var pair: Array = _classic_pair()
	var room: Room = pair[0]
	room.handle(pair[1], {"t": Protocol.START})
	var who: String = _to_act(room)
	room.members[who].timeouts = 1
	_act(room, who, Hand.CALL)
	assert_eq(room.members[who].timeouts, 0)


func test_pause_freezes_clocks() -> void:
	var pair: Array = _classic_pair()
	var room: Room = pair[0]
	var owner: String = pair[1]
	room.handle(owner, {"t": Protocol.START})
	var who: String = _to_act(room)
	_clock.advance(10000)
	room.handle(owner, {"t": Protocol.OWNER, "cmd": Protocol.CMD_PAUSE})
	assert_true(room.paused)
	_clock.advance(500000)
	room.tick()
	assert_eq(_to_act(room), who, "pausada, ninguém estoura")
	assert_eq(int(_last(who, Protocol.STATE)["table"]["turn_ms"]), 20000, "o prazo parou em 20 s")
	_act(room, who, Hand.CALL)
	assert_eq(_last(who, Protocol.ERROR).get("text"), "a mesa está pausada")
	room.handle(pair[2], {"t": Protocol.OWNER, "cmd": Protocol.CMD_RESUME})
	assert_true(room.paused, "só o dono retoma")
	room.handle(owner, {"t": Protocol.OWNER, "cmd": Protocol.CMD_RESUME})
	assert_false(room.paused)
	_clock.advance(19999)
	room.tick()
	assert_eq(_to_act(room), who, "faltava 1 ms")
	_clock.advance(1)
	room.tick()
	assert_eq(room.members[who].timeouts, 1, "agora estourou")


# ---------------------------------------------------------------- recompra


func test_rebuy_accepted() -> void:
	var pair: Array = _classic_pair()
	var room: Room = pair[0]
	room.handle(pair[1], {"t": Protocol.START})
	var loser: String = _bust_someone(room)
	assert_true(loser != "", "alguém zerou")
	assert_eq(int(_last(loser, Protocol.STATE)["you"]["rebuy_ms"]), -1, "oferta sem prazo")
	_clock.advance(3600000)
	room.tick()
	assert_true(room.members[loser].rebuy_offer, "uma hora depois a oferta continua")
	room.handle(loser, {"t": Protocol.REBUY, "accept": true})
	var seat: Table.Seat = room.table.seat_at(room.members[loser].seat)
	assert_eq(seat.rebuys, 1)
	assert_false(room.members[loser].rebuy_offer)
	var mine: Array = _last(loser, Protocol.STATE)["room"]["members"].filter(
		func(m: Dictionary) -> bool: return m["id"] == loser)
	assert_eq(int(mine[0]["rebuys"]), 1, "o marcador de recompras viaja para todos")
	assert_true(room.table.hand_in_progress(), "o jogo seguiu")
	assert_eq(_total_chips(room), 6000, "duas entradas e uma recompra")
	assert_true(room.table.is_balanced())


func test_rebuy_declined_then_sits_again() -> void:
	var pair: Array = _classic_pair()
	var room: Room = pair[0]
	room.handle(pair[1], {"t": Protocol.START})
	var loser: String = _bust_someone(room)
	room.handle(loser, {"t": Protocol.REBUY, "accept": false})
	assert_eq(room.members[loser].seat, -1, "virou espectador")
	assert_false(room.is_closed(), "pode voltar recomprando, a sala não acaba")
	room.handle(loser, {"t": Protocol.SIT})
	assert_true(room.members[loser].seat >= 0, "sentou de novo")
	room.tick()
	assert_true(room.table.hand_in_progress(), "voltou a jogar")
	assert_true(room.table.is_balanced())


## Com prazo configurado (hoje não se usa; o padrão é sem prazo), a oferta vence.
func test_rebuy_offer_expires() -> void:
	var room: Room = _room({"format": Table.CLASSIC, "seats": 4}, {"rebuy_ms": 60000})
	var pair: Array = [room, _join(room, "Ana", "dev-a"), _join(room, "Bruno", "dev-b")]
	room.handle(pair[1], {"t": Protocol.START})
	var loser: String = _bust_someone(room)
	_clock.advance(59999)
	room.tick()
	assert_true(room.members[loser].rebuy_deadline >= 0, "ainda no prazo")
	_clock.advance(1)
	room.tick()
	assert_eq(room.members[loser].seat, -1, "o prazo venceu")
	var events: Array = _last(loser, Protocol.STATE)["events"]
	assert_true(events.any(func(e: Dictionary) -> bool: return e["type"] == "rebuy_declined"))


func test_classic_without_rebuy_ends_alone() -> void:
	var pair: Array = _classic_pair({"rebuy_limit": 0})
	var room: Room = pair[0]
	room.handle(pair[1], {"t": Protocol.START})
	_bust_someone(room)
	room.tick()
	assert_true(room.is_closed(), "sobrou um só")
	var closed: Dictionary = _last(pair[1], Protocol.CLOSED)
	assert_eq(closed.get("reason"), Protocol.R_FINISHED)
	assert_eq(closed["scoreboard"].size(), 2)
	assert_eq(closed["podium"].size(), 0, "pódio só no torneio")


# ---------------------------------------------------------------- dono, expulsão e bots


func test_kick_mid_hand_folds_and_bans() -> void:
	var room: Room = _room({"turn_seconds": 0})
	var a: String = _join(room, "A", "dev-a")
	var b: String = _join(room, "B", "dev-b")
	var c: String = _join(room, "C", "dev-c")
	room.handle(a, {"t": Protocol.START})
	room.handle(b, {"t": Protocol.OWNER, "cmd": Protocol.CMD_KICK, "id": c})
	assert_eq(_last(b, Protocol.ERROR).get("code"), Protocol.E_REFUSED, "só o dono expulsa")
	room.handle(a, {"t": Protocol.OWNER, "cmd": Protocol.CMD_KICK, "id": c})
	assert_eq(_last(c, Protocol.LEFT).get("reason"), Protocol.R_KICKED)
	var count_before: int = _count(c, Protocol.STATE)
	var number: int = room.table.hand_number
	var guard: int = 0
	while room.table.hand_number == number and guard < 20:
		var who: String = _to_act(room)
		assert_true(who != c, "o expulso não joga")
		_act(room, who, Hand.FOLD)
		guard += 1
	assert_false(room.members.has(c), "saiu da sala ao fim da mão")
	assert_eq(_count(c, Protocol.STATE), count_before, "o expulso não recebe mais nada")
	assert_true(room.table.is_balanced(), "as fichas dele viraram saída")
	assert_eq(room.table.cashbox.held(c), 0, "expulso perde as fichas")
	assert_false(room.join({"nick": "C", "device": "dev-c"})["ok"], "não entra de novo")


func test_leave_keeps_chips_held_for_ten_minutes() -> void:
	var room: Room = _room({"turn_seconds": 0})
	var a: String = _join(room, "A", "dev-a")
	var b: String = _join(room, "B", "dev-b")
	var c: String = _join(room, "C", "dev-c")
	room.handle(a, {"t": Protocol.START})
	room.leave(c)
	var guard: int = 0
	while room.members.has(c) and guard < 20:
		_act(room, _to_act(room), Hand.FOLD)
		guard += 1
	assert_true(room.table.cashbox.held(c) > 0, "fichas guardadas")
	assert_true(room.table.is_balanced())
	_clock.advance(600000)
	room.tick()
	assert_eq(room.table.cashbox.held(c), 0, "prazo vencido: saíram da mesa")
	assert_true(room.table.is_balanced())
	assert_true(b != "")


func test_owner_passes_to_oldest_and_empty_room_closes() -> void:
	var room: Room = _room({})
	var a: String = _join(room, "A")
	var b: String = _join(room, "B")
	var c: String = _join(room, "C")
	room.leave(a)
	assert_eq(room.owner_id, b, "o mais antigo assume")
	room.leave(b)
	assert_eq(room.owner_id, c)
	room.leave(c)
	assert_true(room.is_closed(), "sem humanos, fecha")
	assert_eq(room.final.get("reason"), Protocol.R_EMPTY)


func test_bots_add_remove_and_play() -> void:
	var room: Room = _room({"bots": [1, 2]})
	assert_eq(room.members.size(), 2, "dois bots na criação")
	var a: String = _join(room, "Ana")
	assert_eq(room.owner_id, a, "bot nunca é dono")
	room.handle(a, {"t": Protocol.OWNER, "cmd": Protocol.CMD_ADD_BOT, "level": 3})
	assert_eq(room.members.size(), 4)
	var bot_id: String = ""
	for member: Room.Member in room.members.values():
		if member.is_bot and member.level == 3:
			bot_id = member.id
	room.handle(a, {"t": Protocol.OWNER, "cmd": Protocol.CMD_REMOVE_BOT, "id": bot_id})
	assert_false(room.members.has(bot_id), "bot retirado")
	room.handle(a, {"t": Protocol.OWNER, "cmd": Protocol.CMD_REMOVE_BOT, "id": a})
	assert_eq(_last(a, Protocol.ERROR).get("text"), "bot não encontrado")
	room.handle(a, {"t": Protocol.START})
	for _i in 200:
		if room.table.hand_number >= 3 and _to_act(room) == a:
			break
		if _to_act(room) == a:
			_act(room, a, Hand.FOLD)
		else:
			_clock.advance(100)
			room.tick()
	assert_true(room.table.hand_number >= 3, "os bots jogam sozinhos até a vez do humano")
	assert_eq(room.bot_errors, 0, "nenhuma jogada de bot recusada")
	assert_true(room.table.is_balanced())


func test_bot_waits_its_delay() -> void:
	var room: Room = _room({"bots": [1]}, {"bot_min_ms": 1000, "bot_max_ms": 3000})
	var a: String = _join(room, "Ana")
	room.handle(a, {"t": Protocol.START})
	var guard: int = 0
	while _to_act(room) == a and guard < 10:
		_act(room, a, Hand.CALL if not room.table.hand.legal_actions()["can_check"] else Hand.CHECK)
		guard += 1
	var bot_seq: int = int(_last(a, Protocol.STATE)["table"]["seq"])
	_clock.advance(999)
	room.tick()
	assert_eq(int(_last(a, Protocol.STATE)["table"]["seq"]), bot_seq, "antes de 1 s o bot não age")
	_clock.advance(2001)
	room.tick()
	assert_true(int(_last(a, Protocol.STATE)["table"]["seq"]) > bot_seq, "até 3 s o bot agiu")


func test_settings_apply_between_hands() -> void:
	var pair: Array = _classic_pair({"turn_seconds": 0})
	var room: Room = pair[0]
	var owner: String = pair[1]
	room.handle(owner, {"t": Protocol.START})
	room.handle(owner, {"t": Protocol.OWNER, "cmd": Protocol.CMD_SETTINGS, "small_blind": 20, "big_blind": 40})
	assert_eq(room.table.big_blind, 20, "na mão atual não muda")
	_act(room, _to_act(room), Hand.FOLD)
	assert_eq(room.table.big_blind, 40, "vale a partir da mão seguinte")
	assert_eq(room.options["big_blind"], 40)
	room.handle(owner, {"t": Protocol.OWNER, "cmd": Protocol.CMD_SETTINGS, "small_blind": 50, "big_blind": 10})
	assert_eq(_last(owner, Protocol.ERROR).get("text"), "blinds inválidos")


func test_close_mid_hand_refunds_bets() -> void:
	var pair: Array = _classic_pair()
	var room: Room = pair[0]
	room.handle(pair[1], {"t": Protocol.START})
	_act(room, _to_act(room), Hand.CALL)
	room.handle(pair[1], {"t": Protocol.OWNER, "cmd": Protocol.CMD_CLOSE})
	assert_true(room.is_closed())
	assert_false(room.table.hand_in_progress(), "mão cancelada")
	assert_eq(room.table.chips_on_seats(), 4000, "apostas devolvidas")
	for id: String in [pair[1], pair[2]]:
		assert_eq(_last(id, Protocol.CLOSED).get("reason"), Protocol.R_OWNER)
	assert_false(room.join({"nick": "X"})["ok"], "sala encerrada não aceita ninguém")


# ---------------------------------------------------------------- torneio


func test_tournament_levels_rise_with_room_time() -> void:
	var room: Room = _room({"format": Table.TOURNAMENT, "level_minutes": 3, "turn_seconds": 0})
	var a: String = _join(room, "A")
	var b: String = _join(room, "B")
	room.handle(a, {"t": Protocol.START})
	assert_eq(int(_last(a, Protocol.STATE)["table"]["level_ms"]), 180000)
	assert_eq(room.table.level, 0)
	_clock.advance(180000)
	_act(room, _to_act(room), Hand.FOLD)
	assert_eq(room.table.level, 1, "a mão seguinte já é do nível 2")
	assert_true(room.table.big_blind > 20)
	room.handle(a, {"t": Protocol.OWNER, "cmd": Protocol.CMD_ADD_BOT, "level": 1})
	assert_eq(_last(a, Protocol.ERROR).get("text"), "o torneio já começou")
	assert_true(b != "")


func test_tournament_runs_to_podium() -> void:
	var room: Room = _room({"format": Table.TOURNAMENT, "level_minutes": 3, "bots": [1, 2, 3, 2]},
		{"allow_empty": true})
	assert_eq(room.start(), "")
	for _i in 20000:
		if room.is_closed():
			break
		_clock.advance(5000)
		room.tick()
	assert_true(room.is_closed(), "o torneio terminou")
	assert_eq(room.final.get("reason"), Protocol.R_FINISHED)
	var podium: Array = room.final["podium"]
	assert_eq(podium.size(), 3, "pódio com 1º, 2º e 3º")
	assert_eq(room.final["scoreboard"].size(), 4, "o placar tem todos")
	assert_eq(int(podium[0]["place"]), 1)
	assert_true(str(podium[0]["nick"]) != "", "o pódio tem os apelidos")
	assert_eq(room.bot_errors, 0)
	assert_eq(_total_chips(room), 12000, "as fichas do torneio se conservam")


func test_tournament_leaver_keeps_paying_blinds() -> void:
	var room: Room = _room({"format": Table.TOURNAMENT, "turn_seconds": 0})
	var a: String = _join(room, "A")
	var b: String = _join(room, "B")
	var c: String = _join(room, "C")
	room.handle(a, {"t": Protocol.START})
	room.leave(c)
	assert_true(room.members[c].gone, "o lugar fica")
	for _i in 30:
		var who: String = _to_act(room)
		if who == "":
			break
		assert_true(who != c, "quem saiu não espera a vez: desiste na hora")
		_act(room, who, Hand.FOLD)
	assert_true(room.table.hand_number > 3)
	assert_true(b != "")
