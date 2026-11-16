extends RefCounted
## Simulação com ações aleatórias válidas (SPEC 13): partidas clássicas com recompra,
## entradas e saídas, e torneios até o fim.
##
## Depois de cada ação confere a igualdade da caixa de fichas (SPEC 8.1) e que a mesa
## não travou. De vez em quando salva e restaura a mesa no meio da mão, tenta uma ação
## inválida (que precisa ser recusada sem mudar nada) ou cancela a mão.

const Table := preload("res://engine/table.gd")
const Hand := preload("res://engine/hand.gd")
const HandEvaluator := preload("res://engine/hand_evaluator.gd")
const Deck := preload("res://engine/deck.gd")

const MAX_ACTIONS_PER_HAND: int = 300
const MAX_TOURNAMENT_HANDS: int = 3000
const MAX_ERRORS: int = 10
const STACKS: Array[int] = [2000, 2000, 1000, 537, 73, 20001, 45]
const BIG_BLINDS: Array[int] = [20, 20, 2, 13, 50, 100, 7]
const TOURNAMENT_STACKS: Array[int] = [2000, 2000, 1500, 333, 5000]
const LEVEL_MINUTES: Array[int] = [3, 5, 8, 10]

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _table: Table = null
var _errors: Array[String] = []
var _context: String = ""
var _checks: int = 0
var _hands: int = 0
var _actions: int = 0
var _classics: int = 0
var _tournaments: int = 0
var _showdowns: int = 0
var _side_pots: int = 0
var _splits: int = 0
var _rebuys: int = 0
var _leaves: int = 0
var _returns: int = 0
var _expirations: int = 0
var _cancels: int = 0
var _restores: int = 0
var _refusals: int = 0


## Devolve {errors, checks, line}.
func run(hands_target: int, seed_value: int) -> Dictionary:
	_rng.seed = seed_value
	var game: int = 0
	while _hands < hands_target and _errors.size() < MAX_ERRORS:
		_context = "semente %d, partida %d" % [seed_value, game]
		if game % 3 == 2:
			_play_tournament()
		else:
			_play_classic()
		game += 1
	var line: String = (
		"Simulação: %d mãos, %d ações, %d partidas clássicas, %d torneios | "
		+ "showdowns %d, potes paralelos %d, empates %d, cancelamentos %d | "
		+ "recompras %d, saídas %d, voltas %d, prazos vencidos %d | "
		+ "estados restaurados %d, ações inválidas recusadas %d | "
		+ "caixa de fichas conferida após cada ação") % [
			_hands, _actions, _classics, _tournaments, _showdowns, _side_pots, _splits,
			_cancels, _rebuys, _leaves, _returns, _expirations, _restores, _refusals]
	return {"errors": _errors, "checks": _checks, "hands": _hands, "line": line}


func _play_classic() -> void:
	_classics += 1
	_table = Table.new()
	var big: int = _pick(BIG_BLINDS)
	@warning_ignore("integer_division")
	var small: int = maxi(1, big / 2)
	_expect(_table.configure({
		"format": Table.CLASSIC, "starting_stack": _pick(STACKS), "small_blind": small,
		"big_blind": big, "rebuy_limit": _pick(Table.REBUY_LIMITS)}) == "", "opções aceitas")
	var next_id: int = _seat_players(_rng.randi_range(2, 8))

	for i in _rng.randi_range(5, 40):
		if not _table.can_start_hand() or _errors.size() >= MAX_ERRORS:
			break
		_play_hand({"seed": _rng.randi()})
		# Entre uma mão e outra: recompras, saídas, entradas e mudança de blinds.
		for seat in _table.seats.duplicate():
			if seat.state != Table.BUSTED:
				continue
			if _rng.randf() < 0.75:
				_expect(_table.rebuy(seat.index) == "", "recompra aceita")
				_rebuys += 1
			else:
				_expect(_table.decline_rebuy(seat.index) == "", "recusa da recompra aceita")
		_returns_and_deadlines()
		if _rng.randf() < 0.10:
			var playing: Array[int] = _table.participants()
			if not playing.is_empty():
				_expect(_table.remove_player(_pick(playing)) == "", "saída aceita")
				_leaves += 1
		if _rng.randf() < 0.08:
			var free: int = _free_index()
			if free >= 0:
				_expect(_table.add_player(free, "j%d" % next_id) == "", "entrada aceita")
				next_id += 1
		if _rng.randf() < 0.05:
			var new_big: int = _pick(BIG_BLINDS)
			@warning_ignore("integer_division")
			_expect(_table.set_blinds(maxi(1, new_big / 2), new_big) == "", "blinds aceitos")
		_check_table("entre mãos")
		_check_scoreboard()
	_check_scoreboard()


