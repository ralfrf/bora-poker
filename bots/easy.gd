extends RefCounted
## Bot Fácil (SPEC 7): joga mãos demais, paga demais, quase não blefa.

const Situation := preload("res://bots/situation.gd")
const Preflop := preload("res://bots/preflop.gd")
const HandStrength := preload("res://bots/hand_strength.gd")


static func choose(s: Dictionary, traits: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	if int(s["street"]) == Situation.PREFLOP:
		return _preflop(s, traits, rng)
	return _postflop(s, traits, rng)


static func _preflop(s: Dictionary, traits: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var cards: Array = s["cards"]
	var strength: float = Preflop.percentile(cards[0], cards[1])
	var loose: float = traits["loose"]
	var bb: int = s["bb"]
	var to_call: int = s["to_call"]
	# Só aumenta com mão muito boa, e pouco.
	if strength >= 1.0 - 0.05 * float(traits["aggr"]) and rng.randf() < 0.7:
		return Situation.raise_to(s, maxi(int(s["min_to"]), int(s["current_bet"]) + 2 * bb))
	if to_call == 0:
		return Situation.check_or_fold(s)
	# Paga quase tudo o que é barato; só larga as piores quando fica caro.
	var play: float = 0.78
	if to_call > 12 * bb:
		play = 0.20
	elif to_call > 4 * bb:
		play = 0.42
	if strength >= 1.0 - minf(0.95, play * loose):
		return Situation.pay(s)
	return Situation.fold()


static func _postflop(s: Dictionary, traits: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var made: float = HandStrength.made(s["cards"], s["board"])
	var outs: int = HandStrength.outs(s["cards"], s["board"])
	var aggr: float = traits["aggr"]
	if int(s["to_call"]) == 0:
		if made >= 0.80 and rng.randf() < 0.8 * aggr:
			return Situation.raise_pot(s, 0.5)
		if made >= 0.60 and rng.randf() < 0.4 * aggr:
			return Situation.raise_pot(s, 0.35)
		if rng.randf() < 0.03 * float(traits["bluff"]):
			return Situation.raise_pot(s, 0.5)
		return Situation.check_or_fold(s)

	var fraction: float = Situation.bet_fraction(s)
	if made >= 0.86 and rng.randf() < 0.5 * aggr:
		return Situation.raise_to(s, int(s["min_to"]))
	# Qualquer par paga; só pensa duas vezes diante de uma aposta enorme.
	if made >= 0.38:
		if fraction > 2.0 and made < 0.60 and rng.randf() < 0.5:
			return Situation.fold()
		return Situation.pay(s)
	if outs >= 4:
		return Situation.pay(s)
	# Sem nada, ainda paga as apostas pequenas boa parte das vezes.
	if fraction <= 0.55 and rng.randf() < 0.45 * float(traits["loose"]):
		return Situation.pay(s)
	return Situation.fold()
