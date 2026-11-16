extends VBoxContainer
## Uma opção com rótulo em cima e botões lado a lado; só um fica escolhido.
## A largura de cada botão acompanha o tamanho do texto.

signal changed(index: int)

const ROW_H: float = 40.0

var index: int = 0
var _title: Label = null
var _row: HBoxContainer = null
var _group: ButtonGroup = null
var _chip: TextureRect = null
var _compact: bool = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _chip != null:
		_chip.texture = get_theme_icon("chip", "Tokens")


## chips: os botões são valores em fichas; o rótulo ganha o ícone de ficha.
## compact: texto menor nos botões, para valores longos (blinds).
func _init(title: String, labels: Array[String], chosen: int, chips: bool = false,
		compact: bool = false) -> void:
	_compact = compact
	add_theme_constant_override("separation", 4)
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", 5)
	add_child(head)
	_title = Label.new()
	_title.theme_type_variation = "SmallLabel"
	_title.text = title
	head.add_child(_title)
	if chips:
		_chip = TextureRect.new()
		_chip.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		_chip.custom_minimum_size = Vector2(14, 14)
		head.add_child(_chip)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 6)
	add_child(_row)
	set_labels(labels, chosen)


func set_labels(labels: Array[String], chosen: int) -> void:
	for child: Node in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	_group = ButtonGroup.new()
	index = clampi(chosen, 0, labels.size() - 1)
	for i in labels.size():
		var button: Button = Button.new()
		button.text = labels[i]
		button.theme_type_variation = "ChoiceButton"
		button.toggle_mode = true
		button.button_group = _group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0, ROW_H)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_stretch_ratio = maxf(labels[i].length(), 4.0) + 4.0
		button.clip_text = true
		if _compact:
			button.add_theme_font_size_override("font_size", 12)
			button.add_theme_constant_override("h_separation", 0)
			button.size_flags_stretch_ratio = 1.0
		button.button_pressed = i == index
		button.pressed.connect(_on_pressed.bind(i))
		_row.add_child(button)


func _on_pressed(i: int) -> void:
	index = i
	changed.emit(i)
