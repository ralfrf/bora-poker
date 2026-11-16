extends "res://tests/test_case.gd"

const Cards := preload("res://engine/cards.gd")
const Deck := preload("res://engine/deck.gd")


func test_card_text_round_trip() -> void:
	for card in Cards.COUNT:
		assert_eq(Cards.from_text(Cards.to_text(card)), card)


func test_rank_and_suit() -> void:
	var ace_spades: int = Cards.from_text("As")
	assert_eq(Cards.rank(ace_spades), 14)
	assert_eq(Cards.suit_name(ace_spades), "espadas")
	assert_eq(Cards.rank_name(ace_spades), "ás")
	assert_eq(Cards.label(ace_spades), "A♠")
	var two_clubs: int = Cards.from_text("2c")
	assert_eq(two_clubs, 0)
	assert_eq(Cards.rank(two_clubs), 2)
	assert_eq(Cards.suit_name(two_clubs), "paus")
	assert_eq(Cards.label(Cards.from_text("Th")), "10♥")
	assert_eq(Cards.suit_name(Cards.from_text("9d")), "ouros")
	assert_eq(Cards.make(14, 3), ace_spades)


func test_invalid_card_text() -> void:
	assert_eq(Cards.from_text("1s"), -1)
	assert_eq(Cards.from_text("Ax"), -1)
	assert_eq(Cards.from_text("A"), -1)
	assert_eq(Cards.to_text(52), "??")


func test_list_text() -> void:
	var cards: Array[int] = Cards.list_from_text("As Kd 7c")
	assert_eq(cards.size(), 3)
	assert_eq(Cards.list_to_text(cards), "As Kd 7c")


func test_shuffle_has_all_cards_once() -> void:
	var deck: Array[int] = Deck.shuffled(42)
	assert_eq(deck.size(), 52)
	assert_true(Deck.is_valid(deck))


func test_same_seed_same_order() -> void:
	assert_eq(Deck.shuffled(7), Deck.shuffled(7))
	assert_true(Deck.shuffled(7) != Deck.shuffled(8))
	assert_true(Deck.shuffled(7) != Deck.ordered())


func test_stacked_deck() -> void:
	var top: Array[int] = Cards.list_from_text("As Kd 7c")
	var deck: Array[int] = Deck.stacked(top)
	assert_eq(deck.size(), 52)
	assert_true(Deck.is_valid(deck))
	assert_eq(deck.slice(0, 3), top)


func test_deck_validation() -> void:
	assert_false(Deck.is_valid([1, 1]))
	assert_false(Deck.is_valid([52]))
	assert_false(Deck.is_valid([-1]))
	assert_false(Deck.is_valid([1.0]))
	assert_true(Deck.is_valid([0, 51]))
