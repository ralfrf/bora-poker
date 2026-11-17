extends Control
## Abre uma tela do app com dados de exemplo, para as fotos (tests/tools/shot.gd).
## Nada é gravado no perfil de verdade.
##   --screen=profile | profile_edit | home | setup | setup_t | game | showdown |
##            rebuy | watching | ranking | history | result | result_t | live | settings |
##            help | rules | reactions | spectator | paused | held | held_seat | score |
##            servers | servers_wake | servers_full | servers_advanced | remote_rooms |
##            remote_password | remote_wake | remote_empty | remote_setup | remote_waiting
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
const SettingsScreen := preload("res://ui/screens/settings_screen.gd")
const HelpScreen := preload("res://ui/screens/help_screen.gd")
const WifiRoomsScreen := preload("res://ui/screens/wifi_rooms_screen.gd")
const WaitingScreen := preload("res://ui/screens/waiting_screen.gd")
const WifiGame := preload("res://ui/app/wifi_game.gd")
const RemoteGame := preload("res://ui/app/remote_game.gd")
const RemoteHost := preload("res://net/remote_host.gd")
const LoadProbe := preload("res://net/load_probe.gd")
const ServersScreen := preload("res://ui/screens/servers_screen.gd")
const RemoteRoomsScreen := preload("res://ui/screens/remote_rooms_screen.gd")

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
	profile.avatar = 4
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
		"settings":
			screen = SettingsScreen.new(profile)
		"help":
			screen = HelpScreen.new(0)
		"rules":
			screen = HelpScreen.new(1)
		"ranking":
			screen = _game("game", seats, false, true)
		"history":
			screen = _game("history", seats)
		"reactions", "spectator", "paused", "held", "held_seat", "score":
			# Etapa 4, parte B: painel e balões de reação, quem assiste com "Sentar" e mesa pausada.
			screen = _game("game", seats, false, false, screen_name)
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
		"rooms", "rooms_list":
			screen = WifiRoomsScreen.new()
		"wifi_setup":
			screen = OfflineSetupScreen.new(profile, true)
		"waiting":
			screen = WaitingScreen.new(_waiting_game(seats))
		"servers", "servers_wake", "servers_full", "servers_advanced":
			# Etapa 5, parte C: servidores com a lotação (sem ir à internet).
			profile.server_url = ""
			screen = ServersScreen.new(profile)
		"remote_rooms", "remote_password", "remote_wake", "remote_empty":
			screen = RemoteRoomsScreen.new(_remote_list(screen_name), "Servidor 1")
		"remote_setup":
			profile.room_password = "2580"
			profile.online = {"seats": seats, "keep_open": 1}
			screen = OfflineSetupScreen.new(profile, true, true)
		"remote_waiting":
			screen = WaitingScreen.new(_remote_waiting(seats))
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	if screen_name.begins_with("servers"):
		var probe: LoadProbe = screen.get("probe")
		match screen_name:
			"servers_wake":
				probe.pretend(LoadProbe.State.WAKING)
			"servers_full":
				probe.pretend(LoadProbe.State.READY, 100, true)
			_:
				probe.pretend(LoadProbe.State.READY, 23)
		screen.call("_refresh")
		if screen_name == "servers_advanced":
			screen.call("_open_advanced")
	if screen_name == "remote_password":
		var panel: Control = screen.get("_password_panel")
		panel.call("open", "1234")
		panel.call("show_error", "Senha errada; espere 5 s para tentar de novo.")
	if screen_name == "rooms_list":
		var now: int = Time.get_ticks_msec() + 100000
		screen.get("_listener").rooms = {
			"192.168.0.23": {"ip": "192.168.0.23", "port": 47820, "name": "Sala de Bia",
				"format": "classic", "seats": 6, "players": 3, "phase": "lobby", "open": true,
				"seen": now},
			"192.168.0.31": {"ip": "192.168.0.31", "port": 47820, "name": "Sala de Caio",
				"format": "tournament", "seats": 4, "players": 4, "phase": "playing",
				"open": false, "seen": now},
		}
		screen.call("_refresh")


## Sessão à distância de mentira, sem conexão: a lista de salas pronta (ou acordando).
func _remote_list(kind: String) -> RemoteGame:
	var game: RemoteGame = RemoteGame.new()
	if kind == "remote_wake":
		game.link = RemoteGame.Link.CONNECTING
		game.set("_started", Time.get_ticks_msec() - 20000)
		return game
	game.link = RemoteGame.Link.ONLINE
	if kind == "remote_empty":
		return game
	game.rooms = [
		{"id": "K7MP", "name": "Sala de Bia", "owner": "Bia", "format": "classic", "seats": 6,
			"players": 3, "phase": "lobby", "small_blind": 10, "big_blind": 20,
			"level_minutes": 5, "locked": false, "open": true},
		{"id": "QX4D", "name": "Sala de Caio", "owner": "Caio", "format": "classic", "seats": 9,
			"players": 5, "phase": "playing", "small_blind": 25, "big_blind": 50,
			"level_minutes": 5, "locked": true, "open": true},
		{"id": "ZR8H", "name": "Sala de Malu", "owner": "Malu", "format": "tournament", "seats": 4,
			"players": 1, "phase": "lobby", "small_blind": 10, "big_blind": 20,
			"level_minutes": 8, "locked": true, "open": true},
		{"id": "W2TN", "name": "Sala de Zeca", "owner": "Nina", "format": "classic", "seats": 2,
			"players": 1, "phase": "lobby", "small_blind": 5, "big_blind": 10,
			"level_minutes": 5, "locked": false, "open": true},
	]
	game.set("_ever_open", true)
	return game


