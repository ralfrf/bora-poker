extends RefCounted
## Resumo assinado da sala (SPEC 9.4): o que o servidor à distância entrega a cada
## celular entre as mãos, para recriar a sala se o plano gratuito reiniciar e perder a
## memória. Sem banco de dados: quem guarda são os próprios celulares.
##
## O resumo é o retrato da sala sem a mão (Room.snapshot), mais quem o emitiu (boot),
## quando (at, em segundos do relógio do sistema), a ordem dele na sala (rev) e, se a
## sala tinha senha, uma marca dela (lock, HMAC com o segredo; a senha nunca vai). Formato: base64(Deflate(JSON)) + "." +
## base64(HMAC-SHA256 do compactado), ~1 KB numa mesa de 6. Não é cifrado, então não pode levar nada que não seja público:
## sem cartas, sem senha, e os códigos dos aparelhos vão trocados por uma marca da sala
## (device_tag), que não serve para se passar por ninguém.
##
## O segredo vem da variável de ambiente SUMMARY_SECRET (painel do Render). Sem ela, o
## servidor sorteia um segredo ao ligar: tudo funciona, mas nenhum resumo sobrevive a um
## reinício.

const VERSION: int = 1
## Validade do resumo. O servidor emite de novo a cada REFRESH_S numa mão longa, então
## o celular sempre tem um com menos de REFRESH_S + o tempo da volta.
const VALID_S: int = 600
const REFRESH_S: int = 240
## Tolerância para um resumo "do futuro" (relógio do serviço novo um pouco atrás).
const SKEW_S: int = 60
const MAX_TOKEN: int = 32000
## Teto do JSON descompactado (o compactado já passou pela assinatura).
const MAX_BODY: int = 262144
const TAG_LENGTH: int = 16

## Identifica este servidor desde que ligou: resumo do mesmo boot não recria sala (a
## sala acabou de verdade, não houve reinício).
var boot: String = ""
## O segredo veio de fora (sobrevive a um reinício).
var configured: bool = false

var _crypto: Crypto = Crypto.new()
var _sign_key: PackedByteArray = PackedByteArray()
var _device_key: PackedByteArray = PackedByteArray()
var _lock_key: PackedByteArray = PackedByteArray()
var _base64: RegEx = RegEx.create_from_string("^[A-Za-z0-9+/]+={0,2}$")


func _init(secret: String = "") -> void:
	configured = secret != ""
	var raw: PackedByteArray = secret.to_utf8_buffer() if configured \
		else _crypto.generate_random_bytes(32)
	# Uma chave para cada uso, derivadas do mesmo segredo.
	_sign_key = _hmac(raw, "assinatura".to_utf8_buffer())
	_device_key = _hmac(raw, "aparelho".to_utf8_buffer())
	_lock_key = _hmac(raw, "senha".to_utf8_buffer())
	boot = _crypto.generate_random_bytes(6).hex_encode()


## A marca do aparelho nesta sala: é ela que a sala guarda no lugar do código secreto.
## Muda de sala para sala, para o resumo não deixar seguir um aparelho entre salas.
func device_tag(room_id: String, device: String) -> String:
	if device == "":
		return ""
	return _hmac(_device_key, (room_id + "|" + device).to_utf8_buffer()) \
		.hex_encode().left(TAG_LENGTH)


## A marca da senha da sala ("" = sem senha). Vai no resumo para a sala recriada
## conferir a senha que quem volta devolve; sem o segredo do servidor, não dá para
## testar senhas contra ela.
func lock_tag(room_id: String, password: String) -> String:
	if password == "":
		return ""
	return _hmac(_lock_key, (room_id + "|" + password).to_utf8_buffer()) \
		.hex_encode().left(TAG_LENGTH)


## Assina o retrato da sala (Room.snapshot sem a mão). lock: lock_tag da senha.
func sign(room_state: Dictionary, rev: int, lock: String, unix_s: int) -> String:
	var packed: PackedByteArray = JSON.stringify({
		"v": VERSION, "boot": boot, "at": unix_s, "rev": rev, "lock": lock,
		"room": room_state,
	}).to_utf8_buffer().compress(FileAccess.COMPRESSION_DEFLATE)
	return Marshalls.raw_to_base64(packed) + "." + Marshalls.raw_to_base64(_hmac(_sign_key, packed))


## Confere o resumo. Devolve {ok, error, data}; data = {v, boot, at, rev, lock, room}.
## Não confere quem o apresenta nem a sala: isso é com o servidor.
func open(token: String, unix_s: int) -> Dictionary:
	if token.length() > MAX_TOKEN:
		return _bad("resumo grande demais")
	var parts: PackedStringArray = token.split(".")
	if parts.size() != 2 or _base64.search(parts[0]) == null or _base64.search(parts[1]) == null \
			or parts[0].length() % 4 != 0 or parts[1].length() % 4 != 0:
		return _bad("resumo malformado")
	var packed: PackedByteArray = Marshalls.base64_to_raw(parts[0])
	if not _same(Marshalls.base64_to_raw(parts[1]), _hmac(_sign_key, packed)):
		return _bad("assinatura inválida")
	var body: PackedByteArray = packed.decompress_dynamic(MAX_BODY, FileAccess.COMPRESSION_DEFLATE)
	var json: JSON = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return _bad("resumo malformado")
	# O JSON traz todo número como decimal; a sala só usa inteiros (fichas em centavos).
	var data: Dictionary = _whole(json.data)
	if (not _number(data.get("v")) or int(data["v"]) != VERSION
			or not _number(data.get("at")) or not _number(data.get("rev"))
			or typeof(data.get("boot")) != TYPE_STRING or typeof(data.get("lock")) != TYPE_STRING
			or typeof(data.get("room")) != TYPE_DICTIONARY):
		return _bad("resumo malformado")
	var at: int = int(data["at"])
	if unix_s - at > VALID_S:
		return _bad("resumo vencido")
	if at - unix_s > SKEW_S:
		return _bad("resumo com hora errada")
	return {"ok": true, "error": "", "data": data}


func _hmac(key: PackedByteArray, message: PackedByteArray) -> PackedByteArray:
	return _crypto.hmac_digest(HashingContext.HASH_SHA256, key, message)


static func _whole(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			return int(value) if is_finite(value) and value == floorf(value) else value
		TYPE_ARRAY:
			var list: Array = []
			for item: Variant in value:
				list.append(_whole(item))
			return list
		TYPE_DICTIONARY:
			var copy: Dictionary = {}
			for key: Variant in value:
				copy[key] = _whole(value[key])
			return copy
	return value


static func _number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


## Comparação que leva o mesmo tempo acertando ou errando cedo.
static func _same(a: PackedByteArray, b: PackedByteArray) -> bool:
	if a.size() != b.size():
		return false
	var diff: int = 0
	for i in a.size():
		diff |= a[i] ^ b[i]
	return diff == 0


static func _bad(text: String) -> Dictionary:
	return {"ok": false, "error": text, "data": {}}
