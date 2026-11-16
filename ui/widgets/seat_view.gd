extends Control
## Um lugar da mesa: avatar redondo encostado numa placa com apelido e fichas, relógio
## em anel em volta do avatar e marca do botão. O avatar fica do lado do centro da
## mesa (side = 1: à direita da placa; -1: à esquerda). Tamanho fixo de SIZE; as
## cartas e a aposta da rodada são peças separadas, posicionadas pela mesa.

const Paint := preload("res://ui/widgets/paint.gd")
const Money := preload("res://engine/money.gd")
const T: String = "Tokens"
const SIZE: Vector2 = Vector2(120, 44)
const AVATAR: float = 40.0
const PLATE_H: float = 36.0

## nick, stack, avatar, turn, fraction (0 a 1 do tempo que resta), folded, all_in,
## dealer, tag (texto curto da última ação), winner, away, empty.
var data: Dictionary = {}:
	set(value):
		data = value
		modulate.a = 0.45 if (data.get("folded", false) or data.get("away", false)) else 1.0
		queue_redraw()
## Lado do avatar: 1 à direita da placa, -1 à esquerda.
var side: float = 1.0:
	set(value):
		side = value
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = SIZE


## Centro do avatar, em coordenadas do lugar.
func avatar_center() -> Vector2:
	var x: float = SIZE.x - AVATAR / 2.0 if side > 0.0 else AVATAR / 2.0
	return Vector2(x, SIZE.y / 2.0)


## Pulsação do destaque de quem está na vez (0 a 1), atualizada pela mesa.
var pulse: float = 0.0:
	set(value):
		pulse = value
		if data.get("turn", false):
			queue_redraw()


func set_fraction(fraction: float) -> void:
	data["fraction"] = fraction
	queue_redraw()


func _draw() -> void:
	var center: Vector2 = avatar_center()
	var accent: Color = get_theme_color("accent", T)
	var text_color: Color = get_theme_color("text", T)
	var turn: bool = data.get("turn", false)
	var winner: bool = data.get("winner", false)

	if data.get("empty", false):
		draw_arc(center, AVATAR / 2.0, 0, TAU, 48, Color(text_color, 0.18), 1.5, true)
		return

	var ring_color: Color = accent
	if turn and float(data.get("fraction", 1.0)) < 0.25:
		ring_color = get_theme_color("danger", T)
	if turn:
		draw_circle(center, AVATAR / 2.0 + 6.0 + pulse * 3.0,
			Color(ring_color, 0.12 + pulse * 0.14), true, -1.0, true)
	elif winner:
		draw_circle(center, AVATAR / 2.0 + 7.0, Color(ring_color, 0.22), true, -1.0, true)

	# Placa: vai da ponta oposta até o meio do avatar.
	var plate_x: float = 0.0 if side > 0.0 else AVATAR / 2.0
	var plate: Rect2 = Rect2(plate_x, (SIZE.y - PLATE_H) / 2.0, SIZE.x - AVATAR / 2.0, PLATE_H)
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color(get_theme_color("surface", T), 0.94)
	box.border_color = get_theme_color("surface_line", T)
	box.set_border_width_all(1)
	box.set_corner_radius_all(get_theme_constant("radius_panel", T) - 2)
	box.anti_aliasing = true
	box.shadow_color = Color(get_theme_color("shadow", T), 0.35)
	box.shadow_size = 6
	box.shadow_offset = Vector2(0, 2)
	draw_style_box(box, plate)

	var colors: Array[Color] = []
	for i in 5:
		colors.append(get_theme_color("chip_%d" % ((i + 1) % 5), T))
	draw_circle(center, AVATAR / 2.0 + 1.5, get_theme_color("surface_line", T), true, -1.0, true)
	Paint.avatar(self, Rect2(center - Vector2.ONE * AVATAR / 2.0, Vector2.ONE * AVATAR),
		int(data.get("avatar", 0)), colors, 0, 0.0)
	if turn:
		Paint.timer_ring(self, center, AVATAR / 2.0 + 3.0, 3.0,
			float(data.get("fraction", 1.0)), ring_color, Color(text_color, 0.12))
	elif winner:
		draw_arc(center, AVATAR / 2.0 + 3.0, 0, TAU, 64, accent, 3.0, true)

	# Texto na parte da placa que o avatar não cobre.
	var text_left: float = plate.position.x + (6.0 if side > 0.0 else AVATAR / 2.0 + 4.0)
	var text_right: float = plate.end.x - (AVATAR / 2.0 + 4.0 if side > 0.0 else 6.0)
	var text_w: float = text_right - text_left
	var small: int = get_theme_font_size("small", T)
	var tag: String = "All-in" if data.get("all_in", false) else String(data.get("tag", ""))
	var first: String = tag if tag != "" else String(data.get("nick", ""))
	var font: Font = get_theme_font("strong", T)
	draw_string(font, Vector2(text_left, plate.position.y + 15.0),
		_ellipsis(font, first, small, text_w), HORIZONTAL_ALIGNMENT_CENTER, text_w, small,
		accent if tag != "" else get_theme_color("text_dim", T))
	_amount(int(data.get("stack", 0)), text_left, text_w, plate.position.y + 30.0)

	if data.get("dealer", false):
		var spot: Vector2 = center + Vector2(side * (AVATAR / 2.0 + 10.0), -12.0)
		draw_circle(spot + Vector2(0, 1), 8.0, Color(0, 0, 0, 0.3), true, -1.0, true)
		draw_circle(spot, 8.0, get_theme_color("card_face", T), true, -1.0, true)
		var display: Font = get_theme_font("display", T)
		draw_string(display, spot + Vector2(-8, small * 0.34), "B", HORIZONTAL_ALIGNMENT_CENTER,
			16, small - 2, get_theme_color("card_black", T))


func _amount(cents: int, left: float, width: float, baseline: float) -> void:
	var font: Font = get_theme_font("display", T)
	var font_size: int = get_theme_font_size("small", T)
	var text: String = Money.format(cents)
	var text_w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var icon: float = 9.0
	var x: float = left + (width - icon - 4.0 - text_w) / 2.0
	Paint.chip(self, Vector2(x + icon / 2.0, baseline - font_size * 0.36), icon / 2.0,
		get_theme_color("chip_0", T), get_theme_color("chip_mark", T),
		get_theme_constant("chip_style", T))
	draw_string(font, Vector2(x + icon + 4.0, baseline), text, HORIZONTAL_ALIGNMENT_LEFT,
		-1, font_size, get_theme_color("text", T))


func _ellipsis(font: Font, text: String, font_size: int, max_width: float) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
		return text
	var cut: String = text
	while cut.length() > 1 and font.get_string_size(cut + "…", HORIZONTAL_ALIGNMENT_LEFT,
			-1, font_size).x > max_width:
		cut = cut.left(cut.length() - 1)
	return cut + "…"
