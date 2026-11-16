extends "res://tests/test_case.gd"

const Cards := preload("res://engine/cards.gd")
const Deck := preload("res://engine/deck.gd")
const Hand := preload("res://engine/hand.gd")
const Positions := preload("res://engine/positions.gd")
const Table := preload("res://engine/table.gd")

const STRONG: Array[String] = ["Ks Kh", "Qs Qh", "Js Jh"]
const FILLERS: Array[String] = ["3c 9d", "5c 9s", "7c 3h", "5h 7s", "3d 5d", "7d 9c"]
const BOARD: String = "Td 8c 6h 4d 2s"


func _table(options: Dictionary, players: int) -> Table:
	var table: Table = Table.new()
	assert_eq(table.configure(options), "")
	for i in players:
		assert_eq(table.add_player(i, "j%d" % i), "")
	return table


func _classic(players: int, rebuy_limit: int = Table.REBUY_UNLIMITED) -> Table:
	return _table({"format": Table.CLASSIC, "rebuy_limit": rebuy_limit}, players)


func _tournament(players: int) -> Table:
	return _table({"format": Table.TOURNAMENT}, players)


## Joga uma mão em que todos desistem para o big blind.
func _fold_around(table: Table, params: Dictionary = {"seed": 3}) -> void:
	var response: Dictionary = table.start_hand(params)
	assert_true(response["ok"], str(response["error"]))
	var guard: int = 0
	while table.hand_in_progress() and guard < 20:
		guard += 1
		table.apply_action(table.hand.to_act, Hand.FOLD)


## Joga uma mão com o baralho armado: `winner` leva tudo de `losers`, todos all-in;
## os outros desistem. Devolve os eventos da mão.
func _bust(table: Table, winner: int, losers: Array) -> Array:
	var playing: Array[int] = table.participants()
	var button: int = playing[0]
	var holes: Dictionary = {winner: "As Ah"}
	for i in losers.size():
		holes[losers[i]] = STRONG[i]
	var filler: int = 0
	for seat in playing:
		if not holes.has(seat):
			holes[seat] = FILLERS[filler]
			filler += 1
	var top: Array[int] = []
	for card_index in 2:
		for seat in Positions.order_after(playing, button):
			top.append(Cards.list_from_text(holes[seat])[card_index])
	top.append_array(Cards.list_from_text(BOARD))

	var response: Dictionary = table.start_hand({"deck": Deck.stacked(top), "button": button})
	assert_true(response["ok"], str(response["error"]))
	var events: Array = []
	events.append_array(response["events"])
	var guard: int = 0
	while table.hand_in_progress() and guard < 100:
		guard += 1
		var legal: Dictionary = table.hand.legal_actions()
		var seat: int = legal["seat"]
		if seat != winner and not losers.has(seat):
			response = table.apply_action(seat, Hand.FOLD)
		elif legal["can_raise"]:
			var verb: String = Hand.BET if legal["is_bet"] else Hand.RAISE
			response = table.apply_action(seat, verb, legal["max_to"])
		elif legal["can_check"]:
			response = table.apply_action(seat, Hand.CHECK)
		else:
			response = table.apply_action(seat, Hand.CALL)
		assert_true(response["ok"], str(response["error"]))
		events.append_array(response["events"])
	return events


func _find(events: Array, type: String) -> Array:
	var found: Array = []
	for event: Dictionary in events:
		if event["type"] == type:
			found.append(event)
	return found


func _row(table: Table, id: String) -> Dictionary:
	for row in table.scoreboard():
		if row["id"] == id:
			return row
	return {}


# --- Opções e lugares ---

func test_default_options() -> void:
	var table: Table = Table.new()
	assert_eq(table.configure({}), "")
	assert_eq(table.format, Table.CLASSIC)
	assert_eq(table.starting_stack, 2000)
	assert_eq(table.small_blind, 10)
	assert_eq(table.big_blind, 20)
	assert_eq(table.rebuy_limit, Table.REBUY_UNLIMITED, "recompra ilimitada por padrão")


