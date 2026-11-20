extends Control
## Vídeo de divulgação da loja: do app aberto até a mesa cheia em poucos segundos, mesas
## diferentes e o fecho com "Baixe já!". O celular fica no centro, a legenda em cima, e
## cada toque aparece como um círculo. Grave com o Movie Maker do Godot (precisa de
## janela; salve fora do projeto):
##   godot --path . --resolution 1920x1080 --write-movie C:/caminho/promo.avi --fixed-fps 30 res://tests/tools/promo_video.tscn
## Depois de "--", "--curto" grava a versão de até 30 s (as mesmas partes, mais rápidas)
## e "--trilha=classica" ou "--trilha=cassino" troca a trilha de fundo (padrão: lounge).
## "--fotos=C:/pasta" grava as imagens da loja no mesmo estilo (legenda e celular),
## 1920x1080, sem o vídeo: godot --path . res://tests/tools/promo_video.tscn -- --fotos=...
## As partidas são offline, com relógio manual que anda junto com o vídeo; nas que
## imitam o Online, os bots aparecem sem o selo. Nada é gravado no perfil de verdade.

const UiTheme := preload("res://ui/theme/ui_theme.gd")
const PromoMusic := preload("res://tests/tools/promo_music.gd")
const Paint := preload("res://ui/widgets/paint.gd")
const Backdrop := preload("res://ui/widgets/backdrop.gd")
const Profile := preload("res://ui/app/profile.gd")
const OfflineGame := preload("res://ui/app/offline_game.gd")
const OfflineOptions := preload("res://ui/app/offline_options.gd")
const Clock := preload("res://server/clock.gd")
const ProfileScreen := preload("res://ui/screens/profile_screen.gd")
const HomeScreen := preload("res://ui/screens/home_screen.gd")
const GameScreen := preload("res://ui/screens/game_screen.gd")
const ResultScreen := preload("res://ui/screens/result_screen.gd")
const WifiRoomsScreen := preload("res://ui/screens/wifi_rooms_screen.gd")
const RemoteGame := preload("res://ui/app/remote_game.gd")
const RemoteRoomsScreen := preload("res://ui/screens/remote_rooms_screen.gd")
const T: String = "Tokens"
## Volume da trilha de fundo (os sons do jogo ficam desligados no vídeo).
const MUSIC_DB: float = 0.0

const OUT: Vector2i = Vector2i(1920, 1080)
const LOGICAL: Vector2i = Vector2i(800, 360)
const APP_SCALE: float = 2.0
const APP_POS: Vector2 = Vector2(160, 316)
const NICK: String = "Pedro"
const AVATAR: int = 12
## Até quanto o jogador paga (centavos): 1,50, com blinds de 0,10/0,20.
const CHEAP_CALL: int = 150
## Placar mostrado no vídeo: depois de quantas mãos e a maior perda aceita (centavos).
const SCORE_HANDS: int = 5
## Mãos sem all-in no começo da mesa de 9.
const CALM_HANDS: int = 3
const SCORE_FLOOR: int = 600
## Lugares com o topo acima disto (tamanho lógico) ficam sem reação no vídeo.
const TOP_SEAT_Y: float = 40.0

## Bots ligeiros, para caber várias jogadas em poucos segundos de vídeo.
const PACE: Dictionary = {"hand_gap_ms": 2200, "showdown_gap_ms": 3600, "bot_min_ms": 250,
	"bot_max_ms": 550, "bot_evaluations": 200}


## Partida offline que, no modo online, tira o selo de bot (parece gente da turma) e
## liga as reações.
class DemoGame:
	extends OfflineGame

	var online: bool = false

	func _init(clock: Clock, config: Dictionary, seeds: Callable) -> void:
		super(clock, config, seeds)

	func update() -> Array[Dictionary]:
		var messages: Array[Dictionary] = super()
		if online:
			for message: Dictionary in messages:
				var room: Variant = message.get("room")
				if room is Dictionary:
					for member: Dictionary in (room as Dictionary).get("members", []):
						member["bot"] = false
		return messages

	func has_reactions() -> bool:
		return online


