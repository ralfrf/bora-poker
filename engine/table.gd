extends RefCounted
## Mesa pura: lugares com fichas, botão, sequência de mãos, recompra (clássico), níveis
## e eliminação (torneio) e caixa de fichas (SPEC 3.4, 3.5, 6.2 e 8.1).
##
## Não conhece relógio, rede nem tela. O servidor embrulha esta classe com conexões,
## prazos e a visão de cada jogador. O estado inteiro cabe em um dicionário.

const Hand := preload("res://engine/hand.gd")
const Positions := preload("res://engine/positions.gd")
const Cashbox := preload("res://engine/cashbox.gd")
const Tournament := preload("res://engine/tournament.gd")
const Serial := preload("res://engine/serial.gd")

const CLASSIC: String = "classic"
const TOURNAMENT: String = "tournament"

const REBUY_UNLIMITED: int = -1
const REBUY_LIMITS: Array[int] = [-1, 0, 1, 2, 3]
const MAX_SEATS: int = 9
const DEFAULT_STACK: int = 2000              ## clássico: 20,00
const DEFAULT_TOURNAMENT_STACK: int = 3000   ## torneio: 30,00
const DEFAULT_SMALL_BLIND: int = 10
const DEFAULT_BIG_BLIND: int = 20

const PLAYING: String = "playing"   ## tem lugar e joga as próximas mãos
const BUSTED: String = "busted"     ## zerou no clássico e ainda pode recomprar
const OUT: String = "out"           ## saiu, foi eliminado ou virou espectador

const STATE_VERSION: int = 1
const BUTTON_SALT: int = 0x5DEECE66D1CE4E5B
const STATE_SCHEMA: Dictionary = {
	"v": TYPE_INT, "format": TYPE_STRING, "starting_stack": TYPE_INT,
	"small_blind": TYPE_INT, "big_blind": TYPE_INT, "rebuy_limit": TYPE_INT,
	"level_minutes": TYPE_INT, "level": TYPE_INT, "button": TYPE_INT,
	"previous_button": TYPE_INT, "hand_number": TYPE_INT, "seats": TYPE_ARRAY,
	"cashbox": TYPE_DICTIONARY,
}
const SEAT_SCHEMA: Dictionary = {
	"index": TYPE_INT, "id": TYPE_STRING, "stack": TYPE_INT, "state": TYPE_STRING,
	"rebuys": TYPE_INT, "place": TYPE_INT, "expired": TYPE_BOOL, "away": TYPE_BOOL,
}


class Seat:
	extends RefCounted

	var index: int = 0            ## número do lugar; deixa de valer quando o estado é OUT
	var id: String = ""           ## identificação do participante
	var stack: int = 0
	var state: String = "playing"
	var rebuys: int = 0
	var place: int = 0            ## torneio: colocação final; 0 enquanto está no jogo
	var expired: bool = false     ## saiu e o prazo de volta venceu: se voltar, é jogador novo
	var away: bool = false        ## clássico: ausente, fica fora das mãos e não paga blinds


var format: String = CLASSIC
var starting_stack: int = DEFAULT_STACK
var small_blind: int = DEFAULT_SMALL_BLIND
var big_blind: int = DEFAULT_BIG_BLIND
var rebuy_limit: int = REBUY_UNLIMITED
var level_minutes: int = Tournament.DEFAULT_LEVEL_MINUTES
var level: int = 0
var button: int = -1
var previous_button: int = -1     ## botão antes da mão atual, para desfazer um cancelamento
var hand_number: int = 0
var hand: Hand = null             ## a mão atual, ou a última jogada
var cashbox: Cashbox = Cashbox.new()
var seats: Array[Seat] = []       ## todos os que passaram pela mesa
var load_error: String = ""       ## por que o último load_dict falhou


