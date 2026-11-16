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
## Brilho dourado atrás da carta (as suas cartas).
var glow: bool = false:
	set(value):
		glow = value
		queue_redraw()
## Contorno de destaque (cartas da mão vencedora).
var highlight: bool = false:
	set(value):
		highlight = value
		queue_redraw()


## Deslocamento do desenho durante a animação de chegada (a posição do controle não
## muda, então a mesa pode se reorganizar no meio do voo).
var lift: Vector2 = Vector2.ZERO:
	set(value):
		lift = value
		queue_redraw()

var _flight: Tween = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## A carta chega voando de um ponto (em coordenadas do pai) até o lugar dela.
func fly_from(origin: Vector2, delay: float, duration: float = 0.3) -> void:
	if _flight != null:
		_flight.kill()
	lift = origin - position - size / 2.0
	modulate.a = 0.0
	_flight = create_tween().set_parallel()
	_flight.tween_property(self, "lift", Vector2.ZERO, duration).set_delay(delay) 		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_flight.tween_property(self, "modulate:a", 1.0, duration * 0.4).set_delay(delay)


## Termina a animação na hora (carta escondida ou trocada).
func land() -> void:
	if _flight != null:
		_flight.kill()
		_flight = null
	lift = Vector2.ZERO
	modulate.a = 1.0


func _draw() -> void:
	draw_set_transform(lift)
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	var unit: float = size.x / 50.0
	var radius: float = get_theme_constant("radius_card", T) * unit
	if glow:
		var halo: Vector2 = size * Vector2(2.3, 1.9)
		draw_texture_rect(Paint.soft_disc(), Rect2(rect.get_center() - halo / 2.0, halo), false,
			Color(get_theme_color("accent", T), 0.30))
	if highlight:
		var halo: StyleBoxFlat = StyleBoxFlat.new()
		halo.bg_color = Color(0, 0, 0, 0)
		halo.shadow_color = Color(get_theme_color("accent", T), 0.6)
		halo.shadow_size = int(maxf(6.0 * unit, 4.0))
		halo.set_corner_radius_all(int(radius))
		draw_style_box(halo, rect)
	# Sombra em duas camadas: uma macia e larga, outra curta e mais escura.
	for layer: Array in [[0.30, 4.0, 2.5], [0.30, 1.0, 1.0]]:
		var shadow: StyleBoxFlat = StyleBoxFlat.new()
		shadow.bg_color = Color(0, 0, 0, 0)
		shadow.shadow_color = Color(get_theme_color("shadow", T), layer[0])
		shadow.shadow_size = int(maxf(layer[1] * unit, 1.0))
		shadow.shadow_offset = Vector2(0, maxf(layer[2] * unit, 1.0))
		shadow.set_corner_radius_all(int(radius))
		draw_style_box(shadow, rect)
	if card < 0:
		Paint.card_back(self, rect, get_theme_color("card_back_top", T),
			get_theme_color("card_back", T), get_theme_color("card_back_ink", T),
			get_theme_color("card_face", T), get_theme_constant("back_pattern", T), radius)
	else:
		_draw_face(rect, unit, radius)
	if dimmed:
		var veil: StyleBoxFlat = StyleBoxFlat.new()
		veil.bg_color = Color(get_theme_color("bg", T), 0.55)
		veil.set_corner_radius_all(int(radius))
		veil.anti_aliasing = true
		draw_style_box(veil, rect)
	if highlight:
		var accent: Color = get_theme_color("accent", T)
		var ring: StyleBoxFlat = StyleBoxFlat.new()
		ring.draw_center = false
		ring.border_color = accent
		ring.set_border_width_all(int(maxf(2.0 * unit, 2.0)))
		ring.set_corner_radius_all(int(radius + 2.0 * unit))
		ring.anti_aliasing = true
		draw_style_box(ring, rect.grow(maxf(1.5 * unit, 1.5)))


## Cor do naipe: copas e ouros em vermelho, paus e espadas em preto.
static func ink_of(control: Control, suit_index: int) -> Color:
	if suit_index == 1 or suit_index == 2:
		return control.get_theme_color("card_red", T)
	return control.get_theme_color("card_black", T)


