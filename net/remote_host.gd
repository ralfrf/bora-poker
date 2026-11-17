extends RefCounted
## Servidor de salas à distância (SPEC 9.3 e 10): o mesmo servidor de salas dos outros
## modos, atrás do WebSocket, com os limites do plano gratuito. Na mesma porta atende:
##   /saude    verificação de saúde do Render
##   /lotacao  % de lotação e se cabe sala nova (o app consulta antes de entrar)
##   /estado   números para o dono acompanhar (nada de quem joga)
## Quem põe para rodar é deploy/remote_server.gd.

const WsServer := preload("res://net/ws_server.gd")
const Server := preload("res://server/server.gd")
const Clock := preload("res://server/clock.gd")
const Protocol := preload("res://server/protocol.gd")

## Medido no Docker com 512 MB e 0,1 de CPU (etapa 5): 100 salas de 6 + 1 espectador
## ocupam ~67 MB; a mesa de 6 gasta ~88 ms de CPU por mão. 100 mesas de 6 a 120 mãos
## por hora dariam uns 30% da CPU.
const MAX_ROOMS: int = 200
const SLOTS: int = 10000           ## 100 vagas (centésimos; 100 = uma mesa de 6)
const MAX_CONNECTIONS: int = 800
const RATE: int = 20               ## mensagens por segundo por conexão
const WATCHER_CAP: int = 3         ## SPEC 4.3
const EMPTY_CLOSE_MS: int = 300000 ## SPEC 6.5: 5 min, como as fichas guardadas
## Batimento à distância: o app manda "ping" a cada 5 s (ui/app/remote_game.gd), não a
## cada 2 s como no Wi-Fi, para gastar menos banda; calado por 16 s, caiu.
const SILENCE_MS: int = 16000
## Fração de um núcleo do plano gratuito do Render, quando o contêiner não informa a
## própria cota em número (a variável CPU_SHARE pode trocar).
const DEFAULT_CPU_SHARE: float = 0.1

var ws: WsServer = null
var server: Server = null

var _clock: Clock = null
var _started_ms: int = 0
var _busy_us: int = 0
var _cgroup: bool = false
var _share: float = 1.0


## config: substitui os limites acima (testes) e os ajustes das salas.
func _init(clock: Clock = null, config: Dictionary = {}) -> void:
	_clock = clock if clock != null else Clock.new()
	_started_ms = _clock.now_ms()
	_cgroup = _cgroup_cpu_us() >= 0
	_share = _cpu_share() if _cgroup else 1.0
	ws = WsServer.new(_clock)
	ws.max_peers = int(config.get("max_connections", MAX_CONNECTIONS))
	ws.trust_forwarded = true
	ws.http_handler = _http
	ws.silence_ms = SILENCE_MS
	var room_config: Dictionary = {"watcher_cap": WATCHER_CAP, "empty_close_ms": EMPTY_CLOSE_MS}
	room_config.merge(config.get("room", {}), true)
	server = Server.new(ws, _clock, {
		"max_rooms": int(config.get("max_rooms", MAX_ROOMS)),
		"slots": int(config.get("slots", SLOTS)),
		"rate": int(config.get("rate", RATE)),
		"cpu_reader": _cpu_used_us,
		"cpu_share": _share,
		"room": room_config,
		"list_open_only": true,
	}, config.get("seed_source", Callable()))


func listen(port: int, bind_address: String = "*") -> Error:
	return ws.listen(port, bind_address)


## Um passo: conexões, salas e a medição da CPU.
func tick() -> void:
	var start: int = Time.get_ticks_usec()
	server.tick()
	_busy_us += Time.get_ticks_usec() - start


## Há alguém conectado (o laço anda mais rápido).
func busy() -> bool:
	return ws.peer_count() > 0


