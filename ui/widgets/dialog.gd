extends Control
## Pergunta por cima da tela, com o fundo escurecido: título, texto e até dois botões.
## O primeiro botão é o principal (à direita, perto do polegar). Tocar fora fecha sem
## escolher (como o segundo botão).

signal chosen(index: int)

const T: String = "Tokens"

## Falso: tocar fora não fecha (para perguntas que precisam de resposta).
var dismissable: bool = true

var _panel: PanelContainer = null
var _title: Label = null
var _text: Label = null
var _buttons: HBoxContainer = null


func _init() -> void:
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
	rows.add_child(_title)
	_text = Label.new()
	_text.theme_type_variation = "DimLabel"
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(320, 0)
	rows.add_child(_text)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 10)
	_buttons.alignment = BoxContainer.ALIGNMENT_END
	rows.add_child(_buttons)


## Mostra a pergunta. buttons: [principal, secundário].
func ask(title: String, text: String, buttons: Array[String]) -> void:
	_title.text = title
	_text.text = text
	_text.visible = text != ""
	for child: Node in _buttons.get_children():
		_buttons.remove_child(child)
		child.queue_free()
	for i in range(buttons.size() - 1, -1, -1):
		var button: Button = Button.new()
		button.text = buttons[i]
		button.theme_type_variation = "PrimaryButton" if i == 0 else ""
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(136, 48)
		button.pressed.connect(_answer.bind(i))
		_buttons.add_child(button)
	visible = true
	_place()


func _answer(index: int) -> void:
	visible = false
	chosen.emit(index)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and visible:
		_place()


func _place() -> void:
	_panel.reset_size()
	var panel_size: Vector2 = _panel.get_combined_minimum_size()
	_panel.size = panel_size
	_panel.position = ((size - panel_size) / 2.0).round()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and not _panel.get_rect().has_point(event.position):
		if dismissable:
			_answer(1)
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(get_theme_color("shadow", T), 0.6))
