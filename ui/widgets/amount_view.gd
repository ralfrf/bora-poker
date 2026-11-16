extends Control
## Valor em fichas: ícone de ficha (ou pilha) e o número no formato brasileiro, nunca
## com símbolo de moeda. Serve para o pote (big), para as apostas da rodada (stack) e
## para as fichas de cada lugar.

const Paint := preload("res://ui/widgets/paint.gd")
const Money := preload("res://engine/money.gd")
const T: String = "Tokens"

var amount: int = 0:
	set(value):
		amount = value
		_refresh()
## Pote: número grande sobre uma placa de vidro, com três pilhas de fichas.
var big: bool = false:
	set(value):
		big = value
		_refresh()
## Aposta da rodada: pilha de fichas ao lado do número.
var stack: bool = false:
	set(value):
		stack = value
		_refresh()
## Texto antes do número (por exemplo "Lateral"), em tom discreto.
var caption: String = "":
	set(value):
		caption = value
		_refresh()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Centraliza o controle no ponto, já com o tamanho do conteúdo.
func place_at(point: Vector2) -> void:
	size = _content_size()
	position = (point - size / 2.0).round()


func _get_minimum_size() -> Vector2:
	return _content_size()


func _refresh() -> void:
	update_minimum_size()
	if is_inside_tree():
		var center: Vector2 = position + size / 2.0
		size = _content_size()
		position = (center - size / 2.0).round()
	queue_redraw()


func _font() -> Font:
	return get_theme_font("display", T)


func _font_size() -> int:
	return get_theme_font_size("large" if big else "small", T)


func _icon_w() -> float:
	return _font_size() * (1.45 if big else 1.05)


func _text() -> String:
	return Money.format(amount)


func _content_size() -> Vector2:
	if not is_inside_tree():
		return Vector2(10, 10)
	var font_size: int = _font_size()
	var text_w: float = _font().get_string_size(_text(), HORIZONTAL_ALIGNMENT_LEFT, -1,
		font_size).x
	var caption_w: float = 0.0
	if caption != "":
		caption_w = get_theme_font("text", T).get_string_size(caption + " ",
			HORIZONTAL_ALIGNMENT_LEFT, -1, get_theme_font_size("small", T)).x
	var gap: float = font_size * 0.35
	var pad_x: float = 12.0 if big else 6.0
	var height: float = 36.0 if big else 18.0
	return Vector2(ceilf(pad_x * 2.0 + _icon_w() + gap + caption_w + text_w), height)


## Cores das fichas de uma pilha: mais fichas e mais cores quanto maior o valor.
func _fills(count: int, first: int) -> Array[Color]:
	var fills: Array[Color] = []
	for i in count:
		fills.append(get_theme_color("chip_%d" % ((first + i) % 3), T))
	return fills


func _draw() -> void:
	var font_size: int = _font_size()
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	var corner: float = size.y / 2.0
	if big:
		var shadow: StyleBoxFlat = StyleBoxFlat.new()
		shadow.bg_color = Color(0, 0, 0, 0)
		shadow.shadow_color = Color(get_theme_color("shadow", T), 0.45)
		shadow.shadow_size = 8
		shadow.shadow_offset = Vector2(0, 3)
		shadow.set_corner_radius_all(int(corner))
		draw_style_box(shadow, rect)
		Paint.gradient_rect(self, rect, corner, Color(get_theme_color("surface_top", T), 0.85),
			Color(get_theme_color("surface", T), 0.9))
		var rim: StyleBoxFlat = StyleBoxFlat.new()
		rim.draw_center = false
		rim.set_border_width_all(1)
		rim.border_color = Color(get_theme_color("accent", T), 0.45)
		rim.set_corner_radius_all(int(corner))
		rim.anti_aliasing = true
		draw_style_box(rim, rect)
	else:
		var box: StyleBoxFlat = StyleBoxFlat.new()
		box.bg_color = Color(0, 0, 0, 0.5)
		box.set_corner_radius_all(int(corner))
		box.anti_aliasing = true
		draw_style_box(box, rect)
	var pad_x: float = 12.0 if big else 6.0
	var icon_center: Vector2 = Vector2(pad_x + _icon_w() / 2.0, size.y / 2.0)
	var mark: Color = get_theme_color("chip_mark", T)
	if big:
		# Três pilhas lado a lado, de alturas diferentes.
		var r: float = _icon_w() * 0.2
		var heights: Array[int] = [3, 5, 2]
		for k in 3:
			var x: float = icon_center.x + (k - 1) * r * 1.75
			var y: float = icon_center.y + 7.0 + (1.0 if k == 1 else 0.0)
			Paint.chip_stack(self, Vector2(x, y), r, _fills(heights[k], k), mark)
	elif stack:
		var count: int = clampi(int(log(maxf(amount, 1) / 100.0 + 1.0) / log(3.0)) + 1, 1, 4)
		Paint.chip_stack(self, icon_center + Vector2(0, 2.0 + count * 0.9),
			_icon_w() * 0.42, _fills(count, 0), mark)
	else:
		Paint.chip(self, icon_center, _icon_w() * 0.36, get_theme_color("chip_0", T), mark,
			get_theme_constant("chip_style", T))
	var x: float = pad_x + _icon_w() + font_size * 0.35
	var baseline: float = size.y / 2.0 + font_size * 0.36
	if caption != "":
		var small: int = get_theme_font_size("small", T)
		var text_font: Font = get_theme_font("text", T)
		draw_string(text_font, Vector2(x, size.y / 2.0 + small * 0.36), caption + " ",
			HORIZONTAL_ALIGNMENT_LEFT, -1, small, get_theme_color("text_dim", T))
		x += text_font.get_string_size(caption + " ", HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
	draw_string(_font(), Vector2(x, baseline + 1.0), _text(), HORIZONTAL_ALIGNMENT_LEFT, -1,
		font_size, Color(0, 0, 0, 0.5))
	draw_string(_font(), Vector2(x, baseline), _text(), HORIZONTAL_ALIGNMENT_LEFT, -1,
		font_size, get_theme_color("text", T))
