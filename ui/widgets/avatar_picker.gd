extends Control
## Escolha de avatar por cima da tela (sala de espera): os 10 grátis numa fileira e os
## exclusivos embaixo, com o aviso do Beta.
## Tocar num escolhe e fecha; tocar fora fecha sem trocar.
##
## Só exclusivos (Loja): para escolher os avatares que vêm com a compra; os já
## escolhidos aparecem marcados e não se tocam.

signal picked(avatar: int)

const Paint := preload("res://ui/widgets/paint.gd")
const AvatarButton := preload("res://ui/widgets/avatar_button.gd")

const DIAMETER: float = 36.0
const PER_ROW: int = 10

var _panel: PanelContainer = null
var _title: Label = null
var _buttons: Array[AvatarButton] = []
var _exclusive_only: bool = false


func _init(exclusive_only: bool = false) -> void:
	_exclusive_only = exclusive_only
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
	_title.text = "Seu avatar"
	rows.add_child(_title)
	var free: GridContainer = null if exclusive_only else _grid(rows)
	if not exclusive_only:
		var hint: Label = Label.new()
		hint.theme_type_variation = "SmallLabel"
		hint.text = "Exclusivos: grátis no Beta. Depois, só na Loja."
		hint.modulate = Color(1, 1, 1, 0.7)
		rows.add_child(hint)
	var exclusive: GridContainer = _grid(rows)
	var group: ButtonGroup = null if exclusive_only else ButtonGroup.new()
	for index: int in Paint.AVATAR_COUNT:
		if exclusive_only and index < Paint.FREE_AVATARS:
			continue
		var grid: GridContainer = free if index < Paint.FREE_AVATARS else exclusive
		var button: AvatarButton = AvatarButton.new(index, DIAMETER)
		button.button_group = group
		button.pressed.connect(func() -> void:
			visible = false
			picked.emit(index))
		grid.add_child(button)
		_buttons.append(button)


func _grid(rows: VBoxContainer) -> GridContainer:
	var grid: GridContainer = GridContainer.new()
	grid.columns = PER_ROW
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 0)
	rows.add_child(grid)
	return grid


func open(current: int) -> void:
	for button: AvatarButton in _buttons:
		button.set_pressed_no_signal(button.avatar == current)
	visible = true
	_place()


## Só exclusivos: abre com os já escolhidos marcados e travados.
func open_claim(chosen: Array[int], left: int) -> void:
	_title.text = "Escolha um avatar exclusivo (falta 1)" if left == 1 \
		else "Escolha um avatar exclusivo (faltam %d)" % left
	for button: AvatarButton in _buttons:
		button.set_pressed_no_signal(chosen.has(button.avatar))
		button.disabled = chosen.has(button.avatar)
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
