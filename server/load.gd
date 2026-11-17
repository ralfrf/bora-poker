extends RefCounted
## Lotação do servidor à distância (SPEC 9.3): vagas de carga e CPU do último minuto.
##
## Vagas em centésimos (100 = uma mesa de 6), pelo custo medido de cada tamanho com o
## protocolo enxuto (o maior entre CPU e banda). A % mostrada no app é o maior entre a
## CPU usada no último minuto e as vagas em uso.

const SEAT_WEIGHTS: Dictionary = {2: 20, 3: 35, 4: 50, 5: 75, 6: 100, 7: 140, 8: 180, 9: 220}
const WATCHER_WEIGHT: int = 20
const WINDOW_MS: int = 60000
const SAMPLE_MS: int = 5000

const Clock := preload("res://server/clock.gd")

## Vagas do servidor, em centésimos. 0 = sem limite.
var total: int = 0

var _clock: Clock = null
var _cpu_reader: Callable = Callable()   # () -> microssegundos de CPU usados até agora
var _cpu_share: float = 1.0              # fração de um núcleo que o serviço pode usar
var _samples: Array = []                 # [ms, microssegundos de CPU]
var _next_sample: int = 0


## cpu_reader: devolve o total de CPU usado (microssegundos), ou -1 se não sabe.
## cpu_share: fração de um núcleo (0,1 no Render).
func _init(slots_total: int, clock: Clock, cpu_reader: Callable = Callable(),
		cpu_share: float = 1.0) -> void:
	total = slots_total
	_clock = clock
	_cpu_reader = cpu_reader
	_cpu_share = maxf(cpu_share, 0.01)


static func room_weight(seats: int, watchers: int) -> int:
	return int(SEAT_WEIGHTS.get(clampi(seats, 2, 9), 220)) + WATCHER_WEIGHT * maxi(watchers, 0)


## Anota a CPU usada a cada SAMPLE_MS; guarda só o último minuto.
func sample() -> void:
	var now: int = _clock.now_ms()
	if now < _next_sample or not _cpu_reader.is_valid():
		return
	_next_sample = now + SAMPLE_MS
	var used: int = int(_cpu_reader.call())
	if used < 0:
		return
	_samples.append([now, used])
	while _samples.size() > 2 and now - int(_samples[1][0]) >= WINDOW_MS:
		_samples.pop_front()


## CPU usada no último minuto, de 0 a 100 (da parte do núcleo que cabe ao serviço).
func cpu_percent() -> int:
	if _samples.size() < 2:
		return 0
	var first: Array = _samples[0]
	var last: Array = _samples[_samples.size() - 1]
	var elapsed_us: float = (int(last[0]) - int(first[0])) * 1000.0
	if elapsed_us <= 0.0:
		return 0
	return clampi(roundi((int(last[1]) - int(first[1])) / (elapsed_us * _cpu_share) * 100.0), 0, 100)


## Vagas em uso, de 0 a 100.
func slots_percent(used: int) -> int:
	if total <= 0:
		return 0
	return clampi(roundi(used * 100.0 / total), 0, 100)


## A % de lotação mostrada no app.
func percent(used: int) -> int:
	return maxi(cpu_percent(), slots_percent(used))


## Cabe uma sala nova com esse peso?
func fits(used: int, weight: int) -> bool:
	return total <= 0 or used + weight <= total
