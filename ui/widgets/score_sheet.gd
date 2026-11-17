extends Control
## Placar de agora por cima da mesa (SPEC 11.2), aberto pelo botão ao lado do histórico,
## em todos os modos: quem está na mesa e quem já saiu (até 10), com as fichas e o saldo.
## Vem do room.score que o servidor manda em cada state (como se a mão em andamento
## fosse cancelada). A partida continua por trás.

signal closed

const CloseButton := preload("res://ui/widgets/close_button.gd")
const SafeArea := preload("res://ui/theme/safe_area.gd")
const ResultScreen := preload("res://ui/screens/result_screen.gd")
const T: String = "Tokens"

const PANEL_W: float = 560.0
const TITLE_H: float = 34.0
const ROW_H: float = 32.0

var _panel: PanelContainer = null
var _inner: Control = null
var _title: Label = null
var _close: CloseButton = null
var _board: ResultScreen.Board = null
var _empty: Label = null


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
	_title.text = "Placar"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_inner.add_child(_title)
	_close = CloseButton.new()
	_close.pressed.connect(close)
	_inner.add_child(_close)
	_board = ResultScreen.Board.new()
	_inner.add_child(_board)
	_empty = Label.new()
	_empty.theme_type_variation = "DimLabel"
	_empty.text = "O placar aparece quando a partida começa."
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_inner.add_child(_empty)


func open(state: Dictionary, my_id: String) -> void:
	visible = true
	update_from(state, my_id)


func close() -> void:
	if visible:
		visible = false
		closed.emit()


## Atualiza com um state novo (só se estiver aberto).
func update_from(state: Dictionary, my_id: String) -> void:
	if not visible:
		return
	var room: Dictionary = state.get("room", {})
	var members: Array = room.get("members", [])
	_board.rows.clear()
	for row: Dictionary in room.get("score", []):
		_board.rows.append(ResultScreen.board_row(row, members, my_id))
	_empty.visible = _board.rows.is_empty()
	_board.visible = not _empty.visible
	_place()
	_board.queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and visible:
		_place()


func _place() -> void:
	var area: Rect2 = SafeArea.content(self).grow(-8.0)
	var margin: float = 8.0
	var rows: int = maxi(_board.rows.size(), 2)
	var w: float = minf(PANEL_W, area.size.x)
	var h: float = minf(TITLE_H + 12.0 + ResultScreen.Board.HEAD + rows * ROW_H + margin * 2.0,
		area.size.y)
	var inner: Vector2 = Vector2(w, h) - Vector2.ONE * margin * 2.0
	_inner.custom_minimum_size = inner
	_panel.size = Vector2(w, h)
	_panel.position = (area.position + (area.size - Vector2(w, h)) / 2.0).round()
	_title.position = Vector2.ZERO
	_title.size = Vector2(inner.x, TITLE_H)
	_close.size = Vector2(36, 36)
	_close.position = Vector2(inner.x - 38.0, -2.0)
	var top: float = TITLE_H + 10.0
	_board.position = Vector2(14, top)
	_board.size = Vector2(inner.x - 28.0, inner.y - top)
	_empty.position = Vector2(0, top)
	_empty.size = Vector2(inner.x, inner.y - top)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and not _panel.get_rect().has_point(event.position):
		close()
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(get_theme_color("shadow", T), 0.62))
