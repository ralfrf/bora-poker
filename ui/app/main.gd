extends Control
## O app: aplica o tema, lê o perfil e leva de uma tela à outra (SPEC 11.1).
## Primeira abertura (apelido e avatar) → início → mesa offline → partida → placar →
## (anúncio entre partidas, hoje vazio) → início. No Wi-Fi: início → lista de salas →
## criar sala ou entrar → sala de espera → partida → placar → lista. Do início também
## se abrem configurações e ajuda. O botão "voltar" do Android passa pela tela aberta.

const UiTheme := preload("res://ui/theme/ui_theme.gd")
const Profile := preload("res://ui/app/profile.gd")
const OfflineGame := preload("res://ui/app/offline_game.gd")
const WifiGame := preload("res://ui/app/wifi_game.gd")
const WifiRoomsScreen := preload("res://ui/screens/wifi_rooms_screen.gd")
const WaitingScreen := preload("res://ui/screens/waiting_screen.gd")
const OfflineOptions := preload("res://ui/app/offline_options.gd")
const ProfileScreen := preload("res://ui/screens/profile_screen.gd")
const HomeScreen := preload("res://ui/screens/home_screen.gd")
const OfflineSetupScreen := preload("res://ui/screens/offline_setup_screen.gd")
const GameScreen := preload("res://ui/screens/game_screen.gd")
const ResultScreen := preload("res://ui/screens/result_screen.gd")
const SettingsScreen := preload("res://ui/screens/settings_screen.gd")
const HelpScreen := preload("res://ui/screens/help_screen.gd")
const ShopScreen := preload("res://ui/screens/shop_screen.gd")
const Ads := preload("res://ui/app/ads.gd")

const FADE: float = 0.14

var profile: Profile = Profile.new()
var _screen: Control = null
var _last_choice: Dictionary = {}
var _session: RefCounted = null   ## a partida em andamento (para fechar a rede ao sair)


func _ready() -> void:
	theme = UiTheme.current()
	get_tree().quit_on_go_back = false
	profile.load_file()
	if profile.is_new():
		_show_profile(true)
	else:
		_show_home()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _screen == null or not _screen.call("go_back"):
			get_tree().quit()


func _show(screen: Control) -> void:
	var old: Control = _screen
	_screen = screen
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.modulate.a = 0.0
	add_child(screen)
	create_tween().tween_property(screen, "modulate:a", 1.0, FADE)
	if old != null:
		old.process_mode = Node.PROCESS_MODE_DISABLED
		old.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tween: Tween = create_tween()
		tween.tween_property(old, "modulate:a", 0.0, FADE)
		tween.tween_callback(old.queue_free)


func _show_profile(first: bool) -> void:
	var screen: ProfileScreen = ProfileScreen.new(profile, first)
	screen.saved.connect(_show_home)
	screen.cancelled.connect(_show_home)
	_show(screen)


func _show_home() -> void:
	var screen: HomeScreen = HomeScreen.new(profile)
	screen.edit_profile.connect(_show_profile.bind(false))
	screen.play.connect(_on_mode)
	screen.open_settings.connect(func() -> void: _show_simple(SettingsScreen.new(profile)))
	screen.open_help.connect(func() -> void: _show_simple(HelpScreen.new()))
	screen.open_shop.connect(func() -> void: _show_simple(ShopScreen.new()))
	_show(screen)


## Telas que só voltam para o início (configurações, ajuda e loja).
func _show_simple(screen: Control) -> void:
	screen.connect("back", _show_home)
	_show(screen)


func _on_mode(mode: String) -> void:
	profile.last_mode = mode
	profile.save()
	if mode == Profile.MODE_OFFLINE:
		_show_setup()
	elif mode == Profile.MODE_WIFI:
		_show_rooms()


func _show_setup() -> void:
	var screen: OfflineSetupScreen = OfflineSetupScreen.new(profile)
	screen.back.connect(_show_home)
	screen.start.connect(_start_game)
	_show(screen)


func _start_game(choice: Dictionary) -> void:
	_last_choice = choice
	var game: OfflineGame = OfflineGame.new()
	game.begin(profile.nick, profile.avatar, profile.device, OfflineOptions.build(choice))
	_session = game
	var screen: GameScreen = GameScreen.new(game)
	screen.finished.connect(_show_result.bind(false))
	_show(screen)


# ---------------------------------------------------------------- Mesmo Wi-Fi


func _show_rooms(notice: String = "") -> void:
	_end_session()
	var screen: WifiRoomsScreen = WifiRoomsScreen.new(notice)
	screen.back.connect(_show_home)
	screen.create.connect(_show_room_setup)
	screen.join.connect(_join_room)
	_show(screen)


func _show_room_setup() -> void:
	var screen: OfflineSetupScreen = OfflineSetupScreen.new(profile, true)
	screen.back.connect(_show_rooms)
	screen.start.connect(_host_room)
	_show(screen)


func _host_room(choice: Dictionary) -> void:
	var game: WifiGame = WifiGame.new()
	if not game.host(profile.nick, profile.avatar, profile.device,
			OfflineOptions.build_room(choice)):
		_show_rooms(game.error_text)
		return
	_show_waiting(game)


func _join_room(ip: String, port: int) -> void:
	var game: WifiGame = WifiGame.new()
	game.join(ip, port, profile.nick, profile.avatar, profile.device)
	_show_waiting(game)


func _show_waiting(game: WifiGame) -> void:
	_session = game
	var screen: WaitingScreen = WaitingScreen.new(game)
	screen.finished.connect(_show_rooms)
	screen.started.connect(func() -> void: _play_wifi(game))
	screen.avatar_changed.connect(func(avatar: int) -> void:
		profile.avatar = avatar
		profile.save())
	_show(screen)


func _play_wifi(game: WifiGame) -> void:
	var screen: GameScreen = GameScreen.new(game)
	screen.finished.connect(func(final: Dictionary, members: Array, my_id: String) -> void:
		var notice: String = game.failure()
		_end_session()
		if final.is_empty():
			_show_rooms(notice)
		else:
			_show_result(final, members, my_id, true))
	_show(screen)


## Fecha a rede da partida que acabou (servidor, anúncios, conexão).
func _end_session() -> void:
	if _session != null:
		_session.call("shutdown")
		_session = null


func _show_result(final: Dictionary, members: Array, my_id: String, wifi: bool) -> void:
	_end_session()
	var screen: ResultScreen = ResultScreen.new(final, members, my_id)
	# O anúncio de tela cheia, quando existir, passa aqui: entre uma partida e outra.
	screen.again.connect(func() -> void:
		Ads.interstitial(func() -> void:
			if wifi:
				_show_rooms()
			else:
				_start_game(_last_choice)))
	screen.home.connect(func() -> void: Ads.interstitial(_show_home))
	_show(screen)
