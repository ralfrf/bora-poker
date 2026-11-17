extends "res://tests/test_case.gd"

const Cards := preload("res://engine/cards.gd")
const Deck := preload("res://engine/deck.gd")
const Hand := preload("res://engine/hand.gd")
const Positions := preload("res://engine/positions.gd")

const BOARD: String = "2c 7d 9h Jc 3s"   # não ajuda ninguém: decide o par da mão


func _start(stacks: Array, button: int, deck: Array = [], small: int = 10, big: int = 20) -> Hand:
	var seats: Array = []
	for i in stacks.size():
		seats.append({"seat": i, "stack": stacks[i]})
	var params: Dictionary = {
		"seats": seats, "button": button, "small_blind": small, "big_blind": big}
	if deck.is_empty():
		params["seed"] = 1
	else:
		params["deck"] = deck
	var hand: Hand = Hand.new()
	var response: Dictionary = hand.start(params)
	assert_true(response["ok"], "a mão começa: " + str(response["error"]))
	return hand


func _do(hand: Hand, seat: int, action: String, amount: int = 0) -> Dictionary:
	var response: Dictionary = hand.apply_action(seat, action, amount)
	assert_true(response["ok"], "lugar %d %s %d: %s" % [seat, action, amount, response["error"]])
	return response


func _refused(hand: Hand, seat: int, action: String, amount: int = 0) -> void:
	var before: String = JSON.stringify(hand.to_dict())
	var response: Dictionary = hand.apply_action(seat, action, amount)
	assert_false(response["ok"], "lugar %d %s %d devia ser recusado" % [seat, action, amount])
	assert_eq(JSON.stringify(hand.to_dict()), before, "ação recusada não muda o estado")


func _stack(hand: Hand, seat: int) -> int:
	return hand.player_at(seat).stack


func _stacks(hand: Hand) -> Array:
	var list: Array = []
	for player in hand.players:
		list.append(player.stack)
	return list


func _types(events: Array) -> Array:
	var list: Array = []
	for event: Dictionary in events:
		list.append(event["type"])
	return list


func _find(events: Array, type: String) -> Dictionary:
	for event: Dictionary in events:
		if event["type"] == type:
			return event
	return {}


## Baralho armado: holes[i] são as cartas do lugar i; depois vem a mesa.
func _rigged(button: int, holes: Array, board: String) -> Array[int]:
	var seats: Array[int] = []
	for i in holes.size():
		seats.append(i)
	var top: Array[int] = []
	for card_index in 2:
		for seat in Positions.order_after(seats, button):
			top.append(Cards.list_from_text(holes[seat])[card_index])
	top.append_array(Cards.list_from_text(board))
	return Deck.stacked(top)


func _check_down(hand: Hand) -> void:
	var guard: int = 0
	while not hand.finished and guard < 50:
		guard += 1
		var legal: Dictionary = hand.legal_actions()
		_do(hand, legal["seat"], Hand.CHECK if legal["can_check"] else Hand.CALL)


# --- Blinds, ordem e cartas ---

func test_blinds_and_first_to_act_with_three_players() -> void:
	var hand: Hand = _start([1000, 1000, 1000], 0)
	assert_eq(hand.small_blind_seat, 1)
	assert_eq(hand.big_blind_seat, 2)
	assert_eq(_stacks(hand), [1000, 990, 980])
	assert_eq(hand.current_bet, 20)
	assert_eq(hand.committed(), 30)
	assert_eq(hand.to_act, 0, "fala primeiro quem está à esquerda do big blind")
	var legal: Dictionary = hand.legal_actions()
	assert_false(legal["can_check"])
	assert_eq(legal["call"], 20)
	assert_true(legal["can_raise"])
	assert_false(legal["is_bet"], "no pré-flop já existe a aposta do big blind")
	assert_eq(legal["min_to"], 40)
	assert_eq(legal["max_to"], 1000)