func status() -> Dictionary:
	var used: int = server.used_slots()
	var info: Dictionary = server.load_info()
	var memory: Dictionary = _memory()
	return {
		"protocolo": Protocol.VERSION,
		"no_ar_s": (_clock.now_ms() - _started_ms) / 1000,
		"salas": server.rooms.size(),
		"conexoes": ws.peer_count(),
		"apresentadas": server.session_count(),
		"vagas_usadas": used / 100.0,
		"vagas_total": server.capacity.total / 100.0,
		"cpu_pct": server.capacity.cpu_percent(),
		"cpu_fracao": _share,
		"cpu_do_conteiner": _cgroup,
		"lotacao_pct": info["pct"],
		"cheio": info["full"],
		"memoria_mb": memory.get("rss", 0.0),
		"conteiner_mb": memory.get("container", 0.0),
		"pico_conteiner_mb": memory.get("peak", 0.0),
		"enviados_mb": snappedf(ws.bytes_out / 1048576.0, 0.01),
		"recebidos_mb": snappedf(ws.bytes_in / 1048576.0, 0.01),
		"pedidos_estranhos": ws.stray,
	}


func _http(request: Dictionary) -> Dictionary:
	match str(request["path"]).split("?")[0]:
		"/saude":
			return _answer("200 OK", "text/plain", "ok")
		"/lotacao":
			var info: Dictionary = server.load_info()
			return _answer("200 OK", "application/json", JSON.stringify(
				{"v": Protocol.VERSION, "pct": info["pct"], "full": info["full"]}))
		"/estado":
			return _answer("200 OK", "application/json", JSON.stringify(status()))
		"/":
			return _answer("200 OK", "text/plain; charset=utf-8",
				"Bora Poker: servidor de salas. Para jogar, use o app.")
	return _answer("404 Not Found", "text/plain; charset=utf-8", "não encontrado")


static func _answer(code: String, type: String, body: String) -> Dictionary:
	return {"status": code, "type": type, "body": body}


## CPU usada até agora: a do contêiner, se o sistema informa; senão, o tempo dos passos.
func _cpu_used_us() -> int:
	if _cgroup:
		return _cgroup_cpu_us()
	return _busy_us


static func _cgroup_cpu_us() -> int:
	for line: String in _read_lines("/sys/fs/cgroup/cpu.stat"):
		if line.begins_with("usage_usec "):
			return line.substr(11).to_int()
	return -1


## Fração de um núcleo que o contêiner pode usar: a variável CPU_SHARE, senão a cota do
## cgroup ("10000 100000" = 0,1), senão a do plano gratuito.
static func _cpu_share() -> float:
	var forced: String = OS.get_environment("CPU_SHARE")
	if forced.is_valid_float() and forced.to_float() > 0.0:
		return forced.to_float()
	var lines: PackedStringArray = _read_lines("/sys/fs/cgroup/cpu.max")
	if not lines.is_empty():
		var parts: PackedStringArray = lines[0].split(" ")
		if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int() and parts[1].to_int() > 0:
			return parts[0].to_int() / float(parts[1].to_int())
	return DEFAULT_CPU_SHARE


static func _memory() -> Dictionary:
	var result: Dictionary = {}
	for line: String in _read_lines("/proc/self/status"):
		if line.begins_with("VmRSS:"):
			result["rss"] = snappedf(line.split(":")[1].strip_edges().split(" ")[0].to_int() / 1024.0, 0.1)
	for pair: Array in [["container", "/sys/fs/cgroup/memory.current"], ["peak", "/sys/fs/cgroup/memory.peak"]]:
		var lines: PackedStringArray = _read_lines(pair[1])
		if not lines.is_empty() and lines[0].is_valid_int():
			result[pair[0]] = snappedf(lines[0].to_int() / 1048576.0, 0.1)
	return result


## Arquivos de /proc e /sys dizem ter tamanho zero, então a leitura é linha a linha.
static func _read_lines(path: String) -> PackedStringArray:
	var lines: PackedStringArray = []
	if not FileAccess.file_exists(path):
		return lines
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return lines
	while lines.size() < 100:
		var line: String = file.get_line()
		if file.eof_reached() and line == "":
			break
		lines.append(line)
	return lines
