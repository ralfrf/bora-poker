extends RefCounted
## Avaliador de mãos: a melhor combinação de 5 cartas entre as recebidas (de 2 a 7).
##
## score() devolve um inteiro comparável: mão mais forte, número maior; mãos que
## empatam, números iguais. Naipes não desempatam.
## Formato: categoria << 20 | cinco valores de desempate, 4 bits cada.

const HIGH_CARD: int = 0
const PAIR: int = 1
const TWO_PAIR: int = 2
const TRIPS: int = 3
const STRAIGHT: int = 4
const FLUSH: int = 5
const FULL_HOUSE: int = 6
const QUADS: int = 7
const STRAIGHT_FLUSH: int = 8
const ROYAL_FLUSH: int = 9

const CATEGORY_NAMES: Array[String] = [
	"Carta alta", "Par", "Dois pares", "Trinca", "Sequência", "Flush", "Full house",
	"Quadra", "Straight flush", "Royal flush"]


static func score(cards: Array) -> int:
	var rank_mask: int = 0    # bit r ligado se há carta de valor r
	var rank_counts: int = 0  # 3 bits por valor
	var suit_counts: int = 0  # 4 bits por naipe
	var suit_masks: int = 0   # 16 bits por naipe, com os valores daquele naipe
	for card in cards:
		var r: int = (card >> 2) + 2
		var s: int = card & 3
		rank_mask |= 1 << r
		rank_counts += 1 << (r * 3)
		suit_counts += 1 << (s * 4)
		suit_masks |= 1 << (s * 16 + r)

	var flush_mask: int = 0
	for s in 4:
		if ((suit_counts >> (s * 4)) & 15) >= 5:
			flush_mask = (suit_masks >> (s * 16)) & 0xFFFF
	if flush_mask != 0:
		var flush_high: int = _straight_high(flush_mask)
		if flush_high == 14:
			return (ROYAL_FLUSH << 20) | (14 << 16)
		if flush_high > 0:
			return (STRAIGHT_FLUSH << 20) | (flush_high << 16)

	var quad: int = 0
	var trip: int = 0
	var second_trip: int = 0
	var pair: int = 0
	var second_pair: int = 0
	for r in range(14, 1, -1):
		var n: int = (rank_counts >> (r * 3)) & 7
		if n == 4:
			quad = r
		elif n == 3:
			if trip == 0:
				trip = r
			elif second_trip == 0:
				second_trip = r
		elif n == 2:
			if pair == 0:
				pair = r
			elif second_pair == 0:
				second_pair = r

	if quad > 0:
		return (QUADS << 20) | (quad << 16) | (_top(rank_mask & ~(1 << quad), 1) << 12)
	if trip > 0 and (second_trip > 0 or pair > 0):
		return (FULL_HOUSE << 20) | (trip << 16) | (maxi(second_trip, pair) << 12)
	if flush_mask != 0:
		return (FLUSH << 20) | _top(flush_mask, 5)
	var straight_high: int = _straight_high(rank_mask)
	if straight_high > 0:
		return (STRAIGHT << 20) | (straight_high << 16)
	if trip > 0:
		return (TRIPS << 20) | (trip << 16) | (_top(rank_mask & ~(1 << trip), 2) << 8)
	if second_pair > 0:
		var rest: int = rank_mask & ~(1 << pair) & ~(1 << second_pair)
		return (TWO_PAIR << 20) | (pair << 16) | (second_pair << 12) | (_top(rest, 1) << 8)
	if pair > 0:
		return (PAIR << 20) | (pair << 16) | (_top(rank_mask & ~(1 << pair), 3) << 4)
	return (HIGH_CARD << 20) | _top(rank_mask, 5)


static func category(score_value: int) -> int:
	return score_value >> 20


## Nome da mão em português, como aparece na tela.
static func category_name(score_value: int) -> String:
	var index: int = score_value >> 20
	if index < 0 or index >= CATEGORY_NAMES.size():
		return ""
	return CATEGORY_NAMES[index]


## As 5 cartas que formam a melhor mão, da maior para a menor.
static func best_five(cards: Array) -> Array[int]:
	var best: Array[int] = []
	var n: int = cards.size()
	if n <= 5:
		best.assign(cards)
	else:
		var best_score: int = -1
		for a in range(0, n - 4):
			for b in range(a + 1, n - 3):
				for c in range(b + 1, n - 2):
					for d in range(c + 1, n - 1):
						for e in range(d + 1, n):
							var five: Array[int] = [
								cards[a], cards[b], cards[c], cards[d], cards[e]]
							var five_score: int = score(five)
							if five_score > best_score:
								best_score = five_score
								best = five
	best.sort()
	best.reverse()
	return best


## Tudo de uma vez, para o showdown e para a dica da mão.
static func evaluate(cards: Array) -> Dictionary:
	var score_value: int = score(cards)
	return {
		"score": score_value,
		"category": score_value >> 20,
		"name": category_name(score_value),
		"cards": best_five(cards),
	}


## Carta mais alta da sequência contida na máscara de valores; 0 se não há sequência.
## O ás também vale 1, para a sequência A-2-3-4-5 (que termina no 5).
static func _straight_high(mask: int) -> int:
	var m: int = mask | (((mask >> 14) & 1) << 1)
	for high in range(14, 4, -1):
		var need: int = 31 << (high - 4)
		if (m & need) == need:
			return high
	return 0


## Os `count` maiores valores da máscara, 4 bits cada, o maior à esquerda.
static func _top(mask: int, count: int) -> int:
	var packed: int = 0
	var taken: int = 0
	for r in range(14, 1, -1):
		if ((mask >> r) & 1) == 1:
			packed = (packed << 4) | r
			taken += 1
			if taken == count:
				return packed
	return packed << (4 * (count - taken))
