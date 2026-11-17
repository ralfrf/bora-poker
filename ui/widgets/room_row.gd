extends Button
## Uma linha da lista de salas (ou de servidores): título e, embaixo, os detalhes. À
## direita, um selo curto (a % de lotação, por exemplo), o cadeado das salas com senha e
## a seta de entrar.

const FORMAT_NAMES: Dictionary = {"classic": "Clássico", "tournament": "Torneio"}

var title: String = ""
var detail: String = ""
var badge: String = ""
var locked: bool = false


func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE


func _draw() -> void:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	var alpha: float = 0.45 if disabled else (0.92 if not is_pressed() else 0.6)
	box.bg_color = Color(get_theme_color("surface", "Tokens"), alpha)
	box.border_color = get_theme_color("surface_line", "Tokens")
	box.set_border_width_all(1)
	box.set_corner_radius_all(12)
	box.anti_aliasing = true
	draw_style_box(box, Rect2(Vector2.ZERO, size))
	var body: int = get_theme_font_size("body", "Tokens")
	var small: int = get_theme_font_size("small", "Tokens")
	var strong: Font = get_theme_font("strong", "Tokens")
	var right: float = size.x - 16.0
	if not disabled:
		draw_string(strong, Vector2(size.x - 34.0, size.y / 2.0 + 7.0), "›",
			HORIZONTAL_ALIGNMENT_LEFT, -1, body + 6, get_theme_color("accent", "Tokens"))
		right = size.x - 44.0
	if locked:
		_lock(Vector2(right - 9.0, size.y / 2.0), get_theme_color("text_dim", "Tokens"))
		right -= 26.0
	if badge != "":
		var badge_w: float = strong.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, body).x
		draw_string(strong, Vector2(right - badge_w, size.y / 2.0 + body / 2.0 - 2.0), badge,
			HORIZONTAL_ALIGNMENT_LEFT, -1, body, get_theme_color("text", "Tokens"))
		right -= badge_w + 12.0
	var width: float = maxf(20.0, right - 16.0)
	var color: Color = get_theme_color("text", "Tokens")
	if disabled:
		color = get_theme_color("text_dim", "Tokens")
	draw_string(strong, Vector2(16, size.y / 2.0 - 3.0), title, HORIZONTAL_ALIGNMENT_LEFT,
		width, body, color)
	draw_string(get_theme_font("text", "Tokens"), Vector2(16, size.y / 2.0 + small + 2.0),
		detail, HORIZONTAL_ALIGNMENT_LEFT, width, small, get_theme_color("text_dim", "Tokens"))


## Cadeado desenhado: corpo arredondado e a alça em arco.
func _lock(center: Vector2, color: Color) -> void:
	var body: Rect2 = Rect2(center + Vector2(-8, -2), Vector2(16, 12))
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(3)
	box.anti_aliasing = true
	draw_style_box(box, body)
	draw_arc(center + Vector2(0, -3), 5.0, PI, TAU, 12, color, 2.2, true)
	draw_line(center + Vector2(-5, -3), center + Vector2(-5, -1), color, 2.2, true)
	draw_line(center + Vector2(5, -3), center + Vector2(5, -1), color, 2.2, true)
	draw_circle(center + Vector2(0, 3), 1.6, get_theme_color("surface", "Tokens"))
