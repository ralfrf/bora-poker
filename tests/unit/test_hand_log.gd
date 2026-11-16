extends "res://tests/test_case.gd"
## Histórico das mãos (SPEC 11.2): as últimas 50 mãos, só com o que foi público, e as
## suas cartas só para você. Jogado pelo caminho de verdade: app → servidor → resposta.

const OfflineGame := preload("res://ui/app/offline_game.gd")
const OfflineOptions := preload("res://ui/app/offline_options.gd")
const HandLog := preload("res://server/hand_log.gd")
const Clock := preload("res://server/clock.gd")
const Protocol := preload("res://server/protocol.gd")

const FAST: Dictionary = {"hand_gap_ms": 0, "showdown_gap_ms": 0, "bot_min_ms": 0,
	"bot_max_ms": 0, "bot_evaluations": 8}

var _seed: int = 0


func _next_seed() -> int:
	_seed += 1
	return _seed


## Joga até a mão número `wanted` terminar (você sempre passa ou paga e recompra).
func _play(game: OfflineGame, clock: Clock, wanted: int) -> HandLog:
	var log: HandLog = null
	for i in 20000:
		clock.advance(250)
		for message: Dictionary in game.update():
			if message["t"] != Protocol.STATE:
				continue
			var you: Dictionary = message["you"]
			if you.has("legal"):
				game.act("check" if you["legal"]["can_check"] else "call", 0)
			elif you.has("rebuy_ms"):
				game.rebuy(true)
		if log == null and game.room_id != "":
			log = game.get("_server").rooms[game.room_id].history
		if log != null and log.last_hand() >= wanted:
			break
	return log


func _ask(game: OfflineGame) -> Array:
	game.history()
	for message: Dictionary in game.update():
		if message["t"] == Protocol.HANDS:
			return message["hands"]
	return []


func test_history_keeps_last_50_public_hands() -> void:
	_seed = 300
	var clock: Clock = Clock.new(true)
	var game: OfflineGame = OfflineGame.new(clock, FAST, _next_seed)
	game.begin("Rafa", 1, "aparelho-teste-0002",
		OfflineOptions.build(OfflineOptions.clean({"seats": 3})))
	var log: HandLog = _play(game, clock, 8)
	var early: Array = _ask(game)
	assert_true(early.size() >= 8, "a resposta traz as mãos jogadas (%d)" % early.size())
	assert_true(int(early[0]["hand"]) > int(early[-1]["hand"]), "a mais recente vem primeiro")
	_play(game, clock, HandLog.LIMIT + 6)
	var hands: Array = _ask(game)
	assert_eq(hands.size(), HandLog.LIMIT, "guarda só as últimas 50")
	assert_true(int(hands[-1]["hand"]) > 1, "as mais antigas saíram")
	var showdowns: int = 0
	for record: Dictionary in hands:
		var played: bool = false
		var seats: Dictionary = {}
		for player: Dictionary in record["players"]:
			seats[int(player["seat"])] = player
			assert_false(player.has("cards"), "ninguém leva cartas na lista de jogadores")
			assert_true(String(player["nick"]) != "", "apelido de cada um")
			if player["id"] == game.my_id:
				played = true
		assert_eq(record.has("mine"), played, "suas cartas só nas mãos que você jogou")
		if played:
			assert_eq((record["mine"] as Array).size(), 2)
		if record["cancelled"]:
			continue
		# As fichas fecham: o que entrou no pote volta em pagamentos e devoluções.
		var put: int = 0
		for street: Dictionary in record["streets"]:
			for action: Dictionary in street["actions"]:
				put += int(action["amount"])
		var back: int = 0
		for entry: Dictionary in record["payouts"] + record["refunds"]:
			back += int(entry["amount"])
		assert_eq(back, put, "fichas da mão %d conferem" % int(record["hand"]))
		assert_true(record["board"].size() <= 5)
		if record["showdown"]:
			showdowns += 1
			assert_false(record["shown"].is_empty(), "showdown mostra quem ganhou")
	assert_true(showdowns >= 3, "teve showdowns (%d)" % showdowns)
	game.leave()


## As cartas de quem não mostrou nunca aparecem para os outros; cada um só recebe as
## próprias.
func test_history_hides_mucked_cards() -> void:
	_seed = 700
	var clock: Clock = Clock.new(true)
	var game: OfflineGame = OfflineGame.new(clock, FAST, _next_seed)
	game.begin("Rafa", 1, "aparelho-teste-0003",
		OfflineOptions.build(OfflineOptions.clean({"seats": 6})))
	var log: HandLog = _play(game, clock, 16)
	var holes: Array = log.get("_holes")
	var public: Array = log.for_member("")
	assert_eq(public.size(), holes.size())
	var hidden_checked: int = 0
	for k in public.size():
		var record: Dictionary = public[k]
		var private_holes: Dictionary = holes[holes.size() - 1 - k]
		assert_false(record.has("mine"), "quem não jogou não recebe cartas fechadas")
		var open: Dictionary = {}
		for entry: Dictionary in record["shown"] + record["revealed"]:
			open[int(entry["seat"])] = true
		var text: String = var_to_str(record)
		for player: Dictionary in record["players"]:
			if open.has(int(player["seat"])):
				continue
			var cards: Array = private_holes.get(player["id"], [])
			var opened_elsewhere: bool = false
			for entry: Dictionary in record["shown"] + record["revealed"]:
				for card: Variant in entry["cards"]:
					if cards.has(int(card)):
						opened_elsewhere = true
			assert_false(opened_elsewhere, "cartas fechadas de %s escondidas" % player["nick"])
			hidden_checked += 1
		assert_false(text.contains("\"mine\""), "nada particular na versão pública")
		# Cada jogador recebe as próprias cartas, e só elas.
		for id: String in private_holes:
			var mine: Array = log.for_member(id)[k].get("mine", [])
			assert_eq(mine, private_holes[id], "cartas de quem pediu")
	assert_true(hidden_checked > 15, "conferiu mãos escondidas (%d)" % hidden_checked)
	game.leave()