func test_heads_up_button_is_small_blind_and_acts_first_preflop() -> void:
	var hand: Hand = _start([1000, 1000], 0)
	assert_eq(hand.small_blind_seat, 0)
	assert_eq(hand.big_blind_seat, 1)
	assert_eq(_stacks(hand), [990, 980])
	assert_eq(hand.to_act, 0)
	_do(hand, 0, Hand.CALL)
	assert_eq(hand.to_act, 1, "o big blind tem a opção")
	_do(hand, 1, Hand.CHECK)
	assert_eq(hand.street, Hand.FLOP)
	assert_eq(hand.board.size(), 3)
	assert_eq(hand.to_act, 1, "depois do flop o big blind fala primeiro")


func test_big_blind_option() -> void:
	var hand: Hand = _start([1000, 1000, 1000], 0)
	_do(hand, 0, Hand.CALL)
	_do(hand, 1, Hand.CALL)
	assert_eq(hand.street, Hand.PREFLOP, "a rodada não fecha antes do big blind falar")
	var legal: Dictionary = hand.legal_actions()
	assert_eq(legal["seat"], 2)
	assert_true(legal["can_check"])
	assert_true(legal["can_raise"])
	assert_eq(legal["min_to"], 40)
	_do(hand, 2, Hand.RAISE, 60)
	assert_eq(hand.to_act, 0)
	assert_eq(hand.legal_actions()["call"], 40)
	assert_true(hand.legal_actions()["can_raise"], "aumento completo reabre a aposta")


func test_first_to_act_after_flop_is_left_of_button() -> void:
	var hand: Hand = _start([1000, 1000, 1000], 0)
	_do(hand, 0, Hand.CALL)
	_do(hand, 1, Hand.CALL)
	_do(hand, 2, Hand.CHECK)
	assert_eq(hand.street, Hand.FLOP)
	assert_eq(hand.to_act, 1)
	_do(hand, 1, Hand.FOLD)
	assert_eq(hand.to_act, 2, "pula quem desistiu")


func test_deal_order_no_burn_and_showdown() -> void:
	var deck: Array[int] = _rigged(0, ["As Ah", "Ks Kh", "Qs Qh"], BOARD)
	var hand: Hand = _start([1000, 1000, 1000], 0, deck)
	assert_eq(Cards.list_to_text(hand.player_at(0).cards), "As Ah")
	assert_eq(Cards.list_to_text(hand.player_at(1).cards), "Ks Kh")
	assert_eq(Cards.list_to_text(hand.player_at(2).cards), "Qs Qh")
	_check_down(hand)
	assert_true(hand.finished)
	assert_eq(Cards.list_to_text(hand.board), BOARD, "sem queima de cartas")
	assert_eq(_stacks(hand), [1040, 980, 980])
	assert_eq(hand.committed(), 0)
	var result: Dictionary = hand.result
	assert_true(result["showdown"])
	assert_eq(result["payouts"], [{"seat": 0, "amount": 60}])
	var shown: Array = result["shown"]
	assert_eq(shown.size(), 3, "no showdown, todos que chegaram ao fim mostram (também quem perdeu)")
	var winner: Array = shown.filter(func(entry: Dictionary) -> bool: return entry["seat"] == 0)
	assert_eq(winner.size(), 1)
	assert_eq(winner[0]["name"], "Par")
	assert_eq(Cards.list_to_text(winner[0]["best"]), "As Ah Jc 9h 7d")


func test_start_events_do_not_carry_cards() -> void:
	var hand: Hand = Hand.new()
	var response: Dictionary = hand.start({
		"seats": [{"seat": 0, "stack": 500}, {"seat": 1, "stack": 500}, {"seat": 2, "stack": 500}],
		"button": 0, "small_blind": 10, "big_blind": 20, "seed": 5})
	assert_eq(_types(response["events"]), ["blind", "blind", "deal"])
	for event: Dictionary in response["events"]:
		assert_false(event.has("cards") or event.has("hands"))


# --- Aposta e aumento mínimos ---