## Legenda em cima do celular: título grande e uma linha menor, com a barra dourada.
class Caption:
	extends Control

	var title: String = ""
	var subtitle: String = ""
	var fade: float = 0.0:
		set(value):
			fade = value
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func say(new_title: String, new_subtitle: String = "") -> void:
		if new_title == title and new_subtitle == subtitle:
			return
		var tween: Tween = create_tween()
		if fade > 0.0:
			tween.tween_property(self, "fade", 0.0, 0.14)
		tween.tween_callback(func() -> void:
			title = new_title
			subtitle = new_subtitle)
		tween.tween_property(self, "fade", 1.0, 0.28).set_ease(Tween.EASE_OUT) \
			.set_trans(Tween.TRANS_CUBIC)

	func _draw() -> void:
		if title == "":
			return
		var display: Font = get_theme_font("display", T)
		var body: Font = get_theme_font("strong", T)
		var lift: float = (1.0 - fade) * 18.0
		var alpha: float = fade
		var accent: Color = get_theme_color("accent", T)
		draw_rect(Rect2(160, 92 + lift, 9, 150), Color(accent, alpha))
		var shadow: Color = Color(0, 0, 0, 0.5 * alpha)
		draw_string(display, Vector2(196, 172 + lift + 4), title, HORIZONTAL_ALIGNMENT_LEFT, -1,
			68, shadow)
		draw_string(display, Vector2(196, 172 + lift), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 68,
			Color(get_theme_color("text", T), alpha))
		if subtitle != "":
			draw_string(body, Vector2(198, 230 + lift), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1,
				38, Color(get_theme_color("text_dim", T), alpha))


## Cronômetro "do app à mesa": corre desde a primeira tela e para quando a mesa abre.
class Stopwatch:
	extends Control

	var running: bool = false
	var done: bool = false
	var elapsed: float = 0.0
	var fade: float = 0.0:
		set(value):
			fade = value
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if running:
			elapsed += delta
			queue_redraw()

	func _draw() -> void:
		if fade <= 0.0:
			return
		var accent: Color = get_theme_color("accent", T)
		var box: Rect2 = Rect2(1760 - 290, 128, 290, 104)
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.set_corner_radius_all(52)
		style.bg_color = Color(accent, fade) if done else Color(0, 0, 0, 0.45 * fade)
		style.border_color = Color(accent, fade)
		style.set_border_width_all(3)
		draw_style_box(style, box)
		var ink: Color = Color(get_theme_color("on_accent", T), fade) if done \
			else Color(get_theme_color("text", T), fade)
		var center: Vector2 = box.position + Vector2(58, 52)
		draw_arc(center, 24, 0, TAU, 40, ink, 4.0, true)
		draw_line(center + Vector2(-6, -34), center + Vector2(6, -34), ink, 5.0)
		var hand: float = elapsed * TAU / 10.0 - PI / 2.0
		draw_line(center, center + Vector2(cos(hand), sin(hand)) * 17.0, ink, 4.0, true)
		var text: String = ("%.1f s" % elapsed).replace(".", ",")
		draw_string(get_theme_font("display", T), Vector2(box.position.x + 100, box.position.y + 72),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, 56, ink)
		var label: String = "Já na mesa!" if done else "Do app à mesa"
		draw_string(get_theme_font("strong", T), Vector2(box.position.x, box.position.y - 14),
			label, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 30,
			Color(accent if done else get_theme_color("text_dim", T), fade))


## Toques na tela do celular: um ponto que aparece e se abre num anel.
class Touch:
	extends Control

	const LIFE: float = 0.75
	var _taps: Array = []
	var _drag: Vector2 = Vector2(-1, -1)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func tap(at: Vector2) -> void:
		_taps.append([at, 0.0])

	## Dedo arrastando (posição em coordenadas da tela); (-1, -1) solta.
	func drag(at: Vector2) -> void:
		_drag = at
		queue_redraw()

	func _process(delta: float) -> void:
		for item: Array in _taps:
			item[1] = float(item[1]) + delta
		_taps = _taps.filter(func(item: Array) -> bool: return float(item[1]) < LIFE)
		queue_redraw()

	func _draw() -> void:
		if _drag.x >= 0.0:
			draw_circle(_drag, 15.0, Color(1, 1, 1, 0.55))
			draw_arc(_drag, 15.0, 0, TAU, 40, Color(1, 1, 1, 0.9), 2.0, true)
		for item: Array in _taps:
			var at: Vector2 = item[0]
			var age: float = item[1]
			if age < 0.2:
				var grow: float = age / 0.2
				draw_circle(at, 15.0 * (0.6 + 0.4 * grow), Color(1, 1, 1, 0.6 * grow))
				continue
			var k: float = (age - 0.2) / (LIFE - 0.2)
			draw_circle(at, 15.0 * (1.0 - 0.4 * k), Color(1, 1, 1, 0.6 * (1.0 - k)))
			draw_arc(at, 15.0 + 26.0 * k, 0, TAU, 48, Color(1, 1, 1, 0.9 * (1.0 - k)), 3.0, true)