## Quem saiu da mesa: às vezes volta (com as fichas de antes ou com as iniciais), às
## vezes o prazo de volta vence e as fichas guardadas viram saída.
func _returns_and_deadlines() -> void:
	for seat in _table.seats.duplicate():
		if seat.state != Table.OUT:
			continue
		var held: int = _table.cashbox.held(seat.id)
		var roll: float = _rng.randf()
		if held > 0 and roll < 0.25:
			_expect(_table.expire_held(seat.id) == "", "prazo vencido aceito")
			_expirations += 1
		elif roll < 0.55:
			var free: int = _free_index()
			if free < 0:
				continue
			var keep_chips: bool = held > 0 and _rng.randf() < 0.5
			var rebuys_before: int = seat.rebuys
			# A volta com as fichas iniciais pode ser recusada por falta de recompra.
			var answer: String = _table.add_player(free, seat.id, keep_chips)
			if answer == "":
				_returns += 1
				_expect(not keep_chips or _table.seat_at(free).stack == held,
					"volta com as fichas de antes")
				_expect(_table.rebuy_limit < 0 or seat.rebuys <= _table.rebuy_limit,
					"o limite de recompras é respeitado")
			else:
				_expect(not keep_chips, "a volta com as fichas de antes sempre vale")
				_expect(seat.rebuys == rebuys_before and _table.cashbox.held(seat.id) == held,
					"volta recusada não muda nada")


func _free_index() -> int:
	for index in Table.MAX_SEATS:
		if _table.seat_at(index) == null:
			return index
	return -1


func _check_scoreboard() -> void:
	var net_sum: int = 0
	for row in _table.scoreboard():
		net_sum += int(row["net"])
	_expect(net_sum == 0, "os saldos líquidos do placar somam zero")


func _play_tournament() -> void:
	_tournaments += 1
	_table = Table.new()
	var stack: int = _pick(TOURNAMENT_STACKS)
	_expect(_table.configure({
		"format": Table.TOURNAMENT, "starting_stack": stack,
		"level_minutes": _pick(LEVEL_MINUTES)}) == "", "opções aceitas")
	var players: int = _rng.randi_range(2, 8)
	_seat_players(players)

	var elapsed_ms: int = 0
	var played: int = 0
	while (_table.can_start_hand() and played < MAX_TOURNAMENT_HANDS
			and _errors.size() < MAX_ERRORS):
		var level_before: int = _table.level
		_play_hand({"seed": _rng.randi(), "elapsed_ms": elapsed_ms})
		_expect(_table.level >= level_before, "o nível de blinds nunca desce")
		elapsed_ms += _rng.randi_range(20000, 120000)
		played += 1
	if _errors.size() >= MAX_ERRORS:
		return

	_expect(_table.is_over(), "o torneio termina")
	var champions: int = 0
	for seat in _table.seats:
		_expect(seat.place >= 1 and seat.place <= players, "colocação válida")
		if seat.place == 1:
			champions += 1
			_expect(seat.stack == stack * players, "o campeão tem todas as fichas")
		else:
			_expect(seat.stack == 0, "eliminado não tem fichas")
	_expect(champions == 1, "um só campeão")
	_expect(_table.podium().size() >= mini(players, 3), "pódio completo")


