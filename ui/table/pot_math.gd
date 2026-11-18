extends RefCounted
## Contas do pote para a tela, sem nós: o que aparece no centro da mesa, o que volta
## para quem apostou e quem leva quanto no fim da mão. Usado pela mesa e pelo histórico.


## Fichas no centro da mesa. Durante a mão, só o que já foi recolhido das rodadas
## anteriores: as apostas da rodada aparecem na frente de cada lugar e não contam duas
## vezes. No fim da mão, o que foi entregue (sem a aposta não paga, que voltou).
## table: a parte pública da visão (server/view.gd).
static func center(table: Dictionary) -> int:
	if table.get("live", false):
		var collected: int = int(table.get("pot", 0))
		for entry: Dictionary in table.get("seats", []):
			collected -= int(entry.get("bet", 0))
		return maxi(collected, 0)
	var total: int = 0
	for payout: Dictionary in table.get("result", {}).get("payouts", []):
		total += int(payout.get("amount", 0))
	return total


## Apostas que ninguém pagou e voltaram nesta mensagem: {lugar: valor}.
static func refunds(events: Array) -> Dictionary:
	var back: Dictionary = {}
	for event: Dictionary in events:
		if String(event.get("type", "")) == "refund":
			var seat: int = int(event.get("seat", -1))
			back[seat] = int(back.get(seat, 0)) + int(event.get("amount", 0))
	return back


## Quem leva quanto, para o aviso do fim da mão: [{seats, amount}], do maior valor para
## o menor. Fica numa linha só ("dividem") quando todos os potes foram divididos entre
## as mesmas pessoas; com potes paralelos ganhos por pessoas diferentes, cada uma tem a
## sua linha, com o que levou (somar tudo e dizer "dividem" estava errado).
## payouts: [{seat, amount}]; pots: [{winners}] do resultado (vazio em registro antigo).
static func groups(payouts: Array, pots: Array) -> Array:
	if payouts.is_empty():
		return []
	var seats: Array = []
	var total: int = 0
	for payout: Dictionary in payouts:
		seats.append(int(payout["seat"]))
		total += int(payout["amount"])
	var shared: bool = seats.size() > 1 and not pots.is_empty()
	for pot: Dictionary in pots:
		var winners: Array = []
		for seat: Variant in pot.get("winners", []):
			winners.append(int(seat))
		winners.sort()
		var sorted_seats: Array = seats.duplicate()
		sorted_seats.sort()
		if winners != sorted_seats:
			shared = false
	if seats.size() == 1 or shared:
		return [{"seats": seats, "amount": total}]
	var lines: Array = []
	for payout: Dictionary in payouts:
		lines.append({"seats": [int(payout["seat"])], "amount": int(payout["amount"])})
	lines.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["amount"]) > int(b["amount"]))
	return lines
