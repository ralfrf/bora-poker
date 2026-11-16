extends Control
## Uma reação (SPEC 11.2): carinha desenhada pelo jogo ou frase pronta, num balão de vidro
## escuro. Na mesa, aparece sobre o avatar de quem reagiu, cresce, fica um pouco e some
## sozinha (pop()). Também desenha os itens do painel de reações (face()).

const Protocol := preload("res://server/protocol.gd")
const T: String = "Tokens"
const FACE: float = 30.0
const LIFE: float = 2.6

## Índice em Protocol.REACTIONS.
var index: int = 0:
	set(value):
		index = value
		_fit()
		queue_redraw()
## Sem balão: só a carinha ou o texto (o painel desenha o próprio botão).
var bare: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_fit()


func is_face() -> bool:
	return index < Protocol.REACTION_FACES


## Mostra a reação centrada em point (a base do balão) e some depois de LIFE segundos.
func pop(point: Vector2) -> void:
	_fit()
	position = (point - Vector2(size.x / 2.0, size.y)).round()
	pivot_offset = Vector2(size.x / 2.0, size.y)
	scale = Vector2(0.4, 0.4)
	modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, 0.12)
	tween.chain().tween_interval(LIFE)
	tween.chain().tween_property(self, "modulate:a", 0.0, 0.3)
	tween.chain().tween_callback(queue_free)


func _fit() -> void:
	if not is_inside_tree():
		return
	if is_face():
		size = Vector2(FACE + 14.0, FACE + 14.0)
	else:
		var font: Font = get_theme_font("strong", T)
		var font_size: int = get_theme_font_size("small", T)
		var w: float = font.get_string_size(Protocol.REACTIONS[index], HORIZONTAL_ALIGNMENT_LEFT,
			-1, font_size).x
		size = Vector2(ceilf(w) + 22.0, 30.0)


func _draw() -> void:
	var box: Rect2 = Rect2(Vector2.ZERO, size)
	if not bare:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = Color(get_theme_color("surface", T), 0.94)
		style.border_color = Color(get_theme_color("accent", T), 0.8)
		style.set_border_width_all(1)
		style.set_corner_radius_all(int(minf(size.y / 2.0, 16.0)))
		style.shadow_color = Color(0, 0, 0, 0.35)
		style.shadow_size = 6
		style.anti_aliasing = true
		draw_style_box(style, box)
	if is_face():
		face(self, size / 2.0, FACE / 2.0, index)
	else:
		var font: Font = get_theme_font("strong", T)
		var font_size: int = get_theme_font_size("small", T)
		var ascent: float = font.get_ascent(font_size)
		var y: float = (size.y - font.get_height(font_size)) / 2.0 + ascent
		draw_string(font, Vector2(0, y), Protocol.REACTIONS[index], HORIZONTAL_ALIGNMENT_CENTER,
			size.x, font_size, get_theme_color("text", T))


