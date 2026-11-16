extends "res://tests/test_case.gd"

const Cards := preload("res://engine/cards.gd")
const Deck := preload("res://engine/deck.gd")
const HandEvaluator := preload("res://engine/hand_evaluator.gd")


func _score(text: String) -> int:
	return HandEvaluator.score(Cards.list_from_text(text))


func _category(text: String) -> int:
	return HandEvaluator.category(_score(text))


func test_every_category() -> void:
	assert_eq(_category("As Ks Qs Js Ts 2d 3c"), HandEvaluator.ROYAL_FLUSH)
	assert_eq(_category("9h 8h 7h 6h 5h As Ad"), HandEvaluator.STRAIGHT_FLUSH)
	assert_eq(_category("9c 9d 9h 9s Kd 2c 3d"), HandEvaluator.QUADS)
	assert_eq(_category("Kc Kd Kh 2c 2d 7s 8s"), HandEvaluator.FULL_HOUSE)
	assert_eq(_category("Ah Jh 9h 4h 2h Kd Kc"), HandEvaluator.FLUSH)
	assert_eq(_category("9c 8d 7h 6s 5c Ad Ah"), HandEvaluator.STRAIGHT)
	assert_eq(_category("7c 7d 7h Ks 5c 2d 3h"), HandEvaluator.TRIPS)
	assert_eq(_category("7c 7d Kh Ks 5c 2d 3h"), HandEvaluator.TWO_PAIR)
	assert_eq(_category("7c 7d Kh Qs 5c 2d 3h"), HandEvaluator.PAIR)
	assert_eq(_category("7c 9d Kh Qs 5c 2d 3h"), HandEvaluator.HIGH_CARD)


func test_category_order() -> void:
	var hands: Array[String] = [
		"7c 9d Kh Qs 5c 2d 3h",
		"7c 7d Kh Qs 5c 2d 3h",
		"7c 7d Kh Ks 5c 2d 3h",
		"7c 7d 7h Ks 5c 2d 3h",
		"9c 8d 7h 6s 5c Ad Ah",
		"Ah Jh 9h 4h 2h Kd Kc",
		"Kc Kd Kh 2c 2d 7s 8s",
		"9c 9d 9h 9s Kd 2c 3d",
		"9h 8h 7h 6h 5h As Ad",
		"As Ks Qs Js Ts 2d 3c",
	]
	for i in range(1, hands.size()):
		assert_true(_score(hands[i]) > _score(hands[i - 1]), "categoria %d" % i)


func test_category_names() -> void:
	assert_eq(HandEvaluator.category_name(_score("As Ks Qs Js Ts")), "Royal flush")
	assert_eq(HandEvaluator.category_name(_score("9h 8h 7h 6h 5h")), "Straight flush")
	assert_eq(HandEvaluator.category_name(_score("9c 9d 9h 9s Kd")), "Quadra")
	assert_eq(HandEvaluator.category_name(_score("Kc Kd Kh 2c 2d")), "Full house")
	assert_eq(HandEvaluator.category_name(_score("Ah Jh 9h 4h 2h")), "Flush")
	assert_eq(HandEvaluator.category_name(_score("9c 8d 7h 6s 5c")), "Sequência")
	assert_eq(HandEvaluator.category_name(_score("7c 7d 7h Ks 5c")), "Trinca")
	assert_eq(HandEvaluator.category_name(_score("7c 7d Kh Ks 5c")), "Dois pares")
	assert_eq(HandEvaluator.category_name(_score("7c 7d Kh Qs 5c")), "Par")
	assert_eq(HandEvaluator.category_name(_score("7c 9d Kh Qs 5c")), "Carta alta")


func test_wheel_straight() -> void:
	var wheel: int = _score("Ac 2d 3h 4s 5c Kd Kh")
	assert_eq(HandEvaluator.category(wheel), HandEvaluator.STRAIGHT)
	assert_true(_score("2c 3d 4h 5s 6c Kd Kh") > wheel, "sequência até o 6 ganha da A-5")
	assert_true(_score("Ac Kd Qh Js Tc 2d 3h") > _score("Kc Qd Jh Ts 9c 2d 3h"))
	assert_eq(_category("Qc Kd Ah 2s 3c 7d 9h"), HandEvaluator.HIGH_CARD, "não dá a volta")