## Opções da mesa, antes de alguém sentar:
##   format: CLASSIC ou TOURNAMENT
##   starting_stack: fichas iniciais (padrão 20,00 no clássico e 30,00 no torneio)
##   clássico: small_blind, big_blind, rebuy_limit (-1 ilimitada, 0 a 3)
##   torneio: level_minutes (3, 5, 8 ou 10)
## Devolve "" se deu certo, ou o motivo da recusa.
func configure(options: Dictionary) -> String:
	if hand_number > 0 or not seats.is_empty():
		return "a mesa já está em uso"
	var new_format: Variant = options.get("format", CLASSIC)
	if typeof(new_format) != TYPE_STRING or (new_format != CLASSIC and new_format != TOURNAMENT):
		return "formato desconhecido"
	var default_stack: int = DEFAULT_STACK if new_format == CLASSIC else DEFAULT_TOURNAMENT_STACK
	var stack: Variant = options.get("starting_stack", default_stack)
	if typeof(stack) != TYPE_INT or stack <= 0:
		return "fichas iniciais inválidas"
	if new_format == CLASSIC:
		var small: Variant = options.get("small_blind", DEFAULT_SMALL_BLIND)
		var big: Variant = options.get("big_blind", DEFAULT_BIG_BLIND)
		var limit: Variant = options.get("rebuy_limit", REBUY_UNLIMITED)
		if not _valid_blinds(small, big):
			return "blinds inválidos"
		if typeof(limit) != TYPE_INT or not REBUY_LIMITS.has(limit):
			return "limite de recompras inválido"
		small_blind = small
		big_blind = big
		rebuy_limit = limit
	else:
		var minutes: Variant = options.get("level_minutes", Tournament.DEFAULT_LEVEL_MINUTES)
		if typeof(minutes) != TYPE_INT or not Tournament.LEVEL_MINUTES.has(minutes):
			return "tempo por nível inválido"
		level_minutes = minutes
		level = 0
		small_blind = Tournament.small_blind(0)
		big_blind = Tournament.big_blind(0)
		rebuy_limit = 0
	format = new_format
	starting_stack = stack
	return ""


## Senta um participante. No clássico pode ser a qualquer momento (ele joga a partir
## da mão seguinte); no torneio, só antes da primeira mão.
##
## Quem já passou pela mesa e volta (SPEC 6.2):
##   keep_chips verdadeiro: volta com as fichas que estavam guardadas.
##   keep_chips falso: volta com as fichas iniciais. Conta como recompra, e respeita o
##     limite, quando é mais do que ele tinha. Se o prazo de volta já venceu
##     (expire_held), entra como jogador novo, sem gastar recompra.
func add_player(index: int, id: String, keep_chips: bool = false) -> String:
	if index < 0 or index >= MAX_SEATS:
		return "lugar inexistente"
	if id == "":
		return "falta a identificação do jogador"
	if seat_at(index) != null:
		return "lugar ocupado"
	if format == TOURNAMENT and hand_number > 0:
		return "o torneio já começou"
	var seat: Seat = _record(id)
	if seat != null and seat.state != OUT:
		return "esse jogador já está na mesa"
	var held: int = cashbox.held(id)
	if keep_chips:
		if seat == null or held <= 0:
			return "esse jogador não tem fichas guardadas"
		cashbox.release(id, held)
		_sit(seat, index, held)
		return ""
	if seat == null:
		seat = Seat.new()
		seat.id = id
		seats.append(seat)
	else:
		var is_rebuy: bool = not seat.expired and starting_stack > held
		if is_rebuy and not _can_rebuy(seat):
			return "sem recompras"
		if is_rebuy:
			seat.rebuys += 1
		if held > 0:
			# As fichas de antes saem da mesa com ele; as iniciais são uma entrada nova.
			cashbox.release(id, held)
			cashbox.add_exit(id, held)
	cashbox.add_entry(id, starting_stack)
	_sit(seat, index, starting_stack)
	return ""


## Tira um participante da mesa. As fichas dele ficam guardadas, para o caso de voltar
## (SPEC 6.2); o prazo é do servidor, que chama expire_held quando ele vence.
## Só entre mãos, ou durante uma mão da qual ele não participa. No torneio, só antes
## da primeira mão.
func remove_player(index: int) -> String:
	var seat: Seat = seat_at(index)
	if seat == null:
		return "lugar vazio"
	if format == TOURNAMENT and hand_number > 0:
		return "no torneio ninguém sai levando fichas"
	if _in_hand(index):
		return "espere a mão terminar"
	if hand_number == 0:
		# Nada foi jogado ainda: é como se não tivesse sentado.
		cashbox.forget(seat.id)
		seats.erase(seat)
		return ""
	cashbox.hold(seat.id, seat.stack)
	seat.stack = 0
	seat.state = OUT
	seat.expired = false
	return ""


## O prazo de volta venceu: as fichas guardadas saem da mesa de vez. Se ele voltar,
## entra como jogador novo.
func expire_held(id: String) -> String:
	var seat: Seat = _record(id)
	if seat == null or seat.state != OUT:
		return "esse jogador não está fora da mesa"
	var held: int = cashbox.held(id)
	if held <= 0:
		return "esse jogador não tem fichas guardadas"
	cashbox.release(id, held)
	cashbox.add_exit(id, held)
	seat.expired = true
	return ""