## Fecho: a ficha, o nome, os pontos principais e o "Baixe já!".
class EndCard:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var display: Font = get_theme_font("display", T)
		var strong: Font = get_theme_font("strong", T)
		var body: Font = get_theme_font("text", T)
		var text: Color = get_theme_color("text", T)
		var dim: Color = get_theme_color("text_dim", T)
		var accent: Color = get_theme_color("accent", T)
		var shadow: Color = Color(0, 0, 0, 0.55)
		var w: float = size.x
		Paint.chip(self, Vector2(w / 2.0, 200), 92, get_theme_color("chip_0", T),
			get_theme_color("chip_mark", T), get_theme_constant("chip_style", T))
		draw_string(display, Vector2(0, 420 + 5), "Bora Poker", HORIZONTAL_ALIGNMENT_CENTER, w,
			124, shadow)
		draw_string(display, Vector2(0, 420), "Bora Poker", HORIZONTAL_ALIGNMENT_CENTER, w, 124,
			text)
		draw_string(strong, Vector2(0, 492), "Offline e Online sem cadastro",
			HORIZONTAL_ALIGNMENT_CENTER, w, 46, dim)
		draw_string(body, Vector2(0, 578),
			"Sem cadastro  ·  Até 9 na mesa  ·  Mesas e avatares exclusivos  ·  Bots com personalidade",
			HORIZONTAL_ALIGNMENT_CENTER, w, 32, text)
		var pill: Rect2 = Rect2(w / 2.0 - 260, 640, 520, 128)
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.set_corner_radius_all(64)
		style.bg_color = accent
		style.shadow_color = Color(0, 0, 0, 0.45)
		style.shadow_size = 18
		style.shadow_offset = Vector2(0, 6)
		draw_style_box(style, pill)
		draw_string(display, Vector2(pill.position.x, pill.position.y + 90), "Baixe já!",
			HORIZONTAL_ALIGNMENT_CENTER, pill.size.x, 78, get_theme_color("on_accent", T))
		draw_string(strong, Vector2(0, 830), "É grátis!", HORIZONTAL_ALIGNMENT_CENTER, w, 42,
			accent)
		draw_string(body, Vector2(0, 1010),
			"Fichas virtuais, sem dinheiro real. Para maiores de 18 anos.",
			HORIZONTAL_ALIGNMENT_CENTER, w, 28, dim)


var _profile: Profile = null
var _viewport: SubViewport = null
var _frame: Control = null
var _screen: Control = null
var _touch: Touch = null
var _cover: ColorRect = null
var _phone: Control = null
var _caption: Caption = null
var _watch: Stopwatch = null
var _end: EndCard = null
var _music: AudioStreamPlayer = null
var _clock: Clock = null
var _clock_rest: float = 0.0
var _game: DemoGame = null
var _acting: bool = false
## Versão curta (até 30 s), pedida com --curto.
var _short: bool = OS.get_cmdline_user_args().has("--curto")
## Com o placar aberto, o jogador não joga.
var _paused: bool = false


func _ready() -> void:
	OS.low_processor_usage_mode = false
	var window: Window = get_window()
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	theme = UiTheme.current()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop: Control = Backdrop.new()
	backdrop.size = Vector2(OUT)
	add_child(backdrop)
	_build_phone()
	_caption = Caption.new()
	_caption.size = Vector2(OUT)
	add_child(_caption)
	_watch = Stopwatch.new()
	_watch.size = Vector2(OUT)
	add_child(_watch)
	_end = EndCard.new()
	_end.size = Vector2(OUT)
	_end.modulate.a = 0.0
	add_child(_end)
	# Só a trilha: os sons do jogo (cartas, fichas, vez) vão para um canal mudo.
	AudioServer.add_bus()
	var muted: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(muted, "SemSom")
	AudioServer.set_bus_mute(muted, true)
	get_tree().root.child_entered_tree.connect(func(node: Node) -> void:
		if node is AudioStreamPlayer and node != _music:
			(node as AudioStreamPlayer).bus = "SemSom")
	_music = AudioStreamPlayer.new()
	var style: String = "lounge"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--trilha="):
			style = arg.get_slice("=", 1)
	_music.stream = PromoMusic.stream(style)
	_music.volume_db = -40.0
	add_child(_music)
	_profile = Profile.new()
	_profile.load_file("user://perfil_video.cfg")
	_profile.nick = ""
	_profile.avatar = 3
	_profile.felt = "salao"
	_profile.server_url = ""
	var stills: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--fotos="):
			stills = arg.get_slice("=", 1)
	if stills != "":
		_stills(stills)
	else:
		_run()