func test_options_validation() -> void:
	var bad: Array = [
		{"format": "outro"},
		{"format": 5},
		{"starting_stack": 0},
		{"starting_stack": 20.5},
		{"rebuy_limit": 7},
		{"small_blind": 20, "big_blind": 10},
		{"small_blind": 0, "big_blind": 10},
		{"format": Table.TOURNAMENT, "level_minutes": 4},
	]
	for options: Dictionary in bad:
		assert_true(Table.new().configure(options) != "", str(options))
	var table: Table = _classic(2)
	assert_true(table.configure({}) != "", "não reconfigura com gente sentada")


func test_seating() -> void:
	var table: Table = _classic(2)
	assert_true(table.add_player(0, "outro") != "", "lugar ocupado")
	assert_true(table.add_player(5, "j1") != "", "já está na mesa")
	assert_true(table.add_player(9, "novo") != "", "só há 9 lugares")
	assert_true(table.add_player(-1, "novo") != "")
	assert_true(table.add_player(5, "") != "")
	assert_eq(table.add_player(7, "novo"), "")
	assert_eq(table.participants(), [0, 1, 7])
	assert_eq(table.chips_on_seats(), 6000)
	assert_eq(table.cashbox.total_entries(), 6000)
	assert_true(table.is_balanced())


func test_leaving_before_the_first_hand_leaves_no_trace() -> void:
	var table: Table = _classic(3)
	assert_eq(table.remove_player(2), "")
	assert_eq(table.cashbox.total_entries(), 4000)
	assert_eq(table.scoreboard().size(), 2)
	assert_eq(table.add_player(2, "j2"), "")
	assert_eq(table.seat_at(2).rebuys, 0)
	assert_true(table.remove_player(6) != "", "lugar vazio")


func test_needs_two_players_with_chips() -> void:
	var table: Table = _classic(1)
	assert_false(table.can_start_hand())
	assert_false(table.start_hand({"seed": 1})["ok"])
	assert_eq(table.hand_number, 0)
	assert_false(table.is_over(), "nenhuma mão foi jogada")
	assert_false(table.apply_action(0, Hand.FOLD)["ok"])
	assert_false(table.cancel_hand()["ok"])


func test_start_needs_a_seed_or_a_deck() -> void:
	var table: Table = _classic(2)
	assert_false(table.start_hand({})["ok"])
	assert_false(table.start_hand({"seed": "x"})["ok"])
	assert_eq(table.hand_number, 0)
	assert_eq(table.button, -1)
	assert_true(table.start_hand({"seed": 4})["ok"])
	assert_false(table.start_hand({"seed": 5})["ok"], "já há uma mão em andamento")


# --- Botão ---

func test_first_button_is_drawn_then_moves_left() -> void:
	var table: Table = Table.new()
	table.configure({})
	for index: int in [1, 4, 6]:
		table.add_player(index, "j%d" % index)
	_fold_around(table, {"seed": 11})
	var first: int = table.button
	assert_true([1, 4, 6].has(first))
	assert_eq(table.hand_number, 1)
	_fold_around(table, {"seed": 12})
	var second: int = table.button
	assert_eq(second, Positions.next_seat([1, 4, 6], first))
	_fold_around(table, {"seed": 13})
	assert_eq(table.button, Positions.next_seat([1, 4, 6], second))
	assert_eq(table.hand_number, 3)
	assert_true(table.is_balanced())


func test_button_skips_who_is_not_in_the_hand() -> void:
	var table: Table = _classic(3, 0)
	var events: Array = _bust(table, 0, [1])
	assert_eq(table.button, 0)
	assert_eq(_find(events, "busted"), [{"type": "busted", "seat": 1, "can_rebuy": false}])
	assert_eq(table.participants(), [0, 2])
	_fold_around(table)
	assert_eq(table.button, 2, "o botão pula o lugar sem fichas")
	assert_eq(table.hand.small_blind_seat, 2, "mano a mano: o botão põe o small blind")
	assert_eq(table.hand.big_blind_seat, 0)


# --- Clássico: recompra, placar, fim ---

