extends Control
## Escolha de avatar por cima da tela (sala de espera): os 10 avatares em duas fileiras.
## Tocar num escolhe e fecha; tocar fora fecha sem trocar.

signal picked(avatar: int)

const Paint := preload("res://ui/widgets/paint.gd")
const AvatarButton := preload("res://ui/widgets/avatar_button.gd")

const DIAMETER: float = 48.0
const PER_ROW: int = 5

var _panel: PanelContainer = null
var _buttons: Array[AvatarButton] = []


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_panel = PanelContainer.new()
	_panel.theme_type_variation = "DialogPanel"
	add_child(_panel)
	var rows: VBoxContainer = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	_panel.add_child(rows)
	var title: Label = Label.new()
	title.theme_type_variation = "TitleLabel"
	title.text = "Seu avatar"
	rows.add_child(title)
	var grid: GridContainer = GridContainer.new()
	grid.columns = PER_ROW
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	rows.add_child(grid)
	var group: ButtonGroup = ButtonGroup.new()
	for index: int in Paint.AVATAR_COUNT:
		var button: AvatarButton = AvatarButton.new(index, DIAMETER)
		button.button_group = group
		button.pressed.connect(func() -> void:
			visible = false
			picked.emit(index))
		grid.add_child(button)
		_buttons.append(button)


func open(current: int) -> void:
	for i in _buttons.size():
		_buttons[i].set_pressed_no_signal(i == current)
	visible = true
	_place()


func close() -> void:
	visible = false


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
		close()
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(get_theme_color("shadow", "Tokens"), 0.6))
