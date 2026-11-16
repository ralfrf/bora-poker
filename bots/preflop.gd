extends RefCounted
## Tabela de mãos iniciais dos bots: a força de cada uma das 169 mãos antes do flop.
##
## EQUITY é a chance de ganhar contra uma mão ao acaso, em milésimos, gerada por
## bots/tools/gen_preflop_table.gd (40.000 simulações por mão). Posição na tabela, com
## os valores de 0 (o dois) a 12 (o ás):
##   par: maior * 13 + maior | mesmo naipe: maior * 13 + menor | naipes diferentes: menor * 13 + maior

const EQUITY: Array[int] = [
	503, 320, 332, 341, 342, 344, 366, 391, 412, 446, 472, 505, 553,
	362, 537, 351, 363, 364, 367, 380, 398, 424, 454, 482, 513, 558,
	366, 392, 570, 382, 380, 386, 395, 409, 438, 465, 491, 522, 567,
	377, 398, 413, 599, 396, 404, 412, 426, 446, 468, 502, 529, 578,
	378, 393, 411, 428, 630, 421, 431, 443, 459, 476, 510, 544, 578,
	381, 403, 417, 439, 456, 661, 448, 463, 482, 496, 515, 552, 588,
	405, 408, 426, 448, 465, 481, 688, 482, 495, 513, 533, 564, 601,
	423, 433, 442, 456, 477, 492, 513, 720, 519, 534, 550, 579, 608,
	448, 460, 463, 474, 491, 511, 525, 544, 752, 558, 570, 598, 625,
	473, 482, 489, 495, 505, 523, 544, 559, 578, 775, 582, 603, 639,
	499, 510, 521, 524, 539, 544, 557, 574, 597, 603, 801, 616, 644,
	532, 540, 548, 558, 568, 576, 587, 597, 620, 623, 640, 824, 652,
	575, 581, 589, 596, 595, 609, 619, 625, 651, 656, 664, 673, 853,
]

const COMBOS: int = 1326   ## mãos iniciais possíveis, contando os naipes

static var _percentiles: Array[float] = []


## Posição da mão na tabela.
static func index(card_a: int, card_b: int) -> int:
	var high: int = maxi(card_a >> 2, card_b >> 2)
	var low: int = mini(card_a >> 2, card_b >> 2)
	if high == low or (card_a & 3) == (card_b & 3):
		return high * 13 + low
	return low * 13 + high


## Chance contra uma mão ao acaso, de 0 a 1.
static func equity(card_a: int, card_b: int) -> float:
	return EQUITY[index(card_a, card_b)] / 1000.0


## Lugar da mão entre todas as mãos iniciais, de 0 (a pior) a 1 (par de ases).
## "As 20% melhores" são as mãos com percentil de 0,80 para cima.
static func percentile(card_a: int, card_b: int) -> float:
	if _percentiles.is_empty():
		_build_percentiles()
	return _percentiles[index(card_a, card_b)]


## Quantas combinações de naipes a posição da tabela representa.
static func combos(table_index: int) -> int:
	@warning_ignore("integer_division")
	var row: int = table_index / 13
	var column: int = table_index % 13
	if row == column:
		return 6
	return 4 if row > column else 12


static func _build_percentiles() -> void:
	var order: Array[int] = []
	for i in 169:
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		if EQUITY[a] != EQUITY[b]:
			return EQUITY[a] < EQUITY[b]
		return a < b)
	var result: Array[float] = []
	result.resize(169)
	var below: int = 0
	for i in order:
		var count: int = combos(i)
		result[i] = (below + count) / float(COMBOS)
		below += count
	_percentiles = result