## Clássico: marca ou desmarca um jogador como ausente (SPEC 5). O ausente fica fora das
## mãos e não paga blinds; vale a partir da mão seguinte. No torneio o ausente continua
## recebendo cartas, e é o servidor que desiste por ele.
func set_away(index: int, away: bool) -> String:
	var seat: Seat = seat_at(index)
	if seat == null:
		return "lugar vazio"
	if format != CLASSIC:
		return "no torneio o ausente continua nas mãos"
	seat.away = away
	return ""


## Lugares que jogam a próxima mão: quem está sentado, tem fichas e não está ausente.
func participants() -> Array[int]:
	var list: Array[int] = []
	for seat in seats:
		if seat.state == PLAYING and seat.stack > 0 and not seat.away:
			list.append(seat.index)
	list.sort()
	return list


func hand_in_progress() -> bool:
	return hand != null and not hand.finished


func can_start_hand() -> bool:
	return not hand_in_progress() and participants().size() >= 2


## Começa a próxima mão. params:
##   seed: semente do baralho e do sorteio do primeiro botão — ou deck: baralho montado
##   elapsed_ms: (torneio) tempo de jogo decorrido; define o nível de blinds desta mão
##   button: (testes) força o lugar do botão
## Devolve {ok, error, events}. Se a mão não começa, nada muda na mesa.
func start_hand(params: Dictionary) -> Dictionary:
	if hand_in_progress():
		return _error("já há uma mão em andamento")
	var playing: Array[int] = participants()
	if playing.size() < 2:
		return _error("faltam jogadores com fichas")
	if params.has("seed") and typeof(params["seed"]) != TYPE_INT:
		return _error("semente inválida")

	var new_level: int = level
	var new_small: int = small_blind
	var new_big: int = big_blind
	if format == TOURNAMENT and params.has("elapsed_ms"):
		if typeof(params["elapsed_ms"]) != TYPE_INT:
			return _error("tempo decorrido inválido")
		# O nível novo vale a partir desta mão, nunca no meio de uma, e não desce.
		new_level = maxi(level, Tournament.level_at(params["elapsed_ms"], level_minutes))
		new_small = Tournament.small_blind(new_level)
		new_big = Tournament.big_blind(new_level)

	var new_button: Variant
	if params.has("button"):
		new_button = params["button"]
	elif button < 0:
		# Semente derivada, para o sorteio do botão não repetir os números do baralho.
		new_button = Positions.first_button(playing, int(params.get("seed", 0)) ^ BUTTON_SALT)
	else:
		new_button = Positions.next_button(playing, button)

	var entries: Array = []
	for index in playing:
		entries.append({"seat": index, "stack": seat_at(index).stack})
	var hand_params: Dictionary = {
		"seats": entries, "button": new_button,
		"small_blind": new_small, "big_blind": new_big,
	}
	if params.has("deck"):
		hand_params["deck"] = params["deck"]
	elif params.has("seed"):
		hand_params["seed"] = params["seed"]

	var new_hand: Hand = Hand.new()
	var response: Dictionary = new_hand.start(hand_params)
	if not response["ok"]:
		return response
	hand = new_hand
	level = new_level
	small_blind = new_small
	big_blind = new_big
	previous_button = button
	button = new_button
	hand_number += 1
	_after_step(response["events"])
	return response


## Ação do jogador da vez na mão atual. Devolve {ok, error, events}.
func apply_action(index: int, action: String, amount: int = 0) -> Dictionary:
	if not hand_in_progress():
		return _error("não há mão em andamento")
	var response: Dictionary = hand.apply_action(index, action, amount)
	if response["ok"]:
		_after_step(response["events"])
	return response


## Cancela a mão atual e devolve as apostas (SPEC 6.6). O botão volta para onde
## estava, para a mão seguinte repetir as posições e ninguém pular os blinds.
func cancel_hand() -> Dictionary:
	if not hand_in_progress():
		return _error("não há mão em andamento")
	var response: Dictionary = hand.cancel()
	_sync_stacks()
	button = previous_button
	return response


