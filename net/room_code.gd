extends RefCounted
## Código da sala no Wi-Fi (SPEC 9.2): 4 caracteres que levam os dois últimos números do
## IP do anfitrião, para digitar quando a sala não aparece sozinha. Quem digita completa
## os dois primeiros números com os da própria rede.
##
## 4 caracteres de um alfabeto de 32 dão 20 bits: 16 para os dois números e 4 para uma
## conferência, que pega a maioria dos erros de digitação.

const CHARS: String = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   # sem 0, O, 1 e I
const LENGTH: int = 4


## Código do IP, ou "" se não for um IPv4.
static func encode(ip: String) -> String:
	var parts: PackedInt32Array = _octets(ip)
	if parts.is_empty():
		return ""
	var value: int = (parts[2] << 8) | parts[3]
	var packed: int = (value << 4) | _check(value)
	var code: String = ""
	for _i in LENGTH:
		code = CHARS[packed & 31] + code
		packed >>= 5
	return code


## IP do anfitrião a partir do código e do IP de quem digita. "" se o código não vale.
## Aceita minúsculas, espaços e traços.
static func decode(code: String, own_ip: String) -> String:
	var own: PackedInt32Array = _octets(own_ip)
	var clean: String = code.to_upper().replace(" ", "").replace("-", "")
	if own.is_empty() or clean.length() != LENGTH:
		return ""
	var packed: int = 0
	for i in LENGTH:
		var digit: int = CHARS.find(clean[i])
		if digit < 0:
			return ""
		packed = (packed << 5) | digit
	var value: int = packed >> 4
	if value > 0xFFFF or (packed & 15) != _check(value):
		return ""
	return "%d.%d.%d.%d" % [own[0], own[1], value >> 8, value & 255]


## Mostra o código com espaço no meio, para ler em voz alta: "K7 MP".
static func pretty(code: String) -> String:
	return code if code.length() != LENGTH else code.left(2) + " " + code.right(2)


## O IPv4 do aparelho na rede local (Wi-Fi ou ponto de acesso), ou "" se não houver.
## Prefere as interfaces de Wi-Fi às de dados móveis.
static func local_ip() -> String:
	var best: String = ""
	var best_score: int = -1
	for interface: Dictionary in IP.get_local_interfaces():
		var name: String = str(interface.get("name", "")).to_lower()
		for address: String in interface.get("addresses", []):
			var score: int = score_address(address, name)
			if score > best_score:
				best_score = score
				best = address
	return best if best_score > 0 else ""


## Nota de um endereço para ser o da rede local: 0 = não serve.
static func score_address(address: String, interface_name: String) -> int:
	var parts: PackedInt32Array = _octets(address)
	if parts.is_empty() or parts[0] == 127 or (parts[0] == 169 and parts[1] == 254):
		return 0
	var score: int = 0
	if parts[0] == 192 and parts[1] == 168:
		score = 3
	elif parts[0] == 172 and parts[1] >= 16 and parts[1] <= 31:
		score = 2
	elif parts[0] == 10:
		score = 2
	else:
		return 0
	for prefix: String in ["wlan", "wl", "ap", "swlan", "softap", "wi-fi", "wifi", "en"]:
		if interface_name.begins_with(prefix):
			return score + 4
	if interface_name.begins_with("rmnet") or interface_name.begins_with("ccmni") \
			or interface_name.begins_with("v4-rmnet"):
		return 1
	return score


## Endereços de broadcast prováveis para os anúncios: o geral e o da rede /24.
static func broadcast_addresses(ip: String) -> Array[String]:
	var list: Array[String] = ["255.255.255.255"]
	var parts: PackedInt32Array = _octets(ip)
	if not parts.is_empty():
		list.append("%d.%d.%d.255" % [parts[0], parts[1], parts[2]])
	return list


static func _check(value: int) -> int:
	# Espalha os bits: troca de um caractere muda a conferência em ~96% dos casos.
	return ((value * 40503) & 0xFFFF) >> 12


static func _octets(ip: String) -> PackedInt32Array:
	var pieces: PackedStringArray = ip.split(".")
	var result: PackedInt32Array = []
	if pieces.size() != 4:
		return result
	for piece: String in pieces:
		if not piece.is_valid_int() or int(piece) < 0 or int(piece) > 255:
			return PackedInt32Array()
		result.append(int(piece))
	return result
