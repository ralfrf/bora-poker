extends "res://tests/test_case.gd"
## Valores do pote na tela: o pote do centro não conta duas vezes as apostas que ainda
## estão na frente dos lugares, e o aviso do fim da mão diz quanto cada um levou.

const Cards := preload("res://engine/cards.gd")
const Deck := preload("res://engine/deck.gd")
const Hand := preload("res://engine/hand.gd")
const Positions := preload("res://engine/positions.gd")
const Table := preload("res://engine/table.gd")
const View := preload("res://server/view.gd")
const HandLog := preload("res://server/hand_log.gd")
const PotMath := preload("res://ui/table/pot_math.gd")

const BOARD: String = "2c 7d 9h Jc 3s"


func _rigged(seats: Array[int], button: int, holes: Array, board: String) -> Array[int]:
	var top: Array[int] = []
	for card_index in 2:
		for seat in Positions.order_after(seats, button):
			top.append(Cards.list_from_text(holes[seat])[card_index])
	top.append_array(Cards.list_from_text(board))
	return Deck.stacked(top)


func _table(players: int) -> Table:
	var table: Table = Table.new()
	assert_eq(table.configure({"format": Table.CLASSIC}), "")
	for i in players:
		assert_eq(table.add_player(i, "j%d" % i), "")
	return table


func _view(table: Table) -> Dictionary:
	var ids: Dictionary = {}
	for seat in table.hand.players:
		ids[seat.seat] = table.seat_at(seat.seat).id
	return View.public(table, ids)


func _bets(view: Dictionary) -> int:
	var sum: int = 0
	for entry: Dictionary in view["seats"]:
		sum += int(entry["bet"])
	return sum


func _act(table: Table, seat: int, action: String, amount: int = 0) -> Array:
	var response: Dictionary = table.apply_action(seat, action, amount)
	assert_true(response["ok"], "lugar %d %s: %s" % [seat, action, response["error"]])
	return response["events"]


func test_everyone_folds_after_a_raise() -> void:
	# Blinds 10/20; o botão aumenta para 60 e os dois blinds desistem. Na mesa ficaram
	# 10 + 20 + 60 = 90 e ele leva tudo: o motor paga 50 e devolve os 40 que ninguém
	# pagou, mas a tela diz 90, o mesmo do "Pote" e do que entra nas fichas dele.
	var table: Table = _table(3)
	assert_true(table.start_hand({"seed": 1, "button": 0})["ok"])
	var view: Dictionary = _view(table)
	assert_eq(PotMath.center(view), 0, "antes do flop nada foi recolhido: o centro fica vazio")
	assert_eq(PotMath.center(view) + _bets(view), 30, "os blinds aparecem só na frente dos lugares")

	_act(table, 0, Hand.RAISE, 60)
	view = _view(table)
	assert_eq(PotMath.center(view), 0, "o aumento também fica na frente do lugar")
	assert_eq(PotMath.center(view) + _bets(view), 90)
	assert_eq(PotMath.total(view), 90, "\"Pote\" com as apostas da rodada")

	_act(table, 1, Hand.FOLD)
	var events: Array = _act(table, 2, Hand.FOLD)
	view = _view(table)
	var refunds: Dictionary = PotMath.refunds(events)
	assert_eq(refunds, {0: 40}, "a parte não paga do aumento volta para quem aumentou")
	assert_eq(view["result"]["returned"], [{"seat": 0, "amount": 40}], "o resultado guarda a devolução")
	assert_eq(PotMath.center(view), 90, "no fim, o centro mostra tudo o que ele leva")
	assert_eq(PotMath.center_pots(view), [90] as Array[int])
	var groups: Array = PotMath.groups(view["result"]["payouts"], view["result"]["pots"],
		view["result"]["returned"])
	assert_eq(groups, [{"seats": [0], "amount": 90}], "o aviso diz que ele levou 90, como o \"Pote\"")
	assert_eq(table.seat_at(0).stack, 2030, "e as fichas dele batem: 2000 - 60 + 90")