## Recompra de quem zerou no clássico: volta com as fichas iniciais.
func rebuy(index: int) -> String:
	var seat: Seat = seat_at(index)
	if seat == null:
		return "lugar vazio"
	if seat.state != BUSTED:
		return "só recompra quem ficou sem fichas"
	if not _can_rebuy(seat):
		return "sem recompras"
	seat.stack = starting_stack
	seat.rebuys += 1
	seat.state = PLAYING
	cashbox.add_entry(seat.id, starting_stack)
	return ""


## Quantas recompras esse participante já fez nesta mesa (0 se nunca sentou).
func rebuys_of(id: String) -> int:
	var seat: Seat = _record(id)
	return seat.rebuys if seat != null else 0


## Verdadeiro se esse participante já sentou nesta mesa alguma vez.
func knows(id: String) -> bool:
	return _record(id) != null


## Verdadeiro se esse participante saiu e o prazo de volta já venceu: se voltar, é
## jogador novo (SPEC 6.2).
func is_expired(id: String) -> bool:
	var seat: Seat = _record(id)
	return seat != null and seat.expired


## Torneio, mano a mano: o jogador entrega todas as fichas ao outro, que é o campeão
## (SPEC 6.3, ausente há mais de 60 s). Só entre mãos.
func concede(index: int) -> Dictionary:
	if format != TOURNAMENT:
		return _error("só no torneio")
	if hand_in_progress():
		return _error("espere a mão terminar")
	var alive: Array[int] = participants()
	if alive.size() != 2 or not alive.has(index):
		return _error("só vale no mano a mano")
	var loser: Seat = seat_at(index)
	var winner: Seat = seat_at(alive[0] if alive[1] == index else alive[1])
	var amount: int = loser.stack
	winner.stack += amount
	loser.stack = 0
	loser.state = OUT
	loser.place = 2
	winner.place = 1
	var events: Array[Dictionary] = [
		{"type": "conceded", "seat": index, "to": winner.index, "amount": amount},
		{"type": "eliminated", "seat": index, "place": 2},
		{"type": "tournament_end", "winner": winner.index},
	]
	return {"ok": true, "error": "", "events": events}


## Verdadeiro se quem está fora da mesa (saiu ou virou espectador) ainda pode sentar de
## novo gastando uma recompra.
func can_return_with_rebuy(id: String) -> bool:
	var seat: Seat = _record(id)
	return seat != null and seat.state == OUT and not seat.expired and _can_rebuy(seat)


## Quem zerou e não recompra vira espectador.
func decline_rebuy(index: int) -> String:
	var seat: Seat = seat_at(index)
	if seat == null or seat.state != BUSTED:
		return "esse lugar não tem recompra pendente"
	seat.state = OUT
	return ""


## Clássico: o dono muda os blinds entre uma mão e outra.
func set_blinds(small: int, big: int) -> String:
	if format != CLASSIC:
		return "no torneio os blinds seguem os níveis"
	if hand_in_progress():
		return "espere a mão terminar"
	if not _valid_blinds(small, big):
		return "blinds inválidos"
	small_blind = small
	big_blind = big
	return ""


## Clássico: sobra um só com fichas e ninguém pode recomprar.
## Torneio: um jogador tem todas as fichas.
## Um ausente com fichas continua contando: a partida não acaba por ele estar fora.
func is_over() -> bool:
	if hand_number == 0 or hand_in_progress():
		return false
	var with_chips: int = 0
	for seat in seats:
		if seat.state == BUSTED:
			return false
		if seat.state == PLAYING and seat.stack > 0:
			with_chips += 1
	return with_chips <= 1


## Placar: [{seat, id, chips, held, rebuys, net, state, place}].
## chips conta o que está no lugar e o que está apostado na mão em andamento; net é o
## saldo líquido (fichas atuais mais saídas, menos entradas).
## Clássico: do maior saldo para o menor. Torneio: quem ainda joga na frente (por
## fichas), depois os eliminados pela colocação.
func scoreboard() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for seat in seats:
		var chips: int = seat.stack + _chips_in_hand_of(seat)
		rows.append({
			"seat": seat.index, "id": seat.id, "chips": chips,
			"held": cashbox.held(seat.id), "rebuys": seat.rebuys,
			"net": cashbox.net(seat.id, chips), "state": seat.state, "place": seat.place,
		})
	sort_scoreboard(rows, format == TOURNAMENT)
	return rows


