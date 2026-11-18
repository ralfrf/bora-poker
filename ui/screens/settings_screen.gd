extends "res://ui/screens/screen.gd"
## Configurações (SPEC 11.3): sons, vibração e silenciar reações. Cada troca vale na hora
## e fica gravada no perfil. Embaixo, o link da política de privacidade (a Play pede o link
## também dentro do app), que pergunta antes de abrir o navegador.

signal back

const Profile := preload("res://ui/app/profile.gd")
const ToggleRow := preload("res://ui/widgets/toggle_row.gd")
const Dialog := preload("res://ui/widgets/dialog.gd")
const Sfx := preload("res://ui/app/sfx.gd")

const PRIVACY_URL: String = "https://ralfrf.github.io/bora-poker/privacidade/"

var profile: Profile = null

var _title: Label = null
var _sound: ToggleRow = null
var _vibration: ToggleRow = null
var _mute: ToggleRow = null
var _privacy: Button = null
var _done: Button = null
var _dialog: Dialog = null


func _init(owner_profile: Profile) -> void:
	profile = owner_profile


func _build() -> void:
	_title = Label.new()
	_title.theme_type_variation = "TitleLabel"
	_title.text = "Configurações"
	add_child(_title)
	_sound = ToggleRow.new("Sons", "Cartas, fichas, jogadas, vitória e aviso da sua vez",
		profile.sound)
	_sound.toggled.connect(func(on: bool) -> void:
		profile.sound = on
		_save()
		Sfx.play(Sfx.CHIP))
	add_child(_sound)
	_vibration = ToggleRow.new("Vibração", "Quando faltam 5 segundos para acabar a sua vez",
		profile.vibration)
	_vibration.toggled.connect(func(on: bool) -> void:
		profile.vibration = on
		_save()
		Sfx.vibrate(200))
	add_child(_vibration)
	_mute = ToggleRow.new("Silenciar reações", "Não mostra os emojis e as frases dos outros na mesa",
		profile.mute_reactions)
	_mute.toggled.connect(func(on: bool) -> void:
		profile.mute_reactions = on
		_save())
	add_child(_mute)
	_privacy = Button.new()
	_privacy.text = "Política de privacidade"
	_privacy.theme_type_variation = "QuietButton"
	_privacy.focus_mode = Control.FOCUS_NONE
	_privacy.pressed.connect(func() -> void:
		_dialog.ask("Abrir a política de privacidade?", "A página abre no navegador do celular.",
			["Abrir", "Cancelar"]))
	add_child(_privacy)
	_done = action_button("Pronto", true)
	_done.pressed.connect(func() -> void: back.emit())
	add_child(_done)
	_dialog = Dialog.new()
	_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dialog.chosen.connect(func(index: int) -> void:
		if index == 0:
			OS.shell_open(PRIVACY_URL))
	add_child(_dialog)


func _save() -> void:
	profile.apply()
	profile.save()


func _layout() -> void:
	var b: Rect2 = body()
	var col: Rect2 = column()
	place(_title, Rect2(b.position.x, b.position.y, b.size.x, 34))
	var w: float = minf(b.size.x, 460.0)
	var y: float = b.position.y + 48.0
	for row: ToggleRow in [_sound, _vibration, _mute]:
		place(row, Rect2(b.position.x, y, w, ToggleRow.ROW_H))
		row.queue_redraw()
		y += ToggleRow.ROW_H + 10.0
	place(_privacy, Rect2(b.position.x, y, _privacy.get_combined_minimum_size().x, 34))
	place(_done, Rect2(col.position.x, col.end.y - BUTTON_H, col.size.x, BUTTON_H))


func go_back() -> bool:
	if _dialog.visible:
		_dialog.visible = false
	else:
		back.emit()
	return true
