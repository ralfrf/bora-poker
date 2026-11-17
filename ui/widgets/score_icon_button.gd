extends Button
## Botão do placar na mesa: vidro claro (como "Sair", "?" e o histórico) com o desenho de
## um pódio de três degraus.

const T: String = "Tokens"


func _init() -> void:
	theme_type_variation = "QuietButton"
	focus_mode = Control.FOCUS_NONE
	tooltip_text = "Placar"


func _draw() -> void:
	var ink: Color = get_theme_color("text", T)
	var base: float = size.y / 2.0 + 8.0
	var cx: float = size.x / 2.0
	# Degraus: o 2º à esquerda, o 1º no meio (mais alto) e o 3º à direita.
	for step: Array in [[-1, 8.0], [0, 14.0], [1, 5.0]]:
		var x: float = cx + float(step[0]) * 6.5 - 3.0
		draw_rect(Rect2(x, base - float(step[1]), 6.0, float(step[1])), ink, true)
	draw_circle(Vector2(cx, base - 18.5), 2.2, ink, true, -1.0, true)
