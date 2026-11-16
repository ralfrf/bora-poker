extends RefCounted
## Bot Difícil (SPEC 7): estima as chances por simulação (Monte Carlo), usa a posição,
## varia o tamanho das apostas, blefa e semiblefa; com poucas fichas no torneio, joga
## no "empurra ou desiste".

const Situation := preload("res://bots/situation.gd")
const Preflop := preload("res://bots/preflop.gd")
const HandStrength := preload("res://bots/hand_strength.gd")
const Equity := preload("res://bots/equity.gd")

## Teto de processamento: mãos avaliadas por decisão, somando a do bot e as dos
## adversários em cada iteração. Com mais gente na mão, faz menos iterações. É o que
## mantém a decisão barata no 0,1 de CPU do Render.
const MAX_EVALUATIONS: int = 900
const MIN_ITERATIONS: int = 40
## Torneio: com até este número de big blinds, só empurra (all-in) ou desiste.
const PUSH_FOLD_BB: float = 10.0
## Parte das mãos com que abre o pote, conforme quantos ainda falam depois dele.
const OPEN_RANGE: Array[float] = [0.55, 0.55, 0.46, 0.34, 0.26, 0.21, 0.17, 0.15]
const OPEN_RANGE_HEADS_UP: float = 0.72
## [fichas em jogo em big blinds, parte das mãos com que paga um all-in desse tamanho].
const CALL_RANGE: Array = [
	[2.0, 0.85], [4.0, 0.62], [6.0, 0.48], [10.0, 0.32], [15.0, 0.20], [25.0, 0.11],
	[50.0, 0.06], [100.0, 0.035]]


## memory: {aggressor: lugar de quem aumentou por último antes do flop,
##          equity: estimativas já feitas nesta mão, evaluations: teto (opcional)}
static func choose(s: Dictionary, traits: Dictionary, rng: RandomNumberGenerator,
		memory: Dictionary) -> Dictionary:
	if int(s["street"]) == Situation.PREFLOP:
		return _preflop(s, traits, rng)
	return _postflop(s, traits, rng, memory)


