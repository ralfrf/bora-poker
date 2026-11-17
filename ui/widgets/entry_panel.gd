extends Control
## Painel de digitar por cima da tela: título, dica, caixa de texto e dois botões. Serve
## para o código da sala, a senha de 4 números e o endereço do servidor. Fica no alto,
## para o teclado do celular não cobrir.

signal entered(text: String)
signal cancelled

var field: LineEdit = null
var _panel: PanelContainer = null
var _title: Label = null
var _hint: Label = null
var _error: Label = null
var _ok: Button = null


## keyboard: o teclado do celular (LineEdit.KEYBOARD_TYPE_*). O texto fica à mostra: a senha
## da sala é curta e só vale entre amigos.
func _init(title: String, hint: String, placeholder: String, max_length: int,
		keyboard: LineEdit.VirtualKeyboardType = LineEdit.KEYBOARD_TYPE_DEFAULT,
		ok_text: String = "Entrar", width: float = 320.0) -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_panel = PanelContainer.new()
	_panel.theme_type_variation = "DialogPanel"
	add_child(_panel)
	var rows: VBoxContainer = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	_panel.add_child(rows)
	_title = Label.new()
	_title.theme_type_variation = "TitleLabel"
	_title.text = title
	rows.add_child(_title)
	_hint = Label.new()
	_hint.theme_type_variation = "DimLabel"
	_hint.text = hint
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(width, 0)
	_hint.visible = hint != ""
	rows.add_child(_hint)
	field = LineEdit.new()
	field.placeholder_text = placeholder
	field.max_length = max_length
	field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	field.context_menu_enabled = false
	field.custom_minimum_size = Vector2(width, 52)
	field.virtual_keyboard_type = keyboard
	field.text_submitted.connect(func(text: String) -> void: entered.emit(text))
	field.text_changed.connect(func(_text: String) -> void: _error.text = "")
	rows.add_child(field)
	_error = Label.new()
	_error.theme_type_variation = "SmallLabel"
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.custom_minimum_size = Vector2(width, 0)
	rows.add_child(_error)
	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	rows.add_child(buttons)
	var cancel: Button = Button.new()
	cancel.text = "Cancelar"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.custom_minimum_size = Vector2(136, 48)
	cancel.pressed.connect(func() -> void:
		close()
		cancelled.emit())
	buttons.add_child(cancel)
	_ok = Button.new()
	_ok.text = ok_text
	_ok.theme_type_variation = "PrimaryButton"
	_ok.focus_mode = Control.FOCUS_NONE
	_ok.custom_minimum_size = Vector2(136, 48)
	_ok.pressed.connect(func() -> void: entered.emit(field.text))
	buttons.add_child(_ok)


## Abre com esse texto já escrito; title e hint trocam os de antes (se não vazios).
func open(text: String = "", title: String = "", hint: String = "") -> void:
	if title != "":
		_title.text = title
	if hint != "":
		_hint.text = hint
		_hint.visible = true
	field.text = text
	field.caret_column = text.length()
	_error.text = ""
	_error.add_theme_color_override("font_color", get_theme_color("danger", "Tokens"))
	visible = true
	_place()
	field.grab_focus()


func close() -> void:
	field.release_focus()
	visible = false


func show_error(text: String) -> void:
	_error.text = text
	_place()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and visible:
		_place()


func _place() -> void:
	_panel.reset_size()
	var panel_size: Vector2 = _panel.get_combined_minimum_size()
	_panel.size = panel_size
	_panel.position = Vector2(((size.x - panel_size.x) / 2.0), maxf(12.0, size.y * 0.06)).round()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(get_theme_color("shadow", "Tokens"), 0.6))
