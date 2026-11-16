extends Control
## O app: aplica o tema, lê o perfil e leva de uma tela à outra (SPEC 11.1).
## Primeira abertura (apelido e avatar) → início → mesa offline → partida → placar →
## início. O botão "voltar" do Android passa pela tela aberta.

const UiTheme := preload("res://ui/theme/ui_theme.gd")
const Profile := preload("res://ui/app/profile.gd")
const OfflineGame := preload("res://ui/app/offline_game.gd")
const OfflineOptions := preload("res://ui/app/offline_options.gd")
const ProfileScreen := preload("res://ui/screens/profile_screen.gd")
const HomeScreen := preload("res://ui/screens/home_screen.gd")
const OfflineSetupScreen := preload("res://ui/screens/offline_setup_screen.gd")
const GameScreen := preload("res://ui/screens/game_screen.gd")
const ResultScreen := preload("res://ui/screens/result_screen.gd")

const FADE: float = 0.14

var profile: Profile = Profile.new()
var _screen: Control = null
var _last_choice: Dictionary = {}


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
	_show(screen)


func _on_mode(mode: String) -> void:
	profile.last_mode = mode
	profile.save()
	if mode == Profile.MODE_OFFLINE:
		_show_setup()


func _show_setup() -> void:
	var screen: OfflineSetupScreen = OfflineSetupScreen.new(profile)
	screen.back.connect(_show_home)
	screen.start.connect(_start_game)
	_show(screen)


func _start_game(choice: Dictionary) -> void:
	_last_choice = choice
	var game: OfflineGame = OfflineGame.new()
	game.begin(profile.nick, profile.avatar, profile.device, OfflineOptions.build(choice))
	var screen: GameScreen = GameScreen.new(game)
	screen.finished.connect(_show_result)
	_show(screen)


func _show_result(final: Dictionary, members: Array, my_id: String) -> void:
	var screen: ResultScreen = ResultScreen.new(final, members, my_id)
	screen.again.connect(func() -> void: _start_game(_last_choice))
	screen.home.connect(_show_home)
	_show(screen)