func test_rebuy_within_the_limit() -> void:
	var table: Table = _classic(2, 1)
	var events: Array = _bust(table, 0, [1])
	assert_eq(_find(events, "busted"), [{"type": "busted", "seat": 1, "can_rebuy": true}])
	assert_eq(table.seat_at(1).state, Table.BUSTED)
	assert_false(table.can_start_hand(), "quem zerou não joga sem recomprar")
	assert_false(table.is_over(), "ainda há recompra possível")
	assert_true(table.rebuy(0) != "", "só recompra quem zerou")
	assert_eq(table.rebuy(1), "")
	assert_eq(table.seat_at(1).stack, 2000)
	assert_eq(table.seat_at(1).rebuys, 1)
	assert_eq(table.cashbox.entries("j1"), 4000)
	assert_true(table.is_balanced())
	assert_true(table.rebuy(1) != "")
	# Zera de novo: acabou a recompra, vira espectador.
	table.seat_at(0).stack = 3000
	table.seat_at(1).stack = 3000
	events = _bust(table, 0, [1])
	assert_eq(_find(events, "busted")[0]["can_rebuy"], false)
	assert_eq(table.seat_at(1), null)
	assert_true(table.rebuy(1) != "")
	assert_true(table.is_over())
	assert_true(table.is_balanced())


func test_unlimited_rebuys_and_declining() -> void:
	var table: Table = _classic(3)
	for i in 4:
		_bust(table, 0, [1])
		assert_eq(table.rebuy(1), "")
	assert_eq(table.seat_at(1).rebuys, 4)
	_bust(table, 0, [1])
	assert_true(table.decline_rebuy(0) != "")
	assert_eq(table.decline_rebuy(1), "")
	assert_eq(table.seat_at(1), null, "quem não recompra vira espectador")
	assert_eq(table.participants(), [0, 2])
	assert_true(table.is_balanced())


func test_no_rebuy_option() -> void:
	var table: Table = _classic(2, 0)
	_bust(table, 0, [1])
	assert_eq(table.seat_at(1), null)
	assert_true(table.is_over(), "sobrou um só com fichas e ninguém pode recomprar")


func test_scoreboard_with_net_balance() -> void:
	var table: Table = _classic(3)
	_bust(table, 0, [1])
	table.rebuy(1)
	var board: Array[Dictionary] = table.scoreboard()
	assert_eq(board.size(), 3)
	assert_eq(board[0]["id"], "j0", "do maior saldo para o menor")
	assert_eq(board[0]["chips"], 4020)
	assert_eq(board[0]["net"], 2020)
	assert_eq(board[0]["rebuys"], 0)
	assert_eq(_row(table, "j1")["chips"], 2000)
	assert_eq(_row(table, "j1")["net"], -2000)
	assert_eq(_row(table, "j1")["rebuys"], 1)
	assert_eq(_row(table, "j2")["net"], -20)
	var sum: int = 0
	for row in board:
		sum += int(row["net"])
	assert_eq(sum, 0, "os saldos líquidos somam zero")


func test_scoreboard_counts_the_bets_of_the_hand_in_progress() -> void:
	var table: Table = _classic(3)
	assert_true(table.start_hand({"seed": 2, "button": 0})["ok"])
	assert_true(table.apply_action(0, Hand.RAISE, 500)["ok"])
	var sum: int = 0
	for row in table.scoreboard():
		assert_eq(row["chips"], 2000, "o que está apostado ainda é do jogador")
		assert_eq(row["net"], 0)
		sum += int(row["net"])
	assert_eq(sum, 0)


func test_leaving_holds_the_chips() -> void:
	var table: Table = _classic(3)
	_bust(table, 0, [1])
	table.rebuy(1)
	assert_true(table.start_hand({"seed": 2})["ok"])
	assert_true(table.remove_player(0) != "", "não sai no meio da mão")
	table.cancel_hand()
	assert_eq(table.remove_player(0), "")
	assert_eq(table.seat_at(0), null)
	assert_eq(table.cashbox.held("j0"), 4020, "as fichas ficam guardadas")
	assert_eq(table.cashbox.exits("j0"), 0)
	assert_true(table.is_balanced())
	assert_eq(_row(table, "j0")["chips"], 0)
	assert_eq(_row(table, "j0")["held"], 4020)
	assert_eq(_row(table, "j0")["net"], 2020, "o saldo de quem saiu fica no placar")
	assert_eq(table.participants(), [1, 2])
	# O prazo de volta vence: as fichas guardadas viram saída e o saldo não muda.
	assert_true(table.expire_held("j1") != "", "quem está sentado não tem prazo")
	assert_eq(table.expire_held("j0"), "")
	assert_eq(table.cashbox.held("j0"), 0)
	assert_eq(table.cashbox.exits("j0"), 4020)
	assert_eq(_row(table, "j0")["net"], 2020)
	assert_true(table.expire_held("j0") != "")
	assert_true(table.is_balanced())


