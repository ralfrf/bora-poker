extends Control
## Uma carta desenhada pelo jogo. card de 0 a 51 mostra a face; -1 mostra o verso.
## O tamanho da carta é o tamanho do controle; cores, raio e estilo vêm do tema.

const Paint := preload("res://ui/widgets/paint.gd")
const Cards := preload("res://engine/cards.gd")
const T: String = "Tokens"

var card: int = -1:
	set(value):
		card = value
		queue_redraw()
## Carta apagada (quem desistiu, ou carta que não entrou na mão vencedora).
var dimmed: bool = false:
	set(value):
		dimmed = value
		queue_redraw()
## Contorno de destaque (cartas da mão vencedora).
var highlight: bool = false:
	set(value):
		highlight = value
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	var unit: float = size.x / 50.0
	var radius: float = get_theme_constant("radius_card", T) * unit
	var shadow: StyleBoxFlat = StyleBoxFlat.new()
	shadow.bg_color = Color(0, 0, 0, 0)
	shadow.shadow_color = Color(get_theme_color("shadow", T), 0.28)
	shadow.shadow_size = int(maxf(3.0 * unit, 2.0))
	shadow.shadow_offset = Vector2(0, maxf(1.5 * unit, 1.0))
	shadow.set_corner_radius_all(int(radius))
	draw_style_box(shadow, rect)
	if card < 0:
		Paint.card_back(self, rect, get_theme_color("card_back", T),
			get_theme_color("card_back_ink", T), get_theme_constant("back_pattern", T), radius)
	else:
		_draw_face(rect, unit, radius)
	if dimmed:
		var veil: StyleBoxFlat = StyleBoxFlat.new()
		veil.bg_color = Color(get_theme_color("bg", T), 0.55)
		veil.set_corner_radius_all(int(radius))
		veil.anti_aliasing = true
		draw_style_box(veil, rect)
	if highlight:
		var ring: StyleBoxFlat = StyleBoxFlat.new()
		ring.draw_center = false
		ring.border_color = get_theme_color("accent", T)
		ring.set_border_width_all(int(maxf(2.0 * unit, 2.0)))
		ring.set_corner_radius_all(int(radius + 2.0 * unit))
		ring.anti_aliasing = true
		draw_style_box(ring, rect.grow(maxf(1.5 * unit, 1.5)))


func _draw_face(rect: Rect2, unit: float, radius: float) -> void:
	var face: StyleBoxFlat = StyleBoxFlat.new()
	face.bg_color = get_theme_color("card_face", T)
	face.border_color = get_theme_color("card_line", T)
	face.set_border_width_all(1 if face.border_color != face.bg_color else 0)
	face.set_corner_radius_all(int(radius))
	face.anti_aliasing = true
	draw_style_box(face, rect)

	var suit_index: int = Cards.suit(card)
	var ink: Color = get_theme_color("card_red", T) if suit_index == 1 or suit_index == 2 \
		else get_theme_color("card_black", T)
	var label: String = Cards.RANK_LABELS[Cards.rank(card) - 2]
	var font: Font = get_theme_font("display", T)
	var w: float = size.x
	var h: float = size.y
	var pad: float = w * 0.11
	if get_theme_constant("card_style", T) == 0:
		var font_size: int = _fit(font, label, int(h * 0.36), w * 0.62)
		var cap: float = font_size * 0.72
		var text_w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size).x
		draw_string(font, Vector2(pad, pad + cap), label, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, ink)
		if w >= 34.0:
			Paint.suit(self, suit_index, Vector2(pad + text_w / 2.0, pad + cap + h * 0.13),
				h * 0.15, ink)
		Paint.suit(self, suit_index, Vector2(w * 0.64, h * 0.70), h * 0.40, ink)
	else:
		var font_size: int = _fit(font, label, int(h * 0.40), w - pad * 2.0)
		var cap: float = font_size * 0.72
		draw_string(font, Vector2(0, h * 0.08 + cap), label, HORIZONTAL_ALIGNMENT_CENTER,
			w, font_size, ink)
		Paint.suit(self, suit_index, Vector2(w * 0.5, h * 0.70), h * 0.36, ink)


## Maior tamanho de fonte até wanted em que o texto cabe na largura.
func _fit(font: Font, text: String, wanted: int, max_width: float) -> int:
	var font_size: int = wanted
	while font_size > 6 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size).x > max_width:
		font_size -= 1
	return font_size