func test_minimum_bet_and_raise_after_flop() -> void:
	var hand: Hand = _start([1000, 1000], 0)
	_do(hand, 0, Hand.CALL)
	_do(hand, 1, Hand.CHECK)
	var legal: Dictionary = hand.legal_actions()
	assert_true(legal["is_bet"])
	assert_eq(legal["min_to"], 20, "aposta mínima: um big blind")
	assert_eq(legal["max_to"], 980)
	_refused(hand, 1, Hand.BET, 19)
	_refused(hand, 1, Hand.RAISE, 40)
	_do(hand, 1, Hand.BET, 50)
	legal = hand.legal_actions()
	assert_eq(legal["call"], 50)
	assert_false(legal["is_bet"])
	assert_eq(legal["min_to"], 100, "aumento mínimo: o tamanho da última aposta")
	_refused(hand, 0, Hand.RAISE, 99)
	_refused(hand, 0, Hand.BET, 150)
	_do(hand, 0, Hand.RAISE, 150)
	legal = hand.legal_actions()
	assert_eq(legal["call"], 100)
	assert_eq(legal["min_to"], 250, "aumento mínimo: o tamanho do último aumento")
	_refused(hand, 1, Hand.RAISE, 249)
	_do(hand, 1, Hand.RAISE, 250)
	assert_eq(hand.legal_actions()["min_to"], 350)


func test_minimum_raise_before_flop() -> void:
	var hand: Hand = _start([1000, 1000, 1000], 0)
	_refused(hand, 0, Hand.RAISE, 39)
	_do(hand, 0, Hand.RAISE, 70)
	var legal: Dictionary = hand.legal_actions()
	assert_eq(legal["seat"], 1)
	assert_eq(legal["call"], 60)
	assert_eq(legal["min_to"], 120)


func test_minimum_raise_resets_each_round() -> void:
	var hand: Hand = _start([1000, 1000], 0)
	_do(hand, 0, Hand.RAISE, 200)
	_do(hand, 1, Hand.CALL)
	assert_eq(hand.street, Hand.FLOP)
	assert_eq(hand.legal_actions()["min_to"], 20)


# --- All-in incompleto ---

func test_incomplete_all_in_does_not_reopen_betting() -> void:
	# 0 aumenta para 60; 1 vai all-in com 80 (aumento de 20, menor que o mínimo de 40).
	var hand: Hand = _start([1000, 80, 1000], 0)
	_do(hand, 0, Hand.RAISE, 60)
	var legal: Dictionary = hand.legal_actions()
	assert_eq(legal["min_to"], 80, "all-in menor que o aumento mínimo é permitido")
	assert_eq(legal["max_to"], 80)
	_do(hand, 1, Hand.RAISE, 80)
	assert_eq(hand.current_bet, 80)
	assert_eq(hand.min_raise, 40, "all-in incompleto não muda o aumento mínimo")
	legal = hand.legal_actions()
	assert_eq(legal["seat"], 2)
	assert_true(legal["can_raise"], "quem ainda não agiu pode aumentar")
	assert_eq(legal["min_to"], 120)
	_do(hand, 2, Hand.CALL)
	legal = hand.legal_actions()
	assert_eq(legal["seat"], 0)
	assert_eq(legal["call"], 20)
	assert_false(legal["can_raise"], "quem já agiu só pode pagar ou desistir")
	_refused(hand, 0, Hand.RAISE, 120)
	_do(hand, 0, Hand.CALL)
	assert_eq(hand.street, Hand.FLOP)


