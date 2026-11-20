extends RefCounted
## Uma mão de Texas Hold'em No-Limit, dos blinds ao pagamento dos potes (SPEC 3.2 e 3.3).
##
## Puro: não conhece tela, rede nem relógio. O estado inteiro cabe em um dicionário
## (to_dict / load_dict), o que serve aos testes e à gravação no celular do anfitrião.
##
## Valores sempre em centavos inteiros. Em apostar e aumentar, o valor é o total do
## jogador na rodada ("aumentar para"). All-in é a mesma ação com todas as fichas.
## Uma ação inválida nunca muda o estado: a resposta vem com "ok" falso e o motivo.

const Deck := preload("res://engine/deck.gd")
const HandEvaluator := preload("res://engine/hand_evaluator.gd")
const Pots := preload("res://engine/pots.gd")
const Positions := preload("res://engine/positions.gd")
const Serial := preload("res://engine/serial.gd")

const PREFLOP: int = 0
const FLOP: int = 1
const TURN: int = 2
const RIVER: int = 3
const FINISHED: int = 4
const STREET_NAMES: Array[String] = ["preflop", "flop", "turn", "river", "fim"]

const FOLD: String = "fold"
const CHECK: String = "check"
const CALL: String = "call"
const BET: String = "bet"
const RAISE: String = "raise"

const MAX_PLAYERS: int = 10
const STATE_VERSION: int = 1
const STATE_SCHEMA: Dictionary = {
	"v": TYPE_INT, "players": TYPE_ARRAY, "button": TYPE_INT, "small_blind_seat": TYPE_INT,
	"big_blind_seat": TYPE_INT, "small_blind": TYPE_INT, "big_blind": TYPE_INT,
	"street": TYPE_INT, "board": TYPE_ARRAY, "current_bet": TYPE_INT, "min_raise": TYPE_INT,
	"to_act": TYPE_INT, "started": TYPE_BOOL, "finished": TYPE_BOOL, "cancelled": TYPE_BOOL,
	"revealed": TYPE_BOOL, "result": TYPE_DICTIONARY, "deck": TYPE_ARRAY,
	"deck_pos": TYPE_INT,
}
const PLAYER_SCHEMA: Dictionary = {
	"seat": TYPE_INT, "stack": TYPE_INT, "start_stack": TYPE_INT, "bet": TYPE_INT,
	"total": TYPE_INT, "folded": TYPE_BOOL, "all_in": TYPE_BOOL, "seen_bet": TYPE_INT,
	"cards": TYPE_ARRAY,
}


class Player:
	extends RefCounted

	var seat: int = 0
	var stack: int = 0
	var start_stack: int = 0
	var bet: int = 0          ## posto na rodada atual
	var total: int = 0        ## posto na mão inteira e ainda no pote
	var folded: bool = false
	var all_in: bool = false
	## Maior aposta da rodada quando agiu pela última vez; -1 = ainda não agiu na rodada.
	## Quem já respondeu à aposta atual tem seen_bet igual a current_bet.
	var seen_bet: int = -1
	var cards: Array[int] = []


var players: Array[Player] = []   ## quem participa da mão, em ordem de lugar
var button: int = -1
var small_blind_seat: int = -1
var big_blind_seat: int = -1
var small_blind: int = 0
var big_blind: int = 0
var street: int = PREFLOP
var board: Array[int] = []
var current_bet: int = 0          ## maior aposta da rodada (no pré-flop começa no big blind)
var min_raise: int = 0            ## tamanho do último aumento completo da rodada
var to_act: int = -1              ## lugar de quem tem a vez; -1 se ninguém
var started: bool = false
var finished: bool = false
var cancelled: bool = false
var revealed: bool = false        ## showdown de all-in: as cartas foram abertas
var aggressor: int = -1           ## quem apostou ou aumentou por último na rodada; -1 se ninguém
var result: Dictionary = {}
var load_error: String = ""       ## por que o último load_dict falhou
var _deck: Array[int] = []
var _deck_pos: int = 0


