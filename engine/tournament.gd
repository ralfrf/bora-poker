extends RefCounted
## Regras do torneio (SPEC 3.5): níveis de blinds que sobem por tempo e colocação
## dos eliminados. O tempo decorrido vem de fora; este arquivo não lê relógio.

## Níveis iniciais [small blind, big blind], em centavos. Depois do último, dobram.
const LEVELS: Array = [
	[10, 20], [15, 30], [25, 50], [50, 100], [75, 150],
	[100, 200], [150, 300], [200, 400], [300, 600], [500, 1000],
]
const LEVEL_MINUTES: Array[int] = [3, 5, 8, 10]
const DEFAULT_LEVEL_MINUTES: int = 5
## Teto para os blinds não estourarem o inteiro: daqui em diante param de subir.
const MAX_LEVEL: int = 40


static func small_blind(level: int) -> int:
	return _blind(level, 0)


static func big_blind(level: int) -> int:
	return _blind(level, 1)


## Nível (a partir de 0) depois de `elapsed_ms` de jogo, sem contar as pausas.
static func level_at(elapsed_ms: int, level_minutes: int) -> int:
	if elapsed_ms <= 0 or level_minutes <= 0:
		return 0
	@warning_ignore("integer_division")
	return mini(elapsed_ms / (level_minutes * 60000), MAX_LEVEL)


## Quanto falta para o próximo nível, em milissegundos.
static func ms_to_next_level(elapsed_ms: int, level_minutes: int) -> int:
	var level_ms: int = level_minutes * 60000
	if level_ms <= 0:
		return 0
	return level_ms - (maxi(elapsed_ms, 0) % level_ms)


## Colocação de quem saiu na mesma mão. alive_before: quantos tinham fichas antes dela.
## busted: [{seat, start_stack}]. Fica à frente quem tinha mais fichas no início da
## mão; quem tinha o mesmo divide a colocação. Devolve [{seat, place}].
static func assign_places(alive_before: int, busted: Array) -> Array[Dictionary]:
	var sorted: Array = busted.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["start_stack"]) != int(b["start_stack"]):
			return int(a["start_stack"]) > int(b["start_stack"])
		return int(a["seat"]) < int(b["seat"]))
	var places: Array[Dictionary] = []
	for i in sorted.size():
		var place: int = alive_before - sorted.size() + 1 + i
		if i > 0 and int(sorted[i]["start_stack"]) == int(sorted[i - 1]["start_stack"]):
			place = places[i - 1]["place"]
		places.append({"seat": int(sorted[i]["seat"]), "place": place})
	return places


static func _blind(level: int, index: int) -> int:
	var capped: int = clampi(level, 0, MAX_LEVEL)
	if capped < LEVELS.size():
		return LEVELS[capped][index]
	var last: Array = LEVELS[LEVELS.size() - 1]
	return int(last[index]) << (capped - LEVELS.size() + 1)
