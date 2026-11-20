extends "res://tests/test_case.gd"
## Modo offline (SPEC 2 e 8): a sessão do app com o servidor dentro dele, as escolhas da
## mesa offline e o perfil guardado no celular.

const OfflineGame := preload("res://ui/app/offline_game.gd")
const OfflineOptions := preload("res://ui/app/offline_options.gd")
const Profile := preload("res://ui/app/profile.gd")
const Clock := preload("res://server/clock.gd")
const Room := preload("res://server/room.gd")
const Protocol := preload("res://server/protocol.gd")
const Tables := preload("res://ui/theme/tables.gd")
const PotMath := preload("res://ui/table/pot_math.gd")

const FAST: Dictionary = {"hand_gap_ms": 0, "showdown_gap_ms": 0, "bot_min_ms": 0,
	"bot_max_ms": 0, "bot_evaluations": 120}
const TEST_PROFILE: String = "user://perfil_teste.cfg"

var _seed: int = 0


func _next_seed() -> int:
	_seed += 1
	return _seed


func _game(clock: Clock) -> OfflineGame:
	_seed = 900
	return OfflineGame.new(clock, FAST, _next_seed)


## O app joga como um humano que sempre passa ou paga, até completar várias mãos.
func test_offline_plays_full_hands() -> void:
	var clock: Clock = Clock.new(true)
	var game: OfflineGame = _game(clock)
	var choice: Dictionary = OfflineOptions.clean({"seats": 4})
	game.begin("Rafa", 1, "aparelho-teste-0001", OfflineOptions.build(choice))
	var hands: int = 0
	var showdowns: int = 0
	var errors: int = 0
	var my_turns: int = 0
	for i in 4000:
		clock.advance(250)
		for message: Dictionary in game.update():
			if message["t"] == Protocol.ERROR:
				errors += 1
			if message["t"] != Protocol.STATE:
				continue
			for event: Dictionary in message["events"]:
				if event["type"] == "end":
					hands += 1
				elif event["type"] == "showdown":
					showdowns += 1
			var you: Dictionary = message["you"]
			if you.has("legal"):
				my_turns += 1
				game.act("check" if you["legal"]["can_check"] else "call", 0)
			elif you.has("rebuy_ms"):
				game.rebuy(true)
		if hands >= 12 or not game.final.is_empty():
			break
	assert_eq(game.my_id.begins_with("p"), true, "entrou na sala")
	assert_true(hands >= 12, "completou mãos (%d)" % hands)
	assert_true(showdowns >= 1, "teve showdown")
	assert_true(my_turns >= 12, "jogou na própria vez (%d)" % my_turns)
	assert_eq(errors, 0, "nenhuma jogada recusada")
	var state: Dictionary = game.last_state
	assert_eq(state["room"]["members"].size(), 4, "você e três bots")
	var final: Dictionary = game.leave()
	assert_eq(final.get("t", ""), Protocol.CLOSED, "sair devolve o placar")
	var nicks: Array = []
	for row: Dictionary in final.get("scoreboard", []):
		nicks.append(row["nick"])
	assert_true(nicks.has("Rafa"), "você está no placar")
	assert_eq(final["scoreboard"].size(), 4, "placar com os quatro lugares")


## Jogada com número de vez velho é recusada (toque atrasado).
func test_offline_stale_tap_is_refused() -> void:
	var clock: Clock = Clock.new(true)
	var game: OfflineGame = _game(clock)
	game.begin("Rafa", 0, "aparelho-teste-0002", OfflineOptions.build(OfflineOptions.clean({"seats": 2})))
	var refused: bool = false
	for i in 400:
		clock.advance(250)
		for message: Dictionary in game.update():
			if message["t"] == Protocol.ERROR:
				refused = true
			if message["t"] == Protocol.STATE and message["you"].has("legal") and not refused:
				game.last_state["table"]["seq"] = int(message["table"]["seq"]) - 1
				game.act("fold", 0)
		if refused:
			break
	assert_true(refused, "a jogada velha foi recusada")


