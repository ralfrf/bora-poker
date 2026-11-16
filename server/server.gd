extends RefCounted
## Servidor de salas: liga as conexões de um transporte às salas (SPEC 8 e 9.1).
##
## É o mesmo nos três modos. No offline fica dentro do app, com o transporte local e
## uma sala só; no Wi-Fi e no Render o transporte é de rede. Quem hospeda chama tick()
## de tempos em tempos.
##
## O transporte só precisa ter: poll() -> [{type, peer, data}], send(peer, mensagem) e
## drop(peer).

const Room := preload("res://server/room.gd")
const Protocol := preload("res://server/protocol.gd")
const Clock := preload("res://server/clock.gd")

const DEFAULT_MAX_ROOMS: int = 20
const MAX_DEVICE: int = 64
const CODE_CHARS: String = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   # sem 0, O, 1 e I
const CODE_LENGTH: int = 4


class Session:
	extends RefCounted

	var peer: int = 0
	var greeted: bool = false
	var nick: String = ""
	var avatar: int = 0
	var device: String = ""
	var room_id: String = ""
	var member_id: String = ""


var rooms: Dictionary = {}   ## código da sala -> Room

var _transport: Object = null
var _clock: Clock = null
var _max_rooms: int = DEFAULT_MAX_ROOMS
var _room_config: Dictionary = {}
var _seed_source: Callable = Callable()
var _sessions: Dictionary = {}   # peer -> Session
var _routes: Dictionary = {}     # "sala/participante" -> peer
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## config: {max_rooms, room: ajustes repassados a cada sala}.
## seed_source: só nos testes; repassado às salas.
func _init(transport: Object, clock: Clock = null, config: Dictionary = {},
		seed_source: Callable = Callable()) -> void:
	_transport = transport
	_clock = clock if clock != null else Clock.new()
	_max_rooms = int(config.get("max_rooms", DEFAULT_MAX_ROOMS))
	_room_config = config.get("room", {})
	_seed_source = seed_source
	if seed_source.is_valid():
		_rng.seed = int(seed_source.call())
	else:
		_rng.randomize()


## Lê o que chegou, faz o tempo das salas andar e apaga as salas encerradas.
func tick() -> void:
	for event: Dictionary in _transport.call("poll"):
		var peer: int = event["peer"]
		match event["type"]:
			"connect":
				var session: Session = Session.new()
				session.peer = peer
				_sessions[peer] = session
			"disconnect":
				_disconnected(peer)
			"message":
				var session: Session = _sessions.get(peer)
				if session != null and typeof(event["data"]) == TYPE_DICTIONARY:
					_message(session, event["data"])
	for room: Room in rooms.values():
		room.tick()
	for room_id: String in rooms.keys():
		if rooms[room_id].is_closed():
			rooms.erase(room_id)


func _message(session: Session, data: Dictionary) -> void:
	var type: Variant = data.get("t")
	if typeof(type) != TYPE_STRING:
		_refuse(session, Protocol.E_BAD_MESSAGE, "mensagem malformada")
		return
	if type == Protocol.PING:
		_reply(session, {"t": Protocol.PONG})
		return
	if type == Protocol.HELLO:
		_hello(session, data)
		return
	if not session.greeted:
		_refuse(session, Protocol.E_NO_HELLO, "falta a apresentação")
		return
	match type:
		Protocol.LIST_ROOMS:
			var list: Array = []
			for room: Room in rooms.values():
				if not room.is_closed():
					list.append(room.summary())
			_reply(session, {"t": Protocol.ROOMS, "rooms": list})
		Protocol.CREATE_ROOM:
			_create_room(session, data)
		Protocol.JOIN_ROOM:
			_join_room(session, data)
		Protocol.LEAVE:
			_leave(session)
		_:
			var room: Room = rooms.get(session.room_id)
			if room == null:
				_refuse(session, Protocol.E_NO_ROOM, "você não está em uma sala")
			else:
				room.handle(session.member_id, data)


## Toda conexão começa pela versão do protocolo (SPEC 9.1).
func _hello(session: Session, data: Dictionary) -> void:
	var version: Variant = data.get("v")
	if typeof(version) != TYPE_INT or version != Protocol.VERSION:
		_refuse(session, Protocol.E_VERSION, "Atualize o app.")
		_sessions.erase(session.peer)
		_transport.call("drop", session.peer)
		return
	var nick: Variant = data.get("nick", "")
	var avatar: Variant = data.get("avatar", 0)
	var device: Variant = data.get("device", "")
	if typeof(nick) != TYPE_STRING or typeof(avatar) != TYPE_INT or typeof(device) != TYPE_STRING:
		_refuse(session, Protocol.E_BAD_MESSAGE, "apresentação malformada")
		return
	session.nick = Room.clean_nick(nick)
	session.avatar = clampi(avatar, 0, Room.AVATARS - 1)
	session.device = (device as String).left(MAX_DEVICE)
	session.greeted = true
	_reply(session, {"t": Protocol.WELCOME, "v": Protocol.VERSION, "nick": session.nick})


