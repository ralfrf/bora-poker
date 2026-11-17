extends "res://ui/screens/screen.gd"
## Início (SPEC 11.1): os três modos, com o último usado já escolhido. À distância
## ainda aparece como "Em breve". No alto da coluna, o seu perfil e, logo
## abaixo, Configurações e Ajuda (a Loja só aparece quando for liberada).

signal play(mode: String)
signal edit_profile
signal open_settings
signal open_help
signal open_shop

const Profile := preload("res://ui/app/profile.gd")
const ModeCard := preload("res://ui/widgets/mode_card.gd")
const Logo := preload("res://ui/widgets/logo.gd")
const Paint := preload("res://ui/widgets/paint.gd")
const AvatarButton := preload("res://ui/widgets/avatar_button.gd")
const ShopScreen := preload("res://ui/screens/shop_screen.gd")

## Modos prontos nesta versão.
const READY: Array[String] = [Profile.MODE_OFFLINE, Profile.MODE_WIFI]


## Botão do perfil: avatar, apelido e "Editar".
class ProfileChip:
	extends Button

	var nick: String = ""
	var avatar: int = 0

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE

	func _draw() -> void:
		var box: StyleBoxFlat = StyleBoxFlat.new()
		box.bg_color = Color(get_theme_color("surface", "Tokens"), 0.9 if not is_pressed() else 0.6)
		box.border_color = get_theme_color("surface_line", "Tokens")
		box.set_border_width_all(1)
		box.set_corner_radius_all(int(size.y / 2.0))
		box.anti_aliasing = true
		draw_style_box(box, Rect2(Vector2.ZERO, size))
		var r: float = size.y / 2.0 - 5.0
		var center: Vector2 = Vector2(size.y / 2.0, size.y / 2.0)
		Paint.avatar(self, Rect2(center - Vector2.ONE * r, Vector2.ONE * r * 2.0), avatar,
			AvatarButton.colors_of(self), 0, 0.0)
		var left: float = size.y + 2.0
		var width: float = size.x - left - 12.0
		var small: int = get_theme_font_size("small", "Tokens")
		draw_string(get_theme_font("strong", "Tokens"), Vector2(left, size.y / 2.0 - 2.0),
			nick, HORIZONTAL_ALIGNMENT_LEFT, width, small, get_theme_color("text", "Tokens"))
		draw_string(get_theme_font("text", "Tokens"), Vector2(left, size.y / 2.0 + small + 1.0),
			"Editar perfil", HORIZONTAL_ALIGNMENT_LEFT, width, small,
			get_theme_color("accent", "Tokens"))


var profile: Profile = null

var _logo: Logo = null
var _subtitle: Label = null
var _cards: Dictionary = {}   # modo -> ModeCard
var _chip: ProfileChip = null
var _play: Button = null
var _links: Array[Button] = []
var _mode: String = Profile.MODE_OFFLINE


func _init(owner_profile: Profile) -> void:
	profile = owner_profile


func _build() -> void:
	_mode = profile.last_mode if READY.has(profile.last_mode) else READY[0]
	_logo = Logo.new()
	add_child(_logo)
	_subtitle = Label.new()
	_subtitle.theme_type_variation = "SmallLabel"
	_subtitle.text = "Escolha como jogar"
	add_child(_subtitle)
	var group: ButtonGroup = ButtonGroup.new()
	var entries: Array = [
		[Profile.MODE_OFFLINE, "Offline", "Você contra bots, sem internet", ModeCard.ICON_BOTS],
		[Profile.MODE_WIFI, "Mesma rede",
			"Dica: Alguém também pode compartilhar a internet para jogarem juntos.", ModeCard.ICON_WIFI],
		[Profile.MODE_ONLINE, "À distância", "Amigos em qualquer lugar", ModeCard.ICON_WORLD],
	]
	for entry: Array in entries:
		var mode: String = entry[0]
		var card: ModeCard = ModeCard.new(entry[1], entry[2], entry[3], not READY.has(mode))
		card.button_group = group
		card.button_pressed = mode == _mode
		card.pressed.connect(func() -> void: _mode = mode)
		add_child(card)
		_cards[mode] = card
	_chip = ProfileChip.new()
	_chip.nick = profile.nick
	_chip.avatar = profile.avatar
	_chip.pressed.connect(func() -> void: edit_profile.emit())
	add_child(_chip)
	var links: Array = [["Configurações", open_settings], ["Ajuda", open_help]]
	if ShopScreen.VISIBLE:
		links.append(["Loja", open_shop])
	for link: Array in links:
		var button: Button = Button.new()
		button.text = link[0]
		button.theme_type_variation = "QuietButton"
		button.focus_mode = Control.FOCUS_NONE
		var target: Signal = link[1]
		button.pressed.connect(func() -> void: target.emit())
		add_child(button)
		_links.append(button)
	_play = action_button("Jogar", true)
	_play.pressed.connect(func() -> void: play.emit(_mode))
	add_child(_play)


func _layout() -> void:
	var b: Rect2 = body()
	var col: Rect2 = column()
	place(_logo, Rect2(b.position, Vector2(200, 30)))
	place(_subtitle, Rect2(b.position.x, b.position.y + 34.0, b.size.x, 18))
	var top: float = b.position.y + 64.0
	var gap: float = 12.0
	var w: float = (b.size.x - gap * 2.0) / 3.0
	var h: float = minf(b.end.y - top, 240.0)
	top = maxf(top, b.position.y + 64.0 + (b.end.y - top - h) / 2.0)
	var i: int = 0
	for mode: String in Profile.MODES:
		place(_cards[mode], Rect2(b.position.x + i * (w + gap), top, w, h))
		i += 1
	place(_chip, Rect2(col.position.x, col.position.y, col.size.x, 46))
	for k in _links.size():
		place(_links[k], Rect2(col.position.x, col.position.y + 56.0 + k * 46.0, col.size.x, 40))
	place(_play, Rect2(col.position.x, col.end.y - BUTTON_H, col.size.x, BUTTON_H))