## Sala de espera à distância de verdade: um servidor de salas aqui mesmo, o dono (com
## senha) e uma convidada que digitou a senha.
func _remote_waiting(seats: int) -> RemoteGame:
	var remote_host: RemoteHost = RemoteHost.new(null, {"room": FAST})
	remote_host.listen(0, "127.0.0.1")
	set_meta("remote_host", remote_host)
	var address: String = "ws://127.0.0.1:%d" % remote_host.ws.port
	var owner_game: RemoteGame = RemoteGame.new()
	owner_game.open(address, "Rafa", 4, "aparelho-foto")
	owner_game.create(OfflineOptions.build_room(OfflineOptions.clean({"seats": seats})), "2580")
	var guest: RemoteGame = RemoteGame.new()
	guest.open(address, "Bia", 2, "aparelho-bia")
	for _i in 400:
		remote_host.tick()
		owner_game.update()
		guest.update()
		if owner_game.room_id != "" and guest.room_id == "" and not guest.joining() \
				and guest.link == RemoteGame.Link.ONLINE and guest.get("_greeted"):
			guest.join_room(owner_game.room_id, "2580")
		if guest.my_id != "":
			break
		OS.delay_msec(5)
	owner_game.owner("add_bot", {"level": 2})
	for _i in 20:
		remote_host.tick()
		owner_game.update()
		OS.delay_msec(5)
	set_meta("guest", guest)
	return owner_game


func _process(_delta: float) -> void:
	if has_meta("remote_host"):
		(get_meta("remote_host") as RemoteHost).tick()
		(get_meta("guest") as RemoteGame).update()


## Sala de espera do anfitrião, com um bot e um convidado de verdade pela rede local.
func _waiting_game(seats: int) -> WifiGame:
	var options: Dictionary = OfflineOptions.build_room(OfflineOptions.clean({"seats": seats}))
	var host: WifiGame = WifiGame.new()
	host.host("Rafa", 4, "aparelho-foto", options, FAST, Callable(),
		["127.0.0.1"] as Array[String], 0, 47899)
	host.host_ip = "192.168.0.23"
	var guest: WifiGame = WifiGame.new()
	guest.join("127.0.0.1", host.port, "Bia", 2, "aparelho-bia")
	for _i in 200:
		host.update()
		guest.update()
		if guest.my_id != "":
			break
		OS.delay_msec(5)
	host.owner("add_bot", {"level": 2})
	host.update()
	set_meta("guest", guest)
	return host


## Partida de verdade, com relógio manual: anda até a situação pedida e congela.
func _game(kind: String, seats: int, watching: bool = false, ranking: bool = false,
		extra: String = "") -> Control:
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
				"history":
					var log: Object = game.get("_server").rooms[game.room_id].history
					if you.has("legal") and log.last_hand() >= 6:
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
		var table_view: Control = screen.get_child(0)
		if extra == "spectator":
			target["you"] = {"id": "assistindo", "seat": -1, "can_sit": true, "sit_rebuy": false}
		elif extra == "held" or extra == "held_seat":
			# Voltou com fichas guardadas: sala cheia (held) ou com lugar livre (held_seat).
			target["you"] = {"id": "assistindo", "seat": -1, "return_offer": {"before": 150000,
				"initial": 200000, "seat": extra == "held_seat", "can_initial": true}}
		elif extra == "paused":
			target["room"]["paused"] = true
			target["room"]["phase"] = "playing"
		table_view.set("reactions_enabled", extra == "reactions")
		table_view.call("render", target)
		if extra == "reactions":
			screen.open_reactions()
			var seated: Array = target["table"]["seats"]
			table_view.call("show_reaction", int(seated[1]["seat"]), 1)
			table_view.call("show_reaction", int(seated[-1]["seat"]), 7)
		if extra == "score":
			screen.open_score()
		if ranking:
			screen.open_ranking()
		if kind == "history":
			var log: Object = game.get("_server").rooms[game.room_id].history
			screen.open_history()
			screen.get("_history").set_hands(log.for_member(game.my_id), game.my_id), CONNECT_DEFERRED)
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