## Começa a mão. params:
##   seats: [{seat, stack}]  quem participa (2 ou mais, todos com fichas)
##   button: lugar do botão (um dos participantes)
##   small_blind, big_blind: em centavos
##   seed: semente do baralho — ou deck: as cartas na ordem em que saem
## Devolve {ok, error, events}.
func start(params: Dictionary) -> Dictionary:
	if started:
		return _error("a mão já começou")
	var problem: String = _check_start(params)
	if problem != "":
		return _error(problem)

	for entry: Dictionary in params["seats"]:
		var player: Player = Player.new()
		player.seat = entry["seat"]
		player.stack = entry["stack"]
		player.start_stack = player.stack
		players.append(player)
	players.sort_custom(func(a: Player, b: Player) -> bool: return a.seat < b.seat)
	button = params["button"]
	small_blind = params["small_blind"]
	big_blind = params["big_blind"]
	if params.has("deck"):
		_deck.assign(params["deck"])
	else:
		_deck = Deck.shuffled(params["seed"])

	var events: Array[Dictionary] = []
	var seats: Array[int] = seat_list()
	small_blind_seat = Positions.small_blind_seat(seats, button)
	big_blind_seat = Positions.big_blind_seat(seats, button)
	_post_blind(small_blind_seat, small_blind, "small", events)
	_post_blind(big_blind_seat, big_blind, "big", events)
	current_bet = big_blind
	min_raise = big_blind

	# Duas cartas fechadas para cada um, uma por vez, a partir da esquerda do botão.
	var deal_order: Array[int] = Positions.order_after(seats, button)
	for _round in 2:
		for seat in deal_order:
			player_at(seat).cards.append(_draw())
	events.append({"type": "deal"})

	started = true
	street = PREFLOP
	_advance(big_blind_seat + 1, events)
	return _ok(events)


## O que o jogador da vez pode fazer:
##   seat, can_check, call (fichas a pôr para pagar; 0 se pode passar),
##   can_raise, is_bet (verdadeiro: "Apostar"; falso: "Aumentar"),
##   min_to e max_to (total na rodada; max_to é o all-in).
## Dicionário vazio se ninguém tem a vez.
func legal_actions() -> Dictionary:
	if finished or to_act < 0:
		return {}
	var player: Player = player_at(to_act)
	var to_call: int = maxi(0, _call_target(player) - player.bet)
	var max_to: int = player.bet + player.stack
	# Só aumenta quem tem fichas além do pagamento, tem alguém que possa responder e
	# está com a aposta aberta: ainda não agiu na rodada, ou os aumentos desde a sua
	# última ação somam um aumento mínimo completo (all-in incompleto não reabre).
	var can_raise: bool = (
		_able_count() > 1
		and player.stack > to_call
		and (player.seen_bet < 0 or current_bet - player.seen_bet >= min_raise))
	return {
		"seat": player.seat,
		"can_check": to_call == 0,
		"call": mini(to_call, player.stack),
		"can_raise": can_raise,
		"is_bet": current_bet == 0,
		"min_to": mini(current_bet + min_raise, max_to) if can_raise else 0,
		"max_to": max_to if can_raise else 0,
	}


## Aplica a ação do jogador da vez. amount só vale para BET e RAISE.
## Devolve {ok, error, events}.
func apply_action(seat: int, action: String, amount: int = 0) -> Dictionary:
	if not started or finished:
		return _error("não há mão em andamento")
	if seat != to_act:
		return _error("não é a vez desse lugar")
	var legal: Dictionary = legal_actions()
	var player: Player = player_at(seat)
	var paid: int = 0
	match action:
		FOLD:
			player.folded = true
		CHECK:
			if not legal["can_check"]:
				return _error("há aposta a pagar")
		CALL:
			if legal["can_check"]:
				return _error("não há aposta a pagar")
			paid = legal["call"]
			_commit(player, paid)
		BET, RAISE:
			if not legal["can_raise"]:
				return _error("não pode apostar nem aumentar agora")
			if (action == BET) != bool(legal["is_bet"]):
				return _error("use apostar sem aposta na rodada e aumentar quando há")
			var min_to: int = legal["min_to"]
			var max_to: int = legal["max_to"]
			if amount < min_to or amount > max_to:
				return _error("valor fora do permitido")
			paid = amount - player.bet
			var increase: int = amount - current_bet
			_commit(player, paid)
			if increase >= min_raise:
				min_raise = increase
			current_bet = amount
			aggressor = seat
		_:
			return _error("ação desconhecida")
	player.seen_bet = current_bet

	var events: Array[Dictionary] = [{
		"type": "action", "seat": seat, "action": action, "amount": paid,
		"to": player.bet, "all_in": player.all_in,
	}]
	_advance(seat + 1, events)
	return _ok(events)


