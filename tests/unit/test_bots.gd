extends "res://tests/test_case.gd"
## Bots: tabela de mãos iniciais, força da mão, Monte Carlo e jogadas sempre válidas.

const Cards := preload("res://engine/cards.gd")
const Preflop := preload("res://bots/preflop.gd")
const Equity := preload("res://bots/equity.gd")
const HandStrength := preload("res://bots/hand_strength.gd")
const Roster := preload("res://bots/roster.gd")
const Room := preload("res://server/room.gd")
const Clock := preload("res://server/clock.gd")
const Table := preload("res://engine/table.gd")


func _c(text: String) -> Array:
	return Array(Cards.list_from_text(text))


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func test_preflop_table_has_every_hand() -> void:
	assert_eq(Preflop.EQUITY.size(), 169)
	var total: int = 0
	for i in 169:
		total += Preflop.combos(i)
	assert_eq(total, Preflop.COMBOS, "1.326 combinações")
	var aces: Array = _c("As Ah")
	var worst: Array = _c("7c 2d")
	assert_eq(Preflop.percentile(aces[0], aces[1]), 1.0, "par de ases no topo")
	assert_true(Preflop.percentile(worst[0], worst[1]) < 0.05, "7 e 2 de naipes diferentes no fundo")
	assert_true(absf(Preflop.equity(aces[0], aces[1]) - 0.85) < 0.01, "AA contra mão ao acaso: 85%")
	var suited: Array = _c("Ks Qs")
	var offsuit: Array = _c("Ks Qd")
	assert_true(Preflop.equity(suited[0], suited[1]) > Preflop.equity(offsuit[0], offsuit[1]),
		"mesmo naipe vale mais")
	assert_eq(Preflop.index(suited[1], suited[0]), Preflop.index(suited[0], suited[1]), "ordem não importa")


func test_equity_known_results() -> void:
	var aces: float = Equity.estimate(_c("As Ah"), [], 1, 6000, _rng(1))
	assert_true(absf(aces - 0.85) < 0.025, "AA contra um: %.3f" % aces)
	var three: float = Equity.estimate(_c("As Ah"), [], 3, 6000, _rng(2))
	assert_true(absf(three - 0.64) < 0.03, "AA contra três: %.3f" % three)
	var royal: float = Equity.estimate(_c("As Ks"), _c("Qs Js Ts 2d 3c"), 2, 500, _rng(3))
	assert_eq(royal, 1.0, "sequência real máxima não perde")
	var plain: float = Equity.estimate(_c("Ah Td"), _c("Ac 7h 4s"), 1, 4000, _rng(4))
	var against_bettor: float = Equity.estimate(_c("Ah Td"), _c("Ac 7h 4s"), 1, 4000, _rng(4), 3)
	assert_true(against_bettor < plain - 0.05, "contra quem apostou a chance cai")
	assert_eq(Equity.estimate(_c("As Ah"), [], 0, 100, _rng(5)), 0.5, "sem adversário: neutro")


func test_hand_strength_orders_made_hands() -> void:
	var board: Array = _c("Kd 8c 3h")
	var set: float = HandStrength.made(_c("8s 8h"), board)
	var top_pair: float = HandStrength.made(_c("Ks Qh"), board)
	var low_pair: float = HandStrength.made(_c("3s Qh"), board)
	var nothing: float = HandStrength.made(_c("Js Th"), board)
	assert_true(set > top_pair, "trinca > par de cima")
	assert_true(top_pair > low_pair, "par de cima > par de baixo")
	assert_true(low_pair > nothing, "par > nada")
	for value: float in [set, top_pair, low_pair, nothing]:
		assert_true(value >= 0.0 and value <= 1.0, "força entre 0 e 1")
	assert_true(HandStrength.made(_c("2s 4h"), _c("Kd Kc Kh Ks 9d")) < 0.5,
		"a mesa jogando sozinha não é força do jogador")


func test_outs_count_draws() -> void:
	assert_eq(HandStrength.outs(_c("As 5s"), _c("Ks 8s 2d")), 9, "projeto de flush")
	assert_eq(HandStrength.outs(_c("9c 8d"), _c("7h 6s 2c")), 8, "sequência aberta")
	assert_eq(HandStrength.outs(_c("9c 8d"), _c("7h 6s 2c 3d Kd")), 0, "no river não há projeto")
	assert_eq(HandStrength.outs(_c("2c 3d"), _c("Ks 8s 4s")), 0, "o projeto da mesa não é do jogador")


