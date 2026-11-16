extends RefCounted
## Mensagem `state` de exemplo (no formato do servidor), para as fotos da mesa:
## 9 lugares, turn aberto, apostas na rodada e a sua vez com aumento possível.

const Cards := preload("res://engine/cards.gd")


static func make() -> Dictionary:
	var nicks: Array[String] = ["Rafa", "Bia", "Duda", "Léo", "Marina", "Tião", "Carol", "Zé",
		"Gabi"]
	var stacks: Array[int] = [148000, 92500, 210000, 61500, 133000, 0, 87000, 175500, 54000]
	var bets: Array[int] = [0, 0, 6000, 0, 0, 0, 6000, 0, 0]
	var folded: Array[bool] = [false, true, false, false, true, false, false, true, true]
	var members: Array = []
	var seats: Array = []
	for i in 9:
		members.append({"id": "p%d" % i, "nick": nicks[i], "avatar": i, "bot": i != 0,
			"seat": i, "away": false, "connected": true})
		seats.append({"seat": i, "id": "p%d" % i, "stack": stacks[i], "state": "playing",
			"in_hand": true, "bet": bets[i], "total": bets[i] + 4000,
			"folded": folded[i], "all_in": stacks[i] == 0})
	seats[5]["bet"] = 42000
	var board: Array = [Cards.from_text("Ah"), Cards.from_text("Td"), Cards.from_text("7c"),
		Cards.from_text("Qs")]
	return {
		"t": "state",
		"room": {"id": "OFF", "name": "Mesa offline", "phase": "playing", "paused": false,
			"owner": "p0", "options": {"seats": 9, "turn_seconds": 20}, "members": members},
		"table": {"format": "classic", "hand": 12, "live": true, "small_blind": 1000,
			"big_blind": 2000, "button": 3, "street": "turn", "board": board,
			"pot": 124000, "current_bet": 42000, "to_act": 0, "seats": seats, "seq": 40,
			"turn_ms": 13000},
		"you": {"id": "p0", "seat": 0, "cards": [Cards.from_text("As"), Cards.from_text("Kh")],
			"legal": {"seat": 0, "can_check": false, "call": 42000, "can_raise": true,
				"is_bet": false, "min_to": 84000, "max_to": 148000}},
		"events": [{"type": "action", "seat": 2, "action": "call", "amount": 6000},
			{"type": "action", "seat": 6, "action": "call", "amount": 6000},
			{"type": "action", "seat": 5, "action": "raise", "amount": 42000}],
	}