func _create_room(session: Session, data: Dictionary) -> void:
	if session.room_id != "":
		_refuse(session, Protocol.E_REFUSED, "você já está em uma sala")
		return
	if rooms.size() >= _max_rooms:
		_refuse(session, Protocol.E_REFUSED, "o servidor está cheio; tente mais tarde")
		return
	var checked: Dictionary = Room.normalize_options(data.get("options", {}))
	if not checked["ok"]:
		_refuse(session, Protocol.E_REFUSED, checked["error"])
		return
	var options: Dictionary = checked["options"]
	if (options["bots"] as Array).size() >= int(options["seats"]):
		_refuse(session, Protocol.E_REFUSED, "deixe um lugar para você")
		return
	var room_id: String = _new_code()
	var room: Room = Room.new(
		room_id, options, _clock, _deliver.bind(room_id), _room_config, _seed_source)
	rooms[room_id] = room
	_enter(session, room, false)


func _join_room(session: Session, data: Dictionary) -> void:
	if session.room_id != "":
		_refuse(session, Protocol.E_REFUSED, "você já está em uma sala")
		return
	var room_id: Variant = data.get("room")
	var spectate: Variant = data.get("spectate", false)
	if typeof(room_id) != TYPE_STRING or typeof(spectate) != TYPE_BOOL:
		_refuse(session, Protocol.E_BAD_MESSAGE, "pedido malformado")
		return
	var room: Room = rooms.get((room_id as String).to_upper())
	if room == null or room.is_closed():
		_refuse(session, Protocol.E_NO_ROOM, "sala não encontrada")
		return
	_enter(session, room, spectate)


func _enter(session: Session, room: Room, spectate: bool) -> void:
	var result: Dictionary = room.join(
		{"nick": session.nick, "avatar": session.avatar, "device": session.device}, spectate)
	if not result["ok"]:
		_refuse(session, Protocol.E_REFUSED, result["error"])
		return
	session.room_id = room.id
	session.member_id = result["id"]
	_routes[_key(room.id, session.member_id)] = session.peer
	_reply(session, {"t": Protocol.JOINED, "room": room.id, "you": session.member_id})
	room.announce()


func _leave(session: Session) -> void:
	var room: Room = rooms.get(session.room_id)
	if room == null:
		_refuse(session, Protocol.E_NO_ROOM, "você não está em uma sala")
		return
	var member_id: String = session.member_id
	_routes.erase(_key(room.id, member_id))
	session.room_id = ""
	session.member_id = ""
	room.leave(member_id)
	_reply(session, {"t": Protocol.LEFT, "reason": Protocol.R_LEFT})


## A conexão caiu. Por ora vale como sair da sala; a espera de 60 s e a volta são da
## etapa 4 (SPEC 6).
func _disconnected(peer: int) -> void:
	var session: Session = _sessions.get(peer)
	if session == null:
		return
	_sessions.erase(peer)
	var room: Room = rooms.get(session.room_id)
	if room != null:
		_routes.erase(_key(room.id, session.member_id))
		room.leave(session.member_id)


## A saída das salas: entrega a mensagem à conexão do participante.
func _deliver(member_id: String, message: Dictionary, room_id: String) -> void:
	var key: String = _key(room_id, member_id)
	if not _routes.has(key):
		return
	var peer: int = _routes[key]
	_transport.call("send", peer, message)
	if message["t"] == Protocol.LEFT or message["t"] == Protocol.CLOSED:
		# Expulso, ou a sala encerrou: a conexão fica livre para outra sala.
		_routes.erase(key)
		var session: Session = _sessions.get(peer)
		if session != null:
			session.room_id = ""
			session.member_id = ""


func _reply(session: Session, message: Dictionary) -> void:
	_transport.call("send", session.peer, message)


func _refuse(session: Session, code: String, text: String) -> void:
	_reply(session, Protocol.error(code, text))


func _key(room_id: String, member_id: String) -> String:
	return room_id + "/" + member_id


## Código curto da sala, fácil de ditar (a entrada por código é da etapa 4).
func _new_code() -> String:
	while true:
		var code: String = ""
		for _i in CODE_LENGTH:
			code += CODE_CHARS[_rng.randi_range(0, CODE_CHARS.length() - 1)]
		if not rooms.has(code):
			return code
	return ""