func test_roster_names_and_styles() -> void:
	var rng: RandomNumberGenerator = _rng(9)
	var taken: Array = []
	for _i in 8:
		var pick: Dictionary = Roster.pick(rng, taken)
		assert_false(taken.has(pick["name"]), "nome repetido na sala")
		assert_true(Roster.STYLES.has(pick["style"]))
		taken.append(pick["name"])
	assert_true(Roster.is_level(1) and Roster.is_level(3))
	assert_false(Roster.is_level(0) or Roster.is_level("2"))


## Bots com nome de homem usam os retratos de homens, e os de mulher os de mulheres;
## na mesma mesa, nenhum rosto se repete.
func test_bot_avatars_follow_the_name() -> void:
	var gender_of: Dictionary = {}
	for entry: Array in Roster.NAMES:
		assert_true(entry[2] == "m" or entry[2] == "f", "nome sem grupo: " + entry[0])
		gender_of[entry[0]] = entry[2]
	var photos: Array[int] = Roster.MEN_AVATARS + Roster.WOMEN_AVATARS
	assert_eq(photos.size(), Room.AVATARS - 10, "os grupos cobrem todos os retratos")
	for avatar: int in photos:
		assert_true(avatar >= 10 and avatar < Room.AVATARS)
		assert_eq(photos.count(avatar), 1, "retrato em dois grupos")
	for seed_value: int in [1, 2, 3, 4, 5]:
		var room: Room = _bot_table([1, 2, 3, 1, 2, 3, 1, 2, 3], "", Table.CLASSIC, seed_value, 0)
		var faces: Array = []
		for member: Variant in room.members.values():
			var group: Array[int] = Roster.WOMEN_AVATARS if gender_of[member.nick] == "f" 				else Roster.MEN_AVATARS
			assert_true(group.has(member.avatar), "%s com retrato do outro grupo" % member.nick)
			assert_false(faces.has(member.avatar), "rosto repetido na mesa")
			faces.append(member.avatar)
	# Com o grupo todo em uso, repete um rosto do mesmo grupo.
	var rng: RandomNumberGenerator = _rng(3)
	assert_true(Roster.MEN_AVATARS.has(Roster.avatar_for(rng, "m", Roster.MEN_AVATARS)))


## Mesa só de bots, pela sala de verdade: nenhuma jogada pode ser recusada.
func _bot_table(levels: Array, style: String, format: String, seed_value: int, hands: int) -> Room:
	var normalized: Dictionary = Room.normalize_options(
		{"format": format, "seats": levels.size(), "bots": levels, "turn_seconds": 0})
	var counter: Array = [seed_value]
	var next: Callable = func() -> int:
		counter[0] += 1
		return counter[0]
	var config: Dictionary = {"hand_gap_ms": 0, "showdown_gap_ms": 0, "bot_min_ms": 0,
		"bot_max_ms": 0, "allow_empty": true, "bot_evaluations": 150, "bot_style": style}
	var clock: Clock = Clock.new(true)
	var room: Room = Room.new("BOTS", normalized["options"], clock, Callable(), config, next)
	room.start()
	var guard: int = 0
	while not room.is_closed() and room.table.hand_number < hands and guard < hands * 40:
		clock.advance(1000)
		room.tick()
		guard += 1
	return room


func test_every_level_and_style_plays_only_legal_moves() -> void:
	var seed_value: int = 100
	for style: String in Roster.STYLES.keys():
		var room: Room = _bot_table([1, 2, 3, 1, 2, 3], style, Table.CLASSIC, seed_value, 60)
		assert_eq(room.bot_errors, 0, "jogadas recusadas no estilo " + style)
		assert_true(room.table.hand_number >= 60, "a mesa não travou no estilo " + style)
		assert_true(room.table.is_balanced())
		seed_value += 1000


func test_heads_up_and_short_stacks_stay_legal() -> void:
	var room: Room = _bot_table([3, 2], "", Table.TOURNAMENT, 7, 400)
	assert_eq(room.bot_errors, 0, "torneio mano a mano")
	assert_true(room.is_closed() or room.table.hand_number >= 400)
