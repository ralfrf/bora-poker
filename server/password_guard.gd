extends RefCounted
## Tentativas erradas de senha (SPEC 9.3): o servidor conta, em cada sala, por aparelho e
## por IP, com espera crescente. A conta do IP existe porque o código do aparelho é
## escolhido pelo próprio app: quem troca de código a cada tentativa ainda esbarra no
## limite do IP. Não há trava da sala inteira, para quem erra de propósito não trancar os
## amigos do dono do lado de fora. Durante a espera, nem a senha certa entra (senão a
## espera não serviria para nada).
##
## Puro: o relógio vem de fora.

const Clock := preload("res://server/clock.gd")

## Aparelho numa sala: as primeiras erradas não esperam; depois, 5 s, 10 s, 20 s… até 5 min.
const DEVICE_FREE: int = 3
const DEVICE_BASE_MS: int = 5000
const DEVICE_MAX_MS: int = 300000
## IP numa sala (vários aparelhos atrás do mesmo IP, como na rede da operadora): mais folga.
const IP_FREE: int = 8
const IP_BASE_MS: int = 5000
const IP_MAX_MS: int = 300000
## Sem nenhuma errada por esse tempo, a conta zera.
const FORGET_MS: int = 900000
## Acima disso, as contas velhas são apagadas (memória do servidor), no máximo uma vez
## por PRUNE_EVERY_MS.
const PRUNE_AT: int = 2000
const PRUNE_EVERY_MS: int = 60000

var _clock: Clock = null
var _counts: Dictionary = {}   ## "sala/d/aparelho" ou "sala/i/ip" -> {fails, until, last}
var _pruned_at: int = -PRUNE_EVERY_MS


func _init(clock: Clock) -> void:
	_clock = clock


## Quanto falta para esse aparelho (e IP) poder tentar de novo nessa sala (0 = pode agora).
## ip vazio (transporte local) não conta.
func wait_ms(room_id: String, device: String, ip: String = "") -> int:
	var now: int = _clock.now_ms()
	var wait: int = 0
	for key: String in _keys(room_id, device, ip):
		var entry: Variant = _counts.get(key)
		if entry != null and now - int(entry["last"]) < FORGET_MS:
			wait = maxi(wait, int(entry["until"]) - now)
	return wait


## Uma tentativa errada. Devolve a espera que ela causou (0 = pode tentar de novo já).
func failed(room_id: String, device: String, ip: String = "") -> int:
	var now: int = _clock.now_ms()
	if _counts.size() > PRUNE_AT and now - _pruned_at >= PRUNE_EVERY_MS:
		_prune(now)
	var until: int = 0
	var keys: Array[String] = _keys(room_id, device, ip)
	for i in keys.size():
		var by_ip: bool = i == 1
		var entry: Dictionary = _count(keys[i], now, IP_FREE if by_ip else DEVICE_FREE,
			IP_BASE_MS if by_ip else DEVICE_BASE_MS, IP_MAX_MS if by_ip else DEVICE_MAX_MS)
		until = maxi(until, int(entry["until"]))
	return maxi(0, until - now)


## A sala fechou: esquece as contas dela.
func forget_room(room_id: String) -> void:
	for key: String in _counts.keys():
		if key.begins_with(room_id + "/"):
			_counts.erase(key)


static func _keys(room_id: String, device: String, ip: String) -> Array[String]:
	var keys: Array[String] = [room_id + "/d/" + device]
	if ip != "":
		keys.append(room_id + "/i/" + ip)
	return keys


func _count(key: String, now: int, free: int, base_ms: int, max_ms: int) -> Dictionary:
	var entry: Dictionary = _counts.get(key, {"fails": 0, "until": 0, "last": now})
	if now - int(entry["last"]) >= FORGET_MS:
		entry = {"fails": 0, "until": 0, "last": now}
	entry["fails"] = int(entry["fails"]) + 1
	entry["last"] = now
	var over: int = int(entry["fails"]) - free
	if over > 0:
		entry["until"] = now + mini(max_ms, base_ms << mini(over - 1, 20))
	_counts[key] = entry
	return entry


func _prune(now: int) -> void:
	_pruned_at = now
	for key: String in _counts.keys():
		if now - int(_counts[key]["last"]) >= FORGET_MS:
			_counts.erase(key)
