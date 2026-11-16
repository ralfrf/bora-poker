extends RefCounted
## Ponta do app numa conexão WebSocket (SPEC 9.2). Tem a mesma cara da ponta do
## transporte local: send, poll, close e is_open; mais o estado da conexão.
##
## Batimento: manda "ping" a cada PING_MS. Sem ouvir nada do servidor por SILENCE_MS, a
## conexão é dada como perdida (o Wi-Fi caiu ou o anfitrião sumiu). Os "pong" não
## chegam a quem usa.

const Codec := preload("res://net/codec.gd")
const Clock := preload("res://server/clock.gd")
const Protocol := preload("res://server/protocol.gd")

const PING_MS: int = 2000
const SILENCE_MS: int = 6000
const CONNECT_MS: int = 5000
const PAUSE_GAP_MS: int = 3000
const MAX_MESSAGE: int = 1 << 20

enum Status { IDLE, CONNECTING, OPEN, LOST }

var status: Status = Status.IDLE
var url: String = ""

var _ws: WebSocketPeer = null
var _clock: Clock = null
var _since: int = 0
var _last_heard: int = 0
var _last_ping: int = 0
var _last_poll: int = -1


func _init(clock: Clock = null) -> void:
	_clock = clock if clock != null else Clock.new()


## Começa a conectar em ws://host:porta. O resultado aparece em status, depois de poll().
func open(host: String, port: int) -> Error:
	close()
	url = "ws://%s:%d" % [host, port]
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = MAX_MESSAGE
	_ws.outbound_buffer_size = 65536
	_ws.heartbeat_interval = 0.0
	var error: Error = _ws.connect_to_url(url)
	var now: int = _clock.now_ms()
	_since = now
	_last_heard = now
	_last_ping = now
	status = Status.CONNECTING if error == OK else Status.LOST
	return error


func send(message: Dictionary) -> void:
	if status == Status.OPEN:
		_ws.send_text(Codec.encode(message))


## Mensagens que chegaram desde a última chamada.
func poll() -> Array[Dictionary]:
	var messages: Array[Dictionary] = []
	if _ws == null or status == Status.LOST or status == Status.IDLE:
		return messages
	var now: int = _clock.now_ms()
	if _last_poll >= 0 and now - _last_poll > PAUSE_GAP_MS:
		# O próprio app ficou parado: não culpa a conexão por isso.
		_last_heard = now
	_last_poll = now
	_ws.poll()
	var state: int = _ws.get_ready_state()
	if state == WebSocketPeer.STATE_CONNECTING:
		if now - _since > CONNECT_MS:
			_lose()
		return messages
	if state != WebSocketPeer.STATE_OPEN:
		_lose()
		return messages
	if status == Status.CONNECTING:
		status = Status.OPEN
		_last_heard = now
	while _ws.get_available_packet_count() > 0:
		var packet: PackedByteArray = _ws.get_packet()
		_last_heard = now
		if not _ws.was_string_packet():
			continue
		var message: Dictionary = Codec.decode(packet.get_string_from_utf8())
		if not message.is_empty() and message.get("t") != Protocol.PONG:
			messages.append(message)
	if now - _last_ping >= PING_MS:
		_last_ping = now
		_ws.send_text(Codec.encode({"t": Protocol.PING}))
	if now - _last_heard > SILENCE_MS:
		_lose()
	return messages


func close() -> void:
	if _ws != null and status != Status.LOST:
		_ws.close(1000, "")
	_ws = null
	status = Status.IDLE


func is_open() -> bool:
	return status == Status.OPEN


func _lose() -> void:
	if _ws != null:
		_ws.close()
	status = Status.LOST