## O celular: moldura escura com cantos redondos e a tela do app (um SubViewport no
## tamanho lógico do projeto, desenhado em dobro).
func _build_phone() -> void:
	var size_px: Vector2 = Vector2(LOGICAL) * APP_SCALE
	var bezel: Panel = Panel.new()
	var bezel_style: StyleBoxFlat = StyleBoxFlat.new()
	bezel_style.bg_color = Color(0.03, 0.03, 0.05)
	bezel_style.set_corner_radius_all(52)
	bezel_style.border_color = Color(0.25, 0.25, 0.3)
	bezel_style.set_border_width_all(3)
	bezel_style.shadow_color = Color(0, 0, 0, 0.55)
	bezel_style.shadow_size = 36
	bezel_style.shadow_offset = Vector2(0, 12)
	bezel.add_theme_stylebox_override("panel", bezel_style)
	bezel.position = APP_POS - Vector2(18, 18)
	bezel.size = size_px + Vector2(36, 36)
	add_child(bezel)
	_phone = bezel
	var clip: Panel = Panel.new()
	var clip_style: StyleBoxFlat = StyleBoxFlat.new()
	clip_style.bg_color = Color.BLACK
	clip_style.set_corner_radius_all(36)
	clip.add_theme_stylebox_override("panel", clip_style)
	clip.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	clip.position = Vector2(18, 18)
	clip.size = size_px
	bezel.add_child(clip)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(size_px)
	_viewport.size_2d_override = LOGICAL
	_viewport.size_2d_override_stretch = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = false
	_viewport.gui_disable_input = true
	add_child(_viewport)
	var shown: TextureRect = TextureRect.new()
	shown.texture = _viewport.get_texture()
	shown.size = size_px
	shown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(shown)
	_frame = Control.new()
	_frame.theme = UiTheme.current()
	_frame.size = Vector2(LOGICAL)
	_viewport.add_child(_frame)
	_touch = Touch.new()
	_touch.size = Vector2(LOGICAL)
	_touch.z_index = 10
	_frame.add_child(_touch)
	_cover = ColorRect.new()
	_cover.color = Color(0, 0, 0, 0)
	_cover.size = Vector2(LOGICAL)
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.z_index = 9
	_frame.add_child(_cover)


func _process(delta: float) -> void:
	if _clock != null:
		_clock_rest += delta * 1000.0
		var step: int = int(_clock_rest)
		_clock_rest -= step
		_clock.advance(step)
	if _game != null and not _acting and not _paused and _game.last_state.get("you", {}).has("legal"):
		_acting = true
		_auto_act()


