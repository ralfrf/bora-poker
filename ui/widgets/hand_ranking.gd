extends Control
## Ranking das mãos (SPEC 11.3): as 10 combinações em duas colunas, da mais fraca
## (Carta alta, no alto à esquerda) à mais forte (Royal flush, embaixo à direita).
## Cada linha tem um medidor de força, o nome, uma frase curta e cinco cartas de
## exemplo; as que não fazem parte da combinação ficam apagadas. Embaixo, a nota sobre
## o ás na sequência. Não mostra nada da mão do jogador.

const Evaluator := preload("res://engine/hand_evaluator.gd")
const Cards := preload("res://engine/cards.gd")
const CardView := preload("res://ui/widgets/card_view.gd")
const Paint := preload("res://ui/widgets/paint.gd")
const T: String = "Tokens"

## [categoria, frase, cartas de exemplo, quais contam (1) e quais não (0)].
const HANDS: Array = [
	[Evaluator.HIGH_CARD, "Vale a carta mais alta", "Kh 9s 7d 4c 2s", "10000"],
	[Evaluator.PAIR, "Duas cartas do mesmo valor", "Kh Kd Qs 8c 3d", "11000"],
	[Evaluator.TWO_PAIR, "Dois pares diferentes", "Qs Qc 8d 8h 3c", "11110"],
	[Evaluator.TRIPS, "Três cartas do mesmo valor", "Ah As Ad 7c 4s", "11100"],
	[Evaluator.STRAIGHT, "Cinco valores seguidos", "Ah 2s 3d 4c 5h", "11111"],
	[Evaluator.FLUSH, "Cinco cartas do mesmo naipe", "Ks Js 8s 5s 3s", "11111"],
	[Evaluator.FULL_HOUSE, "Uma trinca e um par", "Ah Ac Ad 8s 8h", "11111"],
	[Evaluator.QUADS, "Quatro cartas do mesmo valor", "7s 7h 7c 7d 5h", "11110"],
	[Evaluator.STRAIGHT_FLUSH, "Sequência do mesmo naipe", "5s 6s 7s 8s 9s", "11111"],
	[Evaluator.ROYAL_FLUSH, "Do 10 ao ás, mesmo naipe", "Th Jh Qh Kh Ah", "11111"],
]
const NOTE: String = "Na sequência, o ás pode vir antes do 2 (A-2-3-4-5) ou depois do K (10-J-Q-K-A)."
const ROWS: int = 5
const GAP: float = 8.0
const NOTE_H: float = 20.0
const CARD_GAP: float = 2.0

var _cards: Array = []   # por linha: [CardView × 5]
var _pills: Array[Rect2] = []
var _card_size: Vector2 = Vector2(24, 34)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for entry: Array in HANDS:
		var row: Array[CardView] = []
		var list: Array[int] = Cards.list_from_text(entry[2])
		var counts: String = entry[3]
		for k in 5:
			var card: CardView = CardView.new()
			card.card = list[k]
			card.dimmed = counts[k] == "0"
			card.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(card)
			row.append(card)
		_cards.append(row)
	resized.connect(_layout)


## Altura que o ranking pede para uma largura (linhas de até 56).
static func wanted_height(pill_h: float = 52.0) -> float:
	return pill_h * ROWS + GAP * (ROWS - 1) + GAP + NOTE_H


func _layout() -> void:
	_pills.clear()
	var col_w: float = (size.x - GAP * 1.5) / 2.0
	var pill_h: float = clampf((size.y - NOTE_H - GAP * ROWS) / ROWS, 34.0, 56.0)
	var card_h: float = pill_h - 12.0
	_card_size = Vector2(roundf(card_h * 0.72), roundf(card_h))
	for i in HANDS.size():
		var col: int = i / ROWS
		var row: int = i % ROWS
		var rect: Rect2 = Rect2(col * (col_w + GAP * 1.5), row * (pill_h + GAP), col_w, pill_h)
		_pills.append(rect)
		var cards_w: float = _card_size.x * 5.0 + CARD_GAP * 4.0
		var left: float = rect.end.x - 8.0 - cards_w
		var top: float = rect.position.y + (pill_h - _card_size.y) / 2.0
		for k in 5:
			var card: CardView = _cards[i][k]
			card.size = _card_size
			card.position = Vector2(left + k * (_card_size.x + CARD_GAP), top).round()
	queue_redraw()


