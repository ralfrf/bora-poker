extends RefCounted
## Estimativa de chances por simulação (Monte Carlo), usada pelo bot Difícil (SPEC 7).
##
## Só conhece o que o bot vê: as próprias cartas e a mesa. As cartas dos adversários e
## as que faltam sair são sorteadas a cada iteração.

const HandEvaluator := preload("res://engine/hand_evaluator.gd")


## Chance de levar o pote (um empate conta a fração) com as cartas `hero` e a mesa
## `board` contra `opponents` adversários com mãos ao acaso.
##
## extra: quantas mãos a mais o primeiro adversário recebe, ficando com a melhor delas.
## Serve para representar quem apostou: a mão dele costuma ser melhor que uma ao acaso,
## e tanto melhor quanto maior a aposta.
static func estimate(hero: Array, board: Array, opponents: int, iterations: int,
		rng: RandomNumberGenerator, extra: int = 0) -> float:
	if iterations <= 0 or opponents <= 0 or hero.size() != 2 or board.size() > 5:
		return 0.5
	var used: Dictionary = {}
	for card: int in hero:
		used[card] = true
	for card: int in board:
		used[card] = true
	var deck: Array[int] = []
	for card in 52:
		if not used.has(card):
			deck.append(card)

	var known: int = board.size()
	var missing: int = 5 - known
	var more: int = clampi(extra, 0, 4)
	var need: int = missing + 2 * (opponents + more)
	var last: int = deck.size() - 1
	var mine: Array[int] = [hero[0], hero[1], 0, 0, 0, 0, 0]
	var theirs: Array[int] = [0, 0, 0, 0, 0, 0, 0]
	for i in known:
		mine[2 + i] = board[i]
		theirs[2 + i] = board[i]

	var total: float = 0.0
	for _iteration in iterations:
		# Sorteia só as cartas que esta iteração usa (Fisher-Yates parcial).
		for i in need:
			var j: int = rng.randi_range(i, last)
			var swap: int = deck[i]
			deck[i] = deck[j]
			deck[j] = swap
		for i in missing:
			mine[2 + known + i] = deck[i]
			theirs[2 + known + i] = deck[i]
		var my_score: int = HandEvaluator.score(mine)
		var tied: int = 1
		var lost: bool = false
		var pos: int = missing
		for opponent in opponents:
			theirs[0] = deck[pos]
			theirs[1] = deck[pos + 1]
			pos += 2
			var score: int = HandEvaluator.score(theirs)
			if opponent == 0:
				for _more in more:
					theirs[0] = deck[pos]
					theirs[1] = deck[pos + 1]
					pos += 2
					score = maxi(score, HandEvaluator.score(theirs))
			if score > my_score:
				lost = true
				break
			if score == my_score:
				tied += 1
		if not lost:
			total += 1.0 / tied
	return total / iterations
