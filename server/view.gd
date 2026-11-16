extends RefCounted
## Visão da mesa para um jogador ou espectador (SPEC 8, "Visão por jogador").
##
## Tudo o que sai do servidor sobre a mesa é montado aqui. As cartas fechadas de alguém
## só aparecem para ele mesmo, ou para todos quando o motor as abriu (showdown). O
## baralho nunca aparece.

const Table := preload("res://engine/table.gd")
const Hand := preload("res://engine/hand.gd")


## Parte pública da mesa, igual para todos.
## hand_ids: {lugar: id} de quem recebeu cartas na mão atual (ou na última). O lugar só
## carrega os dados da mão se ainda for da mesma pessoa.
static func public(table: Table, hand_ids: Dictionary) -> Dictionary:
	var hand: Hand = table.hand
	var live: bool = table.hand_in_progress()
	var view: Dictionary = {
		"format": table.format,
		"hand": table.hand_number,
		"live": live,
		"small_blind": table.small_blind,
		"big_blind": table.big_blind,
		"level": table.level,
		"button": table.button,
		"sb_seat": -1,
		"bb_seat": -1,
		"street": "",
		"board": [],
		"pots": [],
		"pot": 0,
		"current_bet": 0,
		"to_act": -1,
	}
	var shown: Dictionary = {}
	if hand != null:
		view["button"] = hand.button
		view["sb_seat"] = hand.small_blind_seat
		view["bb_seat"] = hand.big_blind_seat
		view["street"] = Hand.STREET_NAMES[hand.street]
		view["board"] = hand.board.duplicate()
		if live:
			view["pots"] = hand.current_pots()
			view["pot"] = hand.committed()
			view["current_bet"] = hand.current_bet
			view["to_act"] = hand.to_act
		else:
			view["result"] = hand.result.duplicate(true)
			for entry: Dictionary in hand.result.get("shown", []):
				shown[entry["seat"]] = true

	var seats: Array = []
	for seat in table.seats:
		if seat.state == Table.OUT:
			continue
		var entry: Dictionary = {
			"seat": seat.index, "id": seat.id, "stack": seat.stack, "state": seat.state,
			"rebuys": seat.rebuys, "in_hand": false, "bet": 0, "total": 0,
			"folded": false, "all_in": false,
		}
		var player: Hand.Player = _player(table, seat.index, seat.id, hand_ids)
		if player != null:
			entry["in_hand"] = true
			entry["bet"] = player.bet
			entry["total"] = player.total
			entry["folded"] = player.folded
			entry["all_in"] = player.all_in
			# Cartas abertas pelo motor: all-in sem mais apostas, ou showdown ganho.
			if (hand.revealed and not player.folded) or shown.has(seat.index):
				entry["cards"] = player.cards.duplicate()
		seats.append(entry)
	seats.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["seat"]) < int(b["seat"]))
	view["seats"] = seats
	return view


## Parte particular de quem olha: as próprias cartas e, na vez dele, as ações válidas.
## Espectador (seat -1) não recebe nada daqui.
static func own(table: Table, seat: int, id: String, hand_ids: Dictionary) -> Dictionary:
	var view: Dictionary = {}
	var player: Hand.Player = _player(table, seat, id, hand_ids)
	if player == null:
		return view
	view["cards"] = player.cards.duplicate()
	if table.hand_in_progress() and table.hand.to_act == seat:
		view["legal"] = table.hand.legal_actions()
	return view


## O jogador da mão atual (ou da última) nesse lugar, se for a mesma pessoa.
static func _player(table: Table, seat: int, id: String, hand_ids: Dictionary) -> Hand.Player:
	if table.hand == null or seat < 0 or id == "" or hand_ids.get(seat, "") != id:
		return null
	return table.hand.player_at(seat)
