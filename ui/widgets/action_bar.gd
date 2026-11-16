extends VBoxContainer
## Barra de ações da sua vez: os três botões empilhados (Apostar ou Aumentar em cima,
## Passar ou Pagar, Desistir embaixo), na coluna estreita da direita da mesa.
## Um toque em Apostar ou Aumentar abre o painel de aposta (atalhos mínimo, meio pote,
## pote e all-in, e o controle deslizante); aí o botão mostra o valor e confirma, e
## Desistir vira Voltar. O painel é uma peça separada (`sheet`): quem usa a barra o
## coloca na tela, ao lado dela. Todos os botões têm pelo menos 48 px de altura.
## O valor de apostar e aumentar é o total da aposta na rodada ("aumentar para").

signal acted(action: String, amount: int)
## O painel abriu ou fechou: quem posiciona as peças as recoloca.
signal sheet_toggled(open: bool)

const Money := preload("res://engine/money.gd")
const Paint := preload("res://ui/widgets/paint.gd")
const T: String = "Tokens"
const ROW: float = 48.0
const MAIN_ROW: float = 52.0
## Tempo mínimo entre abrir o painel e confirmar, contra toque duplo sem querer.
const CONFIRM_GUARD_MS: int = 300


## Botão com rótulo e, se houver, o valor com o ícone de ficha.
class ActionButton:
	extends Button

	var label: String = ""
	var amount: int = -1
	var _face: Control = null

	func _init(primary: bool) -> void:
		theme_type_variation = "PrimaryButton" if primary else ""
		focus_mode = Control.FOCUS_NONE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_face = Control.new()
		_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_face.set_anchors_preset(Control.PRESET_FULL_RECT)
		_face.draw.connect(_draw_face)
		add_child(_face)

	func set_content(text: String, value: int) -> void:
		label = text
		amount = value
		_face.queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED or what == NOTIFICATION_THEME_CHANGED:
			if _face != null:
				_face.queue_redraw()

	## Sem valor: rótulo numa linha. Com valor: rótulo pequeno em cima e o valor, com o
	## ícone de ficha, embaixo, para caber em botões estreitos.
	func _draw_face() -> void:
		var ink: Color = get_theme_color("font_disabled_color" if disabled else "font_color")
		var font: Font = get_theme_font("font")
		var font_size: int = get_theme_font_size("font_size")
		if amount < 0:
			_face.draw_string(font, Vector2(0, size.y / 2.0 + font_size * 0.36), label,
				HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, ink)
			return
		var small: int = get_theme_font_size("small", T)
		_face.draw_string(font, Vector2(0, size.y / 2.0 - 3.0), label,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, small, Color(ink, 0.82))
		var number_font: Font = get_theme_font("display", T)
		var number: String = Money.format(amount)
		var number_w: float = number_font.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT,
			-1, font_size).x
		var x: float = (size.x - number_w - 14.0) / 2.0
		var baseline: float = size.y / 2.0 + 3.0 + font_size * 0.72
		var primary: bool = theme_type_variation == "PrimaryButton"
		Paint.chip(_face, Vector2(x + 5.0, baseline - font_size * 0.36), 5.0,
			ink if primary else get_theme_color("chip_0", T),
			get_theme_color("accent", T) if primary else get_theme_color("chip_mark", T),
			get_theme_constant("chip_style", T))
		_face.draw_string(number_font, Vector2(x + 14.0, baseline), number,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)


## Painel de aposta: atalhos 2x2 e controle deslizante com − e +.
var sheet: PanelContainer = null

var _legal: Dictionary = {}
var _pot: int = 0
var _current_bet: int = 0
var _step: int = 1
var _amount: int = 0
var _open: bool = false
var _opened_at: int = 0

var _slider: HSlider = null
var _fold: ActionButton = null
var _call: ActionButton = null
var _raise: ActionButton = null


