extends RefCounted
## Simulação pelo servidor de verdade (SPEC 13): salas com bots dos três níveis e
## clientes de roteiro que jogam ao acaso, demoram, ficam ausentes, recompram ou não,
## saem e voltam, caem, mandam lixo, pausam e expulsam. Tudo passa pelo transporte
## local (em metade das partidas, também pelo JSON).
##
## Depois de cada passo confere: a caixa de fichas, que a mesa não travou, que nenhum
## bot fez jogada recusada e o sigilo de cada mensagem "state" entregue.

const Server := preload("res://server/server.gd")
const Room := preload("res://server/room.gd")
const Clock := preload("res://server/clock.gd")
const Protocol := preload("res://server/protocol.gd")
const LocalTransport := preload("res://net/local_transport.gd")
const Table := preload("res://engine/table.gd")
const Hand := preload("res://engine/hand.gd")

const MAX_ERRORS: int = 10
const MAX_HANDS_PER_GAME: int = 200
const STEP_MS: int = 1000
const STUCK_TICKS: int = 300
const YOU_KEYS: Array[String] = ["cards", "legal", "id", "seat", "rebuy_ms", "return_offer"]
const SEAT_KEYS: Array[String] = ["seat", "id", "stack", "state", "rebuys", "in_hand", "bet",
	"total", "folded", "all_in", "cards"]
const ROOM_CONFIG: Dictionary = {"hand_gap_ms": 0, "showdown_gap_ms": 0, "bot_min_ms": 0,
	"bot_max_ms": 2000, "rebuy_ms": 20000, "held_ms": 120000, "bot_evaluations": 200}


class Person:
	extends RefCounted

	var nick: String = ""
	var device: String = ""
	var client: Object = null
	var state: Dictionary = {}
	var member_id: String = ""
	var in_room: bool = false
	var banned: bool = false
	var watcher: bool = false     ## só assiste e conta os eventos
	var back_in: int = -1         ## ticks até voltar depois de sair (-1 = não volta)
	var idle: int = 0             ## ticks em que não responde na vez


var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _errors: Array[String] = []
var _context: String = ""
var _checks: int = 0
var _hands: int = 0
var _games: int = 0
var _seed_counter: int = 0
var _counts: Dictionary = {}
var _room: Room = null
var _watcher_id: String = ""


func run(hands_target: int, seed_value: int) -> Dictionary:
	_rng.seed = seed_value
	_seed_counter = seed_value * 7919
	# Para no primeiro erro: a partida seguinte não acrescentaria nada ao diagnóstico.
	while _hands < hands_target and _errors.is_empty():
		_context = "semente %d, partida %d" % [seed_value, _games]
		_play_game()
		_games += 1
	var line: String = (
		"Simulação com bots: %d partidas, %d mãos, %d jogadas, %d estouros, %d ausências, "
		+ "%d recompras, %d expulsões, %d saídas, %d quedas, %d pausas, %d recusas esperadas | "
		+ "semente %d | %d erros") % [
		_games, _hands, _count("action"), _count("timeout"), _count("away_on"),
		_count("rebuy"), _count("kick"), _count("leave"), _count("drop"), _count("pause"),
		_count("refused"), seed_value, _errors.size()]
	return {"errors": _errors, "checks": _checks, "hands": _hands, "line": line}


func _count(key: String) -> int:
	return int(_counts.get(key, 0))


func _bump(key: String) -> void:
	_counts[key] = _count(key) + 1


func _fail(message: String) -> void:
	if _errors.size() < MAX_ERRORS:
		_errors.append("%s: %s" % [_context, message])


func _next_seed() -> int:
	_seed_counter += 1
	return _seed_counter


# ---------------------------------------------------------------- uma partida


