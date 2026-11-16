extends Control
## Marca do jogo: a ficha e o nome, lado a lado.

const Paint := preload("res://ui/widgets/paint.gd")
const T: String = "Tokens"


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _get_minimum_size() -> Vector2:
	return Vector2(160, 30)


func _draw() -> void:
	var font: Font = get_theme_font("display", T)
	var font_size: int = get_theme_font_size("large", T)
	Paint.chip(self, Vector2(13, size.y / 2.0), 12.0, get_theme_color("chip_0", T),
		get_theme_color("chip_mark", T), get_theme_constant("chip_style", T))
	draw_string(font, Vector2(34, size.y / 2.0 + font_size * 0.36), "Bora Poker",
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, get_theme_color("text", T))