func test_late_join_plays_from_the_next_hand() -> void:
	var table: Table = _classic(2)
	assert_true(table.start_hand({"seed": 2})["ok"])
	assert_eq(table.add_player(5, "novo"), "")
	assert_eq(table.hand.player_at(5), null, "quem entra não participa da mão em andamento")
	assert_true(table.is_balanced())
	assert_eq(_row(table, "novo")["net"], 0)
	table.cancel_hand()
	assert_true(table.start_hand({"seed": 3})["ok"])
	assert_true(table.hand.player_at(5) != null)
	assert_true(table.is_balanced())


## Uma mão em que o big blind (lugar 2) leva os blinds: 0 fica com 2000, 1 com 1990
## e 2 com 2010.
func _after_one_walk(rebuy_limit: int) -> Table:
	var table: Table = _classic(3, rebuy_limit)
	_fold_around(table, {"seed": 3, "button": 0})
	assert_eq(table.seat_at(1).stack, 1990)
	assert_eq(table.seat_at(2).stack, 2010)
	return table


func test_return_with_the_chips_from_before() -> void:
	var table: Table = _after_one_walk(0)
	assert_true(table.add_player(6, "j1", true) != "", "ainda está sentado")
	assert_eq(table.remove_player(1), "")
	assert_true(table.add_player(6, "ninguém", true) != "", "desconhecido não tem fichas guardadas")
	assert_eq(table.add_player(6, "j1", true), "", "volta em outro lugar, mesmo sem recompras")
	assert_eq(table.seat_at(6).stack, 1990)
	assert_eq(table.seat_at(6).rebuys, 0)
	assert_eq(table.cashbox.held("j1"), 0)
	assert_eq(table.cashbox.entries("j1"), 2000)
	assert_eq(_row(table, "j1")["net"], -10)
	assert_true(table.is_balanced())


func test_return_with_initial_chips_is_a_rebuy_when_it_is_more() -> void:
	var table: Table = _after_one_walk(1)
	assert_eq(table.remove_player(1), "")
	assert_eq(table.add_player(1, "j1"), "")
	assert_eq(table.seat_at(1).stack, 2000)
	assert_eq(table.seat_at(1).rebuys, 1, "20,00 é mais do que os 19,90 que ele tinha")
	assert_eq(table.cashbox.exits("j1"), 1990, "as fichas de antes saem da mesa")
	assert_eq(table.cashbox.entries("j1"), 4000)
	assert_eq(_row(table, "j1")["net"], -10)
	assert_true(table.is_balanced())
	# Agora ele tem exatamente as iniciais: voltar com as iniciais não é recompra.
	assert_eq(table.remove_player(1), "")
	assert_eq(table.add_player(1, "j1"), "")
	assert_eq(table.seat_at(1).rebuys, 1)
	assert_true(table.is_balanced())


func test_return_with_initial_chips_respects_the_rebuy_limit() -> void:
	var table: Table = _after_one_walk(0)
	assert_eq(table.remove_player(1), "")
	assert_true(table.add_player(1, "j1") != "", "sem recompras, só com as fichas de antes")
	assert_eq(table.cashbox.held("j1"), 1990, "a recusa não mexe nas fichas guardadas")
	assert_eq(table.add_player(1, "j1", true), "")
	# Quem tinha mais que as iniciais pode trocar pelas iniciais sem gastar recompra.
	assert_eq(table.remove_player(2), "")
	assert_eq(table.add_player(2, "j2"), "")
	assert_eq(table.seat_at(2).stack, 2000)
	assert_eq(table.seat_at(2).rebuys, 0)
	assert_eq(_row(table, "j2")["net"], 10)
	assert_true(table.is_balanced())


func test_after_the_deadline_returns_as_a_new_player() -> void:
	var table: Table = _after_one_walk(0)
	assert_eq(table.remove_player(1), "")
	assert_eq(table.expire_held("j1"), "")
	assert_true(table.add_player(1, "j1", true) != "", "não há mais fichas guardadas")
	assert_eq(table.add_player(1, "j1"), "", "entra como jogador novo, com as iniciais")
	assert_eq(table.seat_at(1).stack, 2000)
	assert_eq(table.seat_at(1).rebuys, 0)
	assert_eq(table.cashbox.entries("j1"), 4000)
	assert_eq(_row(table, "j1")["net"], -10, "o saldo antigo continua no placar")
	assert_true(table.is_balanced())