func _play_game() -> void:
	var transport: LocalTransport = LocalTransport.new()
	transport.use_json = _games % 2 == 1
	var clock: Clock = Clock.new(true)
	var server: Server = Server.new(transport, clock, {"room": ROOM_CONFIG}, _next_seed)
	var tournament: bool = _games % 3 == 2
	var seats: int = _rng.randi_range(2, 9)
	var human_count: int = mini(_rng.randi_range(1, 3), seats)
	var bots: Array = []
	for _i in _rng.randi_range(0 if human_count > 1 else 1, seats - human_count):
		bots.append(_rng.randi_range(1, 3))
	var options: Dictionary = {
		"format": Table.TOURNAMENT if tournament else Table.CLASSIC, "seats": seats,
		"turn_seconds": [15, 15, 30, 0][_rng.randi() % 4], "bots": bots,
	}
	if tournament:
		options["level_minutes"] = 3
		options["starting_stack"] = [3000, 1000, 400][_rng.randi() % 3]
	else:
		options["rebuy_limit"] = [-1, -1, 1, 0][_rng.randi() % 4]
		options["keep_open"] = _rng.randf() < 0.3
	if options["turn_seconds"] == 0:
		options["turn_seconds"] = 15   # sem limite, um roteiro parado travaria a mesa de propósito

	var people: Array[Person] = []
	for i in human_count + 1:
		var person: Person = Person.new()
		person.nick = "Gente %d" % i
		person.device = "aparelho-%d-%d" % [_games, i]
		person.watcher = i == human_count
		person.client = transport.connect_client()
		person.client.send({"t": Protocol.HELLO, "v": Protocol.VERSION, "nick": person.nick,
			"avatar": i, "device": person.device})
		people.append(person)
	people[0].client.send({"t": Protocol.CREATE_ROOM, "options": options})
	_pump(server, people)
	if server.rooms.is_empty():
		_fail("a sala não foi criada: " + str(options))
		return
	var room_id: String = server.rooms.keys()[0]
	_room = server.rooms[room_id]
	_room.tap = _inspect
	for i in range(1, people.size()):
		people[i].client.send({"t": Protocol.JOIN_ROOM, "room": room_id, "spectate": people[i].watcher})
	_pump(server, people)
	_watcher_id = people[human_count].member_id
	people[0].client.send({"t": Protocol.START})

	var last_seq: int = -1
	var still: int = 0
	var ticks: int = 0
	while not _room.is_closed() and _room.table.hand_number < MAX_HANDS_PER_GAME and _errors.is_empty():
		ticks += 1
		if ticks > MAX_HANDS_PER_GAME * 80:
			break
		for person in people:
			_script(person, transport, room_id)
		clock.advance(STEP_MS)
		_pump(server, people)
		_check_room()
		# Mesa que pode andar e não anda: travou.
		var movable: bool = (_room.phase == Protocol.PLAYING and not _room.paused
			and (_room.table.hand_in_progress() or _room.table.can_start_hand()))
		if _room._seq != last_seq or not movable:
			still = 0
			last_seq = _room._seq
		else:
			still += 1
			if still > STUCK_TICKS:
				_fail("a mesa travou na mão %d" % _room.table.hand_number)
				break
	if not _room.is_closed():
		_room.close(Protocol.R_OWNER)
	_check_final()
	_hands += _room.table.hand_number
	_room.tap = Callable()
	_room = null


## Entrega o que está nas filas e faz o servidor andar.
func _pump(server: Server, people: Array[Person]) -> void:
	server.tick()
	for person in people:
		if person.client == null:
			continue
		for message: Dictionary in person.client.poll():
			match message["t"]:
				Protocol.JOINED:
					person.member_id = message["you"]
					person.in_room = true
				Protocol.STATE:
					person.state = message
				Protocol.LEFT, Protocol.CLOSED:
					person.in_room = false
					person.state = {}
				Protocol.ERROR:
					if message["code"] == Protocol.E_REFUSED or message["code"] == Protocol.E_BAD_MESSAGE:
						_bump("refused")
					elif message["code"] != Protocol.E_NO_ROOM:
						_fail("erro inesperado: " + str(message))


# ---------------------------------------------------------------- roteiro de uma pessoa


