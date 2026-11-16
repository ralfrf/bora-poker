extends RefCounted
## Força da mão depois do flop, por regra simples e sem simulação. É o que os bots
## Fácil e Médio usam; o Difícil usa para reconhecer projetos (SPEC 7).

const HandEvaluator := preload("res://engine/hand_evaluator.gd")


## Força da mão feita, de 0 a 1, olhando as cartas do jogador e a mesa (3 a 5 cartas).
## Referências: 0,15 nada · 0,40 par baixo · 0,50 par do meio · 0,64 a 0,74 par mais
## alto · 0,76 a 0,82 par na mão acima da mesa · 0,83 dois pares · 0,88 trinca · 0,90
## sequência · 0,93 flush · 0,97 full house · 0,99 quadra ou mais.
static func made(cards: Array, board: Array) -> float:
	var all: Array = []
	all.append_array(cards)
	all.append_array(board)
	var score: int = HandEvaluator.score(all)
	var board_score: int = HandEvaluator.score(board)
	var category: int = score >> 20
	var board_category: int = board_score >> 20
	var high: int = maxi(cards[0] >> 2, cards[1] >> 2) + 2
	var low: int = mini(cards[0] >> 2, cards[1] >> 2) + 2

	if category >= HandEvaluator.STRAIGHT:
		if category == board_category:
			# A mesa já faz o jogo sozinha: só vale mais se as minhas cartas melhoram.
			return 0.62 if score > board_score else 0.45
		match category:
			HandEvaluator.STRAIGHT:
				return 0.90
			HandEvaluator.FLUSH:
				return 0.93
			HandEvaluator.FULL_HOUSE:
				return 0.97
		return 0.99
	if category == HandEvaluator.TRIPS:
		if board_category == HandEvaluator.TRIPS:
			return 0.40 if high == 14 else 0.30
		return 0.88
	if category == HandEvaluator.TWO_PAIR:
		if board_category == HandEvaluator.TWO_PAIR:
			return 0.32 if high == 14 else 0.25
		if board_category == HandEvaluator.PAIR:
			# Um par meu mais o par da mesa: vale como um par, um pouco menos.
			return _one_pair(cards, board, high, low) - 0.03
		return 0.83
	if category == HandEvaluator.PAIR:
		if board_category == HandEvaluator.PAIR:
			return 0.27 if high == 14 else 0.18
		return _one_pair(cards, board, high, low)
	# Nada: carta alta.
	var top: int = _board_ranks(board)[0]
	if low > top:
		return 0.27
	if high == 14:
		return 0.24
	return 0.20 if high > top else 0.15


## Cartas que completam um projeto: 9 para quatro cartas do mesmo naipe, 8 para
## sequência aberta dos dois lados, 4 para sequência por dentro (somam até 15).
## Só conta o projeto que usa uma carta do jogador. No river é sempre 0.
static func outs(cards: Array, board: Array) -> int:
	if board.size() < 3 or board.size() >= 5:
		return 0
	var total: int = 0
	# Flush.
	for suit in 4:
		var mine: int = 0
		var count: int = 0
		for card: int in cards:
			if (card & 3) == suit:
				mine += 1
		for card: int in board:
			if (card & 3) == suit:
				count += 1
		if mine > 0 and mine + count == 4:
			total += 9
	# Sequência: valores que, chegando, fecham uma sequência que a mesa sozinha não fecha.
	var all_mask: int = _rank_mask(cards) | _rank_mask(board)
	var board_mask: int = _rank_mask(board)
	if HandEvaluator._straight_high(all_mask) == 0:
		var completing: int = 0
		for rank in range(2, 15):
			var bit: int = 1 << rank
			if (all_mask & bit) != 0:
				continue
			if (HandEvaluator._straight_high(all_mask | bit) > 0
					and HandEvaluator._straight_high(board_mask | bit) == 0):
				completing += 1
		total += mini(completing, 2) * 4
	return mini(total, 15)


## Chance aproximada de completar o projeto: cerca de 2% por carta que serve, para cada
## carta que ainda vai sair.
static func draw_equity(out_count: int, board_size: int) -> float:
	return minf(0.6, out_count * 0.021 * maxi(0, 5 - board_size))


static func _one_pair(cards: Array, board: Array, high: int, low: int) -> float:
	var ranks: Array[int] = _board_ranks(board)
	var top: int = ranks[0]
	var pocket: bool = high == low
	var pair_rank: int = high
	var kicker: int = low
	if not pocket:
		# Qual das minhas cartas fez o par com a mesa?
		if ranks.has(high):
			pair_rank = high
			kicker = low
		else:
			pair_rank = low
			kicker = high
	if pair_rank > top:
		return 0.76 + clampf((pair_rank - 8) * 0.01, 0.0, 0.06)
	if pair_rank == top:
		return 0.64 + (kicker - 2) / 12.0 * 0.10
	var second: int = top
	for rank in ranks:
		if rank < top:
			second = rank
			break
	return 0.50 if pair_rank >= second else 0.40


## Valores da mesa, do maior para o menor.
static func _board_ranks(board: Array) -> Array[int]:
	var ranks: Array[int] = []
	for card: int in board:
		ranks.append((card >> 2) + 2)
	ranks.sort()
	ranks.reverse()
	return ranks


static func _rank_mask(cards: Array) -> int:
	var mask: int = 0
	for card: int in cards:
		mask |= 1 << ((card >> 2) + 2)
	return mask
