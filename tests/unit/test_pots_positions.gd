extends "res://tests/test_case.gd"

const Pots := preload("res://engine/pots.gd")
const Positions := preload("res://engine/positions.gd")


func _entry(seat: int, total: int, folded: bool = false) -> Dictionary:
	return {"seat": seat, "total": total, "folded": folded}


func _bet(seat: int, amount: int, folded: bool = false) -> Dictionary:
	return {"seat": seat, "amount": amount, "folded": folded}


func _sum(pots: Array) -> int:
	var total: int = 0
	for pot: Dictionary in pots:
		total += int(pot["amount"])
	return total


# --- Potes ---

func test_single_pot() -> void:
	var pots: Array[Dictionary] = Pots.build([_entry(0, 100), _entry(1, 100), _entry(2, 100)])
	assert_eq(pots.size(), 1)
	assert_eq(pots[0]["amount"], 300)
	assert_eq(pots[0]["eligible"], [0, 1, 2])


func test_side_pots_by_contribution_level() -> void:
	# 0 está all-in com 100; 1 com 300; 2 pagou 300.
	var pots: Array[Dictionary] = Pots.build([_entry(0, 100), _entry(1, 300), _entry(2, 300)])
	assert_eq(pots.size(), 2)
	assert_eq(pots[0]["amount"], 300)
	assert_eq(pots[0]["eligible"], [0, 1, 2])
	assert_eq(pots[1]["amount"], 400)
	assert_eq(pots[1]["eligible"], [1, 2])


func test_three_levels() -> void:
	var pots: Array[Dictionary] = Pots.build([
		_entry(0, 50), _entry(1, 120), _entry(2, 400), _entry(3, 400)])
	assert_eq(pots.size(), 3)
	assert_eq(pots[0]["amount"], 200)
	assert_eq(pots[1]["amount"], 210)
	assert_eq(pots[1]["eligible"], [1, 2, 3])
	assert_eq(pots[2]["amount"], 560)
	assert_eq(pots[2]["eligible"], [2, 3])
	assert_eq(_sum(pots), 50 + 120 + 400 + 400)


func test_folded_chips_stay_in_the_pots() -> void:
	# 1 desistiu depois de pôr 200: suas fichas ficam nos potes, mas ele não concorre.
	var pots: Array[Dictionary] = Pots.build([
		_entry(0, 100), _entry(1, 200, true), _entry(2, 200)])
	assert_eq(pots.size(), 2)
	assert_eq(pots[0]["amount"], 300)
	assert_eq(pots[0]["eligible"], [0, 2])
	assert_eq(pots[1]["amount"], 200)
	assert_eq(pots[1]["eligible"], [2])


func _state(seat: int, total: int, all_in: bool, folded: bool = false) -> Dictionary:
	return {"seat": seat, "total": total, "folded": folded, "all_in": all_in}


func test_only_an_all_in_closes_a_pot() -> void:
	# Blinds postos e ninguém all-in: um pote só, e quem ainda não pôs nada concorre.
	var pots: Array[Dictionary] = Pots.build([
		_state(0, 0, false), _state(1, 10, false), _state(2, 20, false)])
	assert_eq(pots.size(), 1)
	assert_eq(pots[0]["amount"], 30)
	assert_eq(pots[0]["eligible"], [0, 1, 2])
	# Aumento para 100 pago por um; o terceiro ainda não agiu.
	pots = Pots.build([_state(0, 100, false), _state(1, 100, false), _state(2, 20, false)])
	assert_eq(pots.size(), 1)
	assert_eq(pots[0]["amount"], 220)
	assert_eq(pots[0]["eligible"], [0, 1, 2])


func test_all_in_in_the_middle_of_a_round() -> void:
	# 0 está all-in com 100; 1 apostou 300; 2 ainda não igualou.
	var pots: Array[Dictionary] = Pots.build([
		_state(0, 100, true), _state(1, 300, false), _state(2, 20, false)])
	assert_eq(pots.size(), 2)
	assert_eq(pots[0]["amount"], 220)
	assert_eq(pots[0]["eligible"], [0, 1, 2])
	assert_eq(pots[1]["amount"], 200)
	assert_eq(pots[1]["eligible"], [1, 2])
	# O all-in é a maior aposta: continua um pote só.
	pots = Pots.build([_state(0, 500, true), _state(1, 20, false)])
	assert_eq(pots.size(), 1)
	assert_eq(pots[0]["amount"], 520)
	assert_eq(pots[0]["eligible"], [0, 1])


func test_all_in_flags_at_showdown_match_the_plain_levels() -> void:
	var with_flags: Array[Dictionary] = Pots.build([
		_state(0, 100, true), _state(1, 300, true), _state(2, 300, false),
		_state(3, 150, false, true)])
	var plain: Array[Dictionary] = Pots.build([
		_entry(0, 100), _entry(1, 300), _entry(2, 300), _entry(3, 150, true)])
	assert_eq(with_flags, plain)
	assert_eq(_sum(with_flags), 850)