func test_accumulated_incomplete_all_ins_reopen_betting() -> void:
	# 3 aumenta para 60; 0 all-in com 80 (+20); 1 all-in com 105 (+25): somam 45 >= 40.
	var hand: Hand = _start([80, 105, 1000, 1000], 0)
	assert_eq(hand.to_act, 3)
	_do(hand, 3, Hand.RAISE, 60)
	_do(hand, 0, Hand.RAISE, 80)
	_do(hand, 1, Hand.RAISE, 105)
	assert_eq(hand.min_raise, 40)
	var legal: Dictionary = hand.legal_actions()
	assert_eq(legal["seat"], 2)
	assert_eq(legal["min_to"], 145)
	_do(hand, 2, Hand.CALL)
	legal = hand.legal_actions()
	assert_eq(legal["seat"], 3)
	assert_eq(legal["call"], 45)
	assert_true(legal["can_raise"], "os aumentos acumulados somam um aumento completo")
	assert_eq(legal["min_to"], 145)
	_do(hand, 3, Hand.RAISE, 145)
	assert_true(hand.legal_actions()["can_raise"])


func test_caller_facing_only_an_incomplete_raise_cannot_reraise() -> void:
	# 3 abre 60; 4 all-in 80; 0 paga 80; 1 all-in 105; 2 desiste.
	# 3 enfrentou 45 de aumento desde que agiu: pode aumentar. 0 enfrentou só 25: não pode.
	var hand: Hand = _start([1000, 105, 1000, 1000, 80], 0)
	_do(hand, 3, Hand.RAISE, 60)
	_do(hand, 4, Hand.RAISE, 80)
	_do(hand, 0, Hand.CALL)
	_do(hand, 1, Hand.RAISE, 105)
	_do(hand, 2, Hand.FOLD)
	var legal: Dictionary = hand.legal_actions()
	assert_eq(legal["seat"], 3)
	assert_true(legal["can_raise"])
	_do(hand, 3, Hand.CALL)
	legal = hand.legal_actions()
	assert_eq(legal["seat"], 0)
	assert_eq(legal["call"], 25)
	assert_false(legal["can_raise"])
	_do(hand, 0, Hand.CALL)
	assert_eq(hand.street, Hand.FLOP)


func test_incomplete_all_in_bet_after_flop() -> void:
	var hand: Hand = _start([1000, 1000, 35], 0)
	_do(hand, 0, Hand.CALL)
	_do(hand, 1, Hand.CALL)
	_do(hand, 2, Hand.CHECK)
	_do(hand, 1, Hand.CHECK)
	var legal: Dictionary = hand.legal_actions()
	assert_eq(legal["seat"], 2)
	assert_eq(legal["min_to"], 15, "aposta all-in menor que o big blind")
	_do(hand, 2, Hand.BET, 15)
	legal = hand.legal_actions()
	assert_eq(legal["seat"], 0)
	assert_true(legal["can_raise"])
	assert_eq(legal["min_to"], 35)
	_do(hand, 0, Hand.CALL)
	legal = hand.legal_actions()
	assert_eq(legal["seat"], 1)
	assert_eq(legal["call"], 15)
	assert_false(legal["can_raise"], "já tinha passado e a aposta foi incompleta")


func test_raise_is_not_offered_when_nobody_can_respond() -> void:
	var hand: Hand = _start([100, 300, 500], 0)
	_do(hand, 0, Hand.RAISE, 100)
	_do(hand, 1, Hand.RAISE, 300)
	var legal: Dictionary = hand.legal_actions()
	assert_eq(legal["seat"], 2)
	assert_eq(legal["call"], 280)
	assert_false(legal["can_raise"])
	_refused(hand, 2, Hand.RAISE, 500)


# --- Fim da mão ---

func test_everyone_folds_winner_does_not_show() -> void:
	var hand: Hand = _start([1000, 1000, 1000], 0)
	_do(hand, 0, Hand.RAISE, 100)
	_do(hand, 1, Hand.FOLD)
	var response: Dictionary = _do(hand, 2, Hand.FOLD)
	assert_true(hand.finished)
	assert_eq(hand.street, Hand.FINISHED)
	assert_eq(hand.to_act, -1)
	assert_eq(_stacks(hand), [1030, 990, 980])
	assert_eq(hand.board.size(), 0)
	assert_false(hand.result["showdown"])
	assert_eq(hand.result["shown"], [])
	assert_eq(_find(response["events"], "refund"), {"type": "refund", "seat": 0, "amount": 80})
	assert_false(_types(response["events"]).has("showdown"))


