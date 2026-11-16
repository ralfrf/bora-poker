extends Control
## Abre uma tela do app com dados de exemplo, para as fotos (tests/tools/shot.gd).
## Nada é gravado no perfil de verdade.
##   --screen=profile | profile_edit | home | setup | setup_t | game | showdown |
##            rebuy | result | result_t | live
##   --seed=N  (game e showdown: muda a mesa sorteada)

const Profile := preload("res://ui/app/profile.gd")
const OfflineGame := preload("res://ui/app/offline_game.gd")
const OfflineOptions := preload("res://ui/app/offline_options.gd")
const Clock := preload("res://server/clock.gd")
const ProfileScreen := preload("res://ui/screens/profile_screen.gd")
const HomeScreen := preload("res://ui/screens/home_screen.gd")
const OfflineSetupScreen := preload("res://ui/screens/offline_setup_screen.gd")
const GameScreen := preload("res://ui/screens/game_screen.gd")
const ResultScreen := preload("res://ui/screens/result_screen.gd")

const FAST: Dictionary = {"hand_gap_ms": 0, "showdown_gap_ms": 0, "bot_min_ms": 0,
	"bot_max_ms": 0, "bot_evaluations": 120}

var _seed: int = 1


func _ready() -> void:
	var screen_name: String = "home"
	var seats: int = 6
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--screen="):
			screen_name = arg.get_slice("=", 1)
		elif arg.begins_with("--seed="):
			_seed = int(arg.get_slice("=", 1))
		elif arg.begins_with("--seats="):
			seats = int(arg.get_slice("=", 1))
	var profile: Profile = Profile.new()
	profile.load_file("user://perfil_foto.cfg")
	profile.nick = "Rafa"
	profile.avatar = 1
	profile.offline = {"seats": seats}
	var screen: Control = null
	match screen_name:
		"profile":
			profile.nick = ""
			screen = ProfileScreen.new(profile, true)
		"profile_edit":
			screen = ProfileScreen.new(profile, false)
		"home":
			screen = HomeScreen.new(profile)
		"setup":
			screen = OfflineSetupScreen.new(profile)
		"setup_t":
			profile.offline = {"seats": seats, "format": 1}
			screen = OfflineSetupScreen.new(profile)
		"game", "showdown", "rebuy":
			screen = _game(screen_name, seats)
		"watching":
			# Recompra recusada por enquanto: assistindo, com "Voltar ao jogo".
			screen = _game("rebuy", seats, true)
		"live":
			# Partida com relógio de verdade e bots no tempo normal (teste de fumaça).
			var live: OfflineGame = OfflineGame.new()
			live.begin("Rafa", 1, "aparelho-foto",
				OfflineOptions.build(OfflineOptions.clean({"seats": seats})))
			screen = GameScreen.new(live)
		"result", "result_t":
			screen = _result(screen_name == "result_t")
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen)


## Partida de verdade, com relógio manual: anda até a situação pedida e congela.
func _game(kind: String, seats: int, watching: bool = false) -> Control:
	var clock: Clock = Clock.new(true)
	var game: OfflineGame = OfflineGame.new(clock, FAST, func() -> int:
		_seed += 1
		return _seed)
	var choice: Dictionary = OfflineOptions.clean({"seats": seats, "stack": 0,
		"blinds": 3})
	game.begin("Rafa", 1, "aparelho-foto", OfflineOptions.build(choice))
	var target: Dictionary = {}
	for i in 6000:
		clock.advance(200)
		for message: Dictionary in game.update():
			if message.get("t") != "state":
				continue
			var you: Dictionary = message["you"]
			var table: Dictionary = message["table"]
			match kind:
				"game":
					if you.has("legal") and table["board"].size() >= 3:
						target = message
				"showdown":
					if table.get("result", {}).get("showdown", false) \
							and table["result"]["shown"].size() >= 2:
						target = message
				"rebuy":
					if you.has("rebuy_ms"):
						target = message
			if target.is_empty() and you.has("legal"):
				var legal: Dictionary = you["legal"]
				if kind == "rebuy" and legal["can_raise"]:
					game.act("raise", int(legal["max_to"]))
				else:
					game.act("check" if legal["can_check"] else "call", 0)
		if not target.is_empty():
			break
	if kind == "rebuy" and not target.is_empty():
		# Um bot que já recomprou duas vezes, para a foto mostrar o marcador.
		for member: Dictionary in target["room"]["members"]:
			if member.get("bot", false) and int(member.get("seat", -1)) >= 0:
				member["rebuys"] = 2
				break
	var screen: GameScreen = GameScreen.new(game)
	screen.ready.connect(func() -> void:
		screen.set_process(false)
		screen.get_child(0).set("_watching", watching)
		screen.get_child(0).call("render", target), CONNECT_DEFERRED)
	return screen


func _result(tournament: bool) -> Control:
	var nicks: Array[String] = ["Rafa", "Cida", "Tonho", "Malu", "Zeca", "Nina"]
	var members: Array = []
	var rows: Array = []
	var nets: Array[int] = [1250, 640, -200, -500, -540, -650]
	var places: Array[int] = [2, 1, 3, 4, 5, 6]
	for i in nicks.size():
		members.append({"id": "p%d" % i, "nick": nicks[i], "avatar": i})
		rows.append({"id": "p%d" % i, "nick": nicks[i], "seat": i,
			"chips": (3000 if tournament else 2000) + nets[i], "held": 0, "net": nets[i],
			"place": places[i] if tournament else 0, "rebuys": 0})
	if tournament:
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a["place"]) < int(b["place"]))
		for row: Dictionary in rows:
			row["chips"] = 18000 if row["place"] == 1 else 0
	var final: Dictionary = {"t": "closed", "reason": "finished", "scoreboard": rows,
		"podium": rows.slice(0, 3) if tournament else []}
	return ResultScreen.new(final, members, "p0")

