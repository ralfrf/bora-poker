extends Control
## Fundo das telas fora da mesa: o mesmo salão da mesa (degradê, luzes desfocadas e
## vinheta), com uma luz verde bem fraca lembrando o feltro.

const Paint := preload("res://ui/widgets/paint.gd")
const T: String = "Tokens"


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()


func _draw() -> void:
	var lights: Array[Color] = [get_theme_color("bokeh_0", T), get_theme_color("bokeh_1", T),
		get_theme_color("bokeh_2", T)]
	Paint.room(self, Rect2(Vector2.ZERO, size), get_theme_color("bg_top", T),
		get_theme_color("bg", T), lights)
	var glow: Vector2 = Vector2(size.x * 0.9, size.y * 1.1)
	draw_texture_rect(Paint.soft_disc(), Rect2(Vector2(size.x * 0.4, size.y * 0.6) - glow / 2.0,
		glow), false, Color(get_theme_color("felt_center", T), 0.12))