func test_walk_to_the_big_blind() -> void:
	var hand: Hand = _start([1000, 1000, 1000], 0)
	_do(hand, 0, Hand.FOLD)
	_do(hand, 1, Hand.FOLD)
	assert_true(hand.finished)
	assert_eq(_stacks(hand), [1000, 990, 1010])


func test_all_in_showdown_opens_cards_and_deals_the_rest() -> void:
	var deck: Array[int] = _rigged(0, ["As Ah", "Ks Kh"], BOARD)
	var hand: Hand = _start([500, 300], 0, deck)
	_do(hand, 0, Hand.RAISE, 500)
	assert_eq(hand.legal_actions()["call"], 280)
	var response: Dictionary = _do(hand, 1, Hand.CALL)
	assert_true(hand.finished)
	assert_true(hand.revealed)
	assert_eq(_types(response["events"]), [
		"action", "refund", "reveal", "street", "street", "street", "showdown", "end"])
	assert_eq(_find(response["events"], "refund")["amount"], 200, "aposta não coberta volta")
	assert_eq(Cards.list_to_text(hand.board), BOARD)
	assert_eq(_stacks(hand), [800, 0])
	assert_eq(hand.result["shown"].size(), 2, "em showdown de all-in todos mostram")


func test_all_in_called_on_the_river_shows_everyone() -> void:
	var deck: Array[int] = _rigged(0, ["As Ah", "Ks Kh"], BOARD)
	var hand: Hand = _start([1000, 1000], 0, deck)
	_do(hand, 0, Hand.CALL)
	_do(hand, 1, Hand.CHECK)
	for i in 2:
		_do(hand, 1, Hand.CHECK)
		_do(hand, 0, Hand.CHECK)
	assert_eq(hand.street, Hand.RIVER)
	_do(hand, 1, Hand.BET, 980)
	_do(hand, 0, Hand.CALL)
	assert_true(hand.finished)
	assert_eq(_stacks(hand), [2000, 0])
	assert_eq(hand.result["shown"].size(), 2)


func test_side_pots_at_showdown() -> void:
	# 0 tem a melhor mão mas só 100 fichas; 1 ganha o pote paralelo de 2.
	var deck: Array[int] = _rigged(0, ["As Ah", "Ks Kh", "Qs Qh"], BOARD)
	var hand: Hand = _start([100, 300, 500], 0, deck)
	_do(hand, 0, Hand.RAISE, 100)
	_do(hand, 1, Hand.RAISE, 300)
	_do(hand, 2, Hand.CALL)
	assert_true(hand.finished)
	var pots: Array = hand.result["pots"]
	assert_eq(pots.size(), 2)
	assert_eq(pots[0]["amount"], 300)
	assert_eq(pots[0]["winners"], [0])
	assert_eq(pots[1]["amount"], 400)
	assert_eq(pots[1]["eligible"], [1, 2])
	assert_eq(pots[1]["winners"], [1])
	assert_eq(_stacks(hand), [300, 400, 200])


func test_split_pot_and_odd_cent() -> void:
	# A mesa tem o royal flush: os dois que ficaram empatam. O pote de 25 não divide
	# por igual, e o centavo que sobra vai para o primeiro ganhador à esquerda do botão.
	var deck: Array[int] = _rigged(0, ["2c 3d", "4c 5d", "6c 7d"], "As Ks Qs Js Ts")
	var hand: Hand = _start([1000, 1000, 1000], 0, deck, 5, 10)
	_do(hand, 0, Hand.CALL)
	_do(hand, 1, Hand.FOLD)
	_check_down(hand)
	assert_true(hand.finished)
	assert_eq(hand.result["pots"][0]["amount"], 25)
	assert_eq(hand.result["pots"][0]["shares"], [
		{"seat": 2, "amount": 13}, {"seat": 0, "amount": 12}])
	assert_eq(_stacks(hand), [1002, 995, 1003])
	assert_eq(hand.result["shown"].size(), 2, "os dois ganhadores mostram")