func _draw() -> void:
	if _pills.is_empty():
		return
	var accent: Color = get_theme_color("accent", T)
	var ink: Color = get_theme_color("text", T)
	var dim: Color = get_theme_color("text_dim", T)
	var strong: Font = get_theme_font("strong", T)
	var text_font: Font = get_theme_font("text", T)
	var body: int = get_theme_font_size("body", T)
	var small: int = get_theme_font_size("small", T)
	var cards_w: float = _card_size.x * 5.0 + CARD_GAP * 4.0
	for i in HANDS.size():
		var entry: Array = HANDS[i]
		var rect: Rect2 = _pills[i]
		var best: bool = i == HANDS.size() - 1
		var box: StyleBoxFlat = StyleBoxFlat.new()
		box.bg_color = Color(accent, 0.16) if best else Color(get_theme_color("surface_top", T), 0.55)
		box.border_color = Color(accent, 0.55) if best else Color(get_theme_color("surface_line", T), 0.7)
		box.set_border_width_all(1)
		box.set_corner_radius_all(int(rect.size.y / 2.0))
		box.anti_aliasing = true
		draw_style_box(box, rect)
		# Medidor de força: dez gomos, acesos até a posição da mão.
		var d: float = rect.size.y - 18.0
		var center: Vector2 = Vector2(rect.position.x + 9.0 + d / 2.0, rect.get_center().y)
		for k in 10:
			var from: float = -PI / 2.0 + TAU * k / 10.0 + 0.09
			var to: float = -PI / 2.0 + TAU * (k + 1) / 10.0 - 0.09
			var lit: bool = k <= int(entry[0])
			draw_arc(center, d / 2.0 - 2.5, from, to, 6, accent if lit else Color(dim, 0.28),
				5.0, true)
		var left: float = center.x + d / 2.0 + 9.0
		var width: float = rect.end.x - 8.0 - cards_w - 8.0 - left
		var name: String = Evaluator.CATEGORY_NAMES[int(entry[0])]
		var name_size: int = body if width >= 120.0 else body - 1
		var desc_size: int = small - 1
		var desc_w: float = text_font.get_string_size(String(entry[1]), HORIZONTAL_ALIGNMENT_LEFT,
			-1, desc_size).x
		# Frase em duas linhas (placas estreitas): o nome sobe para caber tudo.
		var two_lines: bool = desc_w > width
		var top: float = rect.position.y + rect.size.y / 2.0 - (9.0 if two_lines else 3.0)
		if two_lines:
			name_size = body - 1
		draw_string(strong, Vector2(left, top), name, HORIZONTAL_ALIGNMENT_LEFT, width,
			name_size, ink)
		if int(entry[0]) == Evaluator.STRAIGHT:
			var w: float = strong.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x
			draw_colored_polygon(Paint._star(Vector2(left + w + 8.0, top - name_size * 0.38),
				5.0, 2.2, 5), accent)
		draw_multiline_string(text_font, Vector2(left, top + desc_size + 3.0), String(entry[1]),
			HORIZONTAL_ALIGNMENT_LEFT, width, desc_size, 2, dim)
	var note_y: float = _pills[ROWS - 1].end.y + GAP + NOTE_H * 0.7
	var note_w: float = text_font.get_string_size(NOTE, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
	var note_x: float = maxf((size.x - note_w) / 2.0, 12.0)
	draw_colored_polygon(Paint._star(Vector2(note_x - 9.0, note_y - small * 0.36), 5.0, 2.2, 5),
		accent)
	draw_string(text_font, Vector2(note_x, note_y), NOTE, HORIZONTAL_ALIGNMENT_LEFT,
		size.x - note_x, small, dim)