func test_busted_player_without_rebuys_cannot_sit_again() -> void:
	var table: Table = _classic(3, 0)
	_bust(table, 0, [1])
	assert_true(table.add_player(1, "j1") != "", "sem recompras")
	assert_true(table.add_player(1, "j1", true) != "")
	assert_true(table.expire_held("j1") != "", "quem zerou não vira jogador novo")
	assert_true(table.add_player(1, "j1") != "")
	assert_true(table.is_balanced())


func test_spectator_who_skipped_the_rebuy_can_sit_later() -> void:
	var table: Table = _classic(3, 1)
	_bust(table, 0, [1])
	assert_eq(table.decline_rebuy(1), "")
	assert_eq(table.add_player(1, "j1"), "", "senta de novo gastando a recompra")
	assert_eq(table.seat_at(1).rebuys, 1)
	_bust(table, 0, [1])
	assert_true(table.add_player(1, "j1") != "")
	assert_true(table.is_balanced())


func test_blinds_change_only_between_hands() -> void:
	var table: Table = _classic(2)
	assert_eq(table.set_blinds(25, 50), "")
	assert_true(table.set_blinds(50, 25) != "")
	assert_true(table.start_hand({"seed": 2})["ok"])
	assert_eq(table.hand.big_blind, 50)
	assert_true(table.set_blinds(50, 100) != "", "não muda no meio da mão")
	table.cancel_hand()
	assert_eq(table.set_blinds(50, 100), "")


func test_cancel_hand_returns_the_bets() -> void:
	var table: Table = _classic(3)
	assert_true(table.start_hand({"seed": 2, "button": 0})["ok"])
	assert_true(table.apply_action(0, Hand.RAISE, 500)["ok"])
	assert_eq(table.chips_in_hand(), 530)
	assert_true(table.is_balanced())
	assert_true(table.cancel_hand()["ok"])
	assert_eq(table.chips_in_hand(), 0)
	for index in 3:
		assert_eq(table.seat_at(index).stack, 2000)
	assert_true(table.is_balanced())
	assert_true(table.can_start_hand())


func test_cancelled_hand_is_dealt_again_from_the_same_positions() -> void:
	var table: Table = _classic(4)
	assert_true(table.start_hand({"seed": 2})["ok"])
	var first_button: int = table.button
	table.cancel_hand()
	assert_eq(table.button, -1, "a primeira mão não valeu: o botão é sorteado de novo")
	_fold_around(table, {"seed": 2})
	assert_eq(table.button, first_button)
	# Cancelar a mão seguinte devolve o botão para repetir as posições.
	assert_true(table.start_hand({"seed": 5})["ok"])
	var second_button: int = table.button
	var blinds: Array = [table.hand.small_blind_seat, table.hand.big_blind_seat]
	assert_true(second_button != first_button)
	table.cancel_hand()
	assert_eq(table.button, first_button)
	assert_true(table.start_hand({"seed": 6})["ok"])
	assert_eq(table.button, second_button)
	assert_eq([table.hand.small_blind_seat, table.hand.big_blind_seat], blinds,
		"ninguém pula os blinds")


# --- Torneio ---

func test_tournament_rules() -> void:
	var table: Table = _tournament(3)
	assert_eq(table.big_blind, 20, "começa em 0,10/0,20")
	assert_eq(table.small_blind, 10)
	assert_eq(table.level_minutes, 5)
	assert_eq(table.starting_stack, 3000, "padrão do torneio: 30,00")
	assert_eq(table.seat_at(0).stack, 3000)
	assert_true(table.set_blinds(50, 100) != "")
	assert_true(table.start_hand({"seed": 2, "elapsed_ms": 0})["ok"])
	assert_true(table.add_player(5, "tarde") != "", "sem entrada depois do início")
	table.cancel_hand()
	assert_true(table.remove_player(0) != "")
	assert_true(table.rebuy(0) != "", "sem recompra")