## Mostrar as cartas por escolha, depois do fim da mão (como nos sites de poker; pedidos
## do dono, 17/11/2026): quem levou o pote porque todos desistiram e quem chegou ao
## showdown e teve a mão perdedora escondida. Uma vez só; quem desistiu não mostra.
## Devolve {ok, error, events}; o evento "show" leva as cartas para todos.
func show_cards(seat: int) -> Dictionary:
	var player: Player = player_at(seat)
	if not finished or cancelled or player == null or player.folded:
		return _error("não há cartas para mostrar")
	if not bool(result.get("showdown", false)):
		var payouts: Array = result.get("payouts", [])
		if payouts.size() != 1 or int(payouts[0]["seat"]) != seat:
			return _error("não há cartas para mostrar")
	for entry: Dictionary in result.get("shown", []):
		if int(entry["seat"]) == seat:
			return _error("as cartas já foram mostradas")
	var shown: Dictionary = {"seat": seat, "cards": player.cards.duplicate(), "score": 0,
		"name": "", "best": []}
	# Com o flop na mesa já há uma mão de 5 cartas para dar nome.
	if board.size() >= 3:
		var seven: Array[int] = _seven(player)
		shown["score"] = HandEvaluator.score(seven)
		shown["name"] = HandEvaluator.category_name(shown["score"])
		shown["best"] = HandEvaluator.best_five(seven)
	(result["shown"] as Array).append(shown)
	var events: Array[Dictionary] = [{"type": "show", "seat": seat,
		"cards": (shown["cards"] as Array).duplicate(), "name": shown["name"],
		"best": (shown["best"] as Array).duplicate()}]
	return _ok(events)


## Cancela a mão e devolve a cada um o que tinha posto (SPEC 6.6).
func cancel() -> Dictionary:
	if not started or finished:
		return _error("não há mão em andamento")
	var refunds: Array[Dictionary] = []
	for player in players:
		if player.total > 0:
			refunds.append({"seat": player.seat, "amount": player.total})
		player.stack += player.total
		player.total = 0
		player.bet = 0
	to_act = -1
	street = FINISHED
	finished = true
	cancelled = true
	result = {"cancelled": true, "refunds": refunds}
	var events: Array[Dictionary] = [{"type": "cancel", "refunds": refunds}]
	return _ok(events)


func player_at(seat: int) -> Player:
	for player in players:
		if player.seat == seat:
			return player
	return null


func seat_list() -> Array[int]:
	var seats: Array[int] = []
	for player in players:
		seats.append(player.seat)
	return seats


## Fichas postas na mão que ainda estão na mesa (apostas e potes).
func committed() -> int:
	var sum: int = 0
	for player in players:
		sum += player.total
	return sum


## Potes como estão agora, do principal para os paralelos: [{amount, eligible}].
func current_pots() -> Array[Dictionary]:
	return Pots.build(_pot_entries())


