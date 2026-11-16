extends Control
## O ranking das mãos por cima da mesa, com o fundo escurecido (aberto pelo botão "?"
## da mesa). A partida continua andando por trás. Fecha no X, tocando fora ou no
## botão "voltar" do Android.

signal closed

const HandRanking := preload("res://ui/widgets/hand_ranking.gd")
const CloseButton := preload("res://ui/widgets/close_button.gd")
const SafeArea := preload("res://ui/theme/safe_area.gd")
const T: String = "Tokens"

const PANEL_W: float = 760.0
const PAD: float = 16.0
const TITLE_H: float = 34.0

var _panel: PanelContainer = null
var _inner: Control = null
var _title: Label = null
var _close: CloseButton = null
var _ranking: HandRanking = null


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
	_title.text = "Ranking das mãos"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_inner.add_child(_title)
	_ranking = HandRanking.new()
	_inner.add_child(_ranking)
	_close = CloseButton.new()
	_close.pressed.connect(close)
	_inner.add_child(_close)


func open() -> void:
	visible = true
	_place()


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and visible:
		_place()


func _place() -> void:
	var area: Rect2 = SafeArea.content(self).grow(-8.0)
	var margin: float = 8.0   # margem do SheetPanel
	var w: float = minf(PANEL_W, area.size.x)
	var h: float = minf(TITLE_H + HandRanking.wanted_height(52.0) + PAD, area.size.y)
	var inner: Vector2 = Vector2(w, h) - Vector2.ONE * margin * 2.0
	_inner.custom_minimum_size = inner
	_panel.size = Vector2(w, h)
	_panel.position = (area.position + (area.size - Vector2(w, h)) / 2.0).round()
	_title.position = Vector2(0, 0)
	_title.size = Vector2(inner.x, TITLE_H)
	_close.size = Vector2(36, 36)
	_close.position = Vector2(inner.x - 38.0, -2.0)
	_ranking.position = Vector2(PAD / 2.0, TITLE_H + 2.0)
	_ranking.size = Vector2(inner.x - PAD, inner.y - TITLE_H - 2.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and not _panel.get_rect().has_point(event.position):
		close()
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(get_theme_color("shadow", T), 0.62))
