extends RefCounted
## Descoberta de salas no Wi-Fi (SPEC 9.2). O anfitrião anuncia a sala por broadcast
## UDP numa porta fixa a cada 1,5 s; os outros celulares escutam e montam a lista. Uma
## sala some da lista depois de EXPIRE_MS sem anúncio.
##
## No Android, ligar o broadcast no socket faz o Godot segurar a trava de multicast do
## Wi-Fi (precisa da permissão CHANGE_WIFI_MULTICAST_STATE); sem ela, muitos aparelhos
## jogam fora os pacotes de broadcast.

const Clock := preload("res://server/clock.gd")
const RoomCode := preload("res://net/room_code.gd")

const PORT: int = 47821
const ANNOUNCE_MS: int = 1500
const EXPIRE_MS: int = 5000
const APP: String = "bora-poker"
const VERSION: int = 1
const MAX_PACKET: int = 1024


## Lado do anfitrião: manda o anúncio de tempos em tempos.
class Announcer:
	extends RefCounted

	var targets: Array[String] = []
	var port: int = PORT

	var _udp: PacketPeerUDP = PacketPeerUDP.new()
	var _clock: Clock = null
	var _last: int = -ANNOUNCE_MS

	## targets: para onde mandar (os testes usam 127.0.0.1); vazio = broadcast da rede.
	func _init(clock: Clock = null, to: Array[String] = [], to_port: int = PORT) -> void:
		_clock = clock if clock != null else Clock.new()
		targets = to
		port = to_port
		_udp.set_broadcast_enabled(true)

	## info: {name, format, seats, players, phase, open, port}. Manda se já deu a hora.
	func poll(info: Dictionary) -> void:
		var now: int = _clock.now_ms()
		if now - _last < ANNOUNCE_MS:
			return
		_last = now
		var packet: Dictionary = info.duplicate()
		packet["app"] = APP
		packet["v"] = VERSION
		var bytes: PackedByteArray = JSON.stringify(packet).to_utf8_buffer()
		var list: Array[String] = targets
		if list.is_empty():
			list = RoomCode.broadcast_addresses(RoomCode.local_ip())
		for address: String in list:
			_udp.set_dest_address(address, port)
			_udp.put_packet(bytes)

	func close() -> void:
		_udp.close()


## Lado de quem procura: escuta os anúncios e guarda as salas vistas.
class Listener:
	extends RefCounted

	## ip -> {ip, port, name, format, seats, players, phase, open, seen}
	var rooms: Dictionary = {}

	var _udp: PacketPeerUDP = PacketPeerUDP.new()
	var _clock: Clock = null

	func _init(clock: Clock = null) -> void:
		_clock = clock if clock != null else Clock.new()

	func listen(listen_port: int = PORT) -> Error:
		_udp.close()
		_udp.set_broadcast_enabled(true)
		return _udp.bind(listen_port, "*")

	func is_listening() -> bool:
		return _udp.is_bound()

	## Lê os anúncios que chegaram e esquece as salas caladas. Devolve verdadeiro se a
	## lista mudou.
	func poll() -> bool:
		var now: int = _clock.now_ms()
		var changed: bool = false
		while _udp.is_bound() and _udp.get_available_packet_count() > 0:
			var bytes: PackedByteArray = _udp.get_packet()
			var ip: String = _udp.get_packet_ip()
			var room: Dictionary = parse(bytes, ip)
			if room.is_empty():
				continue
			room["seen"] = now
			var old: Dictionary = rooms.get(ip, {})
			old.erase("seen")
			var fresh: Dictionary = room.duplicate()
			fresh.erase("seen")
			if old != fresh:
				changed = true
			rooms[ip] = room
		for ip: String in rooms.keys():
			if now - int(rooms[ip]["seen"]) > EXPIRE_MS:
				rooms.erase(ip)
				changed = true
		return changed

	## As salas na ordem do nome.
	func list() -> Array:
		var result: Array = rooms.values()
		result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return str(a["name"]) < str(b["name"]))
		return result

	func close() -> void:
		_udp.close()

	## Confere um anúncio. Devolve a sala, ou {} se não for nosso ou vier malformado.
	static func parse(bytes: PackedByteArray, ip: String) -> Dictionary:
		if bytes.size() > MAX_PACKET or ip == "":
			return {}
		var json: JSON = JSON.new()
		if json.parse(bytes.get_string_from_utf8()) != OK or typeof(json.data) != TYPE_DICTIONARY:
			return {}
		var data: Dictionary = json.data
		if data.get("app") != APP or int(data.get("v", 0)) != VERSION:
			return {}
		var port: int = int(data.get("port", 0))
		if port <= 0 or port > 65535:
			return {}
		return {
			"ip": ip, "port": port,
			"name": str(data.get("name", "")).left(40),
			"format": str(data.get("format", "")),
			"seats": int(data.get("seats", 0)),
			"players": int(data.get("players", 0)),
			"phase": str(data.get("phase", "")),
			"open": bool(data.get("open", false)),
		}