## Duração de um trecho: full na versão normal, short na curta.
func _t(full: float, short: float) -> float:
	return short if _short else full


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## O roteiro.
func _run() -> void:
	_music.play()
	var fade_in: Tween = create_tween()
	fade_in.tween_property(_music, "volume_db", MUSIC_DB, 0.6)
	await _wait(0.2)
	# 1. Primeira vez: o apelido e um avatar exclusivo.
	var profile_screen: Control = ProfileScreen.new(_profile, true)
	_put(profile_screen)
	# Sem o aviso de que os exclusivos serão da Loja: o vídeo não fala de compras.
	(profile_screen.get("_avatar_hint") as Control).visible = false
	_caption.say("Sem cadastro!", "Só um apelido e pronto")
	var appear: Tween = create_tween()
	appear.tween_property(_watch, "fade", 1.0, 0.3)
	_watch.running = true
	await _wait(_t(0.8, 0.5))
	var field: LineEdit = profile_screen.get("_field")
	await _tap(field)
	field.grab_focus()
	for i in range(1, NICK.length() + 1):
		field.text = NICK.substr(0, i)
		field.caret_column = i
		field.text_changed.emit(field.text)
		await _wait(_t(0.14, 0.1))
	field.release_focus()
	await _wait(_t(0.25, 0.15))
	var strip: Control = profile_screen.get("_avatars")
	var target: float = minf(float(strip.call("cell_x", AVATAR)) - 20.0, float(strip.call("max_offset")))
	await _swipe(strip, target)
	var cell: float = strip.call("cell")
	var face: Vector2 = strip.get_global_rect().position \
		+ Vector2(float(strip.call("cell_x", AVATAR)) - float(strip.get("offset")) + cell / 2.0, cell / 2.0)
	await _tap_at(face)
	strip.set("selected", AVATAR)
	strip.emit_signal("picked", AVATAR)
	strip.queue_redraw()
	await _wait(_t(0.45, 0.25))
	await _tap(profile_screen.get("_confirm"))
	# 2. Início, com o Online marcado.
	_profile.nick = NICK
	_profile.avatar = AVATAR
	var home: Control = HomeScreen.new(_profile)
	await _swap(home)
	await _wait(_t(0.6, 0.35))
	await _tap(home.get("_play"))
	# 3. Lista de salas do Online.
	_caption.say("Online com a turma", "Escolha uma sala ou crie a sua")
	var rooms: Control = RemoteRoomsScreen.new(_room_list(), "Servidor 1")
	await _swap(rooms)
	await _wait(_t(0.9, 0.6))
	var list: Control = rooms.get("_list")
	await _tap(list.get_child(0))
	# 4. A mesa cheia: o cronômetro para.
	var table: Control = _start_game("salao", 9, true, _calm_seed(9, 11), false)
	await _swap(table)
	_watch.running = false
	_watch.done = true
	_watch.queue_redraw()
	_caption.say("Em 10 s você já está jogando!", "Sem login, sem e-mail, sem espera")
	await _wait(_t(3.4, 2.6))
	var gone: Tween = create_tween()
	gone.tween_property(_watch, "fade", 0.0, 0.3)
	_caption.say("Até 9 na mesa!", "A turma toda numa mesa só")
	_react(table, 1, 0.6, 2)
	_react(table, 6, 1.6, 5)
	_react(table, 2, _t(2.7, 2.1), 0)
	await _wait(_t(3.6, 2.8))
	# 5. Mesas diferentes, com quantidades diferentes de gente.
	_caption.say("Mesas diferentes", "Salão, Rubi, Safira e Pérola")
	var rubi: Control = _start_game("rubi", 6, true, 41, true)
	await _swap(rubi)
	_react(rubi, 10, 0.8, 1)
	_react(rubi, 0, _t(2.0, 1.2), 3)
	await _wait(_t(3.2, 1.7))
	var perola: Control = _start_game("perola", 2, true, 5, true)
	await _swap(perola)
	_react(perola, 4, _t(1.0, 0.6), 0)
	await _wait(_t(2.8, 1.5))
	var safira: Control = _start_game("safira", 4, true, 73, true)
	await _swap(safira)
	_react(safira, 2, _t(0.9, 0.5), 0)
	await _wait(_t(2.8, 1.5))
	# O placar, numa mesa que já jogou algumas mãos, aberto pelo botão do pódio.
	_caption.say("Placar ao vivo", "Veja quem está ganhando a qualquer momento")
	var scored: Control = _start_scored("salao", 6, 200)
	await _swap(scored)
	_react(scored, 9, 0.3, 0)
	await _wait(_t(0.6, 0.3))
	await _open_score(scored)
	# 6. Offline contra bots.
	_caption.say("Sem internet? Jogue contra bots", "Cada um com nome e estilo próprios")
	await _swap(_start_game("salao", 5, false, 29, true))
	await _wait(_t(3.6, 2.2))
	_stop_game()
	# 7. Mesmo Wi-Fi.
	_caption.say("No mesmo Wi-Fi", "A sala aparece sozinha no celular da turma")
	await _swap(_wifi_rooms())
	await _wait(_t(2.8, 1.7))
	# 8. Torneio com pódio.
	_caption.say("Clássico ou torneio", "Com pódio no final")
	await _swap(_podium())
	await _wait(_t(2.8, 1.7))
	# 9. Fecho.
	_caption.say("", "")
	var out: Tween = create_tween().set_parallel(true)
	out.tween_property(_phone, "modulate:a", 0.0, 0.4)
	out.tween_property(_caption, "fade", 0.0, 0.3)
	out.chain().tween_property(_end, "modulate:a", 1.0, 0.5)
	var ending: float = _t(4.6, 3.2)
	var fade_out: Tween = create_tween()
	fade_out.tween_interval(ending - 1.6)
	fade_out.tween_property(_music, "volume_db", -40.0, 1.5)
	await _wait(ending)
	get_tree().quit()