func _draw_face(rect: Rect2, unit: float, radius: float) -> void:
	var face: Color = get_theme_color("card_face", T)
	Paint.gradient_rect(self, rect, radius, face, get_theme_color("card_face_low", T))
	var line: StyleBoxFlat = StyleBoxFlat.new()
	line.draw_center = false
	line.border_color = get_theme_color("card_line", T)
	line.set_border_width_all(1)
	line.set_corner_radius_all(int(radius))
	line.anti_aliasing = true
	draw_style_box(line, rect)

	var suit_index: int = Cards.suit(card)
	var rank: int = Cards.rank(card)
	var ink: Color = ink_of(self, suit_index)
	var label: String = Cards.RANK_LABELS[rank - 2]
	var font: Font = get_theme_font("display", T)
	var w: float = size.x
	var h: float = size.y
	var pad: float = w * 0.1
	if get_theme_constant("card_style", T) == 1:
		var big_size: int = _fit(font, label, int(h * 0.40), w - pad * 2.0)
		draw_string(font, Vector2(0, h * 0.08 + big_size * 0.72), label,
			HORIZONTAL_ALIGNMENT_CENTER, w, big_size, ink)
		Paint.suit(self, suit_index, Vector2(w * 0.5, h * 0.70), h * 0.36, ink)
		return

	# Índice no canto: valor e, embaixo, o naipe pequeno.
	var font_size: int = _fit(font, label, int(h * 0.34), w * 0.58)
	var cap: float = font_size * 0.72
	var text_w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1,
		font_size).x
	var index_x: float = pad * 0.8
	draw_string(font, Vector2(index_x, pad + cap), label, HORIZONTAL_ALIGNMENT_LEFT, -1,
		font_size, ink)
	if w >= 34.0:
		Paint.suit(self, suit_index, Vector2(index_x + text_w / 2.0, pad + cap + h * 0.12),
			h * 0.13, ink)

	var spot: Vector2 = Vector2(w * 0.63, h * 0.68)
	var pip: float = h * 0.40
	if rank >= 11 and rank <= 13 and w >= 34.0:
		# Figura: painel com moldura dourada, coroa e o naipe.
		var panel: Rect2 = Rect2(w * 0.36, h * 0.30, w * 0.56, h * 0.62)
		Paint.gradient_rect(self, panel, radius * 0.6, get_theme_color("court", T),
			get_theme_color("court", T).darkened(0.08))
		var frame: StyleBoxFlat = StyleBoxFlat.new()
		frame.draw_center = false
		frame.border_color = Color(get_theme_color("accent", T).darkened(0.15), 0.9)
		frame.set_border_width_all(maxi(int(unit * 1.2), 1))
		frame.set_corner_radius_all(int(radius * 0.6))
		frame.anti_aliasing = true
		draw_style_box(frame, panel)
		var center: Vector2 = panel.get_center()
		_crown(Vector2(center.x, panel.position.y + panel.size.y * 0.30), panel.size.x * 0.62,
			rank, get_theme_color("accent", T).darkened(0.1), ink)
		Paint.suit(self, suit_index, Vector2(center.x, panel.position.y + panel.size.y * 0.70),
			panel.size.y * 0.42, ink)
	elif rank == 14 and w >= 34.0:
		# Ás: o naipe grande com um aro fino em volta.
		var c: Vector2 = Vector2(w * 0.6, h * 0.64)
		draw_arc(c, h * 0.27, 0, TAU, 48, Color(ink, 0.25), maxf(unit * 1.0, 1.0), true)
		Paint.suit(self, suit_index, c, h * 0.36, ink)
	else:
		Paint.suit(self, suit_index, spot, pip, ink)


## Coroa da figura: K com cinco pontas, Q com três e pérolas, J com duas.
func _crown(center: Vector2, width: float, rank: int, gold: Color, ink: Color) -> void:
	var tips: int = {11: 2, 12: 3, 13: 5}[rank]
	var half: float = width / 2.0
	var height: float = width * 0.42
	var base_y: float = center.y + height * 0.5
	var points: PackedVector2Array = PackedVector2Array([Vector2(center.x - half, base_y)])
	for i in tips * 2 + 1:
		var x: float = center.x - half + width * i / (tips * 2.0)
		var y: float = center.y - height * 0.5 if i % 2 == 1 else center.y + height * 0.05
		if i == 0 or i == tips * 2:
			y = center.y - height * 0.2
		points.append(Vector2(x, y))
	points.append(Vector2(center.x + half, base_y))
	draw_colored_polygon(points, gold)
	var outline: PackedVector2Array = points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, gold.darkened(0.35), maxf(width * 0.05, 0.8), true)
	for i in tips:
		var x: float = center.x - half + width * (i * 2 + 1) / (tips * 2.0)
		draw_circle(Vector2(x, center.y - height * 0.5), width * 0.07,
			ink if rank == 12 else gold.lightened(0.3), true, -1.0, true)
	draw_rect(Rect2(center.x - half, base_y - height * 0.22, width, height * 0.22),
		gold.darkened(0.2))


## Maior tamanho de fonte até wanted em que o texto cabe na largura.
func _fit(font: Font, text: String, wanted: int, max_width: float) -> int:
	var font_size: int = wanted
	while font_size > 6 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size).x > max_width:
		font_size -= 1
	return font_size