## Estado completo da mão. Traz as cartas fechadas de todos e o baralho: é para gravar
## no próprio servidor (ou no celular do anfitrião), nunca para enviar a um jogador.
func to_dict() -> Dictionary:
	var player_list: Array = []
	for player in players:
		player_list.append({
			"seat": player.seat, "stack": player.stack, "start_stack": player.start_stack,
			"bet": player.bet, "total": player.total, "folded": player.folded,
			"all_in": player.all_in, "seen_bet": player.seen_bet,
			"cards": player.cards.duplicate(),
		})
	return {
		"v": STATE_VERSION,
		"players": player_list,
		"button": button,
		"small_blind_seat": small_blind_seat,
		"big_blind_seat": big_blind_seat,
		"small_blind": small_blind,
		"big_blind": big_blind,
		"street": street,
		"board": board.duplicate(),
		"current_bet": current_bet,
		"min_raise": min_raise,
		"to_act": to_act,
		"started": started,
		"finished": finished,
		"cancelled": cancelled,
		"revealed": revealed,
		"aggressor": aggressor,
		"result": result.duplicate(true),
		"deck": _deck.duplicate(),
		"deck_pos": _deck_pos,
	}


## Restaura um estado gravado por to_dict (inclusive depois de passar por JSON).
## Devolve verdadeiro se deu certo. Se não, o motivo fica em load_error e a mão não muda.
func load_dict(saved: Dictionary) -> bool:
	# O valor padrão é a falha: se a leitura parar no meio, ninguém a toma por sucesso.
	load_error = "erro ao ler o estado da mão"
	var problem: String = _load(saved)
	load_error = problem
	return problem == ""


## Confere o estado inteiro antes de mexer em qualquer campo.
func _load(saved: Dictionary) -> String:
	var data: Dictionary = Serial.ints(saved)
	if not Serial.matches(data, STATE_SCHEMA):
		return "estado da mão incompleto ou com tipo errado"
	if data["v"] != STATE_VERSION:
		return "versão do estado da mão desconhecida"
	if not data["started"]:
		return "a mão gravada não tinha começado"
	var entries: Array = data["players"]
	if entries.size() < 2 or entries.size() > MAX_PLAYERS:
		return "número de jogadores inválido"

	var loaded: Array[Player] = []
	var by_seat: Dictionary = {}
	var dealt: Array = []
	dealt.append_array(data["board"])
	for entry: Variant in entries:
		if not Serial.matches(entry, PLAYER_SCHEMA):
			return "jogador incompleto ou com tipo errado"
		if entry["seat"] < 0 or by_seat.has(entry["seat"]):
			return "lugar repetido ou negativo"
		if (entry["stack"] < 0 or entry["start_stack"] < 0 or entry["bet"] < 0
				or entry["total"] < entry["bet"]):
			return "fichas inválidas"
		if entry["cards"].size() != 2:
			return "cartas inválidas"
		dealt.append_array(entry["cards"])
		var player: Player = Player.new()
		player.seat = entry["seat"]
		player.stack = entry["stack"]
		player.start_stack = entry["start_stack"]
		player.bet = entry["bet"]
		player.total = entry["total"]
		player.folded = entry["folded"]
		player.all_in = entry["all_in"]
		player.seen_bet = entry["seen_bet"]
		player.cards.assign(entry["cards"])
		by_seat[player.seat] = player
		loaded.append(player)
	loaded.sort_custom(func(a: Player, b: Player) -> bool: return a.seat < b.seat)

	var saved_board: Array = data["board"]
	var saved_deck: Array = data["deck"]
	var saved_pos: int = data["deck_pos"]
	if saved_board.size() > 5 or not Deck.is_valid(dealt):
		return "cartas repetidas ou inválidas"
	if not Deck.is_valid(saved_deck) or saved_pos < 0 or saved_pos > saved_deck.size():
		return "baralho inválido"
	if data["street"] < PREFLOP or data["street"] > FINISHED:
		return "rodada inválida"
	if data["finished"] != (data["street"] == FINISHED):
		return "rodada e fim da mão não combinam"
	for key: String in ["button", "small_blind_seat", "big_blind_seat"]:
		if not by_seat.has(data[key]):
			return "botão ou blinds fora da mão"
	if (data["small_blind"] < 1 or data["big_blind"] < data["small_blind"]
			or data["current_bet"] < 0 or data["min_raise"] < 1):
		return "valores de aposta inválidos"
	# Campo novo (17/11/2026): estados gravados antes dele não o têm.
	var saved_aggressor: int = -1
	if data.has("aggressor"):
		if typeof(data["aggressor"]) != TYPE_INT 				or (data["aggressor"] != -1 and not by_seat.has(data["aggressor"])):
			return "quem apostou por último está fora da mão"
		saved_aggressor = data["aggressor"]
	if data["finished"]:
		if data["to_act"] != -1:
			return "mão encerrada com alguém na vez"
	else:
		var actor: Player = by_seat.get(data["to_act"])
		if actor == null or actor.folded or actor.all_in:
			return "a vez não é de quem pode agir"
		if saved_deck.size() - saved_pos < 5 - saved_board.size():
			return "baralho curto para terminar a mão"

	players = loaded
	button = data["button"]
	small_blind_seat = data["small_blind_seat"]
	big_blind_seat = data["big_blind_seat"]
	small_blind = data["small_blind"]
	big_blind = data["big_blind"]
	street = data["street"]
	board.assign(data["board"])
	current_bet = data["current_bet"]
	min_raise = data["min_raise"]
	to_act = data["to_act"]
	started = data["started"]
	finished = data["finished"]
	cancelled = data["cancelled"]
	revealed = data["revealed"]
	aggressor = saved_aggressor
	result = data["result"]
	_deck.assign(data["deck"])
	_deck_pos = data["deck_pos"]
	return ""