## Desenha a carinha kind (0 a 5) centrada em c, com raio r.
static func face(ci: CanvasItem, c: Vector2, r: float, kind: int) -> void:
	var skin: Color = Color(0.98, 0.78, 0.25)
	if kind == 3:
		skin = Color(0.95, 0.45, 0.3)   # bravo: avermelhada
	var line: Color = Color(0.36, 0.2, 0.05)
	ci.draw_circle(c + Vector2(0, r * 0.08), r, Color(0, 0, 0, 0.25), true, -1.0, true)
	ci.draw_circle(c, r, skin, true, -1.0, true)
	ci.draw_circle(c + Vector2(-r * 0.25, -r * 0.3), r * 0.45, Color(1, 1, 1, 0.18), true, -1.0, true)
	ci.draw_arc(c, r, 0, TAU, 32, Color(line, 0.6), maxf(1.0, r * 0.07), true)
	var eye_y: float = -r * 0.22
	var eye_x: float = r * 0.36
	var w: float = maxf(1.5, r * 0.12)
	match kind:
		0:   # feliz
			_eyes(ci, c, eye_x, eye_y, r * 0.11, line)
			ci.draw_arc(c + Vector2(0, r * 0.02), r * 0.52, deg_to_rad(25), deg_to_rad(155), 16,
				line, w, true)
		1:   # risada: olhos fechados e boca aberta
			for side: float in [-1.0, 1.0]:
				ci.draw_arc(c + Vector2(side * eye_x, eye_y + r * 0.06), r * 0.16,
					deg_to_rad(200), deg_to_rad(340), 8, line, w, true)
			var mouth: PackedVector2Array = PackedVector2Array()
			for i in 13:
				var a: float = deg_to_rad(180.0 * i / 12.0)
				mouth.append(c + Vector2(cos(a) * r * 0.55, r * 0.1 + sin(a) * r * 0.5))
			ci.draw_colored_polygon(mouth, Color(0.45, 0.1, 0.08))
			ci.draw_circle(c + Vector2(0, r * 0.45), r * 0.17, Color(0.95, 0.4, 0.45), true, -1.0, true)
		2:   # uau: olhos redondos e boca em O
			for side: float in [-1.0, 1.0]:
				ci.draw_circle(c + Vector2(side * eye_x, eye_y), r * 0.16, Color.WHITE, true, -1.0, true)
				ci.draw_circle(c + Vector2(side * eye_x, eye_y), r * 0.09, line, true, -1.0, true)
			ci.draw_circle(c + Vector2(0, r * 0.4), r * 0.2, Color(0.45, 0.1, 0.08), true, -1.0, true)
		3:   # bravo: sobrancelhas para baixo e boca torta
			_eyes(ci, c, eye_x, eye_y + r * 0.05, r * 0.1, line)
			for side: float in [-1.0, 1.0]:
				ci.draw_line(c + Vector2(side * r * 0.6, eye_y - r * 0.25),
					c + Vector2(side * r * 0.15, eye_y - r * 0.08), line, w, true)
			ci.draw_arc(c + Vector2(0, r * 0.62), r * 0.38, deg_to_rad(205), deg_to_rad(335), 12,
				line, w, true)
		4:   # triste: boca para baixo e uma lágrima
			_eyes(ci, c, eye_x, eye_y, r * 0.1, line)
			ci.draw_arc(c + Vector2(0, r * 0.66), r * 0.4, deg_to_rad(210), deg_to_rad(330), 12,
				line, w, true)
			var tear: Vector2 = c + Vector2(eye_x + r * 0.05, eye_y + r * 0.32)
			ci.draw_colored_polygon(PackedVector2Array([tear + Vector2(0, -r * 0.2),
				tear + Vector2(r * 0.1, 0), tear + Vector2(-r * 0.1, 0)]), Color(0.35, 0.65, 1.0))
			ci.draw_circle(tear, r * 0.1, Color(0.35, 0.65, 1.0), true, -1.0, true)
		5:   # legal: óculos escuros e meio sorriso
			for side: float in [-1.0, 1.0]:
				var lens: Rect2 = Rect2(c + Vector2(side * eye_x - r * 0.27, eye_y - r * 0.15),
					Vector2(r * 0.54, r * 0.34))
				ci.draw_rect(lens, Color(0.1, 0.1, 0.14))
			ci.draw_line(c + Vector2(-eye_x, eye_y - r * 0.08), c + Vector2(eye_x, eye_y - r * 0.08),
				Color(0.1, 0.1, 0.14), w, true)
			ci.draw_arc(c + Vector2(r * 0.08, r * 0.08), r * 0.45, deg_to_rad(20), deg_to_rad(120), 12,
				line, w, true)


static func _eyes(ci: CanvasItem, c: Vector2, x: float, y: float, radius: float,
		color: Color) -> void:
	ci.draw_circle(c + Vector2(-x, y), radius, color, true, -1.0, true)
	ci.draw_circle(c + Vector2(x, y), radius, color, true, -1.0, true)