func test_big_blind_walk() -> void:
	# Todos desistem até o big blind: na mesa, 10 + 20 = 30; ele leva os 30.
	var table: Table = _table(3)
	assert_true(table.start_hand({"seed": 2, "button": 0})["ok"])
	_act(table, 0, Hand.FOLD)
	assert_eq(PotMath.total(_view(table)), 30)
	_act(table, 1, Hand.FOLD)
	var view: Dictionary = _view(table)
	var groups: Array = PotMath.groups(view["result"]["payouts"], view["result"]["pots"],
		view["result"]["returned"])
	assert_eq(groups, [{"seats": [2], "amount": 30}], "o big blind leva os 30 do pote")
	assert_eq(table.seat_at(2).stack, 2010, "2000 - 20 + 30")


func test_caller_wins_when_blinds_fold() -> void:
	# Blinds 0,10 e 0,20; alguém paga 0,20 e os dois blinds desistem: ele leva 0,50.
	var table: Table = _table(3)
	assert_true(table.start_hand({"seed": 4, "button": 0})["ok"])
	_act(table, 0, Hand.CALL)
	assert_eq(PotMath.total(_view(table)), 50)
	_act(table, 1, Hand.FOLD)
	_act(table, 2, Hand.FOLD)
	var view: Dictionary = _view(table)
	var groups: Array = PotMath.groups(view["result"]["payouts"], view["result"]["pots"],
		view["result"]["returned"])
	assert_eq(groups, [{"seats": [0], "amount": 50}], "quem pagou leva os 0,50")
	assert_eq(table.seat_at(0).stack, 2030, "2000 - 20 + 50")


func test_showdown_has_nothing_returned() -> void:
	var table: Table = _table(2)
	assert_true(table.start_hand({"seed": 3, "button": 0})["ok"])
	_act(table, 0, Hand.CALL)
	_act(table, 1, Hand.CHECK)
	for street in 3:
		_act(table, 1, Hand.CHECK)
		_act(table, 0, Hand.CHECK)
	var view: Dictionary = _view(table)
	assert_true(view["result"]["showdown"])
	assert_eq(view["result"]["returned"], [], "showdown: nada devolvido a quem ganhou")
	assert_eq(PotMath.center(view), 40)


func test_collected_chips_stay_in_the_center() -> void:
	# Todos pagam 20 antes do flop: no flop, os 60 estão no centro e ninguém tem aposta.
	var table: Table = _table(3)
	assert_true(table.start_hand({"seed": 2, "button": 0})["ok"])
	_act(table, 0, Hand.CALL)
	_act(table, 1, Hand.CALL)
	_act(table, 2, Hand.CHECK)
	var view: Dictionary = _view(table)
	assert_eq(view["street"], "flop")
	assert_eq(PotMath.center(view), 60)
	assert_eq(_bets(view), 0)
	var seat: int = table.hand.to_act
	_act(table, seat, Hand.BET, 40)
	view = _view(table)
	assert_eq(PotMath.center(view), 60, "a aposta nova fica na frente do lugar, não no centro")
	assert_eq(_bets(view), 40)


func test_side_pots_are_not_a_split() -> void:
	# 0 ganha o pote principal (300) e 1 o paralelo (400): não "dividem 700".
	var seats: Array[int] = [0, 1, 2]
	var hand: Hand = Hand.new()
	var start: Dictionary = hand.start({
		"seats": [{"seat": 0, "stack": 100}, {"seat": 1, "stack": 300}, {"seat": 2, "stack": 500}],
		"button": 0, "small_blind": 10, "big_blind": 20,
		"deck": _rigged(seats, 0, ["As Ah", "Ks Kh", "Qs Qh"], BOARD)})
	assert_true(start["ok"])
	assert_true(hand.apply_action(0, Hand.RAISE, 100)["ok"])
	assert_true(hand.apply_action(1, Hand.RAISE, 300)["ok"])
	assert_true(hand.apply_action(2, Hand.CALL)["ok"])
	assert_true(hand.finished)
	var groups: Array = PotMath.groups(hand.result["payouts"], hand.result["pots"])
	assert_eq(groups, [{"seats": [1], "amount": 400}, {"seats": [0], "amount": 300}],
		"uma linha para cada um, com o que cada um levou")