func _check_start(params: Dictionary) -> String:
	if not Serial.has_keys(params, ["seats", "button", "small_blind", "big_blind"]):
		return "faltam dados para começar a mão"
	if typeof(params["seats"]) != TYPE_ARRAY:
		return "lista de lugares inválida"
	var entries: Array = params["seats"]
	if entries.size() < 2 or entries.size() > MAX_PLAYERS:
		return "a mão precisa de 2 a %d jogadores" % MAX_PLAYERS
	var seen: Dictionary = {}
	for entry: Variant in entries:
		if typeof(entry) != TYPE_DICTIONARY or not Serial.has_keys(entry, ["seat", "stack"]):
			return "lugar inválido"
		if typeof(entry["seat"]) != TYPE_INT or typeof(entry["stack"]) != TYPE_INT:
			return "lugar e fichas precisam ser inteiros"
		if entry["seat"] < 0 or seen.has(entry["seat"]):
			return "lugar repetido ou negativo"
		if entry["stack"] <= 0:
			return "todo participante precisa ter fichas"
		seen[entry["seat"]] = true
	if typeof(params["button"]) != TYPE_INT or not seen.has(params["button"]):
		return "o botão precisa estar com um participante"
	if typeof(params["small_blind"]) != TYPE_INT or typeof(params["big_blind"]) != TYPE_INT:
		return "os blinds precisam ser inteiros"
	if params["small_blind"] < 1 or params["big_blind"] < params["small_blind"]:
		return "blinds inválidos"
	if params.has("deck"):
		if typeof(params["deck"]) != TYPE_ARRAY:
			return "baralho inválido"
		var cards: Array = params["deck"]
		if cards.size() < entries.size() * 2 + 5 or not Deck.is_valid(cards):
			return "baralho inválido"
	elif not params.has("seed") or typeof(params["seed"]) != TYPE_INT:
		return "falta a semente do baralho"
	return ""


func _post_blind(seat: int, blind: int, kind: String, events: Array[Dictionary]) -> void:
	var player: Player = player_at(seat)
	var amount: int = mini(blind, player.stack)
	_commit(player, amount)
	events.append({
		"type": "blind", "kind": kind, "seat": seat, "amount": amount,
		"all_in": player.all_in,
	})


func _commit(player: Player, chips: int) -> void:
	player.stack -= chips
	player.bet += chips
	player.total += chips
	if player.stack == 0:
		player.all_in = true


func _draw() -> int:
	var card: int = _deck[_deck_pos]
	_deck_pos += 1
	return card