func test_no_chip_is_lost_when_a_folder_has_the_most() -> void:
	var pots: Array[Dictionary] = Pots.build([_entry(0, 100), _entry(1, 250, true)])
	assert_eq(_sum(pots), 350)
	assert_eq(pots[-1]["eligible"], [0])


func test_uncalled_bet() -> void:
	assert_eq(Pots.uncalled([_bet(0, 500), _bet(1, 200)]), {"seat": 0, "amount": 300})
	assert_eq(Pots.uncalled([_bet(0, 500), _bet(1, 500)])["amount"], 0)
	assert_eq(Pots.uncalled([_bet(0, 0), _bet(1, 0)])["amount"], 0)
	# A aposta foi coberta até onde quem desistiu tinha posto.
	assert_eq(Pots.uncalled([_bet(0, 500), _bet(1, 200, true), _bet(2, 50)]),
		{"seat": 0, "amount": 300})


func test_split_pot_evenly() -> void:
	var pots: Array[Dictionary] = Pots.distribute(
		[{"amount": 400, "eligible": [0, 1, 2]}], {0: 10, 1: 10, 2: 5}, [1, 2, 0])
	assert_eq(pots[0]["winners"], [1, 0])
	assert_eq(pots[0]["shares"], [{"seat": 1, "amount": 200}, {"seat": 0, "amount": 200}])


func test_odd_cents_go_to_first_winner_left_of_button() -> void:
	# Botão no lugar 0: a ordem à esquerda dele é 1, 2, 0.
	var pots: Array[Dictionary] = Pots.distribute(
		[{"amount": 101, "eligible": [0, 1, 2]}], {0: 10, 1: 5, 2: 10}, [1, 2, 0])
	assert_eq(pots[0]["shares"], [{"seat": 2, "amount": 51}, {"seat": 0, "amount": 50}])


func test_two_odd_cents_among_three_winners() -> void:
	var pots: Array[Dictionary] = Pots.distribute(
		[{"amount": 302, "eligible": [0, 1, 2]}], {0: 7, 1: 7, 2: 7}, [1, 2, 0])
	assert_eq(pots[0]["shares"], [
		{"seat": 1, "amount": 101}, {"seat": 2, "amount": 101}, {"seat": 0, "amount": 100}])


func test_each_pot_goes_to_the_best_eligible_hand() -> void:
	# O lugar 0 tem a melhor mão, mas só concorre ao pote principal.
	var built: Array[Dictionary] = Pots.build([_entry(0, 100), _entry(1, 300), _entry(2, 300)])
	var pots: Array[Dictionary] = Pots.distribute(built, {0: 99, 1: 50, 2: 20}, [1, 2, 0])
	assert_eq(pots[0]["winners"], [0])
	assert_eq(pots[1]["winners"], [1])
	assert_eq(pots[1]["shares"], [{"seat": 1, "amount": 400}])


# --- Posições ---

func test_next_seat_wraps_around() -> void:
	assert_eq(Positions.next_seat([0, 3, 5], 0), 3)
	assert_eq(Positions.next_seat([0, 3, 5], 5), 0)
	assert_eq(Positions.next_seat([0, 3, 5], 4), 5, "funciona com lugar que não participa")
	assert_eq(Positions.next_seat([5, 0, 3], 3), 5, "a ordem da lista não importa")


func test_order_after() -> void:
	assert_eq(Positions.order_after([0, 3, 5], 3), [5, 0, 3])
	assert_eq(Positions.order_after([5, 3, 0], 5), [0, 3, 5])


func test_button_moves_to_next_participant() -> void:
	assert_eq(Positions.next_button([0, 2, 4, 6], 2), 4)
	assert_eq(Positions.next_button([0, 2, 6], 2), 6, "pula quem não participa")
	assert_eq(Positions.next_button([0, 2, 4], 6), 0)


func test_first_button_is_drawn_from_the_seed() -> void:
	var seats: Array[int] = [1, 3, 4, 6]
	var seen: Dictionary = {}
	for seed_value in 60:
		var button: int = Positions.first_button(seats, seed_value)
		assert_true(seats.has(button))
		assert_eq(Positions.first_button(seats, seed_value), button, "mesma semente, mesmo botão")
		seen[button] = true
	assert_eq(seen.size(), 4, "todo lugar pode ser sorteado")


func test_blinds_with_three_or_more() -> void:
	assert_eq(Positions.small_blind_seat([0, 1, 2], 0), 1)
	assert_eq(Positions.big_blind_seat([0, 1, 2], 0), 2)
	assert_eq(Positions.small_blind_seat([0, 1, 2], 2), 0)
	assert_eq(Positions.big_blind_seat([0, 1, 2], 2), 1)


func test_heads_up_button_posts_small_blind() -> void:
	assert_eq(Positions.small_blind_seat([2, 6], 6), 6)
	assert_eq(Positions.big_blind_seat([2, 6], 6), 2)
	assert_eq(Positions.small_blind_seat([2, 6], 2), 2)
	assert_eq(Positions.big_blind_seat([2, 6], 2), 6)
