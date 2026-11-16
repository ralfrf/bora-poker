extends Button
## Avatar redondo que se escolhe com um toque (primeira abertura e perfil).

const Paint := preload("res://ui/widgets/paint.gd")
const T: String = "Tokens"

var avatar: int = 0


func _init(index: int, diameter: float) -> void:
	avatar = index
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	flat = true
	custom_minimum_size = Vector2(diameter + 16.0, diameter + 16.0)
	toggled.connect(func(_on: bool) -> void: queue_redraw())


## As cores dos avatares (as mesmas em todo o app).
static func colors_of(ci: Control) -> Array[Color]:
	return Paint.avatar_colors(ci)


func _draw() -> void:
	var center: Vector2 = size / 2.0
	var radius: float = minf(size.x, size.y) / 2.0 - 8.0
	var accent: Color = get_theme_color("accent", T)
	if button_pressed:
		draw_circle(center, radius + 7.0, Color(accent, 0.16), true, -1.0, true)
		draw_arc(center, radius + 4.0, 0, TAU, 64, accent, 3.0, true)
	else:
		draw_circle(center, radius + 1.5, get_theme_color("surface_line", T), true, -1.0, true)
	Paint.avatar(self, Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0),
		avatar, colors_of(self), 0, 0.0)
	if not button_pressed:
		draw_circle(center, radius, Color(get_theme_color("bg", T), 0.35), true, -1.0, true)