func _script(person: Person, transport: LocalTransport, room_id: String) -> void:
	if person.watcher:
		if person.in_room and _room.paused and _room.owner_id == person.member_id:
			person.client.send({"t": Protocol.OWNER, "cmd": Protocol.CMD_RESUME})
		return
	if not person.in_room:
		_maybe_return(person, transport, room_id)
		return
	var roll: float = _rng.randf()
	if roll < 0.002:
		_bump("leave")
		person.client.send({"t": Protocol.LEAVE})
		person.in_room = false
		person.back_in = _rng.randi_range(5, 80)
		return
	if roll < 0.003:
		_bump("drop")
		person.client.close()
		person.client = null
		person.in_room = false
		person.back_in = _rng.randi_range(5, 80)
		return
	if roll < 0.005:
		person.client.send([{"t": "zzz"}, {"t": 7}, {"t": Protocol.ACT, "seq": "x"},
			{"t": Protocol.OWNER, "cmd": "voar"}, {"t": Protocol.SIT, "seat": 99}][_rng.randi() % 5])
	if _room.owner_id == person.member_id:
		_owner_moves(person)
	var you: Dictionary = person.state.get("you", {})
	var seated: bool = int(you.get("seat", -1)) >= 0
	if you.has("rebuy_ms"):
		var answer: float = _rng.randf()
		if answer < 0.15:
			person.client.send({"t": Protocol.REBUY, "accept": answer < 0.11})
	elif you.has("return_offer"):
		# Voltou com fichas guardadas: escolhe as de antes ou as iniciais.
		if you["return_offer"].get("seat", false) and _rng.randf() < 0.05:
			person.client.send({"t": Protocol.RETURN_CHOICE, "keep": _rng.randf() < 0.6})
	elif not seated and _rng.randf() < 0.02:
		person.client.send({"t": Protocol.SIT})
	if seated and _rng.randf() < 0.004:
		var away: bool = not _member_away(person)
		if away:
			_bump("away_on")
		person.client.send({"t": Protocol.AWAY, "on": away})
	elif seated and _member_away(person) and _rng.randf() < 0.05:
		person.client.send({"t": Protocol.AWAY, "on": false})
	if you.has("legal"):
		_play(person, you["legal"])


func _member_away(person: Person) -> bool:
	for entry: Dictionary in person.state.get("room", {}).get("members", []):
		if entry["id"] == person.member_id:
			return bool(entry["away"])
	return false


## A jogada de quem está na vez: às vezes demora (e estoura o tempo), às vezes manda
## um número de vez velho, quase sempre joga algo válido ao acaso.
func _play(person: Person, legal: Dictionary) -> void:
	if person.idle > 0:
		person.idle -= 1
		return
	var roll: float = _rng.randf()
	if roll < 0.03:
		person.idle = _rng.randi_range(10, 70)   # largou o celular: costuma estourar o tempo
		return
	if roll < 0.12:
		return
	var seq: int = int(person.state["table"]["seq"])
	if roll < 0.14:
		seq -= 1
	var action: String = Hand.CHECK if legal["can_check"] else Hand.CALL
	var amount: int = 0
	var pick: float = _rng.randf()
	if pick < 0.15 and not legal["can_check"]:
		action = Hand.FOLD
	elif pick > 0.75 and legal["can_raise"]:
		action = Hand.BET if legal["is_bet"] else Hand.RAISE
		amount = int(legal["max_to"]) if _rng.randf() < 0.2 else _rng.randi_range(
			int(legal["min_to"]), int(legal["max_to"]))
	person.client.send({"t": Protocol.ACT, "seq": seq, "action": action, "amount": amount})


func _owner_moves(person: Person) -> void:
	var roll: float = _rng.randf()
	if _room.paused:
		if roll < 0.1:
			person.client.send({"t": Protocol.OWNER, "cmd": Protocol.CMD_RESUME})
		return
	if roll < 0.002:
		_bump("pause")
		person.client.send({"t": Protocol.OWNER, "cmd": Protocol.CMD_PAUSE})
	elif roll < 0.003:
		var target: String = _random_member(false, person.member_id)
		if target != "":
			_bump("kick")
			person.client.send({"t": Protocol.OWNER, "cmd": Protocol.CMD_KICK, "id": target})
	elif roll < 0.005:
		person.client.send({"t": Protocol.OWNER, "cmd": Protocol.CMD_ADD_BOT, "level": _rng.randi_range(1, 3)})
	elif roll < 0.007:
		person.client.send({"t": Protocol.OWNER, "cmd": Protocol.CMD_REMOVE_BOT,
			"id": _random_member(true, "")})
	elif roll < 0.009:
		var small: int = [5, 10, 20, 50][_rng.randi() % 4]
		person.client.send({"t": Protocol.OWNER, "cmd": Protocol.CMD_SETTINGS,
			"small_blind": small, "big_blind": small * _rng.randi_range(1, 3),
			"turn_seconds": [15, 30][_rng.randi() % 2]})


func _random_member(bot: bool, except: String) -> String:
	var list: Array = []
	for member: Room.Member in _room.members.values():
		if member.is_bot == bot and member.id != except and member.id != _watcher_id:
			list.append(member.id)
	return "" if list.is_empty() else list[_rng.randi() % list.size()]