## A ordem do placar (também usada no placar calculado sem o anfitrião, net/host_lost.gd).
static func sort_scoreboard(rows: Array, tournament: bool) -> void:
	if tournament:
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if int(a["place"]) != int(b["place"]):
				return int(a["place"]) < int(b["place"])
			if int(a["chips"]) != int(b["chips"]):
				return int(a["chips"]) > int(b["chips"])
			return str(a["id"]) < str(b["id"]))
	else:
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if int(a["net"]) != int(b["net"]):
				return int(a["net"]) > int(b["net"])
			return str(a["id"]) < str(b["id"]))


## Torneio: quem ficou em 1º, 2º e 3º. [{place, seat, id}].
func podium() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for row in scoreboard():
		if int(row["place"]) >= 1 and int(row["place"]) <= 3:
			rows.append({"place": row["place"], "seat": row["seat"], "id": row["id"]})
	return rows


## Lugar ocupado com esse número, ou null.
func seat_at(index: int) -> Seat:
	for seat in seats:
		if seat.index == index and seat.state != OUT:
			return seat
	return null


func chips_on_seats() -> int:
	var sum: int = 0
	for seat in seats:
		sum += seat.stack
	return sum


func chips_in_hand() -> int:
	return hand.committed() if hand != null else 0


## A igualdade da caixa de fichas (SPEC 8.1).
func is_balanced() -> bool:
	return cashbox.is_balanced(chips_on_seats(), chips_in_hand())


## Estado completo da mesa. Inclui a mão com as cartas fechadas e o baralho: é para
## gravar no próprio servidor, nunca para enviar a um jogador.
func to_dict() -> Dictionary:
	var seat_list: Array = []
	for seat in seats:
		seat_list.append({
			"index": seat.index, "id": seat.id, "stack": seat.stack, "state": seat.state,
			"rebuys": seat.rebuys, "place": seat.place, "expired": seat.expired,
			"away": seat.away,
		})
	var saved_hand: Variant = null
	if hand != null:
		saved_hand = hand.to_dict()
	return {
		"v": STATE_VERSION,
		"format": format,
		"starting_stack": starting_stack,
		"small_blind": small_blind,
		"big_blind": big_blind,
		"rebuy_limit": rebuy_limit,
		"level_minutes": level_minutes,
		"level": level,
		"button": button,
		"previous_button": previous_button,
		"hand_number": hand_number,
		"seats": seat_list,
		"cashbox": cashbox.to_dict(),
		"hand": saved_hand,
	}


## Restaura um estado gravado por to_dict (inclusive depois de passar por JSON).
## Devolve verdadeiro se deu certo. Se não, o motivo fica em load_error e a mesa não muda.
func load_dict(saved: Dictionary) -> bool:
	# O valor padrão é a falha: se a leitura parar no meio, ninguém a toma por sucesso.
	load_error = "erro ao ler o estado da mesa"
	var problem: String = _load(saved)
	load_error = problem
	return problem == ""


