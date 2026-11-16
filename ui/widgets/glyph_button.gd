extends Button
## Botão redondo de vidro claro da mesa (como "Sair" e "?") com um desenho simples:
## "react" (balão de fala com um sorriso: abrir as reações), "pause" (duas barras) e
## "play" (triângulo: retomar a mesa pausada).

const T: String = "Tokens"

var glyph: String = "react":
	set(value):
		glyph = value
		queue_redraw()


func _init(kind: String = "react") -> void:
	glyph = kind
	theme_type_variation = "QuietButton"
	focus_mode = Control.FOCUS_NONE


func _draw() -> void:
	var ink: Color = get_theme_color("text", T)
	if disabled:
		ink.a = 0.35
	var c: Vector2 = size / 2.0
	match glyph:
		"react":
			# Balão arredondado com rabinho embaixo à esquerda e um sorriso dentro.
			var box: Rect2 = Rect2(c + Vector2(-10, -9), Vector2(20, 15))
			var style: StyleBoxFlat = StyleBoxFlat.new()
			style.bg_color = Color(0, 0, 0, 0)
			style.border_color = ink
			style.set_border_width_all(2)
			style.set_corner_radius_all(6)
			style.anti_aliasing = true
			draw_style_box(style, box)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-6, 5), c + Vector2(-1, 5),
				c + Vector2(-8, 11)]), ink)
			draw_circle(c + Vector2(-4, -3.5), 1.4, ink, true, -1.0, true)
			draw_circle(c + Vector2(4, -3.5), 1.4, ink, true, -1.0, true)
			draw_arc(c + Vector2(0, -2.5), 4.5, deg_to_rad(25), deg_to_rad(155), 10, ink,
				1.6, true)
		"pause":
			draw_rect(Rect2(c + Vector2(-6, -8), Vector2(4, 16)), ink)
			draw_rect(Rect2(c + Vector2(2, -8), Vector2(4, 16)), ink)
		"play":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-5, -8), c + Vector2(8, 0),
				c + Vector2(-5, 8)]), ink)
