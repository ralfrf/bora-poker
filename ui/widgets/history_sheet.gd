extends Control
## Histórico das mãos por cima da mesa (SPEC 11.2), aberto pelo botão ao lado do "?".
## À esquerda, as últimas mãos (a mais recente no alto) com quem ganhou; à direita, a
## mão escolhida: blinds, cartas da mesa, as suas cartas, o que cada um fez em cada
## rodada e como terminou. Só mostra o que o servidor mandou, que já vem sem as cartas
## de quem não mostrou. A partida continua por trás.

signal closed

const CloseButton := preload("res://ui/widgets/close_button.gd")
const CardView := preload("res://ui/widgets/card_view.gd")
const SafeArea := preload("res://ui/theme/safe_area.gd")
const Money := preload("res://engine/money.gd")
const T: String = "Tokens"

const PANEL_W: float = 780.0
const PANEL_H: float = 340.0
const TITLE_H: float = 34.0
const LIST_W: float = 220.0
const MINI: Vector2 = Vector2(22, 31)
const STREETS: Dictionary = {"preflop": "Pré-flop", "flop": "Flop", "turn": "Turn",
	"river": "River"}


## Uma mão na lista: número, quem ganhou e quanto.
class Entry:
	extends Button

	var title: String = ""
	var line: String = ""
	var amount: int = -1
	var mine: bool = false

	func _init() -> void:
		toggle_mode = true
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(0, 46)
		# Deixa o arraste chegar à rolagem da lista.
		mouse_filter = Control.MOUSE_FILTER_PASS
		toggled.connect(func(_on: bool) -> void: queue_redraw())

	func _draw() -> void:
		var accent: Color = get_theme_color("accent", "Tokens")
		var box: StyleBoxFlat = StyleBoxFlat.new()
		box.bg_color = Color(accent, 0.16) if button_pressed \
			else Color(get_theme_color("surface_top", "Tokens"), 0.45)
		box.border_color = Color(accent, 0.7) if button_pressed \
			else Color(get_theme_color("surface_line", "Tokens"), 0.6)
		box.set_border_width_all(1)
		box.set_corner_radius_all(10)
		box.anti_aliasing = true
		draw_style_box(box, Rect2(Vector2.ZERO, size))
		var strong: Font = get_theme_font("strong", "Tokens")
		var text_font: Font = get_theme_font("text", "Tokens")
		var small: int = get_theme_font_size("small", "Tokens")
		draw_string(strong, Vector2(10, 19), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 20,
			small + 1, get_theme_color("text", "Tokens"))
		var color: Color = accent if mine else get_theme_color("text_dim", "Tokens")
		var right: float = size.x - 10.0
		if amount >= 0:
			var number: Font = get_theme_font("display", "Tokens")
			var text: String = Money.format(amount)
			var w: float = number.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
			draw_string(number, Vector2(right - w, 37), text, HORIZONTAL_ALIGNMENT_LEFT, -1, small,
				color)
			var icon: Texture2D = get_theme_icon("chip", "Tokens")
			draw_texture(icon, Vector2(right - w - 17.0, 26))
			right -= w + 22.0
		draw_string(text_font, Vector2(10, 37), line, HORIZONTAL_ALIGNMENT_LEFT, right - 10.0,
			small, color)


var _panel: PanelContainer = null
var _inner: Control = null
var _title: Label = null
var _close: CloseButton = null
var _list_scroll: ScrollContainer = null
var _list: VBoxContainer = null
var _detail_scroll: ScrollContainer = null
var _detail: VBoxContainer = null
var _message: Label = null
var _hands: Array = []
var _my_id: String = ""
var _selected: int = -1   # número da mão escolhida


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_panel = PanelContainer.new()
	_panel.theme_type_variation = "SheetPanel"
	add_child(_panel)
	_inner = Control.new()
	_panel.add_child(_inner)
	_title = Label.new()
	_title.theme_type_variation = "TitleLabel"
	_title.text = "Histórico das mãos"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_inner.add_child(_title)
	_close = CloseButton.new()
	_close.pressed.connect(close)
	_inner.add_child(_close)
	_list_scroll = ScrollContainer.new()
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_inner.add_child(_list_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_scroll.add_child(_list)
	_detail_scroll = ScrollContainer.new()
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_inner.add_child(_detail_scroll)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 3)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_scroll.add_child(_detail)
	_message = Label.new()
	_message.theme_type_variation = "DimLabel"
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_inner.add_child(_message)


## Abre esperando a resposta do servidor.
func open() -> void:
	visible = true
	if _hands.is_empty():
		_show_message("Carregando…")
	_place()


func close() -> void:
	if visible:
		visible = false
		closed.emit()


