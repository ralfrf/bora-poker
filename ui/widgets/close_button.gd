extends Button
## Botão redondo de fechar (um X em vidro escuro), para painéis por cima da tela.

const T: String = "Tokens"


func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(36, 36)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)


func _draw() -> void:
	var center: Vector2 = size / 2.0
	var r: float = minf(size.x, size.y) / 2.0 - 2.0
	draw_circle(center + Vector2(0, 1.5), r, Color(0, 0, 0, 0.4), true, -1.0, true)
	var fill: Color = get_theme_color("surface_top", T)
	draw_circle(center, r, fill.darkened(0.2) if is_pressed() else fill, true, -1.0, true)
	draw_arc(center, r, 0, TAU, 40, get_theme_color("surface_line", T), 1.0, true)
	var k: float = r * 0.38
	var ink: Color = get_theme_color("text", T)
	draw_line(center + Vector2(-k, -k), center + Vector2(k, k), ink, 2.4, true)
	draw_line(center + Vector2(-k, k), center + Vector2(k, -k), ink, 2.4, true)
