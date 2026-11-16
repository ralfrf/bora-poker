extends RefCounted
## Transporte local em memória (SPEC 8): no modo offline as mensagens do protocolo
## passam direto do app para o servidor de mesa, sem rede.
##
## As mensagens ficam em filas e só são entregues em poll(), dos dois lados. Assim um
## lado nunca chama o outro no meio de uma jogada.
##
## Lado do servidor (o mesmo contrato que o transporte de rede vai seguir):
##   poll() -> [{type: "connect" | "message" | "disconnect", peer, data}]
##   send(peer, mensagem), drop(peer)
## Lado do app: connect_client() devolve uma ponta com send, poll, close e is_open.

const Codec := preload("res://net/codec.gd")


class Endpoint:
	extends RefCounted

	var peer: int = 0
	var _transport: WeakRef = null
	var _inbox: Array[Dictionary] = []
	var _open: bool = true

	func send(message: Dictionary) -> void:
		var transport: Object = _transport.get_ref() if _transport != null else null
		if _open and transport != null:
			transport.call("_from_client", peer, message)

	## Mensagens que chegaram do servidor desde a última chamada.
	func poll() -> Array[Dictionary]:
		var messages: Array[Dictionary] = _inbox
		_inbox = []
		return messages

	func close() -> void:
		if not _open:
			return
		_open = false
		var transport: Object = _transport.get_ref() if _transport != null else null
		if transport != null:
			transport.call("_client_closed", peer)

	func is_open() -> bool:
		return _open


## Verdadeiro: cada mensagem vira texto JSON e volta, como acontece na rede. Os testes
## ligam isto para garantir que o protocolo sobrevive à viagem.
var use_json: bool = false

var _endpoints: Dictionary = {}   # peer -> Endpoint
var _events: Array[Dictionary] = []
var _next_peer: int = 1


func connect_client() -> Endpoint:
	var endpoint: Endpoint = Endpoint.new()
	endpoint.peer = _next_peer
	endpoint._transport = weakref(self)
	_next_peer += 1
	_endpoints[endpoint.peer] = endpoint
	_events.append({"type": "connect", "peer": endpoint.peer, "data": {}})
	return endpoint


## Lado do servidor: o que aconteceu desde a última chamada.
func poll() -> Array[Dictionary]:
	var events: Array[Dictionary] = _events
	_events = []
	return events


func send(peer: int, message: Dictionary) -> void:
	var endpoint: Endpoint = _endpoints.get(peer)
	if endpoint != null and endpoint._open:
		endpoint._inbox.append(_copy(message))


## O servidor encerra a conexão.
func drop(peer: int) -> void:
	var endpoint: Endpoint = _endpoints.get(peer)
	if endpoint == null:
		return
	endpoint._open = false
	_endpoints.erase(peer)
	_events.append({"type": "disconnect", "peer": peer, "data": {}})


func _from_client(peer: int, message: Dictionary) -> void:
	if _endpoints.has(peer):
		_events.append({"type": "message", "peer": peer, "data": _copy(message)})


func _client_closed(peer: int) -> void:
	if _endpoints.erase(peer):
		_events.append({"type": "disconnect", "peer": peer, "data": {}})


## Cada lado recebe a sua cópia: ninguém mexe no dicionário do outro.
func _copy(message: Dictionary) -> Dictionary:
	if use_json:
		return Codec.decode(Codec.encode(message))
	return message.duplicate(true)