## As mãos que o servidor mandou (a mais recente primeiro). my_id: quem está olhando.
func set_hands(hands: Array, my_id: String) -> void:
	_hands = hands
	_my_id = my_id
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if hands.is_empty():
		_show_message("Nenhuma mão terminou ainda.")
		return
	_message.visible = false
	_list_scroll.visible = true
	_detail_scroll.visible = true
	var group: ButtonGroup = ButtonGroup.new()
	var keep: bool = false
	for record: Dictionary in hands:
		keep = keep or int(record["hand"]) == _selected
	if not keep:
		_selected = int(hands[0]["hand"])
	for record: Dictionary in hands:
		var entry: Entry = Entry.new()
		entry.button_group = group
		entry.title = "Mão %d" % int(record["hand"])
		var outcome: Array = _outcome(record)
		entry.line = outcome[0]
		entry.amount = outcome[1]
		entry.mine = outcome[2]
		var number: int = int(record["hand"])
		entry.button_pressed = number == _selected
		entry.pressed.connect(func() -> void:
			_selected = number
			_show_detail(record))
		_list.add_child(entry)
		if number == _selected:
			_show_detail(record)


func _show_message(text: String) -> void:
	_message.text = text
	_message.visible = true
	_list_scroll.visible = false
	_detail_scroll.visible = false


## [texto, valor ou -1, você ganhou].
func _outcome(record: Dictionary) -> Array:
	if record.get("cancelled", false):
		return ["Cancelada: fichas devolvidas", -1, false]
	var names: Array[String] = []
	var total: int = 0
	var me: bool = false
	for payout: Dictionary in record.get("payouts", []):
		total += int(payout["amount"])
		var player: Dictionary = _player(record, int(payout["seat"]))
		names.append(_nick(player))
		me = me or player.get("id", "") == _my_id
	if names.is_empty():
		return ["", -1, false]
	var who: String = names[0] if names.size() == 1 else " e ".join(names)
	return ["%s %s" % [who, "ganha" if names.size() == 1 else "dividem"], total, me]


func _player(record: Dictionary, seat: int) -> Dictionary:
	for player: Dictionary in record.get("players", []):
		if int(player["seat"]) == seat:
			return player
	return {}


func _nick(player: Dictionary) -> String:
	if player.is_empty():
		return "?"
	return "Você" if player.get("id", "") == _my_id and _my_id != "" else String(player["nick"])


# ------------------------------------------------------------------ detalhe


func _show_detail(record: Dictionary) -> void:
	for child: Node in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	var head: HBoxContainer = _row()
	head.add_child(_label("Mão %d" % int(record["hand"]), "StrongLabel"))
	head.add_child(_label("   Blinds", "SmallLabel"))
	_amount(head, int(record["small_blind"]))
	head.add_child(_label(" /", "SmallLabel"))
	_amount(head, int(record["big_blind"]))
	var cards_row: HBoxContainer = _row()
	cards_row.add_theme_constant_override("separation", 3)
	cards_row.add_child(_label("Mesa ", "SmallLabel"))
	var board: Array = record.get("board", [])
	if board.is_empty():
		cards_row.add_child(_label("sem cartas", "SmallLabel"))
	_cards(cards_row, board)
	if record.has("mine"):
		cards_row.add_child(_label("     Suas cartas ", "SmallLabel"))
		_cards(cards_row, record["mine"])
	_detail.add_child(_gap(4))
	for street: Dictionary in record.get("streets", []):
		var actions: Array = street.get("actions", [])
		if actions.is_empty() and (street.get("cards", []) as Array).is_empty():
			continue
		var title: HBoxContainer = _row()
		title.add_theme_constant_override("separation", 3)
		var name_label: Label = _label(STREETS.get(street["street"], street["street"]),
			"NameLabel")
		name_label.add_theme_color_override("font_color", get_theme_color("accent", T))
		title.add_child(name_label)
		_cards(title, street.get("cards", []))
		for action: Dictionary in actions:
			_action_row(record, action)
	_detail.add_child(_gap(4))
	var result_title: Label = _label("Resultado", "NameLabel")
	result_title.add_theme_color_override("font_color", get_theme_color("accent", T))
	_detail.add_child(result_title)
	if record.get("cancelled", false):
		_detail.add_child(_label("Mão cancelada: as fichas voltaram para cada um.", "SmallLabel"))
	var shown_names: Dictionary = {}
	for entry: Dictionary in record.get("shown", []):
		shown_names[int(entry["seat"])] = String(entry["name"])
	var opened: Dictionary = {}
	for entry: Dictionary in record.get("revealed", []) + record.get("shown", []):
		var seat: int = int(entry["seat"])
		if opened.has(seat):
			continue
		opened[seat] = true
		var row: HBoxContainer = _row()
		row.add_theme_constant_override("separation", 3)
		row.add_child(_label(_nick(_player(record, seat)), "NameLabel"))
		row.add_child(_label(" mostra ", "SmallLabel"))
		_cards(row, entry["cards"])
		if shown_names.has(seat):
			row.add_child(_label("  " + shown_names[seat], "SmallLabel"))
	if not record.get("cancelled", false):
		for refund: Dictionary in record.get("refunds", []):
			var row: HBoxContainer = _row()
			row.add_child(_label(_nick(_player(record, int(refund["seat"]))), "NameLabel"))
			row.add_child(_label(" recebe de volta a aposta não paga", "SmallLabel"))
			_amount(row, int(refund["amount"]))
	for payout: Dictionary in record.get("payouts", []):
		var seat: int = int(payout["seat"])
		var row: HBoxContainer = _row()
		row.add_child(_label(_nick(_player(record, seat)), "NameLabel"))
		row.add_child(_label(" ganha", "SmallLabel"))
		_amount(row, int(payout["amount"]))
		if shown_names.has(seat):
			row.add_child(_label(" com " + shown_names[seat].to_lower(), "SmallLabel"))
		elif not record.get("showdown", false):
			row.add_child(_label("  (os outros desistiram)", "SmallLabel"))
	_detail_scroll.scroll_vertical = 0


