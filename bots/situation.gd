extends RefCounted
## O que o bot tira da visão que recebe do servidor, a mesma de um humano naquele lugar
## (SPEC 7, "Sem trapaça"), e as jogadas que ele pode devolver.

const Positions := preload("res://engine/positions.gd")

const STREETS: Array[String] = ["preflop", "flop", "turn", "river"]
const PREFLOP: int = 0
const FLOP: int = 1
const TURN: int = 2
const RIVER: int = 3


## Lê a mensagem "state". Devolve um dicionário vazio se não é a vez do bot.
##   cards, board, street, bb, sb, pot (tudo o que está na mesa), current_bet,
##   to_call, can_check, can_raise, is_bet, min_to, max_to, stack, bet,
##   opponents (ainda na mão), able (ainda com fichas), players (receberam cartas),
##   effective (o máximo que posso perder nesta mão daqui em diante),
##   behind (antes do flop: quantos ainda falam depois de mim),
##   in_position (depois do flop sou o último a falar), tournament
static func read(state: Dictionary) -> Dictionary:
	var you: Dictionary = state.get("you", {})
	var table: Dictionary = state.get("table", {})
	if not you.has("legal") or not you.has("cards"):
		return {}
	var legal: Dictionary = you["legal"]
	var seat: int = you["seat"]
	var me: Dictionary = {}
	var live: Array[int] = []
	var opponents: int = 0
	var able: int = 0
	var players: int = 0
	var biggest_other: int = 0
	for entry: Dictionary in table["seats"]:
		if not entry["in_hand"]:
			continue
		players += 1
		if int(entry["seat"]) == seat:
			me = entry
			live.append(seat)
			continue
		if entry["folded"]:
			continue
		live.append(int(entry["seat"]))
		opponents += 1
		if not entry["all_in"]:
			able += 1
		biggest_other = maxi(biggest_other, int(entry["stack"]) + int(entry["bet"]))
	if me.is_empty():
		return {}

	var street: int = maxi(0, STREETS.find(str(table["street"])))
	var stack: int = me["stack"]
	var bet: int = me["bet"]
	# Ordem depois do flop: começa à esquerda do botão e termina nele.
	var order: Array[int] = Positions.order_after(live, int(table["button"]))
	# Ordem antes do flop: começa à esquerda do big blind e termina nele.
	var preflop_order: Array[int] = Positions.order_after(live, int(table["bb_seat"]))
	return {
		"seat": seat,
		"cards": you["cards"],
		"board": table["board"],
		"street": street,
		"bb": int(table["big_blind"]),
		"sb": int(table["small_blind"]),
		"pot": int(table["pot"]),
		"current_bet": int(table["current_bet"]),
		"to_call": int(legal["call"]),
		"can_check": bool(legal["can_check"]),
		"can_raise": bool(legal["can_raise"]),
		"is_bet": bool(legal["is_bet"]),
		"min_to": int(legal["min_to"]),
		"max_to": int(legal["max_to"]),
		"stack": stack,
		"bet": bet,
		"opponents": opponents,
		"able": able,
		"players": players,
		"effective": mini(stack + bet, biggest_other),
		"behind": preflop_order.size() - 1 - preflop_order.find(seat),
		"in_position": order[order.size() - 1] == seat,
		"tournament": str(table["format"]) == "tournament",
	}


static func fold() -> Dictionary:
	return {"action": "fold", "amount": 0}


## Passa se puder; senão desiste.
static func check_or_fold(s: Dictionary) -> Dictionary:
	if s["can_check"]:
		return {"action": "check", "amount": 0}
	return fold()


## Paga; se não há o que pagar, passa.
static func pay(s: Dictionary) -> Dictionary:
	if s["can_check"]:
		return {"action": "check", "amount": 0}
	return {"action": "call", "amount": 0}


## Aposta ou aumenta até `to` (total na rodada), ajustado ao permitido. Se não pode
## aumentar, paga. Se o valor leva a maior parte das fichas, vai all-in de uma vez.
static func raise_to(s: Dictionary, to: int) -> Dictionary:
	if not s["can_raise"]:
		return pay(s)
	var max_to: int = s["max_to"]
	var unit: int = maxi(1, int(s["sb"]))
	var amount: int = to - (to % unit)
	amount = clampi(amount, int(s["min_to"]), max_to)
	if amount * 3 >= max_to * 2:
		amount = max_to
	return {"action": "bet" if s["is_bet"] else "raise", "amount": amount}


## Aposta ou aumenta uma fração do pote (contando o pagamento da aposta atual).
static func raise_pot(s: Dictionary, fraction: float) -> Dictionary:
	var pot_after_call: int = int(s["pot"]) + int(s["to_call"])
	return raise_to(s, int(s["current_bet"]) + int(pot_after_call * fraction))


static func all_in(s: Dictionary) -> Dictionary:
	if not s["can_raise"]:
		return pay(s)
	return {"action": "bet" if s["is_bet"] else "raise", "amount": int(s["max_to"])}


## Garante que a jogada escolhida é válida; na dúvida, passa ou desiste.
static func sanitize(s: Dictionary, choice: Dictionary) -> Dictionary:
	match str(choice.get("action", "")):
		"fold":
			return check_or_fold(s)
		"check", "call":
			return pay(s) if choice["action"] == "call" else check_or_fold(s)
		"bet", "raise":
			if not s["can_raise"]:
				return pay(s)
			var amount: int = clampi(int(choice.get("amount", 0)), int(s["min_to"]), int(s["max_to"]))
			return {"action": "bet" if s["is_bet"] else "raise", "amount": amount}
	return check_or_fold(s)


## A aposta que tenho de pagar, como fração do pote antes dela.
static func bet_fraction(s: Dictionary) -> float:
	var before: int = int(s["pot"]) - int(s["to_call"])
	return float(s["to_call"]) / maxf(1.0, float(before))


## O preço de pagar: a parte do pote final que sai do meu bolso.
static func pot_odds(s: Dictionary) -> float:
	var to_call: int = s["to_call"]
	return float(to_call) / maxf(1.0, float(int(s["pot"]) + to_call))
