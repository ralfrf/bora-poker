extends RefCounted
## Partida offline: o servidor de mesa roda dentro do app, ligado pelo transporte local,
## sem rede (SPEC 2 e 8). O app fala com ele só pelo protocolo (SPEC 9.1): hello,
## create_room, start, act, rebuy, away e leave; e desenha cada mensagem state.
##
## Quem usa chama update() a cada quadro: faz o servidor andar (relógios, bots, mãos)
## e devolve as mensagens que chegaram.

const Server := preload("res://server/server.gd")
const Clock := preload("res://server/clock.gd")
const Protocol := preload("res://server/protocol.gd")
const LocalTransport := preload("res://net/local_transport.gd")

var my_id: String = ""
var room_id: String = ""
var last_state: Dictionary = {}
## A mensagem closed (placar), quando a sala encerra.
var final: Dictionary = {}

var _transport: LocalTransport = null
var _server: Server = null
var _client: LocalTransport.Endpoint = null
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
	_client.send({"t": Protocol.HELLO, "v": Protocol.VERSION, "nick": nick,
		"avatar": avatar, "device": device})
	_client.send({"t": Protocol.CREATE_ROOM, "options": options})


func update() -> Array[Dictionary]:
	_server.tick()
	var messages: Array[Dictionary] = _client.poll()
	for message: Dictionary in messages:
		match message.get("t"):
			Protocol.JOINED:
				my_id = str(message.get("you", ""))
				room_id = str(message.get("room", ""))
				if not _started:
					_started = true
					_client.send({"t": Protocol.START})
			Protocol.STATE:
				last_state = message
			Protocol.CLOSED:
				final = message
	return messages


## Jogada na sua vez. Leva o número da vez do último state, para um toque atrasado não
## valer na vez seguinte.
func act(action: String, amount: int) -> void:
	var seq: int = int(last_state.get("table", {}).get("seq", -1))
	_client.send({"t": Protocol.ACT, "seq": seq, "action": action, "amount": amount})


func rebuy(accept: bool) -> void:
	_client.send({"t": Protocol.REBUY, "accept": accept})


## "Voltei": deixa de estar ausente.
func back() -> void:
	_client.send({"t": Protocol.AWAY, "on": false})


## Sai da mesa e devolve o placar. Sem outro humano, a sala encerra na hora; no modo
## offline o servidor está aqui dentro, então o placar vem direto da sala.
func leave() -> Dictionary:
	if not final.is_empty():
		return final
	var room: Object = _server.rooms.get(room_id)
	_client.send({"t": Protocol.LEAVE})
	update()
	if room != null and not (room.get("final") as Dictionary).is_empty():
		final = room.get("final")
	return final