func test_wheel_straight_flush() -> void:
	var steel_wheel: int = _score("Ah 2h 3h 4h 5h Kd Kc")
	assert_eq(HandEvaluator.category(steel_wheel), HandEvaluator.STRAIGHT_FLUSH)
	assert_true(_score("2h 3h 4h 5h 6h Kd Kc") > steel_wheel)


func test_straight_uses_the_highest_cards() -> void:
	assert_eq(_score("4c 5d 6h 7s 8c 9d Th"), _score("6c 7d 8h 9s Tc 2d 2h"))


func test_flush_beats_straight_in_the_same_cards() -> void:
	# Sequência e flush, mas não straight flush: vale o flush.
	assert_eq(_category("9h 8h 7h 6h 5c Kh 2d"), HandEvaluator.FLUSH)


func test_flush_uses_five_highest_of_the_suit() -> void:
	assert_eq(_score("Ah Kh 9h 4h 2h 3h 7h"), _score("Ah Kh 9h 7h 4h"))
	assert_true(_score("Ah Kh 9h 7h 4h 2c 2d") > _score("Ah Kh 9h 7h 3h 2c 2d"))


func test_full_house_choices() -> void:
	# Duas trincas: a maior vira trinca, a menor vira o par.
	assert_eq(_score("Kc Kd Kh 2c 2d 2s 8s"), _score("Kc Kd Kh 2c 2d"))
	# Trinca com dois pares: usa o par mais alto.
	assert_eq(_score("Kc Kd Kh 9c 9d 2s 2c"), _score("Kc Kd Kh 9c 9d"))
	assert_true(_score("Kc Kd Kh 2c 2d") > _score("Qc Qd Qh Ac Ad"), "a trinca decide")
	assert_true(_score("Kc Kd Kh 3c 3d") > _score("Ks Kd Kh 2c 2d"), "depois o par")


func test_quads_kicker() -> void:
	assert_true(_score("9c 9d 9h 9s Ad") > _score("9c 9d 9h 9s Kd"))
	# Quadra com trinca nas 7 cartas: o desempate é a carta mais alta que sobra.
	assert_eq(_score("9c 9d 9h 9s Kd Kc Kh"), _score("9c 9d 9h 9s Kd"))


func test_two_pair_choices() -> void:
	# Três pares: os dois maiores e a melhor carta que sobra.
	assert_eq(_score("Ac Ad Kc Kd Qc Qd 2s"), _score("Ac Ad Kc Kd Qc"))
	assert_eq(_score("Ac Ad Kc Kd 2c 2d Qs"), _score("Ac Ad Kc Kd Qs"))
	assert_true(_score("Ac Ad 3c 3d 4s") > _score("Kc Kd Qc Qd As"), "o par maior decide")
	assert_true(_score("Ac Ad 4c 4d 2s") > _score("As Ah 3c 3d Ks"), "depois o segundo par")
	assert_true(_score("Ac Ad 4c 4d Ks") > _score("As Ah 4h 4s Qs"), "depois a carta alta")


func test_kickers() -> void:
	assert_true(_score("Ac Ad Kh 7s 5c") > _score("As Ah Qh Js 9c"), "par: 1ª carta")
	assert_true(_score("Ac Ad Kh 7s 5c") > _score("As Ah Kd 6s 5d"), "par: 2ª carta")
	assert_true(_score("Ac Ad Kh 7s 5c") > _score("As Ah Kd 7d 4d"), "par: 3ª carta")
	assert_true(_score("7c 7d 7h Ks 5c") > _score("7c 7d 7h Qs Jc"), "trinca")
	assert_true(_score("Ac Kd 9h 7s 5c") > _score("As Kh 9d 7d 4d"), "carta alta: 5ª carta")


func test_suits_never_break_ties() -> void:
	assert_eq(_score("Ac Kd 9h 7s 5c"), _score("As Kh 9d 7c 5d"))
	assert_eq(_score("Ac Ad Kh 7s 5c"), _score("As Ah Kd 7d 5d"))
	assert_eq(_score("Ah Jh 9h 4h 2h"), _score("As Js 9s 4s 2s"))
	assert_eq(_score("9c 8d 7h 6s 5c"), _score("9s 8s 7s 6s 5d"))


func test_board_plays() -> void:
	var board: String = "As Ks Qs Js Ts"
	assert_eq(_score(board + " 2c 3d"), _score(board + " 9h 9d"))