## Segue a mão depois de uma ação: acha quem fala a seguir ou fecha a rodada.
func _advance(from_seat: int, events: Array[Dictionary]) -> void:
	if _live_count() == 1:
		to_act = -1
		_settle(false, events, _refund_uncalled(events))
		return
	var next: int = _next_to_act(from_seat)
	if next != -1:
		to_act = next
		return
	_close_round(events)


func _close_round(events: Array[Dictionary]) -> void:
	to_act = -1
	_refund_uncalled(events)
	for player in players:
		player.bet = 0
		player.seen_bet = -1
	current_bet = 0
	min_raise = big_blind

	if _able_count() <= 1:
		# All-in sem mais apostas possíveis: abre as cartas e solta o resto da mesa.
		revealed = true
		var hands: Array[Dictionary] = []
		for player in players:
			if not player.folded:
				hands.append({"seat": player.seat, "cards": player.cards.duplicate()})
		events.append({"type": "reveal", "hands": hands})
		while street < RIVER:
			_deal_street(events)
		_settle(true, events)
		return
	if street == RIVER:
		_settle(true, events)
		return
	_deal_street(events)
	to_act = _next_to_act(button + 1)


func _deal_street(events: Array[Dictionary]) -> void:
	street += 1
	aggressor = -1
	var cards: Array[int] = []
	for i in (3 if street == FLOP else 1):
		cards.append(_draw())
	board.append_array(cards)
	events.append({"type": "street", "street": STREET_NAMES[street], "cards": cards})


## Devolve a quem apostou a parte que ninguém pagou. Devolve {seat, amount} (vazio sem devolução).
func _refund_uncalled(events: Array[Dictionary]) -> Dictionary:
	var bets: Array[Dictionary] = []
	for player in players:
		bets.append({"seat": player.seat, "amount": player.bet, "folded": player.folded})
	var refund: Dictionary = Pots.uncalled(bets)
	var amount: int = refund["amount"]
	if amount <= 0:
		return {}
	var owner: Player = player_at(refund["seat"])
	owner.bet -= amount
	owner.total -= amount
	owner.stack += amount
	owner.all_in = false
	events.append({"type": "refund", "seat": owner.seat, "amount": amount})
	return {"seat": owner.seat, "amount": amount}


## Paga os potes e encerra a mão. returned: a aposta não paga devolvida a quem ficou
## sozinho quando todos desistiram; vai no resultado para a tela dizer que ele levou
## tudo o que estava na mesa (o pote mais as próprias fichas que voltaram).
func _settle(showdown: bool, events: Array[Dictionary], returned: Dictionary = {}) -> void:
	var scores: Dictionary = {}
	for player in players:
		if not player.folded:
			scores[player.seat] = HandEvaluator.score(_seven(player)) if showdown else 0
	var order: Array[int] = Positions.order_after(seat_list(), button)
	var pots: Array[Dictionary] = Pots.distribute(Pots.build(_pot_entries()), scores, order)

	var won: Dictionary = {}
	for pot in pots:
		for share: Dictionary in pot["shares"]:
			var seat: int = share["seat"]
			won[seat] = int(won.get(seat, 0)) + int(share["amount"])

	var payouts: Array[Dictionary] = []
	var nets: Array[Dictionary] = []
	for player in players:
		var amount: int = won.get(player.seat, 0)
		player.stack += amount
		player.total = 0
		player.bet = 0
		if amount > 0:
			payouts.append({"seat": player.seat, "amount": amount})
		nets.append({"seat": player.seat, "amount": player.stack - player.start_stack})

	var shown: Array[Dictionary] = []
	if showdown:
		for seat: int in _show_order(scores, pots):
			var player: Player = player_at(seat)
			var seven: Array[int] = _seven(player)
			var score: int = scores[seat]
			shown.append({
				"seat": seat,
				"cards": player.cards.duplicate(),
				"score": score,
				"name": HandEvaluator.category_name(score),
				"best": HandEvaluator.best_five(seven),
			})

	result = {
		"showdown": showdown,
		"board": board.duplicate(),
		"pots": pots,
		"payouts": payouts,
		"nets": nets,
		"shown": shown,
		"returned": [returned] if not returned.is_empty() else [],
	}
	to_act = -1
	street = FINISHED
	finished = true
	if showdown:
		events.append({"type": "showdown", "shown": shown})
	events.append({"type": "end", "pots": pots, "payouts": payouts,
		"returned": result["returned"].duplicate(true)})