func test_uncalled_bet_returns_when_the_round_closes() -> void:
	var hand: Hand = _start([1000, 300], 0)
	_do(hand, 0, Hand.CALL)
	_do(hand, 1, Hand.CHECK)
	_do(hand, 1, Hand.CHECK)
	_do(hand, 0, Hand.BET, 500)
	assert_eq(hand.legal_actions()["call"], 280)
	var response: Dictionary = _do(hand, 1, Hand.CALL)
	var types: Array = _types(response["events"])
	assert_eq(_find(response["events"], "refund"), {"type": "refund", "seat": 0, "amount": 220})
	assert_true(types.find("refund") < types.find("reveal"))
	assert_true(hand.finished)
	assert_eq(_stack(hand, 0) + _stack(hand, 1), 1300)
	assert_eq(hand.result["pots"][0]["amount"], 600)


# --- Blinds incompletos ---

func test_short_big_blind_heads_up() -> void:
	# O big blind só tem 12: o outro paga só o que falta para igualar e não pode aumentar.
	var hand: Hand = _start([1000, 12], 0)
	assert_eq(_stacks(hand), [990, 0])
	var legal: Dictionary = hand.legal_actions()
	assert_eq(legal["seat"], 0)
	assert_eq(legal["call"], 2)
	assert_false(legal["can_check"])
	assert_false(legal["can_raise"])
	_do(hand, 0, Hand.CALL)
	assert_true(hand.finished)
	assert_eq(hand.result["pots"][0]["amount"], 24)
	assert_eq(_stack(hand, 0) + _stack(hand, 1), 1012)


func test_short_big_blind_multiway_keeps_full_blind_to_call() -> void:
	var hand: Hand = _start([1000, 1000, 12], 0)
	var legal: Dictionary = hand.legal_actions()
	assert_eq(legal["call"], 20, "com mais gente para agir, paga-se o big blind cheio")
	assert_eq(legal["min_to"], 40)
	_do(hand, 0, Hand.CALL)
	var response: Dictionary = _do(hand, 1, Hand.FOLD)
	assert_eq(_find(response["events"], "refund"), {"type": "refund", "seat": 0, "amount": 8})
	assert_true(hand.finished)
	assert_eq(hand.result["pots"][0]["amount"], 34)


func test_short_small_blind_ends_betting_at_once() -> void:
	var hand: Hand = _start([5, 1000], 0)
	assert_true(hand.finished, "ninguém tem o que decidir")
	assert_eq(hand.board.size(), 5)
	assert_eq(hand.result["pots"][0]["amount"], 10)
	assert_eq(_stack(hand, 0) + _stack(hand, 1), 1005)


# --- Ações inválidas e estado ---

func test_invalid_actions_are_refused() -> void:
	var hand: Hand = _start([1000, 1000, 1000], 0)
	_refused(hand, 1, Hand.FOLD)
	_refused(hand, 9, Hand.CALL)
	_refused(hand, 0, Hand.CHECK)
	_refused(hand, 0, "dance")
	_refused(hand, 0, Hand.RAISE, 39)
	_refused(hand, 0, Hand.RAISE, 1001)
	_refused(hand, 0, Hand.RAISE, -5)
	_refused(hand, 0, Hand.BET, 60)
	_do(hand, 0, Hand.CALL)
	_do(hand, 1, Hand.CALL)
	_refused(hand, 2, Hand.CALL)
	_do(hand, 2, Hand.FOLD)
	_do(hand, 1, Hand.BET, 20)
	_do(hand, 0, Hand.FOLD)
	assert_true(hand.finished)
	assert_false(hand.apply_action(1, Hand.CHECK)["ok"], "a mão já acabou")
	assert_eq(hand.legal_actions(), {})


