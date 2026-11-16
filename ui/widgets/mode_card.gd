extends Button
## Cartão de um modo de jogo no início: desenho, nome e uma linha de explicação.
## Modo ainda não pronto aparece apagado, com o selo "Em breve", e não se escolhe.

const T: String = "Tokens"

const ICON_BOTS: int = 0
const ICON_WIFI: int = 1
const ICON_WORLD: int = 2

var title: String = ""
var line: String = ""
var glyph: int = 0
var soon: bool = false


func _init(card_title: String, card_line: String, card_icon: int, is_soon: bool) -> void:
	title = card_title
	line = card_line
	glyph = card_icon
	soon = is_soon
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	flat = true
	disabled = soon
	toggled.connect(func(_on: bool) -> void: queue_redraw())


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var accent: Color = get_theme_color("accent", T)
	var text_color: Color = get_theme_color("text", T)
	var dim: Color = get_theme_color("text_dim", T)
	var chosen: bool = button_pressed and not soon
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color(accent, 0.10) if chosen else Color(get_theme_color("surface", T), 0.9)
	box.border_color = accent if chosen else get_theme_color("surface_line", T)
	box.set_border_width_all(2 if chosen else 1)
	box.set_corner_radius_all(get_theme_constant("radius_panel", T))
	box.anti_aliasing = true
	draw_style_box(box, Rect2(Vector2.ZERO, size))

	var alpha: float = 0.42 if soon else 1.0
	var ink: Color = Color(accent if chosen else text_color, alpha)
	var icon_size: float = clampf(size.y * 0.13, 16.0, 30.0)
	_draw_glyph(Vector2(size.x / 2.0, size.y * 0.34), icon_size, ink)

	var display: Font = get_theme_font("display", T)
	var body: Font = get_theme_font("text", T)
	var body_size: int = get_theme_font_size("body", T)
	var small: int = get_theme_font_size("small", T)
	var title_y: float = size.y * 0.62
	draw_string(display, Vector2(0, title_y), title, HORIZONTAL_ALIGNMENT_CENTER, size.x,
		body_size, Color(text_color, alpha))
	_lines(body, line, Vector2(12, title_y + small + 8.0), size.x - 24.0, small,
		Color(dim, alpha))
	if soon:
		var badge_font: Font = get_theme_font("strong", T)
		var label: String = "Em breve"
		var w: float = badge_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1,
			small).x + 16.0
		var badge: Rect2 = Rect2(size.x - w - 10.0, 10.0, w, 20.0)
		var pill: StyleBoxFlat = StyleBoxFlat.new()
		pill.bg_color = get_theme_color("surface_line", T)
		pill.set_corner_radius_all(10)
		pill.anti_aliasing = true
		draw_style_box(pill, badge)
		draw_string(badge_font, Vector2(badge.position.x, badge.position.y + 14.0), label,
			HORIZONTAL_ALIGNMENT_CENTER, w, small, text_color)


## Texto centrado que quebra em até duas linhas.
func _lines(font: Font, text: String, origin: Vector2, width: float, font_size: int,
		color: Color) -> void:
	var rows: Array[String] = [""]
	for word: String in text.split(" "):
		var attempt: String = (rows[-1] + " " + word).strip_edges()
		if rows[-1] != "" and font.get_string_size(attempt, HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_size).x > width:
			rows.append(word)
		else:
			rows[-1] = attempt
	for i in mini(rows.size(), 2):
		draw_string(font, origin + Vector2(0, i * (font_size + 4.0)), rows[i],
			HORIZONTAL_ALIGNMENT_CENTER, width, font_size, color)


func _draw_glyph(center: Vector2, s: float, ink: Color) -> void:
	var w: float = maxf(s * 0.12, 2.0)
	match glyph:
		ICON_BOTS:
			# Rosto de robô: cabeça, antena, olhos e boca.
			var box: StyleBoxFlat = StyleBoxFlat.new()
			box.draw_center = false
			box.border_color = ink
			box.set_border_width_all(int(w))
			box.set_corner_radius_all(int(s * 0.4))
			box.anti_aliasing = true
			draw_style_box(box, Rect2(center - Vector2(s, s * 0.78), Vector2(s * 2.0, s * 1.56)))
			draw_line(center + Vector2(0, -s * 0.78), center + Vector2(0, -s * 1.1), ink, w, true)
			draw_circle(center + Vector2(0, -s * 1.2), s * 0.15, ink, true, -1.0, true)
			draw_circle(center + Vector2(-s * 0.42, -s * 0.08), s * 0.18, ink, true, -1.0, true)
			draw_circle(center + Vector2(s * 0.42, -s * 0.08), s * 0.18, ink, true, -1.0, true)
			draw_line(center + Vector2(-s * 0.34, s * 0.38), center + Vector2(s * 0.34, s * 0.38),
				ink, w, true)
		ICON_WIFI:
			var base: Vector2 = center + Vector2(0, s * 0.75)
			draw_circle(base, s * 0.17, ink, true, -1.0, true)
			for k in 3:
				draw_arc(base, s * (0.6 + k * 0.48), -PI * 0.76, -PI * 0.24, 24, ink, w * 1.1, true)
		ICON_WORLD:
			draw_arc(center, s, 0, TAU, 48, ink, w, true)
			draw_line(center + Vector2(-s, 0), center + Vector2(s, 0), ink, w * 0.8, true)
			var meridian: PackedVector2Array = PackedVector2Array()
			for k in 33:
				var a: float = TAU * k / 32.0
				meridian.append(center + Vector2(cos(a) * s * 0.42, sin(a) * s))
			draw_polyline(meridian, ink, w * 0.8, true)
			for y: float in [-0.5, 0.5]:
				var half: float = s * sqrt(1.0 - y * y)
				draw_line(center + Vector2(-half, y * s), center + Vector2(half, y * s), ink,
					w * 0.8, true)