func _action_row(record: Dictionary, action: Dictionary) -> void:
	var row: HBoxContainer = _row()
	row.add_child(_label(_nick(_player(record, int(action["seat"]))), "NameLabel"))
	var amount: int = -1
	var verb: String = ""
	if action.has("blind"):
		verb = "small blind" if action["blind"] == "small" else "big blind"
		amount = int(action["amount"])
	else:
		match String(action["action"]):
			"fold":
				verb = "Desistiu"
			"check":
				verb = "Passou"
			"call":
				verb = "Pagou"
				amount = int(action["amount"])
			"bet":
				verb = "Apostou"
				amount = int(action["to"])
			"raise":
				verb = "Aumentou para"
				amount = int(action["to"])
	row.add_child(_label(" " + verb, "SmallLabel"))
	if amount >= 0:
		_amount(row, amount)
	if action.get("all_in", false):
		var tag: Label = _label("  All-in", "NameLabel")
		tag.add_theme_color_override("font_color", get_theme_color("danger", T))
		row.add_child(tag)


func _row() -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	_detail.add_child(row)
	return row


func _label(text: String, variation: String) -> Label:
	var label: Label = Label.new()
	label.theme_type_variation = variation
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _gap(height: float) -> Control:
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(0, height)
	return gap


## Valor ao lado do ícone de ficha.
func _amount(row: HBoxContainer, cents: int) -> void:
	var icon: TextureRect = TextureRect.new()
	icon.texture = get_theme_icon("chip", T)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.custom_minimum_size = Vector2(20, 18)
	row.add_child(icon)
	row.add_child(_label(Money.format(cents), "AmountLabel"))


func _cards(row: HBoxContainer, cards: Array) -> void:
	for card_value: Variant in cards:
		var card: CardView = CardView.new()
		card.card = int(card_value)
		card.custom_minimum_size = MINI
		card.size = MINI
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(card)


# ------------------------------------------------------------------ posições


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and visible:
		_place()


func _place() -> void:
	var area: Rect2 = SafeArea.content(self).grow(-8.0)
	var margin: float = 8.0
	var w: float = minf(PANEL_W, area.size.x)
	var h: float = minf(PANEL_H, area.size.y)
	var inner: Vector2 = Vector2(w, h) - Vector2.ONE * margin * 2.0
	_inner.custom_minimum_size = inner
	_panel.size = Vector2(w, h)
	_panel.position = (area.position + (area.size - Vector2(w, h)) / 2.0).round()
	_title.position = Vector2.ZERO
	_title.size = Vector2(inner.x, TITLE_H)
	_close.size = Vector2(36, 36)
	_close.position = Vector2(inner.x - 38.0, -2.0)
	var top: float = TITLE_H + 6.0
	_list_scroll.position = Vector2(4, top)
	_list_scroll.size = Vector2(LIST_W, inner.y - top)
	_detail_scroll.position = Vector2(LIST_W + 20.0, top)
	_detail_scroll.size = Vector2(inner.x - LIST_W - 24.0, inner.y - top)
	_message.position = Vector2(0, top)
	_message.size = Vector2(inner.x, inner.y - top)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and not _panel.get_rect().has_point(event.position):
		close()
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(get_theme_color("shadow", T), 0.62))
