extends RefCounted
## Bot Médio (SPEC 7): segue uma tabela de mãos iniciais por posição e decide pela
## força da mão e pelas odds do pote. Joga certinho e blefa pouco.

const Situation := preload("res://bots/situation.gd")
const Preflop := preload("res://bots/preflop.gd")
const HandStrength := preload("res://bots/hand_strength.gd")

## Parte das mãos com que abre o pote, conforme quantos ainda falam depois dele.
const OPEN_RANGE: Array[float] = [0.50, 0.50, 0.36, 0.27, 0.21, 0.17, 0.14, 0.12]


static func choose(s: Dictionary, traits: Dictionary, rng: RandomNumberGenerator,
		was_aggressor: bool) -> Dictionary:
	if int(s["street"]) == Situation.PREFLOP:
		return _preflop(s, traits)
	return _postflop(s, traits, rng, was_aggressor)


static func _preflop(s: Dictionary, traits: Dictionary) -> Dictionary:
	var cards: Array = s["cards"]
	var strength: float = Preflop.percentile(cards[0], cards[1])
	var loose: float = traits["loose"]
	var bb: int = s["bb"]
	var to_call: int = s["to_call"]
	var current_bet: int = s["current_bet"]

	if current_bet <= bb:
		# Ninguém aumentou ainda.
		var limped: int = maxi(0, int(s["pot"]) - bb - int(s["sb"]))
		if to_call == 0:
			if strength >= 0.90:
				return Situation.raise_to(s, 3 * bb + limped)
			return Situation.check_or_fold(s)
		var open: float = OPEN_RANGE[mini(int(s["behind"]), OPEN_RANGE.size() - 1)] * loose
		if strength >= 1.0 - open:
			return Situation.raise_to(s, 3 * bb + limped)
		if to_call * 2 <= bb and strength >= 0.45:
			return Situation.pay(s)   # completa o small blind com mão razoável
		return Situation.fold()

	# Já houve aumento.
	@warning_ignore("integer_division")
	var raise_bb: int = current_bet / maxi(1, bb)
	if strength >= 0.97:
		return Situation.raise_to(s, current_bet * 3)
	if to_call * 3 <= bb * 4 and strength >= 0.35:
		return Situation.pay(s)   # falta pouco para ver o flop
	if raise_bb <= 4:
		var defend: float = (0.30 if int(s["behind"]) == 0 else 0.15) * loose
		if strength >= 1.0 - defend:
			return Situation.pay(s)
	elif raise_bb <= 12:
		if strength >= 0.93:
			return Situation.pay(s)
	else:
		# All-in ou quase: paga com mão forte, e com um pouco mais se for barato.
		var need: float = 0.95 if to_call > 8 * bb else 0.80
		if strength >= need:
			return Situation.pay(s)
	return Situation.fold()


static func _postflop(s: Dictionary, traits: Dictionary, rng: RandomNumberGenerator,
		was_aggressor: bool) -> Dictionary:
	var board: Array = s["board"]
	var made: float = HandStrength.made(s["cards"], board)
	var outs: int = HandStrength.outs(s["cards"], board)
	var draw: float = HandStrength.draw_equity(outs, board.size())
	var opponents: int = s["opponents"]
	# Contra mais gente, a mesma mão vale menos.
	var strength: float = made - 0.04 * (opponents - 1)
	var aggr: float = traits["aggr"]

	if int(s["to_call"]) == 0:
		if strength >= 0.60 and rng.randf() < 0.85 * aggr:
			return Situation.raise_pot(s, 0.66)
		# Aposta de continuação: abriu antes do flop e está contra um só.
		if (was_aggressor and int(s["street"]) == Situation.FLOP and opponents == 1
				and rng.randf() < 0.35 * float(traits["bluff"])):
			return Situation.raise_pot(s, 0.5)
		return Situation.check_or_fold(s)

	var fraction: float = Situation.bet_fraction(s)
	if strength >= 0.86 and rng.randf() < 0.8 * aggr:
		return Situation.raise_pot(s, 0.8)
	# Quanto maior a aposta, melhor a mão que ele quer para pagar.
	if strength >= 0.42 + 0.18 * minf(fraction, 1.5):
		return Situation.pay(s)
	# Projeto: paga quando as odds do pote compensam.
	var next_card: float = HandStrength.draw_equity(outs, 4)
	if outs > 0 and maxf(next_card * 1.3, draw * 0.8) >= Situation.pot_odds(s):
		return Situation.pay(s)
	return Situation.fold()