## Quem mostra no showdown, na ordem em que mostra (como nos sites de poker, com as
## mãos perdedoras escondidas automaticamente; mudado a pedido do dono em 17/11/2026,
## antes todos mostravam). Showdown de all-in: as cartas já estão abertas e todos
## mostram. Senão, abre primeiro quem apostou ou aumentou por último na rodada final
## (sem aposta nela, o primeiro à esquerda do botão) e segue pela mesa: cada um mostra
## se a sua mão empata ou ganha da melhor já mostrada, ou se leva parte de algum pote
## disputado; senão, esconde. Quem desistiu nunca mostra.
func _show_order(scores: Dictionary, pots: Array[Dictionary]) -> Array[int]:
	var live: Array[int] = []
	for player in players:
		if not player.folded:
			live.append(player.seat)
	var first: int = aggressor if live.has(aggressor) else -1
	var order: Array[int] = []
	if first >= 0:
		order.append(first)
		for seat in Positions.order_after(live, first):
			if seat != first:
				order.append(seat)
	else:
		order = Positions.order_after(live, button)
	if revealed:
		return order
	var winners: Dictionary = {}
	for pot: Dictionary in pots:
		if (pot["eligible"] as Array).size() < 2:
			continue
		for seat: int in pot["winners"]:
			winners[seat] = true
	var shown: Array[int] = []
	var best: int = -1
	for seat in order:
		var score: int = scores[seat]
		if shown.is_empty() or score >= best or winners.has(seat):
			shown.append(seat)
			best = maxi(best, score)
	return shown


func _pot_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for player in players:
		entries.append({
			"seat": player.seat, "total": player.total, "folded": player.folded,
			"all_in": player.all_in,
		})
	return entries


func _seven(player: Player) -> Array[int]:
	var cards: Array[int] = []
	cards.append_array(player.cards)
	cards.append_array(board)
	return cards


## Quem ainda disputa o pote.
func _live_count() -> int:
	var count: int = 0
	for player in players:
		if not player.folded:
			count += 1
	return count


## Quem ainda pode agir: não desistiu e tem fichas.
func _able_count() -> int:
	var count: int = 0
	for player in players:
		if not player.folded and not player.all_in:
			count += 1
	return count


## Maior aposta da rodada entre os outros que disputam o pote.
func _others_max_bet(player: Player) -> int:
	var highest: int = 0
	for other in players:
		if other != player and not other.folded:
			highest = maxi(highest, other.bet)
	return highest


## Quanto o jogador precisa ter na rodada para pagar. Em geral é a maior aposta
## (no pré-flop, o big blind cheio, mesmo que o dono dele tenha posto menos). Quando
## todos os outros estão all-in, basta igualar o que eles puseram de fato.
func _call_target(player: Player) -> int:
	if _able_count() <= 1:
		return _others_max_bet(player)
	return current_bet


func _needs_action(player: Player) -> bool:
	if player.folded or player.all_in:
		return false
	if _able_count() <= 1:
		return player.bet < _others_max_bet(player)
	return player.seen_bet != current_bet


## Primeiro jogador que precisa agir, a partir do lugar dado (inclusive); -1 se nenhum.
func _next_to_act(from_seat: int) -> int:
	var count: int = players.size()
	var first: int = 0
	for i in count:
		if players[i].seat >= from_seat:
			first = i
			break
	for step in count:
		var player: Player = players[(first + step) % count]
		if _needs_action(player):
			return player.seat
	return -1


func _ok(events: Array[Dictionary]) -> Dictionary:
	return {"ok": true, "error": "", "events": events}


func _error(message: String) -> Dictionary:
	var events: Array[Dictionary] = []
	return {"ok": false, "error": message, "events": events}