func test_fewer_than_five_cards() -> void:
	assert_eq(_category("Ac Ad"), HandEvaluator.PAIR)
	assert_eq(_category("Ac Kd"), HandEvaluator.HIGH_CARD)
	assert_true(_score("Ac Ad") > _score("Kc Kd"))
	assert_true(_score("Ac Kd") > _score("Ac Qd"))
	assert_eq(_category("Ac Kc Qc Jc"), HandEvaluator.HIGH_CARD, "4 cartas não fazem flush")
	assert_eq(_category("7c 7d 7h 2s 3c 9d"), HandEvaluator.TRIPS)


func test_best_five() -> void:
	var seven: Array[int] = Cards.list_from_text("2c Kd Kh 9s Kc 2d 7s")
	var five: Array[int] = HandEvaluator.best_five(seven)
	assert_eq(Cards.list_to_text(five), "Kh Kd Kc 2d 2c")
	assert_eq(HandEvaluator.score(five), HandEvaluator.score(seven))
	var info: Dictionary = HandEvaluator.evaluate(seven)
	assert_eq(info["name"], "Full house")
	assert_eq(info["category"], HandEvaluator.FULL_HOUSE)
	assert_eq(info["cards"], five)


func test_matches_reference_evaluator() -> void:
	# Compara o avaliador rápido com um avaliador ingênuo (todas as combinações de 5).
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2026
	var mismatches: int = 0
	var categories: Dictionary = {}
	for i in 1500:
		var seven: Array[int] = Deck.shuffled(rng.randi()).slice(0, 7)
		var fast: int = HandEvaluator.score(seven)
		categories[HandEvaluator.category(fast)] = true
		if fast != _reference7(seven):
			mismatches += 1
			if mismatches <= 3:
				fail("diferença em %s" % Cards.list_to_text(seven))
		if HandEvaluator.score(HandEvaluator.best_five(seven)) != fast:
			mismatches += 1
	assert_eq(mismatches, 0)
	assert_true(categories.size() >= 7, "a amostra cobre várias categorias")


func _reference7(cards: Array[int]) -> int:
	var best: int = -1
	for a in range(0, 3):
		for b in range(a + 1, 4):
			for c in range(b + 1, 5):
				for d in range(c + 1, 6):
					for e in range(d + 1, 7):
						best = maxi(best, _reference5(
							[cards[a], cards[b], cards[c], cards[d], cards[e]]))
	return best


func _reference5(cards: Array) -> int:
	var ranks: Array[int] = []
	var is_flush: bool = true
	var counts: Dictionary = {}
	for card: int in cards:
		var r: int = Cards.rank(card)
		ranks.append(r)
		counts[r] = int(counts.get(r, 0)) + 1
		if Cards.suit(card) != Cards.suit(cards[0]):
			is_flush = false
	ranks.sort()
	ranks.reverse()
	var straight_high: int = 0
	if counts.size() == 5:
		if ranks[0] - ranks[4] == 4:
			straight_high = ranks[0]
		elif ranks == [14, 5, 4, 3, 2]:
			straight_high = 5
	if straight_high > 0:
		var kind: int = HandEvaluator.STRAIGHT
		if is_flush:
			kind = HandEvaluator.ROYAL_FLUSH if straight_high == 14 else HandEvaluator.STRAIGHT_FLUSH
		return (kind << 20) | (straight_high << 16)
	# Grupos ordenados por quantidade e depois por valor.
	var groups: Array = counts.keys()
	groups.sort_custom(func(x: int, y: int) -> bool:
		return counts[x] > counts[y] or (counts[x] == counts[y] and x > y))
	var shape: Array[int] = []
	var packed: int = 0
	for i in groups.size():
		shape.append(counts[groups[i]])
		packed |= int(groups[i]) << (16 - 4 * i)
	var category: int = HandEvaluator.HIGH_CARD
	if shape == [4, 1]:
		category = HandEvaluator.QUADS
	elif shape == [3, 2]:
		category = HandEvaluator.FULL_HOUSE
	elif is_flush:
		category = HandEvaluator.FLUSH
	elif shape == [3, 1, 1]:
		category = HandEvaluator.TRIPS
	elif shape == [2, 2, 1]:
		category = HandEvaluator.TWO_PAIR
	elif shape == [2, 1, 1, 1]:
		category = HandEvaluator.PAIR
	return (category << 20) | packed
