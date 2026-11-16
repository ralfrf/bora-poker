extends Control
## Fundo das telas fora da mesa: o mesmo degradê do fundo da mesa, com uma luz suave
## atrás do conteúdo.

const T: String = "Tokens"


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()


func _draw() -> void:
	var top: Color = get_theme_color("bg_top", T)
	var bottom: Color = get_theme_color("bg", T)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size,
		Vector2(0, size.y)]), PackedColorArray([top, top, bottom, bottom]))
	# Luz do feltro, bem fraca, para lembrar a mesa.
	var glow: Color = get_theme_color("felt_center", T)
	var center: Vector2 = Vector2(size.x * 0.4, size.y * 0.55)
	for i in 6:
		var r: float = size.y * (0.95 - i * 0.13)
		draw_circle(center, r, Color(glow, 0.022), true, -1.0, true)
