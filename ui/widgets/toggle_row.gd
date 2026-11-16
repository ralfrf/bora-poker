extends Button
## Uma configuração que liga e desliga: placa de vidro com título, uma frase curta e
## a chave à direita. Tocar em qualquer parte da placa troca o valor.

const T: String = "Tokens"
const ROW_H: float = 56.0

var title: String = ""
var detail: String = ""


func _init(row_title: String, row_detail: String, on: bool) -> void:
	title = row_title
	detail = row_detail
	toggle_mode = true
	flat = true
	focus_mode = Control.FOCUS_NONE
	button_pressed = on
	custom_minimum_size = Vector2(0, ROW_H)
	toggled.connect(func(_value: bool) -> void: queue_redraw())


func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	var accent: Color = get_theme_color("accent", T)
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color(get_theme_color("surface_top", T), 0.55)
	box.border_color = Color(get_theme_color("surface_line", T), 0.8)
	box.set_border_width_all(1)
	box.set_corner_radius_all(get_theme_constant("radius_panel", T))
	box.anti_aliasing = true
	draw_style_box(box, rect)
	var strong: Font = get_theme_font("strong", T)
	var text_font: Font = get_theme_font("text", T)
	var body: int = get_theme_font_size("body", T)
	var small: int = get_theme_font_size("small", T)
	var track: Vector2 = Vector2(48, 28)
	var text_w: float = size.x - 16.0 - track.x - 28.0
	draw_string(strong, Vector2(16, size.y / 2.0 - 3.0), title, HORIZONTAL_ALIGNMENT_LEFT,
		text_w, body, get_theme_color("text", T))
	draw_string(text_font, Vector2(16, size.y / 2.0 + small + 2.0), detail,
		HORIZONTAL_ALIGNMENT_LEFT, text_w, small, get_theme_color("text_dim", T))
	# Chave: trilho em ouro quando ligada, bolinha clara que corre para a direita.
	var on: bool = button_pressed
	var track_rect: Rect2 = Rect2(Vector2(size.x - 16.0 - track.x, (size.y - track.y) / 2.0),
		track)
	var rail: StyleBoxFlat = StyleBoxFlat.new()
	rail.bg_color = accent if on else Color(get_theme_color("bg", T), 0.8)
	rail.border_color = get_theme_color("accent_line", T) if on else get_theme_color("surface_line", T)
	rail.set_border_width_all(1)
	rail.set_corner_radius_all(int(track.y / 2.0))
	rail.anti_aliasing = true
	draw_style_box(rail, track_rect)
	var knob_r: float = track.y / 2.0 - 3.5
	var knob: Vector2 = Vector2(track_rect.end.x - track.y / 2.0 if on
		else track_rect.position.x + track.y / 2.0, track_rect.get_center().y)
	draw_circle(knob + Vector2(0, 1.5), knob_r, Color(0, 0, 0, 0.35), true, -1.0, true)
	draw_circle(knob, knob_r, Color.WHITE if on else get_theme_color("text_dim", T), true, -1.0,
		true)
