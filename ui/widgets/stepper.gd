extends VBoxContainer
## Número com − e + (lugares da mesa). Rótulo em cima, como as outras opções.

signal changed(value: int)

var value: int = 0
var low: int = 0
var high: int = 0
var _number: Label = null
var _minus: Button = null
var _plus: Button = null
var _suffix: String = ""


func _init(title: String, start: int, min_value: int, max_value: int, suffix: String) -> void:
	low = min_value
	high = max_value
	_suffix = suffix
	add_theme_constant_override("separation", 4)
	var label: Label = Label.new()
	label.theme_type_variation = "SmallLabel"
	label.text = title
	add_child(label)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	_minus = _button("−", -1)
	row.add_child(_minus)
	_number = Label.new()
	_number.theme_type_variation = "NumberLabel"
	_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_number.custom_minimum_size = Vector2(0, 40)
	row.add_child(_number)
	_plus = _button("+", 1)
	row.add_child(_plus)
	_apply(start)


func _button(text: String, step: int) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.theme_type_variation = "ChoiceButton"
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(56, 40)
	button.pressed.connect(func() -> void:
		_apply(value + step)
		changed.emit(value))
	return button


func _apply(new_value: int) -> void:
	value = clampi(new_value, low, high)
	_number.text = "%d %s" % [value, _suffix]
	_minus.disabled = value <= low
	_plus.disabled = value >= high