func test_real_split_stays_together() -> void:
	# Os dois têm A-K com o mesmo par de cima: dividem o pote de 40.
	var seats: Array[int] = [0, 1]
	var hand: Hand = Hand.new()
	var start: Dictionary = hand.start({
		"seats": [{"seat": 0, "stack": 1000}, {"seat": 1, "stack": 1000}],
		"button": 0, "small_blind": 10, "big_blind": 20,
		"deck": _rigged(seats, 0, ["As Kd", "Ad Kh"], "Ac Kc 7d 3s 2h")})
	assert_true(start["ok"])
	assert_true(hand.apply_action(0, Hand.CALL)["ok"])
	while not hand.finished:
		assert_true(hand.apply_action(hand.to_act, Hand.CHECK)["ok"])
	var groups: Array = PotMath.groups(hand.result["payouts"], hand.result["pots"])
	assert_eq(groups, [{"seats": [0, 1], "amount": 40}], "uma linha só: dividem 40")


func test_history_keeps_who_won_each_pot() -> void:
	# O histórico guarda os vencedores de cada pote, para a lista dizer o mesmo que a mesa.
	var table: Table = _table(3)
	var log: HandLog = HandLog.new()
	var ids: Dictionary = {0: "j0", 1: "j1", 2: "j2"}
	var names: Dictionary = {"j0": "Ana", "j1": "Bia", "j2": "Caio"}
	log.note(table.start_hand({"seed": 1, "button": 0})["events"], table, ids, names)
	log.note(_act(table, 0, Hand.RAISE, 60), table, ids, names)
	log.note(_act(table, 1, Hand.FOLD), table, ids, names)
	log.note(_act(table, 2, Hand.FOLD), table, ids, names)
	var record: Dictionary = log.for_member("j0")[0]
	assert_eq(record["pots"], [{"amount": 50, "winners": [0]}])
	assert_eq(record["returned"], [{"seat": 0, "amount": 40}], "o histórico guarda a devolução")
	assert_eq(PotMath.groups(record["payouts"], record["pots"], record["returned"]),
		[{"seats": [0], "amount": 90}], "a lista diz 90, como a mesa")
	# Registro antigo, sem os potes: cada um com o seu valor.
	assert_eq(PotMath.groups([{"seat": 2, "amount": 30}, {"seat": 1, "amount": 70}], []),
		[{"seats": [1], "amount": 70}, {"seats": [2], "amount": 30}])


func test_side_pots_are_separated_in_the_center() -> void:
	# 0 foi all-in com 100 antes do flop; 1 e 2 seguem e 1 aposta 200 no flop.
	var table: Table = Table.new()
	assert_eq(table.configure({"format": Table.CLASSIC}), "")
	for i in 3:
		assert_eq(table.add_player(i, "j%d" % i), "")
	table.seat_at(0).stack = 100
	assert_true(table.start_hand({"seed": 4, "button": 2})["ok"])
	while table.hand.street == Hand.PREFLOP:
		var seat: int = table.hand.to_act
		var legal: Dictionary = table.hand.legal_actions()
		if seat == 0:
			_act(table, 0, Hand.RAISE if legal["can_raise"] else Hand.CALL, 100 if legal["can_raise"] else 0)
		elif legal["can_check"]:
			_act(table, seat, Hand.CHECK)
		else:
			_act(table, seat, Hand.CALL)
	var view: Dictionary = _view(table)
	assert_eq(PotMath.center_pots(view), [300], "sem aposta paralela ainda: um pote só")
	_act(table, table.hand.to_act, Hand.BET, 200)
	view = _view(table)
	assert_eq(PotMath.center_pots(view), [300], "a aposta nova não entra nas pilhas do centro")
	assert_eq(PotMath.total(view), 500, "o total do \"Pote\" inclui a aposta da rodada")
	_act(table, table.hand.to_act, Hand.CALL)
	view = _view(table)
	assert_eq(PotMath.center_pots(view), [300, 400], "recolhida, vira o pote paralelo")
	assert_eq(PotMath.total(view), 700)
