extends Control
## Marcas impressas no feltro onde caem as cartas da mesa, como numa mesa de verdade:
## cinco contornos discretos, com "Flop" no meio dos três primeiros, "Turn" e "River".
## A carta, quando chega, fica por cima da marca. O controle ocupa a área das cinco
## cartas; card e gap vêm da mesa.

const T: String = "Tokens"

var card: Vector2 = Vector2(44, 62)
var gap: float = 4.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var ink: Color = get_theme_color("felt_line", T)
	var font: Font = get_theme_font("strong", T)
	var font_size: int = get_theme_font_size("small", T)
	var radius: int = int(get_theme_constant("radius_card", T) * card.x / 50.0)
	var labels: Array[String] = ["", "Flop", "", "Turn", "River"]
	for i in 5:
		var rect: Rect2 = Rect2(Vector2(i * (card.x + gap), 0), card)
		var box: StyleBoxFlat = StyleBoxFlat.new()
		box.bg_color = Color(0, 0, 0, 0.16)
		box.border_color = Color(ink, 0.16)
		box.set_border_width_all(1)
		box.set_corner_radius_all(radius)
		box.anti_aliasing = true
		draw_style_box(box, rect)
		if labels[i] != "":
			draw_string(font, Vector2(rect.position.x, rect.get_center().y + font_size * 0.36),
				labels[i], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size, Color(ink, 0.3))
