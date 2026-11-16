extends "res://ui/app/game_session.gd"
## Partida offline: o servidor de mesa roda dentro do app, ligado pelo transporte local,
## sem rede (SPEC 2 e 8). O app fala com ele só pelo protocolo (SPEC 9.1): hello,
## create_room, start, act, rebuy, away e leave; e desenha cada mensagem state.

const Server := preload("res://server/server.gd")
const Clock := preload("res://server/clock.gd")
const LocalTransport := preload("res://net/local_transport.gd")

var _transport: LocalTransport = null
var _server: Server = null
var _started: bool = false


## clock, room_config e seed_source: só nos testes (relógio manual, sem esperas).
func _init(clock: Clock = null, room_config: Dictionary = {},
		seed_source: Callable = Callable()) -> void:
	_transport = LocalTransport.new()
	_server = Server.new(_transport, clock if clock != null else Clock.new(),
		{"max_rooms": 1, "room": room_config}, seed_source)
	_client = _transport.connect_client()


## Apresenta-se e cria a sala; a partida começa assim que a sala confirma a entrada.
func begin(nick: String, avatar: int, device: String, options: Dictionary) -> void:
	send({"t": Protocol.HELLO, "v": Protocol.VERSION, "nick": nick,
		"avatar": avatar, "device": device})
	send({"t": Protocol.CREATE_ROOM, "options": options})


func _pump() -> void:
	_server.tick()


func _track(message: Dictionary) -> void:
	super(message)
	if message.get("t") == Protocol.JOINED and not _started:
		_started = true
		start()


## Sai da mesa e devolve o placar. Sem outro humano, a sala encerra na hora; no modo
## offline o servidor está aqui dentro, então o placar vem direto da sala.
func leave() -> Dictionary:
	if not final.is_empty():
		return final
	var room: Object = _server.rooms.get(room_id)
	send({"t": Protocol.LEAVE})
	update()
	if room != null and not (room.get("final") as Dictionary).is_empty():
		final = room.get("final")
	return final