func _init() -> void:
	add_theme_constant_override("separation", 8)
	_raise = ActionButton.new(true)
	_call = ActionButton.new(false)
	_fold = ActionButton.new(false)
	for button: ActionButton in [_raise, _call, _fold]:
		button.custom_minimum_size = Vector2(0, MAIN_ROW)
		add_child(button)
	_fold.pressed.connect(_on_fold)
	_call.pressed.connect(_on_call)
	_raise.pressed.connect(_on_raise)

	sheet = PanelContainer.new()
	sheet.visible = false
	var rows: VBoxContainer = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	sheet.add_child(rows)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	rows.add_child(grid)
	for entry: Array in [["Mínimo", 0], ["½ pote", 1], ["Pote", 2], ["All-in", 3]]:
		var button: Button = Button.new()
		button.text = entry[0]
		button.theme_type_variation = "QuietButton"
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0, ROW)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_quick.bind(entry[1]))
		grid.add_child(button)
	var slider_row: HBoxContainer = HBoxContainer.new()
	slider_row.add_theme_constant_override("separation", 8)
	rows.add_child(slider_row)
	slider_row.add_child(_step_button("−", -1))
	_slider = HSlider.new()
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.custom_minimum_size = Vector2(0, 32)
	_slider.focus_mode = Control.FOCUS_NONE
	_slider.value_changed.connect(func(value: float) -> void: _set_amount(int(value)))
	slider_row.add_child(_slider)
	slider_row.add_child(_step_button("+", 1))


## O painel fica fora da barra na árvore; o estilo dele vem do tema da barra.
func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and sheet != null:
		var box: StyleBoxFlat = StyleBoxFlat.new()
		box.bg_color = get_theme_color("surface", T)
		box.border_color = get_theme_color("surface_line", T)
		box.set_border_width_all(1)
		box.set_corner_radius_all(get_theme_constant("radius_panel", T))
		box.anti_aliasing = true
		box.shadow_color = Color(get_theme_color("shadow", T), 0.35)
		box.shadow_size = 12
		box.shadow_offset = Vector2(0, 4)
		box.set_content_margin_all(8)
		sheet.add_theme_stylebox_override("panel", box)


## Mostra as ações válidas (o campo legal de you). pot: total na mesa; step: small blind.
func show_legal(legal: Dictionary, pot: int, current_bet: int, step: int) -> void:
	_legal = legal
	_pot = pot
	_current_bet = current_bet
	_step = maxi(step, 1)
	var can_raise: bool = legal.get("can_raise", false)
	_raise.disabled = not can_raise
	if can_raise:
		_slider.min_value = int(legal["min_to"])
		_slider.max_value = int(legal["max_to"])
		_slider.step = _step
		_set_amount(int(legal["min_to"]))
	_set_open(false)


## Abre o painel de aposta já no valor mínimo.
func open_sheet() -> void:
	if _legal.get("can_raise", false):
		_set_amount(int(_legal["min_to"]))
		_set_open(true)


func close_sheet() -> void:
	_set_open(false)


func _set_open(value: bool) -> void:
	_open = value
	_opened_at = Time.get_ticks_msec()
	sheet.visible = value
	_refresh_labels()
	sheet_toggled.emit(value)


func _refresh_labels() -> void:
	_fold.set_content("Voltar" if _open else "Desistir", -1)
	if _legal.get("can_check", false):
		_call.set_content("Passar", -1)
	else:
		_call.set_content("Pagar", int(_legal.get("call", 0)))
	var word: String = "Apostar" if _legal.get("is_bet", false) else "Aumentar"
	if not _open:
		_raise.set_content(word, -1)
		return
	if _amount >= int(_legal.get("max_to", 0)):
		word = "All-in"
	_raise.set_content(word, _amount)


func _step_button(text: String, direction: int) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.theme_type_variation = "QuietButton"
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(ROW, ROW)
	button.pressed.connect(func() -> void: _set_amount(_amount + direction * _step))
	return button


func _set_amount(value: int) -> void:
	var low: int = int(_legal.get("min_to", 0))
	var high: int = int(_legal.get("max_to", 0))
	# O controle anda em passos do small blind, mas o mínimo e o all-in sempre valem.
	if value > low and value < high:
		value = low + int(round(float(value - low) / _step)) * _step
	_amount = clampi(value, low, high)
	_slider.set_value_no_signal(_amount)
	_refresh_labels()


func _on_quick(kind: int) -> void:
	var pot_after_call: int = _pot + int(_legal.get("call", 0))
	match kind:
		0:
			_set_amount(int(_legal.get("min_to", 0)))
		1:
			@warning_ignore("integer_division")
			_set_amount(_current_bet + pot_after_call / 2)
		2:
			_set_amount(_current_bet + pot_after_call)
		3:
			_set_amount(int(_legal.get("max_to", 0)))


func _on_fold() -> void:
	if _open:
		_set_open(false)
	else:
		acted.emit("fold", 0)


func _on_call() -> void:
	acted.emit("check" if _legal.get("can_check", false) else "call", 0)


func _on_raise() -> void:
	if not _open:
		open_sheet()
		return
	if Time.get_ticks_msec() - _opened_at < CONFIRM_GUARD_MS:
		return
	acted.emit("bet" if _legal.get("is_bet", false) else "raise", _amount)