func test_start_validation() -> void:
	var good: Dictionary = {
		"seats": [{"seat": 0, "stack": 100}, {"seat": 1, "stack": 100}],
		"button": 0, "small_blind": 10, "big_blind": 20, "seed": 1}
	var cases: Array = [
		["seats", [{"seat": 0, "stack": 100}]],
		["seats", [{"seat": 0, "stack": 100}, {"seat": 0, "stack": 100}]],
		["seats", [{"seat": 0, "stack": 100}, {"seat": 1, "stack": 0}]],
		["seats", [{"seat": 0, "stack": 100}, {"seat": 1, "stack": 1.5}]],
		["seats", "nada"],
		["button", 5],
		["small_blind", 0],
		["big_blind", 5],
		["deck", [1, 1, 2, 3, 4, 5, 6, 7, 8]],
		["deck", [1, 2, 3]],
	]
	for case: Array in cases:
		var params: Dictionary = good.duplicate(true)
		params[case[0]] = case[1]
		assert_false(Hand.new().start(params)["ok"], "%s = %s" % [case[0], str(case[1])])
	var no_seed: Dictionary = good.duplicate(true)
	no_seed.erase("seed")
	assert_false(Hand.new().start(no_seed)["ok"], "sem semente")
	var hand: Hand = Hand.new()
	assert_true(hand.start(good)["ok"])
	assert_false(hand.start(good)["ok"], "não começa duas vezes")


func test_same_seed_same_hand() -> void:
	var first: Hand = _start([1000, 1000, 1000], 1)
	var second: Hand = _start([1000, 1000, 1000], 1)
	assert_eq(JSON.stringify(first.to_dict()), JSON.stringify(second.to_dict()))


func test_save_and_restore_in_the_middle_of_a_hand() -> void:
	var hand: Hand = _start([1000, 640, 1000, 815], 0)
	_do(hand, 3, Hand.RAISE, 60)
	_do(hand, 0, Hand.CALL)
	_do(hand, 1, Hand.FOLD)
	_do(hand, 2, Hand.CALL)
	_do(hand, 2, Hand.BET, 90)
	var saved: String = JSON.stringify(hand.to_dict())
	var copy: Hand = Hand.new()
	assert_true(copy.load_dict(JSON.parse_string(saved)), copy.load_error)
	assert_eq(JSON.stringify(copy.to_dict()), saved)
	assert_eq(copy.legal_actions(), hand.legal_actions())
	# As duas seguem iguais até o fim.
	_do(hand, 3, Hand.RAISE, 300)
	_do(copy, 3, Hand.RAISE, 300)
	_check_down(hand)
	_check_down(copy)
	assert_true(copy.finished)
	assert_eq(JSON.stringify(copy.to_dict()), JSON.stringify(hand.to_dict()))
	# Uma mão terminada também se restaura, com o resultado.
	var done: Hand = Hand.new()
	assert_true(done.load_dict(JSON.parse_string(JSON.stringify(hand.to_dict()))), done.load_error)
	assert_eq(JSON.stringify(done.result), JSON.stringify(hand.result))