## Quem saiu ou caiu volta depois de um tempo, com uma conexão nova se for preciso.
func _maybe_return(person: Person, transport: LocalTransport, room_id: String) -> void:
	if person.back_in < 0 or person.banned:
		return
	person.back_in -= 1
	if person.back_in > 0:
		return
	person.back_in = -1
	if person.client == null:
		person.client = transport.connect_client()
		person.client.send({"t": Protocol.HELLO, "v": Protocol.VERSION, "nick": person.nick,
			"avatar": 0, "device": person.device})
	person.client.send({"t": Protocol.JOIN_ROOM, "room": room_id})


# ---------------------------------------------------------------- conferências


func _check_room() -> void:
	_checks += 1
	if not _room.table.is_balanced():
		_fail("caixa de fichas desequilibrada na mão %d" % _room.table.hand_number)
	if _room.bot_errors > 0:
		_fail("%d jogada(s) de bot recusada(s)" % _room.bot_errors)
		_room.bot_errors = 0
	for seat in _room.table.seats:
		if seat.stack < 0:
			_fail("fichas negativas no lugar %d" % seat.index)


func _check_final() -> void:
	_checks += 1
	if not _room.table.is_balanced():
		_fail("caixa de fichas desequilibrada no fim")
	var final: Dictionary = _room.final
	if final.is_empty() or final["t"] != Protocol.CLOSED:
		_fail("a sala não mandou o placar final")
		return
	if _room.table.format == Table.TOURNAMENT and final["reason"] == Protocol.R_FINISHED:
		# Quem cai na mesma mão com as mesmas fichas divide a colocação (SPEC 3.5).
		var places: Array = []
		for row: Dictionary in final["podium"]:
			places.append(int(row["place"]))
		var on_board: int = 0
		for row: Dictionary in final["scoreboard"]:
			if int(row["place"]) >= 1 and int(row["place"]) <= 3:
				on_board += 1
		var sorted: Array = places.duplicate()
		sorted.sort()
		if places.count(1) != 1 or sorted != places or places.size() != on_board:
			_fail("pódio errado: " + str(places))


## Toda mensagem que a sala entrega passa por aqui (room.tap).
func _inspect(member_id: String, message: Dictionary) -> void:
	if message["t"] != Protocol.STATE:
		return
	_checks += 1
	var member: Room.Member = _room.members.get(member_id)
	var you: Dictionary = message["you"]
	var table: Table = _room.table
	var hand: Hand = table.hand
	for key: String in you.keys():
		if not YOU_KEYS.has(key):
			_fail("campo inesperado em you: " + key)
	if message["table"].has("deck") or message["room"].has("device"):
		_fail("dado secreto na mensagem")
	if you.has("cards"):
		var seat: int = int(you["seat"])
		if member == null or seat < 0 or hand == null or _room._hand_ids.get(seat, "") != member_id:
			_fail("cartas para quem não está na mão: " + member_id)
		elif you["cards"] != Array(hand.player_at(seat).cards):
			_fail("cartas erradas para " + member_id)
	if you.has("legal") and (hand == null or not table.hand_in_progress() or hand.to_act != int(you["seat"])):
		_fail("ações válidas para quem não está na vez: " + member_id)
	var shown: Dictionary = {}
	if hand != null:
		for entry: Dictionary in hand.result.get("shown", []):
			shown[int(entry["seat"])] = true
	for entry: Dictionary in message["table"]["seats"]:
		for key: String in entry.keys():
			if not SEAT_KEYS.has(key):
				_fail("campo inesperado no lugar: " + key)
		if entry.has("cards"):
			var player: Hand.Player = hand.player_at(int(entry["seat"])) if hand != null else null
			var open: bool = player != null and ((hand.revealed and not player.folded)
				or shown.has(int(entry["seat"])))
			if not open:
				_fail("cartas fechadas na parte pública, lugar %d" % int(entry["seat"]))
	for member_entry: Dictionary in message["room"]["members"]:
		if member_entry.has("device"):
			_fail("código do aparelho vazou")
	if member_id == _watcher_id:
		if not you.get("cards", []).is_empty():
			_fail("espectador recebeu cartas")
		for event: Dictionary in message["events"]:
			_bump(str(event.get("type", "")))