## Confere o estado inteiro antes de mexer em qualquer campo.
func _load(saved: Dictionary) -> String:
	var data: Dictionary = Serial.ints(saved)
	if not Serial.matches(data, STATE_SCHEMA) or not data.has("hand"):
		return "estado da mesa incompleto ou com tipo errado"
	if data["v"] != STATE_VERSION:
		return "versão do estado da mesa desconhecida"
	if data["format"] != CLASSIC and data["format"] != TOURNAMENT:
		return "formato desconhecido"
	if (data["starting_stack"] <= 0 or not _valid_blinds(data["small_blind"], data["big_blind"])
			or not REBUY_LIMITS.has(data["rebuy_limit"]) or data["level"] < 0
			or not Tournament.LEVEL_MINUTES.has(data["level_minutes"])
			or data["hand_number"] < 0):
		return "opções da mesa inválidas"

	var loaded_seats: Array[Seat] = []
	var by_index: Dictionary = {}
	var ids: Dictionary = {}
	var stack_sum: int = 0
	for entry: Variant in data["seats"]:
		if not Serial.matches(entry, SEAT_SCHEMA):
			return "lugar incompleto ou com tipo errado"
		var seat: Seat = Seat.new()
		seat.index = entry["index"]
		seat.id = entry["id"]
		seat.stack = entry["stack"]
		seat.state = entry["state"]
		seat.rebuys = entry["rebuys"]
		seat.place = entry["place"]
		seat.expired = entry["expired"]
		seat.away = entry["away"]
		if seat.id == "" or ids.has(seat.id):
			return "jogador repetido ou sem identificação"
		if seat.stack < 0 or seat.rebuys < 0 or seat.place < 0:
			return "valores do lugar inválidos"
		if seat.state == OUT:
			if seat.stack != 0:
				return "quem está fora da mesa não tem fichas no lugar"
		elif seat.state == PLAYING or seat.state == BUSTED:
			if seat.index < 0 or seat.index >= MAX_SEATS or by_index.has(seat.index):
				return "lugar repetido ou inexistente"
			by_index[seat.index] = seat
		else:
			return "situação do lugar desconhecida"
		ids[seat.id] = true
		stack_sum += seat.stack
		loaded_seats.append(seat)

	var loaded_cashbox: Cashbox = Cashbox.new()
	if not loaded_cashbox.load_dict(data["cashbox"]):
		return loaded_cashbox.load_error
	var loaded_hand: Hand = null
	var hand_chips: int = 0
	if data["hand"] != null:
		if typeof(data["hand"]) != TYPE_DICTIONARY:
			return "estado da mão inválido"
		loaded_hand = Hand.new()
		if not loaded_hand.load_dict(data["hand"]):
			return loaded_hand.load_error
		hand_chips = loaded_hand.committed()
		if not loaded_hand.finished:
			# Cada jogador da mão precisa estar sentado, com as mesmas fichas.
			for player in loaded_hand.players:
				var seat: Seat = by_index.get(player.seat)
				if seat == null or seat.state != PLAYING or seat.stack != player.stack:
					return "a mão não combina com os lugares"
	if not loaded_cashbox.is_balanced(stack_sum, hand_chips):
		return "a caixa de fichas não fecha"

	format = data["format"]
	starting_stack = data["starting_stack"]
	small_blind = data["small_blind"]
	big_blind = data["big_blind"]
	rebuy_limit = data["rebuy_limit"]
	level_minutes = data["level_minutes"]
	level = data["level"]
	button = data["button"]
	previous_button = data["previous_button"]
	hand_number = data["hand_number"]
	seats = loaded_seats
	cashbox = loaded_cashbox
	hand = loaded_hand
	return ""


func _sit(seat: Seat, index: int, stack: int) -> void:
	seat.index = index
	seat.stack = stack
	seat.state = PLAYING
	seat.expired = false
	seat.away = false


## Depois de cada passo da mão: copia as fichas para os lugares e, se a mão acabou,
## resolve quem zerou.
func _after_step(events: Array) -> void:
	_sync_stacks()
	if hand.finished:
		_settle(events)


func _sync_stacks() -> void:
	for player in hand.players:
		seat_at(player.seat).stack = player.stack


func _settle(events: Array) -> void:
	var busted: Array = []
	for player in hand.players:
		if player.stack > 0:
			continue
		var seat: Seat = seat_at(player.seat)
		if format == CLASSIC:
			seat.state = BUSTED if _can_rebuy(seat) else OUT
			events.append({
				"type": "busted", "seat": seat.index, "can_rebuy": seat.state == BUSTED})
		else:
			busted.append({"seat": player.seat, "start_stack": player.start_stack})
	if format != TOURNAMENT:
		return
	for entry in Tournament.assign_places(hand.players.size(), busted):
		var seat: Seat = seat_at(entry["seat"])
		seat.place = entry["place"]
		seat.state = OUT
		events.append({"type": "eliminated", "seat": seat.index, "place": seat.place})
	var alive: Array[int] = participants()
	if alive.size() == 1:
		var winner: Seat = seat_at(alive[0])
		winner.place = 1
		events.append({"type": "tournament_end", "winner": winner.index})


## O que o participante tem apostado na mão em andamento.
func _chips_in_hand_of(seat: Seat) -> int:
	if seat.state == OUT or not hand_in_progress():
		return 0
	var player: Hand.Player = hand.player_at(seat.index)
	return player.total if player != null else 0


func _can_rebuy(seat: Seat) -> bool:
	return format == CLASSIC and (rebuy_limit == REBUY_UNLIMITED or seat.rebuys < rebuy_limit)


func _in_hand(index: int) -> bool:
	return hand_in_progress() and hand.player_at(index) != null


func _record(id: String) -> Seat:
	for seat in seats:
		if seat.id == id:
			return seat
	return null


func _valid_blinds(small: Variant, big: Variant) -> bool:
	return (typeof(small) == TYPE_INT and typeof(big) == TYPE_INT
		and small >= 1 and big >= small)


func _error(message: String) -> Dictionary:
	var events: Array[Dictionary] = []
	return {"ok": false, "error": message, "events": events}