func test_load_refuses_broken_state() -> void:
	var good: Dictionary = _start([1000, 1000, 1000], 0).to_dict()
	assert_true(Hand.new().load_dict(good), "o estado bom carrega")
	var changes: Array = [
		["v", 99],
		["v", "1"],
		["players", "nada"],
		["players", []],
		["street", "flop"],
		["street", null],
		["street", 9],
		["street", Hand.FINISHED],          # rodada de fim com a mão em andamento
		["big_blind", 20.5],
		["small_blind", 0],
		["to_act", 7],                      # lugar que não está na mão
		["to_act", -1],                     # mão em andamento sem ninguém na vez
		["button", 5],
		["deck_pos", 52],                   # baralho sem cartas para terminar a mão
		["deck_pos", -1],
		["deck", [1, 1, 2]],
		["board", [0, 1, 2, 3, 4, 5]],
		["started", false],
		["finished", "sim"],
		["result", []],
	]
	for change: Array in changes:
		var state: Dictionary = good.duplicate(true)
		state[change[0]] = change[1]
		var hand: Hand = _start([500, 500], 0)
		var before: String = JSON.stringify(hand.to_dict())
		assert_false(hand.load_dict(state), "%s = %s" % [change[0], str(change[1])])
		assert_true(hand.load_error != "")
		assert_eq(JSON.stringify(hand.to_dict()), before, "a mão não muda quando a leitura falha")
	assert_false(Hand.new().load_dict({}))

	# Problemas dentro de um jogador.
	var player_changes: Array = [
		["stack", -5], ["stack", "muito"], ["cards", [0]], ["cards", [0, 0]],
		["seat", 1], ["folded", 1], ["total", -1],
	]
	for change: Array in player_changes:
		var state: Dictionary = good.duplicate(true)
		state["players"][0][change[0]] = change[1]
		assert_false(Hand.new().load_dict(state), "jogador: %s = %s" % [change[0], str(change[1])])
	var missing: Dictionary = good.duplicate(true)
	missing["players"][0].erase("seen_bet")
	assert_false(Hand.new().load_dict(missing))
	# Quem tem a vez não pode ter desistido.
	var folded: Dictionary = good.duplicate(true)
	folded["players"][0]["folded"] = true
	assert_false(Hand.new().load_dict(folded))


func test_cancel_returns_every_bet() -> void:
	var hand: Hand = _start([1000, 700, 400], 0)
	_do(hand, 0, Hand.RAISE, 100)
	_do(hand, 1, Hand.CALL)
	var response: Dictionary = hand.cancel()
	assert_true(response["ok"])
	assert_true(hand.finished)
	assert_true(hand.cancelled)
	assert_eq(_stacks(hand), [1000, 700, 400])
	assert_eq(hand.committed(), 0)
	assert_eq(hand.to_act, -1)
	assert_false(hand.cancel()["ok"])


func test_current_pots_during_the_hand() -> void:
	var hand: Hand = _start([100, 1000, 1000], 0)
	# Sem all-in há um pote só, e quem ainda não agiu concorre a ele.
	assert_eq(hand.current_pots(), [{"amount": 30, "eligible": [0, 1, 2]}])
	_do(hand, 0, Hand.RAISE, 100)
	_do(hand, 1, Hand.CALL)
	assert_eq(hand.current_pots(), [{"amount": 220, "eligible": [0, 1, 2]}])
	hand = _start([100, 1000, 1000], 0)
	_do(hand, 0, Hand.RAISE, 100)
	_do(hand, 1, Hand.RAISE, 300)
	_do(hand, 2, Hand.CALL)
	assert_eq(hand.street, Hand.FLOP)
	var pots: Array[Dictionary] = hand.current_pots()
	assert_eq(pots.size(), 2)
	assert_eq(pots[0]["amount"], 300)
	assert_eq(pots[0]["eligible"], [0, 1, 2])
	assert_eq(pots[1]["amount"], 400)
	assert_eq(pots[1]["eligible"], [1, 2])
	assert_eq(hand.committed(), 700)


func test_folded_players_never_show() -> void:
	var deck: Array[int] = _rigged(0, ["As Ah", "Ks Kh", "Qs Qh"], BOARD)
	var hand: Hand = _start([1000, 1000, 1000], 0, deck)
	_do(hand, 0, Hand.FOLD)   # o par de ases desiste antes do flop
	_check_down(hand)
	var seats: Array = hand.result["shown"].map(func(entry: Dictionary) -> int: return entry["seat"])
	seats.sort()
	assert_eq(seats, [1, 2], "quem chegou ao fim mostra, ganhando ou perdendo; quem desistiu, não")


func test_nobody_shows_when_everyone_else_folds() -> void:
	var hand: Hand = _start([1000, 1000, 1000], 0)
	_do(hand, 0, Hand.FOLD)
	_do(hand, 1, Hand.FOLD)
	assert_true(hand.finished)
	assert_false(hand.result["showdown"])
	assert_eq(hand.result["shown"], [], "sem showdown, ninguém mostra")
