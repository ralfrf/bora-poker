extends RefCounted
## Junta vários transportes num só, para o servidor de salas (SPEC 8). No Wi-Fi o
## anfitrião joga pelo transporte local e os convidados chegam pelo WebSocket; o
## servidor vê uma lista única de conexões.
##
## O número de cada conexão leva junto qual transporte a trouxe:
## número geral = número no transporte * STRIDE + posição do transporte.

const STRIDE: int = 4

var _parts: Array = []


func add(transport: Object) -> void:
	assert(_parts.size() < STRIDE)
	_parts.append(transport)


func poll() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for index in _parts.size():
		for event: Dictionary in _parts[index].call("poll"):
			var copy: Dictionary = event.duplicate()
			copy["peer"] = int(event["peer"]) * STRIDE + index
			events.append(copy)
	return events


func send(peer: int, message: Dictionary) -> void:
	@warning_ignore("integer_division")
	_parts[peer % STRIDE].call("send", peer / STRIDE, message)


## O `state` pelo protocolo enxuto, quando o transporte da conexão sabe mandar assim.
func send_state(peer: int, message: Dictionary, pack: RefCounted) -> void:
	var part: Object = _parts[peer % STRIDE]
	@warning_ignore("integer_division")
	var inner: int = peer / STRIDE
	if part.has_method("send_state"):
		part.call("send_state", inner, message, pack)
	else:
		part.call("send", inner, message)


## IP da conexão, quando o transporte dela sabe ("" no transporte local).
func peer_ip(peer: int) -> String:
	var part: Object = _parts[peer % STRIDE]
	@warning_ignore("integer_division")
	return str(part.call("peer_ip", peer / STRIDE)) if part.has_method("peer_ip") else ""


func drop(peer: int) -> void:
	@warning_ignore("integer_division")
	_parts[peer % STRIDE].call("drop", peer / STRIDE)
