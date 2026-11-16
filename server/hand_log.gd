extends RefCounted
## Histórico das mãos da partida (SPEC 11.2): as últimas LIMIT mãos terminadas, com o
## que cada um fez em cada rodada e como a mão acabou. Montado pelo servidor a partir
## dos mesmos eventos que vão para a mesa, então vale igual nos três modos.
##
## Só guarda o que foi público: blinds, ações, cartas da mesa, cartas abertas no all-in
## e no showdown, devoluções e pagamentos. As cartas fechadas de cada um ficam à parte e
## só voltam para o próprio dono (for_member). Cartas de quem desistiu, ou de quem
## ganhou sem showdown, nunca aparecem para os outros.
##
## Registro de uma mão:
##   {hand, small_blind, big_blind, button,
##    players: [{seat, id, nick, stack}],          fichas no começo da mão
##    streets: [{street, cards, actions: [...]}],  preflop, flop, turn, river
##       ação: {seat, blind: "small"|"big", amount, all_in}
##          ou {seat, action, amount, to, all_in}
##    board, revealed: [{seat, cards}], shown: [{seat, cards, name, best}],
##    refunds: [{seat, amount}], payouts: [{seat, amount}],
##    showdown: bool, cancelled: bool}
## for_member acrescenta "mine": as suas cartas, se você jogou a mão.

const Table := preload("res://engine/table.gd")
const Hand := preload("res://engine/hand.gd")

const LIMIT: int = 50
const HAND_EVENTS: Array[String] = ["blind", "deal", "action", "street", "reveal", "refund",
	"showdown", "end", "cancel"]

var _hands: Array[Dictionary] = []   # terminadas, da mais antiga à mais recente
var _holes: Array[Dictionary] = []   # em paralelo: {id: cartas}
var _open: Dictionary = {}           # mão em andamento
var _open_holes: Dictionary = {}


## Anota os eventos de um passo da mesa. ids: {lugar: id} de quem recebeu cartas na
## mão; names: {id: apelido}.
func note(events: Array, table: Table, ids: Dictionary, names: Dictionary) -> void:
	for event: Dictionary in events:
		var type: String = String(event.get("type", ""))
		if not HAND_EVENTS.has(type):
			continue
		if (type == "blind" or type == "deal") and table.hand != null \
				and (_open.is_empty() or int(_open["hand"]) != table.hand_number):
			_begin(table, ids, names)
		if _open.is_empty():
			continue
		var streets: Array = _open["streets"]
		match type:
			"blind":
				streets[-1]["actions"].append({"seat": int(event["seat"]),
					"blind": String(event["kind"]), "amount": int(event["amount"]),
					"all_in": bool(event.get("all_in", false))})
			"action":
				streets[-1]["actions"].append({"seat": int(event["seat"]),
					"action": String(event["action"]), "amount": int(event["amount"]),
					"to": int(event.get("to", 0)), "all_in": bool(event.get("all_in", false))})
			"street":
				streets.append({"street": String(event["street"]),
					"cards": (event["cards"] as Array).duplicate(), "actions": []})
			"reveal":
				_open["revealed"] = (event["hands"] as Array).duplicate(true)
			"refund":
				(_open["refunds"] as Array).append({"seat": int(event["seat"]),
					"amount": int(event["amount"])})
			"showdown":
				_open["showdown"] = true
				var shown: Array = []
				for entry: Dictionary in event["shown"]:
					shown.append({"seat": int(entry["seat"]), "cards": (entry["cards"] as Array).duplicate(),
						"name": String(entry["name"]), "best": (entry["best"] as Array).duplicate()})
				_open["shown"] = shown
			"end":
				var payouts: Array = []
				for payout: Dictionary in event["payouts"]:
					payouts.append({"seat": int(payout["seat"]), "amount": int(payout["amount"])})
				_open["payouts"] = payouts
				var board: Array = []
				for street: Dictionary in streets:
					board.append_array(street["cards"])
				_open["board"] = board
				_close()
			"cancel":
				_open["cancelled"] = true
				var refunds: Array = []
				for refund: Dictionary in event.get("refunds", []):
					refunds.append({"seat": int(refund["seat"]), "amount": int(refund["amount"])})
				_open["refunds"] = refunds
				_close()


## As mãos terminadas, da mais recente à mais antiga, vistas por quem pede.
func for_member(id: String) -> Array:
	var list: Array = []
	for i in range(_hands.size() - 1, -1, -1):
		var record: Dictionary = _hands[i].duplicate(true)
		if id != "" and _holes[i].has(id):
			record["mine"] = (_holes[i][id] as Array).duplicate()
		list.append(record)
	return list


func size() -> int:
	return _hands.size()


## Número da última mão terminada (0 se ainda não houve).
func last_hand() -> int:
	return int(_hands[-1]["hand"]) if not _hands.is_empty() else 0


func _begin(table: Table, ids: Dictionary, names: Dictionary) -> void:
	var hand: Hand = table.hand
	var players: Array = []
	_open_holes = {}
	for player: Hand.Player in hand.players:
		var id: String = String(ids.get(player.seat, ""))
		players.append({"seat": player.seat, "id": id, "nick": String(names.get(id, "")),
			"stack": player.start_stack})
		if id != "":
			_open_holes[id] = player.cards.duplicate()
	players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["seat"] < b["seat"])
	_open = {
		"hand": table.hand_number, "small_blind": hand.small_blind,
		"big_blind": hand.big_blind, "button": hand.button, "players": players,
		"streets": [{"street": Hand.STREET_NAMES[0], "cards": [], "actions": []}],
		"board": [], "revealed": [], "shown": [], "refunds": [], "payouts": [],
		"showdown": false, "cancelled": false,
	}


func _close() -> void:
	_hands.append(_open)
	_holes.append(_open_holes)
	while _hands.size() > LIMIT:
		_hands.pop_front()
		_holes.pop_front()
	_open = {}
	_open_holes = {}