static func _preflop(s: Dictionary, traits: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var cards: Array = s["cards"]
	var strength: float = Preflop.percentile(cards[0], cards[1])
	var loose: float = traits["loose"]
	var bb: int = maxi(1, int(s["bb"]))
	var to_call: int = s["to_call"]
	var current_bet: int = s["current_bet"]
	var stack: int = s["stack"]
	var odds: float = Situation.pot_odds(s)

	if s["tournament"] and float(stack + int(s["bet"])) / bb <= PUSH_FOLD_BB:
		return _push_or_fold(s, strength, loose, odds)

	if current_bet <= bb:
		# Ninguém aumentou ainda.
		var limped: int = maxi(0, int(s["pot"]) - bb - int(s["sb"]))
		if to_call == 0:
			if strength >= 0.80:
				return Situation.raise_to(s, 3 * bb + limped)
			return Situation.check_or_fold(s)
		var open: float = OPEN_RANGE[mini(int(s["behind"]), OPEN_RANGE.size() - 1)]
		if int(s["players"]) == 2:
			open = OPEN_RANGE_HEADS_UP
		if strength >= 1.0 - minf(0.95, open * loose):
			return Situation.raise_to(s, int(bb * rng.randf_range(2.5, 3.2)) + limped)
		if to_call * 2 <= bb and strength >= 0.30:
			return Situation.pay(s)   # completa o small blind
		return Situation.fold()

	# Aumento grande ou all-in: decide pela tabela de pagamento.
	if to_call * 5 >= stack * 2 or current_bet >= 9 * bb:
		var stake: float = float(s["effective"]) / bb
		if to_call * 5 < stack * 2:
			stake = minf(stake, 2.5 * current_bet / bb)
		if strength >= 1.0 - _call_range(stake, odds):
			if strength >= 0.97:
				return Situation.all_in(s)
			return Situation.pay(s)
		return Situation.fold()

	# Aumento comum. Contra um só, aumenta de novo com bem mais mãos: quem abriu desiste
	# da maior parte do que abriu.
	var heads_up: bool = int(s["opponents"]) == 1
	if strength >= (0.90 if heads_up else 0.95):
		return Situation.raise_to(s, current_bet * 3)
	if (heads_up and strength >= 0.55 and strength < 0.80
			and rng.randf() < 0.20 * float(traits["bluff"])):
		return Situation.raise_to(s, current_bet * 3)   # aumenta de novo sem mão, às vezes
	# Defende mais quando fecha a rodada, contra um só, e quando o aumento é barato.
	var defend: float = 0.24
	if int(s["players"]) == 2:
		defend = 0.55
	elif int(s["behind"]) == 0:
		defend = 0.45
	defend *= pow(2.5 / maxf(2.0, float(current_bet) / bb), 0.8) * loose
	if strength >= 1.0 - minf(0.90, defend):
		return Situation.pay(s)
	return Situation.fold()


## Torneio com poucas fichas: all-in ou nada.
static func _push_or_fold(s: Dictionary, strength: float, loose: float, odds: float) -> Dictionary:
	var bb: int = maxi(1, int(s["bb"]))
	var stack_bb: float = float(int(s["stack"]) + int(s["bet"])) / bb
	if int(s["current_bet"]) <= bb:
		# Quanto menos fichas e menos gente para falar, mais mãos ele empurra.
		var push: float = clampf(1.0 - 0.045 * stack_bb, 0.50, 0.95)
		push /= 1.0 + 0.5 * maxi(0, int(s["behind"]) - 1)
		if int(s["to_call"]) == 0:
			if strength >= 1.0 - push * 0.6:
				return Situation.all_in(s)
			return Situation.check_or_fold(s)
		if strength >= 1.0 - minf(0.97, push * loose):
			return Situation.all_in(s)
		return Situation.check_or_fold(s)
	if strength >= 1.0 - _call_range(float(s["effective"]) / bb, odds):
		return Situation.all_in(s)
	return Situation.fold()


## Parte das mãos com que paga, pelo tamanho do que está em jogo e pelo preço.
static func _call_range(stake_bb: float, odds: float) -> float:
	var share: float = CALL_RANGE[CALL_RANGE.size() - 1][1]
	if stake_bb <= CALL_RANGE[0][0]:
		share = CALL_RANGE[0][1]
	else:
		for i in range(1, CALL_RANGE.size()):
			if stake_bb <= CALL_RANGE[i][0]:
				var from: Array = CALL_RANGE[i - 1]
				var to: Array = CALL_RANGE[i]
				var t: float = (stake_bb - from[0]) / (to[0] - from[0])
				share = lerpf(from[1], to[1], t)
				break
	# Preço melhor que o de um all-in seco (cerca de 0,45): paga com mais mãos.
	return minf(0.95, share * clampf(0.45 / maxf(odds, 0.05), 1.0, 2.5))


static func _postflop(s: Dictionary, traits: Dictionary, rng: RandomNumberGenerator,
		memory: Dictionary) -> Dictionary:
	var street: int = s["street"]
	var opponents: int = s["opponents"]
	var aggr: float = traits["aggr"]
	var outs: int = HandStrength.outs(s["cards"], s["board"])

	if int(s["to_call"]) == 0:
		var equity: float = _equity(s, 0, rng, memory)
		if equity >= 0.82:
			# Mão muito forte: de vez em quando só passa, para armar.
			if opponents == 1 and street < Situation.RIVER and rng.randf() < 0.12:
				return Situation.check_or_fold(s)
			return Situation.raise_pot(s, rng.randf_range(0.60, 0.95))
		if equity >= 0.56 + 0.05 * (opponents - 1) and rng.randf() < 0.9 * aggr:
			return Situation.raise_pot(s, rng.randf_range(0.45, 0.70))
		if outs >= 8 and rng.randf() < 0.55 * aggr:
			return Situation.raise_pot(s, 0.6)   # semiblefe com projeto
		if opponents <= 2 and equity < 0.40:
			var chance: float = 0.16
			if opponents == 1:
				chance = 0.40 if s["in_position"] else 0.30
			if int(memory.get("aggressor", -1)) == int(s["seat"]) and street == Situation.FLOP:
				chance += 0.25   # aposta de continuação
			if street == Situation.RIVER:
				chance *= 0.6
			if rng.randf() < chance * float(traits["bluff"]):
				return Situation.raise_pot(s, rng.randf_range(0.50, 0.70))
		return Situation.check_or_fold(s)

	# Diante de uma aposta: quem aposta tem mão melhor que uma ao acaso, e tanto melhor
	# quanto maior a aposta.
	var fraction: float = Situation.bet_fraction(s)
	var extra: int = 1
	if fraction > 0.45:
		extra += 1
	if fraction > 0.90:
		extra += 1
	if street >= Situation.TURN:
		extra += 1   # aposta no turn ou no river costuma ser mais forte que no flop
	if int(s["bet"]) > 0:
		extra += 2   # aumentaram por cima da minha aposta
	var faced: float = _equity(s, extra, rng, memory)
	var odds: float = Situation.pot_odds(s)
	if faced >= 0.80 and rng.randf() < 0.8:
		return Situation.raise_pot(s, rng.randf_range(0.70, 1.0))
	if (outs >= 8 and street < Situation.RIVER and opponents == 1
			and rng.randf() < 0.15 * aggr):
		return Situation.raise_pot(s, 0.8)   # semiblefe aumentando
	var margin: float = 0.07 if street == Situation.RIVER else 0.04
	if faced >= odds + margin:
		return Situation.pay(s)
	if outs >= 8 and street == Situation.FLOP and faced >= odds - 0.05:
		return Situation.pay(s)   # projeto forte: o que pode ganhar depois compensa
	return Situation.fold()


## Chance estimada, guardada por rodada para não simular duas vezes a mesma situação.
static func _equity(s: Dictionary, extra: int, rng: RandomNumberGenerator,
		memory: Dictionary) -> float:
	var opponents: int = maxi(1, int(s["opponents"]))
	var key: int = int(s["street"]) * 100 + opponents * 10 + extra
	var cache: Dictionary = memory.get("equity", {})
	if cache.has(key):
		return cache[key]
	var budget: int = mini(MAX_EVALUATIONS, int(memory.get("evaluations", MAX_EVALUATIONS)))
	@warning_ignore("integer_division")
	var iterations: int = maxi(MIN_ITERATIONS, budget / (1 + opponents + extra))
	var value: float = Equity.estimate(s["cards"], s["board"], opponents, iterations, rng, extra)
	cache[key] = value
	memory["equity"] = cache
	return value
