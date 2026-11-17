extends RefCounted
## Relógio do servidor, recebido de fora (SPEC 8). No jogo lê o tempo do sistema; nos
## testes é manual, para simular estouros de tempo e prazos sem esperar.
##
## skip() tira um trecho do tempo: no Wi-Fi, o tempo em que o app do anfitrião ficou
## suspenso não conta para a sala (SPEC 6.4: os relógios ficam parados).

## Hora de partida do relógio manual (unix_s), um dia qualquer de 2027.
const MANUAL_EPOCH_S: int = 1_800_000_000

var manual: bool = false
var _now_ms: int = 0
var _skipped: int = 0


func _init(is_manual: bool = false) -> void:
	manual = is_manual


## Milissegundos desde um ponto fixo qualquer. Só as diferenças importam.
func now_ms() -> int:
	return (_now_ms if manual else Time.get_ticks_msec()) - _skipped


## Segundos do relógio do sistema (hora de verdade), para o que precisa valer depois de
## um reinício (o resumo assinado, SPEC 9.4). No manual, anda junto com now_ms.
func unix_s() -> int:
	if manual:
		return MANUAL_EPOCH_S + _now_ms / 1000
	return int(Time.get_unix_time_from_system())


## Só no relógio manual: faz o tempo passar.
func advance(ms: int) -> void:
	_now_ms += maxi(ms, 0)


## Daqui em diante, o relógio fica ms atrás: esse trecho não passou para quem o usa.
func skip(ms: int) -> void:
	_skipped += maxi(ms, 0)
