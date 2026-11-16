extends Button
## Botão do histórico das mãos na mesa: vidro claro (como "Sair" e "?") com o desenho
## de uma lista (três linhas com marcadores).

const T: String = "Tokens"


func _init() -> void:
	theme_type_variation = "QuietButton"
	focus_mode = Control.FOCUS_NONE
	tooltip_text = "Histórico das mãos"


func _draw() -> void:
	var ink: Color = get_theme_color("text", T)
	var center: Vector2 = size / 2.0
	for i in 3:
		var y: float = center.y + (i - 1) * 6.0
		draw_circle(Vector2(center.x - 8.0, y), 1.8, ink, true, -1.0, true)
		draw_line(Vector2(center.x - 4.0, y), Vector2(center.x + 9.0, y), ink, 2.0, true)