## Imagens da loja: cada uma com um motivo para escolher o app, na ordem da página.
func _stills(dir: String) -> void:
	var window: Window = get_window()
	window.borderless = true
	window.position = Vector2i.ZERO
	window.size = OUT
	_touch.visible = false
	DirAccess.make_dir_recursive_absolute(dir)
	_profile.nick = NICK
	_profile.avatar = AVATAR
	await _wait(0.3)
	# 1. A mesa cheia.
	var full: Control = _start_game("salao", 9, true, _calm_seed(9, 11), false)
	_warm_turn(_game, _clock)
	await _still(dir, "1_mesa_9", "Até 9 amigos na mesma mesa",
		"Online, no mesmo Wi-Fi ou contra bots", full, [[6, 2], [1, 5]])
	# 2. Sem cadastro.
	var profile_screen: Control = ProfileScreen.new(_profile, true)
	_profile.nick = ""
	_put(profile_screen)
	_profile.nick = NICK
	(profile_screen.get("_avatar_hint") as Control).visible = false
	var field: LineEdit = profile_screen.get("_field")
	field.text = NICK
	field.text_changed.emit(NICK)
	var strip: Control = profile_screen.get("_avatars")
	strip.set("selected", AVATAR)
	strip.emit_signal("picked", AVATAR)
	await _wait(0.2)
	strip.call("_scroll_to", float(strip.call("cell_x", Paint.FREE_AVATARS)) - 40.0)
	await _still(dir, "2_sem_cadastro", "Sem cadastro",
		"Só um apelido: em segundos você já está jogando", null, [])
	# 3. Online.
	await _still(dir, "3_online", "Jogue online com a turma",
		"Crie sua sala, com senha se quiser", RemoteRoomsScreen.new(_room_list(), "Servidor 1"), [])
	# 4. Mesas.
	var rubi: Control = _start_game("rubi", 6, true, 41, false)
	_warm_turn(_game, _clock)
	await _still(dir, "4_mesas", "Mesas bonitas e diferentes", "Salão, Rubi, Safira e Pérola",
		rubi, [[10, 1]])
	# 5. Offline contra bots.
	var bots: Control = _start_game("safira", 5, false, 29, false)
	_warm_turn(_game, _clock)
	await _still(dir, "5_bots", "Sem internet? Jogue contra bots",
		"Fácil, Médio, Difícil ou Misto, cada um com seu estilo", bots, [])
	# 6. Mesmo Wi-Fi.
	_stop_game()
	await _still(dir, "6_mesmo_wifi", "No mesmo Wi-Fi",
		"A sala aparece sozinha no celular da turma", _wifi_rooms(), [])
	# 7. Torneio.
	await _still(dir, "7_torneio", "Clássico ou torneio", "Blinds que sobem e pódio no final",
		_podium(), [])
	get_tree().quit()


## Uma imagem: legenda pronta, a tela no celular, a mesa parada e as reações pedidas
## ([índice, qual das outras pessoas]).
func _still(dir: String, file: String, title: String, subtitle: String, screen: Control,
		reactions: Array) -> void:
	_caption.title = title
	_caption.subtitle = subtitle
	_caption.fade = 1.0
	if screen != null:
		_put(screen)
	_paused = true
	_clock = null
	await _wait(1.2)
	for item: Array in reactions:
		_react(_screen, int(item[0]), 0.0, int(item[1]))
	await _wait(0.7)
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	var path: String = dir.path_join("tela_loja_%s.png" % file)
	image.save_png(path)
	print("salvo: ", path, " (", image.get_width(), "x", image.get_height(), ")")
	_paused = false


## Anda a partida até a vez do jogador com o flop na mesa (os botões aparecem na foto).
func _warm_turn(game: DemoGame, clock: Clock) -> void:
	for i in 20000:
		clock.advance(100)
		game.update()
		var state: Dictionary = game.last_state
		var you: Dictionary = state.get("you", {})
		if not you.has("legal"):
			continue
		if (state.get("table", {}).get("board", []) as Array).size() >= 3:
			return
		var legal: Dictionary = you["legal"]
		if legal["can_check"]:
			game.act("check", 0)
		else:
			game.act("call" if _keeps_going(game) else "fold", 0)


func _put(screen: Control) -> void:
	if _screen != null:
		_screen.queue_free()
	_screen = screen
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.add_child(screen)
	_frame.move_child(screen, 0)


## Troca de tela com um escurecer rápido.
func _swap(screen: Control) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(_cover, "color:a", 1.0, 0.12)
	await tween.finished
	_put(screen)
	await _wait(0.05)
	var back: Tween = create_tween()
	back.tween_property(_cover, "color:a", 0.0, 0.16)
	await back.finished


func _tap(control: Control) -> void:
	await _tap_at(control.get_global_rect().get_center())


func _tap_at(at: Vector2) -> void:
	_touch.tap(at)
	await _wait(0.24)


## Dedo arrastando a fileira de avatares até os exclusivos.
func _swipe(strip: Control, target: float) -> void:
	var rect: Rect2 = strip.get_global_rect()
	var from: float = strip.get("offset")
	var start: Vector2 = Vector2(rect.end.x - 50.0, rect.get_center().y)
	var steps: int = 14 if _short else 22
	for i in steps + 1:
		var k: float = ease(float(i) / steps, -2.0)
		strip.call("_scroll_to", lerpf(from, target, k))
		_touch.drag(start - Vector2((target - from) * k, 0))
		await get_tree().process_frame
	_touch.drag(Vector2(-1, -1))
	await _wait(0.2)