func test_new_level_applies_from_the_next_hand() -> void:
	var table: Table = _tournament(3)
	_fold_around(table, {"seed": 1, "elapsed_ms": 0})
	assert_eq(table.hand.big_blind, 20)
	assert_true(table.start_hand({"seed": 2, "elapsed_ms": 299000})["ok"])
	assert_eq(table.hand.big_blind, 20)
	# O tempo passa durante a mão, mas os blinds dela não mudam.
	assert_eq(table.level, 0)
	table.cancel_hand()
	_fold_around(table, {"seed": 3, "elapsed_ms": 300000})
	assert_eq(table.level, 1)
	assert_eq(table.hand.small_blind, 15)
	assert_eq(table.hand.big_blind, 30)
	_fold_around(table, {"seed": 4, "elapsed_ms": 10})
	assert_eq(table.level, 1, "o nível nunca desce")
	_fold_around(table, {"seed": 5, "elapsed_ms": 3000000})
	assert_eq(table.hand.big_blind, 2000, "nível 11: 10,00/20,00")


func test_refused_start_does_not_change_the_level() -> void:
	var table: Table = _tournament(3)
	assert_false(table.start_hand({"elapsed_ms": 1200000})["ok"], "falta a semente")
	assert_eq(table.level, 0)
	assert_eq(table.big_blind, 20)
	assert_eq(table.hand_number, 0)
	assert_eq(table.button, -1)
	assert_false(table.start_hand({"seed": 1, "elapsed_ms": "muito"})["ok"])
	assert_eq(table.level, 0)


func test_elimination_order_in_the_same_hand() -> void:
	var table: Table = _tournament(4)
	table.seat_at(0).stack = 3500
	table.seat_at(1).stack = 2500
	var events: Array = _bust(table, 0, [1, 2])
	# 2 começou a mão com 3000 e 1 com 2500: 2 fica à frente.
	assert_eq(_find(events, "eliminated"), [
		{"type": "eliminated", "seat": 2, "place": 3},
		{"type": "eliminated", "seat": 1, "place": 4}])
	assert_eq(table.participants(), [0, 3])
	assert_false(table.is_over())
	assert_eq(_find(events, "tournament_end"), [])
	events = _bust(table, 0, [3])
	assert_eq(_find(events, "eliminated"), [{"type": "eliminated", "seat": 3, "place": 2}])
	assert_eq(_find(events, "tournament_end"), [{"type": "tournament_end", "winner": 0}])
	assert_true(table.is_over())
	assert_false(table.can_start_hand())
	assert_eq(table.seat_at(0).stack, 12000, "o campeão tem todas as fichas")
	assert_eq(table.podium(), [
		{"place": 1, "seat": 0, "id": "j0"},
		{"place": 2, "seat": 3, "id": "j3"},
		{"place": 3, "seat": 2, "id": "j2"}])
	assert_true(table.is_balanced())


func test_tied_elimination_shares_the_place() -> void:
	var table: Table = _tournament(3)
	table.seat_at(0).stack = 4000
	table.seat_at(1).stack = 2500
	table.seat_at(2).stack = 2500
	_bust(table, 0, [1, 2])
	assert_true(table.is_over())
	assert_eq(table.podium(), [
		{"place": 1, "seat": 0, "id": "j0"},
		{"place": 2, "seat": 1, "id": "j1"},
		{"place": 2, "seat": 2, "id": "j2"}])


func test_tournament_scoreboard_order() -> void:
	var table: Table = _tournament(4)
	_bust(table, 0, [1])
	var board: Array[Dictionary] = table.scoreboard()
	assert_eq(board[0]["id"], "j0", "quem ainda joga vem na frente, por fichas")
	assert_eq(board[0]["place"], 0)
	assert_eq(board[3]["id"], "j1")
	assert_eq(board[3]["place"], 4)


# --- Estado ---