## Senta `count` jogadores em lugares sorteados. Devolve o próximo número de jogador.
func _seat_players(count: int) -> int:
	var indexes: Array[int] = []
	for index in Table.MAX_SEATS:
		indexes.append(index)
	for i in range(indexes.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var swap: int = indexes[i]
		indexes[i] = indexes[j]
		indexes[j] = swap
	for i in count:
		_expect(_table.add_player(indexes[i], "j%d" % i) == "", "jogador sentado")
	return count


func _play_hand(params: Dictionary) -> void:
	var chips_before: int = _table.chips_on_seats()
	var response: Dictionary = _table.start_hand(params)
	_expect(response["ok"], "a mão começa: " + str(response["error"]))
	if not response["ok"]:
		return
	_hands += 1
	_check_table("início da mão")

	var steps: int = 0
	while _table.hand_in_progress():
		steps += 1
		if steps > MAX_ACTIONS_PER_HAND:
			_expect(false, "a mão não termina")
			_table.cancel_hand()
			return
		var roll: float = _rng.randf()
		if roll < 0.003:
			_expect(_table.cancel_hand()["ok"], "cancelamento aceito")
			_cancels += 1
			_check_table("mão cancelada")
			_expect(_table.chips_on_seats() == chips_before, "cancelar devolve as apostas")
			return
		if roll < 0.05:
			_save_and_restore()
		elif roll < 0.10:
			_try_invalid_action()
		_random_action()
		_check_table("depois da ação")
	_check_result(chips_before)


func _random_action() -> void:
	var hand: Hand = _table.hand
	var legal: Dictionary = hand.legal_actions()
	_expect(not legal.is_empty(), "alguém tem a vez")
	if legal.is_empty():
		return
	var seat: int = legal["seat"]
	var player: Hand.Player = hand.player_at(seat)
	_expect(player != null and not player.folded and not player.all_in,
		"a vez é de quem pode agir")
	_expect(int(legal["call"]) <= player.stack, "pagar cabe nas fichas")
	var can_check: bool = legal["can_check"]
	var can_raise: bool = legal["can_raise"]
	if can_raise:
		_expect(int(legal["min_to"]) <= int(legal["max_to"])
			and int(legal["min_to"]) > hand.current_bet
			and int(legal["max_to"]) == player.bet + player.stack,
			"limites do aumento coerentes")

	var action: String = Hand.CHECK if can_check else Hand.CALL
	var amount: int = 0
	var roll: float = _rng.randf()
	if roll < (0.02 if can_check else 0.2):
		action = Hand.FOLD
	elif roll >= 0.65 and can_raise:
		action = Hand.BET if legal["is_bet"] else Hand.RAISE
		amount = _raise_amount(legal, hand.big_blind)
	var response: Dictionary = _table.apply_action(seat, action, amount)
	_expect(response["ok"], "ação válida aceita (%s %d): %s" % [
		action, amount, str(response["error"])])
	_actions += 1


func _raise_amount(legal: Dictionary, big_blind: int) -> int:
	var low: int = legal["min_to"]
	var high: int = legal["max_to"]
	var roll: float = _rng.randf()
	if roll < 0.30:
		return low
	if roll < 0.42:
		return high
	if roll < 0.90:
		return low + _rng.randi_range(0, mini(high - low, 4 * big_blind))
	return _rng.randi_range(low, high)


## Uma ação inválida precisa ser recusada e não pode mudar nada.
func _try_invalid_action() -> void:
	var hand: Hand = _table.hand
	var legal: Dictionary = hand.legal_actions()
	if legal.is_empty():
		return
	var seat: int = legal["seat"]
	var raise_verb: String = Hand.BET if legal["is_bet"] else Hand.RAISE
	var wrong_verb: String = Hand.RAISE if legal["is_bet"] else Hand.BET
	var before: String = JSON.stringify(_table.to_dict())
	var response: Dictionary
	match _rng.randi_range(0, 5):
		0:  # fora da vez
			response = _table.apply_action(seat + 1, Hand.FOLD)
		1:  # passar com aposta a pagar, ou pagar sem aposta
			response = _table.apply_action(seat, Hand.CALL if legal["can_check"] else Hand.CHECK)
		2:  # acima do all-in, ou aumento sem direito
			var too_much: int = int(legal["max_to"]) + 1
			if not legal["can_raise"]:
				too_much = hand.current_bet + hand.min_raise
			response = _table.apply_action(seat, raise_verb, too_much)
		3:  # abaixo do mínimo
			response = _table.apply_action(seat, raise_verb, int(legal["min_to"]) - 1)
		4:
			response = _table.apply_action(seat, "dançar")
		_:  # verbo trocado
			response = _table.apply_action(seat, wrong_verb, int(legal["min_to"]))
	_expect(not response["ok"], "ação inválida recusada")
	_expect(JSON.stringify(_table.to_dict()) == before, "ação recusada não muda o estado")
	_refusals += 1


## Salva a mesa em JSON, restaura em outra e segue a partida na restaurada.
func _save_and_restore() -> void:
	var saved: String = JSON.stringify(_table.to_dict())
	var copy: Table = Table.new()
	var loaded: bool = copy.load_dict(JSON.parse_string(saved))
	_expect(loaded, "estado restaurado: " + copy.load_error)
	if not loaded:
		return
	_expect(JSON.stringify(copy.to_dict()) == saved, "estado restaurado igual ao salvo")
	_table = copy
	_restores += 1
	_check_scoreboard()


func _check_table(moment: String) -> void:
	_expect(_table.is_balanced(), "caixa de fichas fechada (%s)" % moment)
	for seat in _table.seats:
		_expect(seat.stack >= 0, "fichas nunca negativas")
	var hand: Hand = _table.hand
	if hand == null:
		return
	var start_sum: int = 0
	var now_sum: int = 0
	for player in hand.players:
		_expect(player.stack >= 0 and player.bet >= 0 and player.total >= player.bet,
			"valores do jogador coerentes")
		start_sum += player.start_stack
		now_sum += player.stack + player.total
	_expect(start_sum == now_sum, "fichas da mão conservadas (%s)" % moment)
	if hand.finished:
		return
	_expect(hand.to_act >= 0, "a mesa não trava: alguém tem a vez")
	var pot_sum: int = 0
	for pot in hand.current_pots():
		pot_sum += int(pot["amount"])
	_expect(pot_sum == hand.committed(), "os potes somam o que foi apostado")


func _check_result(chips_before: int) -> void:
	var hand: Hand = _table.hand
	if hand.cancelled:
		return
	_expect(hand.finished and hand.committed() == 0 and hand.to_act == -1, "mão encerrada")
	_expect(_table.chips_on_seats() == chips_before, "a mão não cria nem destrói fichas")
	var result: Dictionary = hand.result
	var showdown: bool = result["showdown"]
	var pots: Array = result["pots"]

	var dealt: Array = hand.board.duplicate()
	var scores: Dictionary = {}
	for player in hand.players:
		dealt.append_array(player.cards)
		if not player.folded:
			var seven: Array = player.cards + hand.board
			scores[player.seat] = HandEvaluator.score(seven)
	_expect(Deck.is_valid(dealt), "nenhuma carta repetida")

	for pot: Dictionary in pots:
		var eligible: Array = pot["eligible"]
		var winners: Array = pot["winners"]
		var share_sum: int = 0
		var lowest: int = -1
		var highest: int = -1
		for share: Dictionary in pot["shares"]:
			var amount: int = share["amount"]
			share_sum += amount
			lowest = amount if lowest < 0 else mini(lowest, amount)
			highest = maxi(highest, amount)
			_expect(winners.has(share["seat"]), "só ganhador recebe")
		_expect(share_sum == int(pot["amount"]), "o pote é entregue inteiro")
		_expect(highest - lowest <= 1, "divisão igual, com diferença de no máximo um centavo")
		_expect(not winners.is_empty(), "todo pote tem ganhador")
		if showdown:
			var best: int = -1
			for seat: int in eligible:
				best = maxi(best, int(scores[seat]))
			for seat: int in eligible:
				_expect(winners.has(seat) == (int(scores[seat]) == best),
					"ganha o pote a melhor mão entre os elegíveis")
		if winners.size() > 1:
			_splits += 1

	var net_sum: int = 0
	for entry: Dictionary in result["nets"]:
		net_sum += int(entry["amount"])
	_expect(net_sum == 0, "ganhos e perdas da mão somam zero")
	if showdown:
		_showdowns += 1
		_expect(hand.board.size() == 5, "showdown com as 5 cartas na mesa")
		_expect(not result["shown"].is_empty(), "alguém mostra no showdown")
	else:
		_expect(result["shown"].is_empty(), "sem showdown ninguém mostra")
	for entry: Dictionary in result["shown"]:
		_expect(not hand.player_at(entry["seat"]).folded, "quem desistiu não mostra")
	if pots.size() > 1:
		_side_pots += 1


func _pick(list: Array) -> int:
	return list[_rng.randi_range(0, list.size() - 1)]


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition or _errors.size() >= MAX_ERRORS:
		return
	var hand_number: int = _table.hand_number if _table != null else 0
	_errors.append("%s, mão %d: %s" % [_context, hand_number, message])