## Uma partida nova com relógio manual. warm: já começa no flop da primeira mão.
func _start_game(felt: String, seats: int, online: bool, seed: int, warm: bool) -> Control:
	_stop_game()
	var clock: Clock = Clock.new(true)
	var next_seed: Array[int] = [seed]
	var game: DemoGame = DemoGame.new(clock, PACE, func() -> int:
		next_seed[0] += 1
		return next_seed[0])
	game.online = online
	var choice: Dictionary = OfflineOptions.clean({"seats": seats})
	choice["felt"] = felt
	game.begin(NICK, AVATAR, "aparelho-video", OfflineOptions.build(choice))
	if warm:
		_warm(game, clock)
	_clock = clock
	_clock_rest = 0.0
	_game = game
	_acting = false
	return GameScreen.new(game)


func _stop_game() -> void:
	_game = null
	_clock = null


## Anda a partida até o flop (pagando ou passando pelo jogador), sem desenhar.
func _warm(game: DemoGame, clock: Clock) -> void:
	for i in 4000:
		clock.advance(100)
		game.update()
		var state: Dictionary = game.last_state
		if state.is_empty():
			continue
		if (state.get("table", {}).get("board", []) as Array).size() >= 3:
			return
		var you: Dictionary = state.get("you", {})
		if you.has("legal"):
			var legal: Dictionary = you["legal"]
			if legal["can_check"]:
				game.act("check", 0)
			else:
				game.act("call" if _keeps_going(game) else "fold", 0)


## Passa ou paga até CHEAP_CALL; mais caro que isso, desiste (para não ficar sem fichas
## no meio do vídeo).
func _keeps_going(game: DemoGame) -> bool:
	var legal: Dictionary = game.last_state.get("you", {}).get("legal", {})
	return legal.get("can_check", false) or int(legal.get("call", 0)) <= CHEAP_CALL


## Partida que já jogou SCORE_HANDS mãos, da primeira semente a partir de first_seed em
## que ninguém perdeu mais que SCORE_FLOOR e o jogador está no positivo (placar bonito).
func _start_scored(felt: String, seats: int, first_seed: int) -> Control:
	var screen: Control = null
	for seed in range(first_seed, first_seed + 150):
		if screen != null:
			screen.free()
		screen = _start_game(felt, seats, true, seed, false)
		_warm_hands(_game, _clock)
		if _nice_score(_game):
			break
	return screen


## Primeira semente a partir de first_seed em que, nas CALM_HANDS primeiras mãos,
## ninguém vai de all-in nem fica sem fichas (o começo do vídeo sem sustos).
func _calm_seed(seats: int, first_seed: int) -> int:
	for seed in range(first_seed, first_seed + 300):
		var clock: Clock = Clock.new(true)
		var next_seed: Array[int] = [seed]
		var game: DemoGame = DemoGame.new(clock, PACE, func() -> int:
			next_seed[0] += 1
			return next_seed[0])
		game.begin(NICK, AVATAR, "aparelho-video", OfflineOptions.build(
			OfflineOptions.clean({"seats": seats})))
		var calm: bool = true
		for i in 20000:
			clock.advance(100)
			game.update()
			var table: Dictionary = game.last_state.get("table", {})
			if int(table.get("hand", 0)) > CALM_HANDS:
				break
			for seat: Dictionary in table.get("seats", []):
				if seat.get("all_in", false) or int(seat.get("rebuys", 0)) > 0:
					calm = false
			if not calm:
				break
			var you: Dictionary = game.last_state.get("you", {})
			if you.has("legal"):
				var legal: Dictionary = you["legal"]
				if legal["can_check"]:
					game.act("check", 0)
				else:
					game.act("call" if _keeps_going(game) else "fold", 0)
		game.shutdown()
		if calm:
			return seed
	return first_seed


func _warm_hands(game: DemoGame, clock: Clock) -> void:
	for i in 20000:
		clock.advance(100)
		game.update()
		var state: Dictionary = game.last_state
		if state.is_empty():
			continue
		var table: Dictionary = state.get("table", {})
		if int(table.get("hand", 0)) > SCORE_HANDS and (table.get("board", []) as Array).size() >= 3:
			return
		var you: Dictionary = state.get("you", {})
		if you.has("legal"):
			var legal: Dictionary = you["legal"]
			if legal["can_check"]:
				game.act("check", 0)
			else:
				game.act("call" if _keeps_going(game) else "fold", 0)


func _nice_score(game: DemoGame) -> bool:
	var rows: Array = game.last_state.get("room", {}).get("score", [])
	if rows.is_empty():
		return false
	for row: Dictionary in rows:
		var net: int = int(row.get("net", 0))
		if net < -SCORE_FLOOR or (str(row.get("id", "")) == game.my_id and net <= 0):
			return false
	return true


## Na vez do jogador: o dedo toca em Pagar, Passar ou Desistir.
func _auto_act() -> void:
	var game: DemoGame = _game
	await _wait(0.65)
	if game == _game and game != null and _screen is GameScreen \
			and game.last_state.get("you", {}).has("legal"):
		var bar: Object = _screen.get("_table").get("_bar")
		var button: Button = bar.get("_call" if _keeps_going(game) else "_fold")
		if button != null and button.is_visible_in_tree():
			await _tap(button)
			if game == _game:
				button.pressed.emit()
	await _wait(0.3)
	_acting = false


