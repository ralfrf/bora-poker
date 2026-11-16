extends RefCounted
## Teste de força dos bots (SPEC 7 e 13): Difícil vence Médio e Médio vence Fácil.
##
## Partidas espelhadas no mano a mano: o mesmo número de mãos, com as mesmas sementes,
## duas vezes, trocando os bots de lugar. Cada lugar recebe as mesmas cartas nas duas
## vezes, então a sorte se anula e sobra a diferença de jogo. Clássico com 100 big
## blinds e recompra ilimitada; o resultado é o ganho do mais forte em big blinds por
## 100 mãos, com o erro padrão calculado mão a mão.

const Room := preload("res://server/room.gd")
const Clock := preload("res://server/clock.gd")
const Table := preload("res://engine/table.gd")
const Roster := preload("res://bots/roster.gd")

## [mais forte, mais fraco]
const MATCHES: Array = [[Roster.HARD, Roster.MEDIUM], [Roster.MEDIUM, Roster.EASY],
	[Roster.HARD, Roster.EASY]]
## O mais forte precisa ganhar por pelo menos tantos erros padrão.
const MIN_Z: float = 2.0

var _checks: int = 0


func run(hands: int, seed_value: int) -> Dictionary:
	var errors: Array[String] = []
	var parts: Array[String] = []
	var played: int = 0
	for pair: Array in MATCHES:
		var strong: int = pair[0]
		var weak: int = pair[1]
		var first: Array = _half(strong, weak, hands, seed_value, false)
		var second: Array = _half(strong, weak, hands, seed_value, true)
		var count: int = mini(first.size(), second.size())
		played += first.size() + second.size()
		var total: float = 0.0
		var squares: float = 0.0
		for i in count:
			var paired: float = (first[i] + second[i]) / 2.0
			total += paired
			squares += paired * paired
		var mean: float = total / maxf(count, 1)
		var variance: float = maxf(squares / maxf(count, 1) - mean * mean, 0.0)
		var error: float = sqrt(variance / maxf(count, 1))
		var z: float = mean / error if error > 0.0 else 0.0
		var label: String = "%s x %s" % [Roster.LEVEL_NAMES[strong], Roster.LEVEL_NAMES[weak]]
		parts.append("%s: %+.1f bb/100 (± %.1f)" % [label, mean * 100.0, error * 100.0])
		_checks += 1
		if count < hands:
			errors.append("%s: só %d mãos jogadas" % [label, count])
		elif z < MIN_Z:
			errors.append("%s: o mais forte não venceu com folga (%+.1f bb/100, z = %.1f)" % [
				label, mean * 100.0, z])
	var line: String = "Força dos bots (%d mãos por lado, semente %d): %s" % [
		hands, seed_value, " | ".join(parts)]
	return {"errors": errors, "checks": _checks, "hands": played, "line": line}


## Joga `hands` mãos e devolve o ganho do mais forte em cada mão, em big blinds.
func _half(strong: int, weak: int, hands: int, seed_value: int, swapped: bool) -> Array:
	var normalized: Dictionary = Room.normalize_options({
		"format": Table.CLASSIC, "seats": 2, "turn_seconds": 0,
		"bots": [weak, strong] if swapped else [strong, weak]})
	var counter: Array = [seed_value]
	var next: Callable = func() -> int:
		counter[0] += 1
		return counter[0]
	# A espera de 1 ms entre mãos faz cada tick jogar no máximo uma mão.
	var config: Dictionary = {"hand_gap_ms": 1, "showdown_gap_ms": 1, "bot_min_ms": 0,
		"bot_max_ms": 0, "allow_empty": true, "bot_style": Roster.NEUTRAL}
	var clock: Clock = Clock.new(true)
	var room: Room = Room.new("FORCA", normalized["options"], clock, Callable(), config, next)
	var strong_seat: int = 1 if swapped else 0
	var strong_id: String = room.member_at(strong_seat).id
	var big: float = float(room.table.big_blind)
	var results: Array = []
	var last_net: int = 0
	var last_hand: int = 0
	room.start()
	var guard: int = 0
	while results.size() < hands and guard < hands * 20:
		guard += 1
		clock.advance(1000)
		room.tick()
		# Cada tick pode jogar várias mãos; mede entre mãos, com a mesa parada.
		if room.table.hand_number != last_hand and not room.table.hand_in_progress():
			var net: int = _net(room, strong_id)
			var finished: int = room.table.hand_number - last_hand
			for i in finished:
				results.append(float(net - last_net) / big / finished)
			last_net = net
			last_hand = room.table.hand_number
	if room.bot_errors > 0:
		push_error("teste de força: %d jogada(s) de bot recusada(s)" % room.bot_errors)
	return results.slice(0, hands)


func _net(room: Room, id: String) -> int:
	var chips: int = 0
	for seat in room.table.seats:
		if seat.id == id:
			chips = seat.stack
	return room.table.cashbox.net(id, chips)