## Toda combinação da tela offline vira opções que o servidor aceita, com a mesa cheia.
func test_offline_options_are_valid() -> void:
	for format in 2:
		for seats in range(OfflineOptions.MIN_SEATS, OfflineOptions.MAX_SEATS + 1):
			for bots in OfflineOptions.BOT_LEVELS.size():
				for k in 5:
					var choice: Dictionary = OfflineOptions.clean({"format": format,
						"seats": seats, "bots": bots, "stack": k % 4, "blinds": (k + 1) % 4,
						"t_stack": k % 3, "minutes": k % 4, "turn": k % 4, "rebuys": k})
					var checked: Dictionary = Room.normalize_options(OfflineOptions.build(choice))
					if not checked["ok"]:
						fail("recusada: %s (%s)" % [str(choice), checked["error"]])
						return
					assert_eq((checked["options"]["bots"] as Array).size(), seats - 1)
	var mixed: Array = OfflineOptions.bot_levels({"seats": 5, "bots": 3})
	assert_eq(mixed, [1, 2, 3, 1], "misto alterna os níveis")


func test_offline_options_clean_restores_defaults() -> void:
	var choice: Dictionary = OfflineOptions.clean({"seats": 12, "format": "x", "turn": 3,
		"rebuys": 9})
	assert_eq(choice["seats"], OfflineOptions.DEFAULT_SEATS)
	assert_eq(choice["format"], 0)
	assert_eq(choice["turn"], 3)
	assert_eq(choice["rebuys"], OfflineOptions.DEFAULTS["rebuys"])
	assert_eq(OfflineOptions.blind_labels()[0], "0,05/0,10")


## Mesa da sala (SPEC 12): o dono escolhe, o servidor confere e todos recebem nas opções.
func test_felt_choice() -> void:
	assert_eq(Tables.ALL.keys(), Array(Room.FELTS), "as mesmas mesas no servidor e na tela")
	assert_eq(Room.normalize_options({})["options"]["felt"], Room.DEFAULT_FELT, "padrão")
	assert_eq(Room.normalize_options({"felt": "rubi"})["options"]["felt"], "rubi")
	assert_eq(Room.normalize_options({"felt": "dourada"})["options"]["felt"], "salao",
		"mesa desconhecida vira a Salão, sem recusar a sala")
	assert_eq(Room.normalize_options({"felt": 3})["options"]["felt"], "salao")
	var choice: Dictionary = OfflineOptions.clean({"seats": 3})
	assert_eq(OfflineOptions.build(choice)["felt"], "salao", "sem escolha, a Salão")
	choice["felt"] = "perola"
	assert_eq(OfflineOptions.build_room(choice)["felt"], "perola")
	var clock: Clock = Clock.new(true)
	var game: OfflineGame = _game(clock)
	game.begin("Rafa", 1, "aparelho-teste-0002", OfflineOptions.build(choice))
	var felt: String = ""
	for i in 20:
		clock.advance(250)
		for message: Dictionary in game.update():
			if message["t"] == Protocol.STATE:
				felt = str(message.get("room", {}).get("options", {}).get("felt", ""))
		if felt != "":
			break
	assert_eq(felt, "perola", "a mesa chega a quem joga")


func test_profile_round_trip() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE))
	var profile: Profile = Profile.new()
	profile.load_file(TEST_PROFILE)
	assert_true(profile.is_new(), "sem arquivo, perfil novo")
	assert_eq(profile.device.length(), 24, "código do aparelho criado")
	profile.set_nick("   Rafa da Silva Sauro Pereira  ")
	profile.avatar = 2
	profile.last_mode = Profile.MODE_OFFLINE
	profile.offline = {"seats": 6}
	assert_eq(profile.felt, "salao", "mesa padrão")
	profile.felt = "safira"
	assert_true(profile.save(), "salvou")
	var again: Profile = Profile.new()
	again.load_file(TEST_PROFILE)
	assert_false(again.is_new())
	assert_eq(again.nick, "Rafa da Silva Sa", "apelido limpo e cortado em 16")
	assert_eq(again.avatar, 2)
	assert_eq(again.device, profile.device, "o mesmo aparelho")
	assert_eq(again.offline, {"seats": 6})
	assert_eq(again.felt, "safira", "a última mesa escolhida volta")
	again.set_nick("   ")
	assert_true(again.is_new(), "apelido em branco não vale")
	var file: FileAccess = FileAccess.open(TEST_PROFILE, FileAccess.WRITE)
	file.store_string("isto não é um perfil [[[")
	file.close()
	var broken: Profile = Profile.new()
	broken.load_file(TEST_PROFILE)
	assert_true(broken.is_new(), "arquivo estragado vira perfil novo")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE))


