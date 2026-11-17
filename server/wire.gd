extends RefCounted
## Protocolo enxuto na rede (SPEC 9.1). As mensagens pequenas viajam como texto JSON.
## As grandes viajam em quadros binários:
##
##   [1][tamanho u32][JSON compactado]               qualquer mensagem grande
##   [2][tem room u8][tamanho u32][tamanho compactado u32][parte pública][parte pessoal]
##
## No `state`, a parte pública ({room?, table, events}) é montada e compactada uma vez
## por lance e a mesma cópia vai para todos; `room` só vai a quem ainda não tem a versão
## atual. A parte pessoal é o `you` de cada um, em JSON sem compactar (é pequena). O app
## remonta a foto completa com o último `room` que recebeu.

const Codec := preload("res://net/codec.gd")
const Protocol := preload("res://server/protocol.gd")

const KIND_MESSAGE: int = 1
const KIND_STATE: int = 2
## Texto acima disso vai compactado.
const COMPRESS_MIN: int = 512
## Teto do tamanho descompactado que o app aceita.
const MAX_RAW: int = 1 << 22
const MODE: int = FileAccess.COMPRESSION_DEFLATE

## As partes públicas de um lance, compactadas só quando alguém precisa delas.
class StatePack:
	extends RefCounted

	var _room_json: String = ""
	var _room: Dictionary = {}
	var _table: Dictionary = {}
	var _events: Array = []
	var _with_room: PackedByteArray = PackedByteArray()
	var _without_room: PackedByteArray = PackedByteArray()

	func _init(room: Dictionary, table: Dictionary, events: Array) -> void:
		_room = room
		_table = table
		_events = events

	## room em JSON, montado na primeira vez: o transporte compara com o último que
	## cada conexão recebeu.
	func room_json() -> String:
		if _room_json == "":
			_room_json = JSON.stringify(_room)
		return _room_json

	## O quadro de uma pessoa. with_room: a conexão ainda não tem este room.
	func frame(you: Dictionary, with_room: bool) -> PackedByteArray:
		var shared: PackedByteArray = _shared(with_room)
		var head: PackedByteArray = PackedByteArray()
		head.resize(2)
		head[0] = KIND_STATE
		head[1] = 1 if with_room else 0
		return head + shared + JSON.stringify(you).to_utf8_buffer()

	## [tamanho u32][tamanho compactado u32][compactado]
	static func block(raw: PackedByteArray) -> PackedByteArray:
		var packed: PackedByteArray = raw.compress(MODE)
		var head: PackedByteArray = PackedByteArray()
		head.resize(8)
		head.encode_u32(0, raw.size())
		head.encode_u32(4, packed.size())
		return head + packed

	func _shared(with_room: bool) -> PackedByteArray:
		if with_room:
			if _with_room.is_empty():
				# O room em JSON já existe: a parte pública é montada a partir dele.
				_with_room = block(('{"room":%s,"table":%s,"events":%s}' % [room_json(),
					JSON.stringify(_table), JSON.stringify(_events)]).to_utf8_buffer())
			return _with_room
		if _without_room.is_empty():
			_without_room = block(JSON.stringify({"table": _table, "events": _events}).to_utf8_buffer())
		return _without_room


## Mensagem comum para a rede: texto, ou quadro binário compactado se for grande.
## Devolve String ou PackedByteArray.
static func encode(message: Dictionary) -> Variant:
	var text: String = Codec.encode(message)
	if text.length() < COMPRESS_MIN:
		return text
	var head: PackedByteArray = PackedByteArray([KIND_MESSAGE])
	return head + StatePack.block(text.to_utf8_buffer())


## Lê um quadro binário. room_cache: {"room": último room recebido}, atualizado aqui.
## Devolve a mensagem completa, ou {} se o quadro estiver estragado.
static func decode(data: PackedByteArray, room_cache: Dictionary) -> Dictionary:
	if data.is_empty():
		return {}
	match data[0]:
		KIND_MESSAGE:
			var raw: PackedByteArray = _unblock(data, 1)
			return {} if raw.is_empty() else Codec.decode(raw.get_string_from_utf8())
		KIND_STATE:
			if data.size() < 10:
				return {}
			var packed: int = data.decode_u32(6)
			if 10 + packed > data.size():
				return {}
			var shared_raw: PackedByteArray = _unblock(data, 2)
			if shared_raw.is_empty():
				return {}
			var shared: Dictionary = Codec.decode(shared_raw.get_string_from_utf8())
			var you: Dictionary = Codec.decode(data.slice(10 + packed).get_string_from_utf8())
			if shared.is_empty() or not shared.has("table"):
				return {}
			if data[1] == 1:
				room_cache["room"] = shared.get("room", {})
			if not room_cache.has("room"):
				return {}
			return {"t": Protocol.STATE, "room": (room_cache["room"] as Dictionary).duplicate(true),
				"table": shared["table"], "you": you, "events": shared.get("events", [])}
	return {}


static func _unblock(data: PackedByteArray, at: int) -> PackedByteArray:
	if data.size() < at + 8:
		return PackedByteArray()
	var raw_size: int = data.decode_u32(at)
	var packed_size: int = data.decode_u32(at + 4)
	if raw_size <= 0 or raw_size > MAX_RAW or at + 8 + packed_size > data.size():
		return PackedByteArray()
	var raw: PackedByteArray = data.slice(at + 8, at + 8 + packed_size).decompress(raw_size, MODE)
	return raw if raw.size() == raw_size else PackedByteArray()
