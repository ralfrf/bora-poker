extends "res://ui/screens/screen.gd"
## Primeira abertura e edição do perfil (SPEC 11.1): apelido e avatar, sem cadastro.
## Na coluna da direita, o seu lugar como vai aparecer na mesa.

signal saved
signal cancelled

const Profile := preload("res://ui/app/profile.gd")
const Room := preload("res://server/room.gd")
const AvatarButton := preload("res://ui/widgets/avatar_button.gd")
const SeatView := preload("res://ui/widgets/seat_view.gd")
const Logo := preload("res://ui/widgets/logo.gd")

const AvatarPaint := preload("res://ui/widgets/paint.gd")

const AVATAR_D: float = 40.0

var profile: Profile = null
var first: bool = true

var _logo: Logo = null
var _title: Label = null
var _field: LineEdit = null
var _hint: Label = null
var _avatar_label: Label = null
var _avatars: HBoxContainer = null
var _preview_label: Label = null
var _preview: SeatView = null
var _confirm: Button = null
var _cancel: Button = null
var _avatar: int = 0


func _init(owner_profile: Profile, first_time: bool) -> void:
	profile = owner_profile
	first = first_time


func _build() -> void:
	_avatar = clampi(profile.avatar, 0, AvatarPaint.AVATAR_COUNT - 1)
	_logo = Logo.new()
	add_child(_logo)
	_title = Label.new()
	_title.theme_type_variation = "TitleLabel"
	_title.text = "Como a turma vai te chamar?" if first else "Seu perfil"
	add_child(_title)
	_field = LineEdit.new()
	_field.placeholder_text = "Seu apelido"
	_field.max_length = Room.MAX_NICK
	_field.text = profile.nick
	_field.context_menu_enabled = false
	_field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	_field.text_changed.connect(func(_text: String) -> void: _refresh())
	_field.text_submitted.connect(func(_text: String) -> void: _field.release_focus())
	add_child(_field)
	_hint = Label.new()
	_hint.theme_type_variation = "SmallLabel"
	_hint.text = "Até %d letras. Sem cadastro: fica só neste celular." % Room.MAX_NICK
	add_child(_hint)
	_avatar_label = Label.new()
	_avatar_label.theme_type_variation = "SmallLabel"
	_avatar_label.text = "Avatar"
	add_child(_avatar_label)
	_avatars = HBoxContainer.new()
	_avatars.add_theme_constant_override("separation", 2)
	add_child(_avatars)
	var group: ButtonGroup = ButtonGroup.new()
	for index: int in AvatarPaint.AVATAR_COUNT:
		var button: AvatarButton = AvatarButton.new(index, AVATAR_D)
		button.button_group = group
		button.button_pressed = index == _avatar
		button.pressed.connect(func() -> void:
			_avatar = index
			_refresh())
		_avatars.add_child(button)
	_preview_label = Label.new()
	_preview_label.theme_type_variation = "SmallLabel"
	_preview_label.text = "Na mesa"
	_preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_preview_label)
	_preview = SeatView.new()
	add_child(_preview)
	_confirm = action_button("Continuar" if first else "Salvar", true)
	_confirm.pressed.connect(_on_confirm)
	add_child(_confirm)
	_cancel = action_button("Voltar", false)
	_cancel.visible = not first
	_cancel.pressed.connect(func() -> void: cancelled.emit())
	add_child(_cancel)
	_refresh()


func _layout() -> void:
	var b: Rect2 = body()
	var col: Rect2 = column()
	place(_logo, Rect2(b.position, Vector2(200, 30)))
	# Bloco do formulário centrado na altura que sobra abaixo da marca.
	var block_h: float = 36.0 + 10.0 + 52.0 + 6.0 + 18.0 + 18.0 + 18.0 + AVATAR_D + 16.0
	var top: float = maxf(b.position.y + 44.0, b.position.y + 30.0 + (b.size.y - 30.0 - block_h) / 2.0)
	var w: float = minf(b.size.x, 420.0)
	var y: float = top
	place(_title, Rect2(b.position.x, y, b.size.x, 36))
	y += 46.0
	place(_field, Rect2(b.position.x, y, w, 52))
	y += 58.0
	place(_hint, Rect2(b.position.x + 2.0, y, w, 18))
	y += 36.0
	place(_avatar_label, Rect2(b.position.x + 2.0, y, w, 18))
	y += 18.0
	_avatars.position = Vector2(b.position.x - 8.0, y).round()
	_avatars.size = _avatars.get_combined_minimum_size()
	place(_confirm, Rect2(col.position.x, col.end.y - BUTTON_H, col.size.x, BUTTON_H))
	place(_cancel, Rect2(col.position.x, col.end.y - BUTTON_H * 2.0 - 8.0, col.size.x, BUTTON_H))
	# A prévia fica na altura do campo do apelido: digita e já vê como fica.
	var preview_y: float = _field.position.y - 20.0
	place(_preview_label, Rect2(col.position.x, preview_y, col.size.x, 18))
	_preview.position = Vector2(col.get_center().x - SeatView.SIZE.x / 2.0,
		_field.position.y + 4.0).round()


func _refresh() -> void:
	var nick: String = _field.text.strip_edges()
	_confirm.disabled = nick == ""
	_preview.data = {"nick": nick if nick != "" else "Seu apelido", "avatar": _avatar,
		"stack": 2000}


func _on_confirm() -> void:
	if _field.text.strip_edges() == "":
		return
	profile.set_nick(_field.text)
	profile.avatar = _avatar
	profile.save()
	saved.emit()


func go_back() -> bool:
	if first:
		return false
	cancelled.emit()
	return true
