extends RefCounted
## Potes paralelos, aposta não coberta e divisão do pote (SPEC 3.2 item 13 e 3.3).
## As listas usam dicionários com "seat", para o resultado sobreviver ao JSON.


## Parte da maior aposta que ninguém igualou e que volta para quem apostou.
## bets: [{seat, amount, folded}]. Devolve {seat, amount}; amount 0 se não há o que devolver.
static func uncalled(bets: Array) -> Dictionary:
	var top_seat: int = -1
	var top: int = 0
	var second: int = 0
	var top_folded: bool = false
	for entry: Dictionary in bets:
		var amount: int = entry["amount"]
		if amount > top:
			second = top
			top = amount
			top_seat = entry["seat"]
			top_folded = entry["folded"]
		elif amount > second:
			second = amount
	if top_seat < 0 or top_folded or top == second:
		return {"seat": -1, "amount": 0}
	return {"seat": top_seat, "amount": top - second}


## Monta os potes a partir do total que cada um pôs na mão.
## entries: [{seat, total, folded, all_in}]. Devolve [{amount, eligible}], do principal
## para os paralelos.
##
## Só um all-in fecha um pote: cada nível de contribuição de quem está all-in vira um
## pote, e o que passa do último all-in forma o pote seguinte. Quem ainda tem fichas
## concorre a todos os potes, mesmo antes de igualar a aposta (o que só acontece no meio
## de uma rodada). As fichas de quem desistiu entram nos potes até onde alcançam.
## Sem "all_in", todo mundo é tratado como all-in: um pote por nível de contribuição.
static func build(entries: Array) -> Array[Dictionary]:
	var levels: Array[int] = []
	var live: Array[int] = []
	var top: int = 0
	for entry: Dictionary in entries:
		if entry["folded"]:
			continue
		live.append(entry["seat"])
		var total: int = entry["total"]
		top = maxi(top, total)
		if total > 0 and entry.get("all_in", true) and not levels.has(total):
			levels.append(total)
	if top > 0 and not levels.has(top):
		levels.append(top)
	levels.sort()

	var pots: Array[Dictionary] = []
	var previous: int = 0
	for level in levels:
		var amount: int = 0
		var eligible: Array[int] = []
		for entry: Dictionary in entries:
			var total: int = entry["total"]
			amount += mini(total, level) - mini(total, previous)
			if not entry["folded"] and (total >= level or not entry.get("all_in", true)):
				eligible.append(entry["seat"])
		pots.append({"amount": amount, "eligible": eligible})
		previous = level

	# Fichas de quem desistiu acima do último nível. Não acontece em uma mão normal,
	# mas nenhuma ficha pode sumir.
	var extra: int = 0
	for entry: Dictionary in entries:
		extra += maxi(0, int(entry["total"]) - previous)
	if extra > 0:
		if pots.is_empty():
			pots.append({"amount": extra, "eligible": live})
		else:
			pots[-1]["amount"] = int(pots[-1]["amount"]) + extra
	return pots


## Entrega cada pote à melhor mão entre os elegíveis; no empate, divide igualmente.
## scores: {lugar: pontuação}. order: os lugares na ordem em que recebem os centavos
## que sobram da divisão (a começar pelo primeiro à esquerda do botão).
## Devolve os potes com "winners" e "shares" ([{seat, amount}]).
static func distribute(pots: Array, scores: Dictionary, order: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for pot: Dictionary in pots:
		var eligible: Array[int] = []
		eligible.assign(pot["eligible"])
		var amount: int = pot["amount"]
		var best: int = -1
		for seat in eligible:
			best = maxi(best, int(scores[seat]))
		var winners: Array[int] = []
		for seat: int in order:
			if eligible.has(seat) and int(scores[seat]) == best:
				winners.append(seat)
		var shares: Array[Dictionary] = []
		if not winners.is_empty():
			@warning_ignore("integer_division")
			var share: int = amount / winners.size()
			var leftover: int = amount % winners.size()
			for i in winners.size():
				shares.append({
					"seat": winners[i],
					"amount": share + (1 if i < leftover else 0),
				})
		result.append({
			"amount": amount, "eligible": eligible, "winners": winners, "shares": shares,
		})
	return result
