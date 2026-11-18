extends Button
## Cartão de um nível da Loja (SPEC 12): o desenho do que vem (os avatares, a mesa
## escolhida ou os dois), o nome, até três linhas curtas e, embaixo, a pílula com o
## preço que a loja do celular informou (ou "Em breve", "Comprado", "Você já tem").
## Só se toca quando dá para comprar.

const Paint := preload("res://ui/widgets/paint.gd")
const TableFelt := preload("res://ui/widgets/table_felt.gd")
const Tables := preload("res://ui/theme/tables.gd")
const T: String = "Tokens"

const SHRINK: float = 0.3
const PICTURE_H: float = 78.0
const PILL_H: float = 30.0

var title: String = ""
var lines: Array[String] = []
## Texto da pílula de baixo; highlight: dourada (à venda) ou apagada.
var pill: String = ""
var highlight: bool = false
## Selo no canto (ex.: "Mais completo"); "" sem selo.
var badge: String = ""
## Avatares desenhados no alto; mesa: o nome da mesa ("" sem mesa).
var avatars: Array[int] = []
## Relógio no alto (a renovação do tempo sem anúncios).
var clock: bool = false
var table: String = "":
	set(value):
		table = value
		if _felt != null:
			_felt.visible = table != ""
			_felt.skin = Tables.skin(table)
		queue_redraw()

var _felt: TableFelt = null


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	flat = true
	clip_contents = true
	_felt = TableFelt.new()
	_felt.show_room = false
	_felt.scale = Vector2.ONE * SHRINK
	_felt.visible = false
	_felt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_felt)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_fit()
		queue_redraw()


func refresh() -> void:
	_fit()
	queue_redraw()


func _picture() -> Rect2:
	return Rect2(10, 24 if badge != "" else 10, size.x - 20.0, PICTURE_H)


func _fit() -> void:
	var pic: Rect2 = _picture()
	var thumb: Vector2 = Vector2(pic.size.x, pic.size.y)
	if not avatars.is_empty():
		thumb.x -= 34.0
	var inset: float = TableFelt.RAIL + 4.0
	var full: Vector2 = thumb / SHRINK
	_felt.position = pic.position
	_felt.size = full
	_felt.felt_rect = Rect2(Vector2.ONE * inset, full - Vector2.ONE * inset * 2.0)


func _draw() -> void:
	var accent: Color = get_theme_color("accent", T)
	var text_color: Color = get_theme_color("text", T)
	var dim: Color = get_theme_color("text_dim", T)
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	var radius: int = get_theme_constant("radius_panel", T)
	Paint.gradient_rect(self, rect, radius, Color(get_theme_color("surface_top", T), 0.75),
		Color(get_theme_color("surface", T), 0.88))
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.draw_center = false
	box.border_color = Color(accent, 0.7) if badge != "" else Color(get_theme_color("surface_line", T), 0.8)
	box.set_border_width_all(2 if badge != "" else 1)
	box.set_corner_radius_all(radius)
	box.anti_aliasing = true
	draw_style_box(box, rect)

	var pic: Rect2 = _picture()
	if not avatars.is_empty():
		var d: float = 40.0 if table == "" else 30.0
		var colors: Array[Color] = Paint.avatar_colors(self)
		var count: int = avatars.size()
		var step: float = d * 0.78
		var start: Vector2
		if table == "":
			start = Vector2(pic.get_center().x - (step * (count - 1) + d) / 2.0,
				pic.get_center().y - d / 2.0)
		else:
			start = Vector2(pic.end.x - d, pic.position.y + 4.0)
		for i in count:
			var at: Vector2 = start + (Vector2(step, 0) if table == "" else Vector2(0, d * 0.82)) * i
			var r: Rect2 = Rect2(at, Vector2.ONE * d)
			draw_circle(r.get_center(), d / 2.0 + 2.0, get_theme_color("surface", T), true, -1.0, true)
			Paint.avatar(self, r, avatars[i], colors, 0, 0.0)

	if clock:
		var c: Vector2 = pic.get_center()
		var r: float = pic.size.y * 0.36
		draw_circle(c, r + 3.0, Color(accent, 0.16), true, -1.0, true)
		draw_arc(c, r, 0, TAU, 48, accent, 3.0, true)
		draw_line(c, c + Vector2(0, -r * 0.62), accent, 3.0, true)
		draw_line(c, c + Vector2(r * 0.45, 0), accent, 3.0, true)
		draw_circle(c, 3.0, accent, true, -1.0, true)

	var display: Font = get_theme_font("display", T)
	var body: Font = get_theme_font("text", T)
	var strong: Font = get_theme_font("strong", T)
	var body_size: int = get_theme_font_size("body", T)
	var small: int = get_theme_font_size("small", T)
	var y: float = pic.end.y + 10.0 + body_size
	draw_string(display, Vector2(0, y), title, HORIZONTAL_ALIGNMENT_CENTER, size.x,
		_fit_size(display, title, size.x - 12.0, body_size, small), text_color)
	y += 6.0
	for line: String in lines:
		for row: String in _wrap(body, line, size.x - 16.0, small):
			y += small + 4.0
			if y > size.y - PILL_H - 12.0:
				break
			draw_string(body, Vector2(8, y), row, HORIZONTAL_ALIGNMENT_CENTER, size.x - 16.0,
				small, dim)

	var pill_rect: Rect2 = Rect2(10, size.y - PILL_H - 10.0, size.x - 20.0, PILL_H)
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = accent if highlight else Color(get_theme_color("surface_line", T), 0.7)
	fill.set_corner_radius_all(int(PILL_H / 2.0))
	fill.anti_aliasing = true
	draw_style_box(fill, pill_rect)
	var ink: Color = get_theme_color("bg", T) if highlight else Color(text_color, 0.75)
	var pill_size: int = _fit_size(strong, pill, pill_rect.size.x - 12.0, small + 1, small - 2)
	draw_string(strong, Vector2(pill_rect.position.x, pill_rect.get_center().y + pill_size * 0.36),
		pill, HORIZONTAL_ALIGNMENT_CENTER, pill_rect.size.x, pill_size, ink)

	if badge != "":
		var w: float = strong.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, small - 1).x + 14.0
		var tag: Rect2 = Rect2((size.x - w) / 2.0, 0, w, 18)
		var pill_box: StyleBoxFlat = StyleBoxFlat.new()
		pill_box.bg_color = accent
		pill_box.corner_radius_bottom_left = 8
		pill_box.corner_radius_bottom_right = 8
		pill_box.anti_aliasing = true
		draw_style_box(pill_box, tag)
		draw_string(strong, Vector2(tag.position.x, 13), badge, HORIZONTAL_ALIGNMENT_CENTER,
			w, small - 1, get_theme_color("bg", T))


## O maior tamanho de letra, entre largest e smallest, em que o texto cabe na largura.
static func _fit_size(font: Font, text: String, width: float, largest: int,
		smallest: int) -> int:
	var font_size: int = largest
	while font_size > smallest and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size).x > width:
		font_size -= 1
	return font_size


static func _wrap(font: Font, text: String, width: float, font_size: int) -> Array[String]:
	var rows: Array[String] = [""]
	for word: String in text.split(" "):
		var attempt: String = (rows[-1] + " " + word).strip_edges()
		if rows[-1] != "" and font.get_string_size(attempt, HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_size).x > width:
			rows.append(word)
		else:
			rows[-1] = attempt
	return rows
