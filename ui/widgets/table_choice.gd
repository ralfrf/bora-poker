extends Button
## A mesa da sala, em miniatura, para o dono escolher ao criar (SPEC 11.3 e 12). Cada
## toque passa para a mesa seguinte. Embaixo, o nome; as mesas da Loja vêm com o aviso
## de que são grátis só durante o Beta.

const TableFelt := preload("res://ui/widgets/table_felt.gd")
const Tables := preload("res://ui/theme/tables.gd")
const T: String = "Tokens"
## A miniatura é a mesa de verdade desenhada grande e reduzida, para a borda e a
## estampa ficarem na proporção certa.
const SHRINK: float = 0.36
const THUMB_H: float = 64.0

signal felt_changed(id: String)

var felt: String = Tables.SALAO:
	set(value):
		felt = value if Tables.ALL.has(value) else Tables.SALAO
		if _felt != null:
			_felt.skin = Tables.skin(felt)
		queue_redraw()

## Falso: só mostra a mesa (sala de espera), sem trocar no toque e sem o aviso do Beta.
var pickable: bool = true:
	set(value):
		pickable = value
		mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE
		queue_redraw()

## Falso: sem o aviso do Beta embaixo (sala de espera, onde não cabe).
var beta_note: bool = true

var _felt: TableFelt = null


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	flat = true
	clip_text = true
	_felt = TableFelt.new()
	_felt.show_room = false
	_felt.scale = Vector2.ONE * SHRINK
	add_child(_felt)
	pressed.connect(_next)


func _ready() -> void:
	_felt.skin = Tables.skin(felt)
	resized.connect(_fit)
	_fit()


func _fit() -> void:
	var inset: float = TableFelt.RAIL + 4.0
	var full: Vector2 = Vector2(size.x, THUMB_H) / SHRINK
	_felt.size = full
	_felt.felt_rect = Rect2(Vector2.ONE * inset, full - Vector2.ONE * inset * 2.0)


func _next() -> void:
	var ids: Array = Tables.ALL.keys()
	felt = ids[(ids.find(felt) + 1) % ids.size()]
	felt_changed.emit(felt)


func _draw() -> void:
	var font: Font = get_theme_font("strong", T)
	var small: Font = get_theme_font("text", T)
	var font_size: int = get_theme_font_size("small", T)
	var y: float = THUMB_H + 16.0
	var title: String = str(Tables.skin(felt)["name"])
	draw_string(font, Vector2(0, y), ("Mesa: %s  ›" if pickable else "Mesa: %s") % title,
		HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, get_theme_color("text", T))
	if pickable and beta_note and felt != Tables.SALAO:
		draw_string(font, Vector2(0, y + 17.0), "Grátis no Beta.", HORIZONTAL_ALIGNMENT_CENTER,
			size.x, font_size, get_theme_color("accent", T))
		draw_string(small, Vector2(0, y + 33.0), "Depois, só na Loja.",
			HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, get_theme_color("text_dim", T))