func test_save_and_restore_the_table() -> void:
	var table: Table = _classic(4, 2)
	_bust(table, 0, [1])
	table.rebuy(1)
	table.remove_player(3)
	assert_true(table.start_hand({"seed": 8})["ok"])
	table.apply_action(table.hand.to_act, Hand.CALL)
	var saved: String = JSON.stringify(table.to_dict())
	var copy: Table = Table.new()
	assert_true(copy.load_dict(JSON.parse_string(saved)), copy.load_error)
	assert_eq(JSON.stringify(copy.to_dict()), saved)
	assert_true(copy.is_balanced())
	assert_eq(copy.hand.to_act, table.hand.to_act)
	assert_eq(copy.cashbox.held("j3"), 2000, "as fichas guardadas de quem saiu voltam junto")
	# As duas mesas seguem iguais.
	for target: Table in [table, copy]:
		var guard: int = 0
		while target.hand_in_progress() and guard < 50:
			guard += 1
			var legal: Dictionary = target.hand.legal_actions()
			target.apply_action(legal["seat"], Hand.CHECK if legal["can_check"] else Hand.CALL)
	assert_eq(JSON.stringify(copy.to_dict()), JSON.stringify(table.to_dict()))


func test_save_and_restore_before_the_first_hand() -> void:
	var table: Table = _tournament(3)
	var saved: String = JSON.stringify(table.to_dict())
	var copy: Table = Table.new()
	assert_true(copy.load_dict(JSON.parse_string(saved)), copy.load_error)
	assert_eq(copy.hand, null)
	assert_eq(copy.format, Table.TOURNAMENT)
	assert_eq(JSON.stringify(copy.to_dict()), saved)


## Mesa clássica de 3 com uma mão em andamento, já em formato de estado salvo.
func _saved_mid_hand() -> Dictionary:
	var table: Table = _classic(3)
	_fold_around(table, {"seed": 3, "button": 0})
	assert_true(table.start_hand({"seed": 8})["ok"])
	return JSON.parse_string(JSON.stringify(table.to_dict()))


func _refuses(state: Dictionary, why: String) -> void:
	var table: Table = _classic(2)
	var before: String = JSON.stringify(table.to_dict())
	assert_false(table.load_dict(state), why)
	assert_true(table.load_error != "", why)
	assert_eq(JSON.stringify(table.to_dict()), before, "a mesa não muda quando a leitura falha")


func test_load_refuses_broken_state() -> void:
	assert_true(Table.new().load_dict(_saved_mid_hand()), "o estado bom carrega")
	_refuses({}, "vazio")
	var changes: Array = [
		["v", 2], ["format", "outro"], ["format", 3], ["starting_stack", 0],
		["big_blind", 5], ["rebuy_limit", 9], ["level_minutes", 4], ["hand_number", -1],
		["seats", "nada"], ["seats", [{"index": 0}]], ["cashbox", {}], ["hand", {"v": 1}],
		["hand", "nada"], ["button", "zero"],
	]
	for change: Array in changes:
		var state: Dictionary = _saved_mid_hand()
		state[change[0]] = change[1]
		_refuses(state, "%s = %s" % [change[0], str(change[1])])
	var missing: Dictionary = _saved_mid_hand()
	missing.erase("hand")
	_refuses(missing, "sem a chave da mão")


func test_load_refuses_state_that_does_not_add_up() -> void:
	# Um campo da mão com o tipo errado: antes isso travava a mesa em silêncio.
	var state: Dictionary = _saved_mid_hand()
	state["hand"]["street"] = "flop"
	_refuses(state, "rodada com tipo errado")
	# Jogador da mão sem lugar na mesa.
	state = _saved_mid_hand()
	state["seats"][0]["index"] = 7
	_refuses(state, "jogador da mão sem lugar")
	# Fichas do lugar diferentes das fichas na mão.
	state = _saved_mid_hand()
	state["seats"][0]["stack"] = state["seats"][0]["stack"] + 1
	_refuses(state, "fichas que não combinam")
	# Ficha que some: a caixa não fecha.
	state = _saved_mid_hand()
	state["cashbox"]["accounts"]["j0"]["entries"] = 5000
	_refuses(state, "caixa que não fecha")
	# Dois jogadores no mesmo lugar, ou o mesmo jogador duas vezes.
	state = _saved_mid_hand()
	state["seats"][1]["index"] = state["seats"][0]["index"]
	_refuses(state, "lugar repetido")
	state = _saved_mid_hand()
	state["seats"][1]["id"] = state["seats"][0]["id"]
	_refuses(state, "jogador repetido")
	state = _saved_mid_hand()
	state["seats"][0]["state"] = "voando"
	_refuses(state, "situação desconhecida")