func test_room_with_friends_always_starts_from_the_default() -> void:
	# Pedido do dono: criar sala (Mesma rede e Online) não lembra a última sala.
	var options: Dictionary = OfflineOptions.build_room(OfflineOptions.ROOM_DEFAULTS)
	assert_eq(options["format"], "classic")
	assert_eq(options["seats"], 4)
	assert_eq(options["turn_seconds"], 15)
	assert_true(options["keep_open"], "manter sala aberta")
	assert_eq(options["starting_stack"], 2000, "fichas iniciais 20")
	assert_eq([options["small_blind"], options["big_blind"]], [10, 20], "blinds 0,10/0,20")
	assert_eq(options["rebuy_limit"], -1, "recompras sem limite")
	assert_eq(OfflineOptions.clean(OfflineOptions.ROOM_DEFAULTS), OfflineOptions.ROOM_DEFAULTS,
		"todas as escolhas existem nas listas")


## Todos desistem (antes ou depois do flop): o aviso diz quanto o ganhador levou, e é o
## mesmo valor do "Pote" na tela logo antes e do que entra nas fichas dele. Partida real,
## com o humano aumentando antes do flop e bots que pagam, aumentam e desistem.
func test_offline_fold_out_pays_the_pot_shown() -> void:
	var clock: Clock = Clock.new(true)
	var game: OfflineGame = _game(clock)
	game.begin("Rafa", 1, "aparelho-teste-0011", OfflineOptions.build(OfflineOptions.clean({"seats": 5})))
	var prev: Dictionary = {}
	var fold_outs: int = 0
	var mine: int = 0
	var walks: int = 0
	var after_flop: int = 0
	var wrong: Array[String] = []
	for i in 20000:
		clock.advance(250)
		for message: Dictionary in game.update():
			if message["t"] != Protocol.STATE:
				continue
			var table: Dictionary = message["table"]
			var ended: bool = false
			for event: Dictionary in message["events"]:
				if event["type"] == "end":
					ended = true
			if ended and not prev.is_empty() and not table["result"].get("showdown", true) \
					and table["result"]["payouts"].size() == 1:
				var result: Dictionary = table["result"]
				var winner: int = int(result["payouts"][0]["seat"])
				var groups: Array = PotMath.groups(result["payouts"], result["pots"], result["returned"])
				var shown_pot: int = PotMath.total(prev)
				var before: int = -1
				var after: int = -1
				for entry: Dictionary in prev["seats"]:
					if int(entry["seat"]) == winner:
						before = int(entry["stack"])
				for entry: Dictionary in table["seats"]:
					if int(entry["seat"]) == winner:
						after = int(entry["stack"])
				var said: int = int(groups[0]["amount"])
				if groups.size() != 1 or said != shown_pot or after - before != said \
						or PotMath.center(table) != said:
					wrong.append("mão %d: Pote %d, aviso %d, fichas +%d, centro %d" % [
						int(table["hand"]), shown_pot, said, after - before, PotMath.center(table)])
				fold_outs += 1
				if winner == int(message["you"].get("seat", -1)):
					mine += 1
				if String(prev["street"]) != "preflop":
					after_flop += 1
				elif result["returned"].size() == 1 and int(result["returned"][0]["amount"]) \
						== int(table["big_blind"]) - int(table["small_blind"]):
					walks += 1
			if table.get("live", false):
				prev = table
			var you: Dictionary = message["you"]
			if you.has("legal"):
				var legal: Dictionary = you["legal"]
				if String(table["street"]) == "preflop" and legal["can_raise"]:
					game.act("raise", int(legal["min_to"]))
				else:
					game.act("check" if legal["can_check"] else "fold", 0)
			elif you.has("rebuy_ms"):
				game.rebuy(true)
		if fold_outs >= 40 and mine >= 5 and after_flop >= 3 or not game.final.is_empty():
			break
	assert_eq(wrong, [] as Array[String], "aviso, \"Pote\" e fichas batem")
	assert_true(fold_outs >= 40, "mãos em que todos desistiram (%d)" % fold_outs)
	assert_true(mine >= 5, "você levou o pote com todos desistindo (%d)" % mine)
	assert_true(after_flop >= 3, "todos desistiram depois do flop (%d)" % after_flop)
	print("    desistências: %d (suas %d, depois do flop %d, big blind %d)" % [fold_outs, mine, after_flop, walks])