## Reação de outra pessoa da mesa (who: qual das outras) depois de delay segundos.
func _react(screen: Control, index: int, delay: float, who: int) -> void:
	await _wait(delay)
	if screen != _screen or _game == null:
		return
	var seats: Array = _game.last_state.get("table", {}).get("seats", [])
	var table: Control = screen.get("_table")
	var views: Variant = table.get("_seats")
	# Só quem não está no alto da mesa: lá em cima o balão sai da tela.
	var others: Array = seats.filter(func(seat: Dictionary) -> bool:
		var slot: int = table.call("_slot_of", int(seat.get("seat", -1)))
		return str(seat.get("id", "")) != _game.my_id and slot >= 0 			and (views[slot] as Control).position.y > TOP_SEAT_Y)
	if others.is_empty():
		return
	var seat: Dictionary = others[who % others.size()]
	table.call("show_reaction", int(seat.get("seat", -1)), index)


## O dedo toca no botão do placar, o placar fica aberto um pouco e fecha.
func _open_score(screen: Control) -> void:
	var button: BaseButton = screen.get("_table").get("_score")
	_paused = true
	await _wait(_t(0.4, 0.2))
	await _tap(button)
	button.pressed.emit()
	await _wait(_t(2.8, 1.6))
	screen.get("_score").call("close")
	_paused = false
	await _wait(0.3)


func _room_list() -> RemoteGame:
	var game: RemoteGame = RemoteGame.new()
	game.link = RemoteGame.Link.ONLINE
	game.rooms = [
		{"id": "QX4D", "name": "Sala de Caio", "owner": "Caio", "format": "classic", "seats": 9,
			"players": 8, "phase": "lobby", "small_blind": 25, "big_blind": 50,
			"level_minutes": 5, "locked": false, "open": true, "felt": "salao"},
		{"id": "K7MP", "name": "Sala de Bia", "owner": "Bia", "format": "classic", "seats": 6,
			"players": 3, "phase": "playing", "small_blind": 10, "big_blind": 20,
			"level_minutes": 5, "locked": false, "open": true, "felt": "rubi"},
		{"id": "ZR8H", "name": "Sala de Malu", "owner": "Malu", "format": "tournament", "seats": 4,
			"players": 1, "phase": "lobby", "small_blind": 10, "big_blind": 20,
			"level_minutes": 8, "locked": true, "open": true, "felt": "safira"},
		{"id": "W2TN", "name": "Sala de Zeca", "owner": "Zeca", "format": "classic", "seats": 2,
			"players": 1, "phase": "lobby", "small_blind": 5, "big_blind": 10,
			"level_minutes": 5, "locked": false, "open": true, "felt": "perola"},
	]
	game.set("_ever_open", true)
	return game


func _wifi_rooms() -> Control:
	var screen: Control = WifiRoomsScreen.new()
	screen.ready.connect(func() -> void:
		var now: int = Time.get_ticks_msec() + 600000
		screen.get("_listener").rooms = {
			"192.168.0.23": {"ip": "192.168.0.23", "port": 47820, "name": "Sala de Bia",
				"format": "classic", "seats": 6, "players": 3, "phase": "lobby", "open": true,
				"felt": "rubi", "seen": now},
			"192.168.0.31": {"ip": "192.168.0.31", "port": 47820, "name": "Sala de Caio",
				"format": "tournament", "seats": 4, "players": 2, "phase": "lobby",
				"open": true, "felt": "safira", "seen": now},
		}
		screen.call("_refresh"), CONNECT_DEFERRED)
	return screen


func _podium() -> Control:
	var nicks: Array[String] = [NICK, "Cida", "Tonho", "Malu", "Zeca", "Nina"]
	var faces: Array[int] = [AVATAR, 20, 14, 23, 16, 25]
	var places: Array[int] = [1, 2, 3, 4, 5, 6]
	var members: Array = []
	var rows: Array = []
	for i in nicks.size():
		members.append({"id": "p%d" % i, "nick": nicks[i], "avatar": faces[i]})
		rows.append({"id": "p%d" % i, "nick": nicks[i], "seat": i,
			"chips": 18000 if places[i] == 1 else 0, "held": 0, "net": 0, "place": places[i],
			"rebuys": 0})
	var final: Dictionary = {"t": "closed", "reason": "finished", "scoreboard": rows,
		"podium": rows.slice(0, 3)}
	return ResultScreen.new(final, members, "p0")
