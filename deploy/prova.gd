extends SceneTree
## Prova da hospedagem: na mesma porta, responde HTTP (página de teste de conexão,
## /estado e /saude) e WebSocket em /eco, que devolve cada mensagem recebida. Ao
## subir, roda a bateria de testes em outro processo e anota o pico de memória.
##
##   godot --headless --path /app -s res://deploy/prova.gd [-- --sem-testes]
##
## O aperto de mão e os quadros do WebSocket são feitos à mão sobre TCP, porque o
## WebSocketPeer do Godot não atende HTTP comum na mesma porta.

const DEFAULT_PORT: int = 10000
const MAX_CLIENTS: int = 20
const MAX_REQUEST: int = 8192
const MAX_FRAME: int = 4096
const REQUEST_MS: int = 10000
const IDLE_MS: int = 120000
const MAX_RESULTS: int = 10
const WS_GUID: String = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


class Conn:
	extends RefCounted
	var peer: StreamPeerTCP = null
	var buf: PackedByteArray = PackedByteArray()
	var ws: bool = false
	var last_ms: int = 0


var _server: TCPServer = TCPServer.new()
var _conns: Array[Conn] = []
var _tests: Dictionary = {"estado": "não rodou", "pico_processo_mb": 0.0,
	"pico_conteiner_mb": 0.0, "segundos": 0}
var _results: Array[String] = []
var _pid: int = -1
var _tests_start_ms: int = 0
var _next_sample_ms: int = 0
var _peak_kb: int = 0


func _initialize() -> void:
	# Sem tela o laço giraria sem parar e gastaria a CPU toda. A 60 quadros por segundo
	# cada resposta espera no máximo uns 16 ms.
	Engine.max_fps = 60
	var port: int = DEFAULT_PORT
	if OS.get_environment("PORT").is_valid_int():
		port = OS.get_environment("PORT").to_int()
	var err: Error = _server.listen(port, "*")
	print("prova: ouvindo na porta %d (%s)" % [port, error_string(err)])
	if err != OK:
		quit(1)
		return
	if not OS.get_cmdline_user_args().has("--sem-testes"):
		_start_tests()


func _process(_delta: float) -> bool:
	var now: int = Time.get_ticks_msec()
	while _server.is_connection_available():
		var peer: StreamPeerTCP = _server.take_connection()
		if _conns.size() >= MAX_CLIENTS:
			peer.disconnect_from_host()
			continue
		peer.set_no_delay(true)   # mensagens pequenas saem na hora, sem esperar o TCP juntar
		var conn: Conn = Conn.new()
		conn.peer = peer
		conn.last_ms = now
		_conns.append(conn)
	for conn: Conn in _conns.duplicate():
		if not _poll(conn, now):
			conn.peer.disconnect_from_host()
			_conns.erase(conn)
	_watch_tests(now)
	return false


# ---------------------------------------------------------------- testes


func _start_tests() -> void:
	var args: PackedStringArray = ["--headless", "--path",
		ProjectSettings.globalize_path("res://"), "-s", "res://tests/run_tests.gd"]
	_pid = OS.create_process(OS.get_executable_path(), args)
	_tests_start_ms = Time.get_ticks_msec()
	_tests["estado"] = "rodando" if _pid > 0 else "não foi possível iniciar"
	print("prova: testes iniciados (processo %d)" % _pid)


## Enquanto os testes rodam, lê o pico de memória do processo a cada segundo. O pico
## do contêiner inclui também este processo.
func _watch_tests(now: int) -> void:
	if _pid <= 0 or now < _next_sample_ms:
		return
	_next_sample_ms = now + 1000
	var running: bool = OS.is_process_running(_pid)
	for line: String in _read_lines("/proc/%d/status" % _pid):
		if line.begins_with("VmHWM:"):
			_peak_kb = maxi(_peak_kb, line.split(":")[1].strip_edges().split(" ")[0].to_int())
	_tests["pico_processo_mb"] = snappedf(_peak_kb / 1024.0, 0.1)
	var cgroup: PackedStringArray = _read_lines("/sys/fs/cgroup/memory.peak")
	if not cgroup.is_empty() and cgroup[0].is_valid_int():
		_tests["pico_conteiner_mb"] = snappedf(cgroup[0].to_int() / 1048576.0, 0.1)
	_tests["segundos"] = (now - _tests_start_ms) / 1000
	if not running:
		var code: int = OS.get_process_exit_code(_pid)
		_tests["estado"] = "passaram" if code == 0 else "falharam (código %d)" % code
		print("prova: testes %s em %d s; pico do processo %.1f MB; pico do contêiner %.1f MB" % [
			_tests["estado"], _tests["segundos"], _tests["pico_processo_mb"],
			_tests["pico_conteiner_mb"]])
		_pid = -1


## Arquivos de /proc e /sys dizem ter tamanho zero, então a leitura é linha a linha.
func _read_lines(path: String) -> PackedStringArray:
	var lines: PackedStringArray = []
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return lines
	while lines.size() < 200:
		var line: String = file.get_line()
		if file.eof_reached() and line == "":
			break
		lines.append(line)
	return lines


# ---------------------------------------------------------------- conexões


## Falso: fechar a conexão.
func _poll(conn: Conn, now: int) -> bool:
	conn.peer.poll()
	if conn.peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return false
	var available: int = conn.peer.get_available_bytes()
	if available > 0:
		var got: Array = conn.peer.get_data(available)
		if got[0] != OK:
			return false
		conn.buf.append_array(got[1])
		conn.last_ms = now
	if conn.ws:
		return _frames(conn) and now - conn.last_ms < IDLE_MS
	var end: int = conn.buf.get_string_from_ascii().find("\r\n\r\n")
	if end < 0:
		return conn.buf.size() <= MAX_REQUEST and now - conn.last_ms < REQUEST_MS
	var head: String = conn.buf.slice(0, end).get_string_from_utf8()
	conn.buf = conn.buf.slice(end + 4)
	return _http(conn, head)


func _http(conn: Conn, head: String) -> bool:
	var lines: PackedStringArray = head.split("\r\n")
	var first: PackedStringArray = lines[0].split(" ")
	if first.size() < 3:
		return false
	var path: String = first[1]
	var headers: Dictionary = {}
	for i in range(1, lines.size()):
		var colon: int = lines[i].find(":")
		if colon > 0:
			headers[lines[i].left(colon).strip_edges().to_lower()] = lines[i].substr(colon + 1).strip_edges()
	if str(headers.get("upgrade", "")).to_lower() == "websocket":
		if not path.begins_with("/eco") or not headers.has("sec-websocket-key"):
			_reply(conn, "400 Bad Request", "text/plain", "pedido inválido")
			return false
		var accept: String = Marshalls.raw_to_base64(
			(str(headers["sec-websocket-key"]) + WS_GUID).sha1_buffer())
		conn.peer.put_data(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n"
			+ "Connection: Upgrade\r\nSec-WebSocket-Accept: %s\r\n\r\n" % accept).to_utf8_buffer())
		conn.ws = true
		return _frames(conn)
	var route: String = path.split("?")[0]
	match route:
		"/":
			_reply(conn, "200 OK", "text/html; charset=utf-8", PAGE)
		"/saude":
			_reply(conn, "200 OK", "text/plain", "ok")
		"/estado":
			var state: Dictionary = _tests.duplicate()
			state["resultados"] = _results
			_reply(conn, "200 OK", "application/json", JSON.stringify(state))
		"/registro":
			_record(path)
			_reply(conn, "204 No Content", "text/plain", "")
		_:
			_reply(conn, "404 Not Found", "text/plain", "não encontrado")
	return false


## Guarda só os números que a página mediu, sem nada de quem mediu.
func _record(path: String) -> void:
	var parts: PackedStringArray = []
	for pair: String in path.get_slice("?", 1).split("&"):
		var kv: PackedStringArray = pair.split("=")
		if kv.size() == 2 and kv[0] in ["con", "min", "med", "max"] and kv[1].is_valid_int():
			parts.append("%s=%d" % [kv[0], kv[1].to_int()])
	if parts.is_empty():
		return
	var line: String = "%s %s" % [Time.get_datetime_string_from_system(true), " ".join(parts)]
	print("prova: ida e volta ", line)
	_results.append(line)
	if _results.size() > MAX_RESULTS:
		_results.pop_front()


func _reply(conn: Conn, status: String, type: String, body: String) -> void:
	var data: PackedByteArray = body.to_utf8_buffer()
	var head: String = ("HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\n"
		+ "Cache-Control: no-store\r\nConnection: close\r\n\r\n") % [status, type, data.size()]
	conn.peer.put_data(head.to_utf8_buffer())
	if not data.is_empty():
		conn.peer.put_data(data)


## Lê os quadros que já chegaram inteiros. Falso: fechar.
func _frames(conn: Conn) -> bool:
	while conn.buf.size() >= 2:
		var b: PackedByteArray = conn.buf
		var opcode: int = b[0] & 0x0F
		var length: int = b[1] & 0x7F
		var pos: int = 2
		if (b[1] & 0x80) == 0 or length == 127 or (b[0] & 0x80) == 0:
			return false   # do cliente vem sempre mascarado, pequeno e inteiro
		if length == 126:
			if b.size() < 4:
				return true
			length = (b[2] << 8) | b[3]
			pos = 4
		if length > MAX_FRAME:
			return false
		if b.size() < pos + 4 + length:
			return true
		var mask: PackedByteArray = b.slice(pos, pos + 4)
		var payload: PackedByteArray = b.slice(pos + 4, pos + 4 + length)
		for i in length:
			payload[i] = payload[i] ^ mask[i % 4]
		conn.buf = b.slice(pos + 4 + length)
		match opcode:
			1, 2:
				_send_frame(conn, opcode, payload)
			8:
				_send_frame(conn, 8, payload.slice(0, 2))
				return false
			9:
				_send_frame(conn, 10, payload)
			10:
				pass
			_:
				return false
	return true


func _send_frame(conn: Conn, opcode: int, payload: PackedByteArray) -> void:
	var head: PackedByteArray = PackedByteArray([0x80 | opcode])
	if payload.size() < 126:
		head.append(payload.size())
	else:
		head.append_array(PackedByteArray([126, payload.size() >> 8, payload.size() & 0xFF]))
	conn.peer.put_data(head + payload)


const PAGE: String = """<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Bora Poker: teste de conexão</title>
<style>
body{font-family:system-ui,sans-serif;background:#0f172a;color:#f1f5f9;margin:0;padding:16px;max-width:560px}
h1{font-size:22px}p{color:#94a3b8}
button{font-size:18px;padding:12px 22px;border:0;border-radius:12px;background:#f5c542;color:#111;font-weight:700}
#r{white-space:pre-line;font-size:18px;line-height:1.5;margin-top:18px}
#t{color:#94a3b8;font-size:14px;margin-top:18px;white-space:pre-line}
</style></head><body>
<h1>Bora Poker: teste de conexão</h1>
<p>Mede o tempo de ida e volta até o servidor pelo WebSocket seguro.</p>
<button id="b">Testar</button>
<div id="r"></div><div id="t"></div>
<script>
const r = document.getElementById("r");
async function estado() {
  try {
    const e = await (await fetch("/estado", {cache: "no-store"})).json();
    let s = "Testes no servidor: " + e.estado + " (" + e.segundos + " s)";
    if (e.pico_processo_mb) s += "\\nPico de memória dos testes: " + e.pico_processo_mb + " MB";
    if (e.pico_conteiner_mb) s += "\\nPico do contêiner: " + e.pico_conteiner_mb + " MB";
    document.getElementById("t").textContent = s;
  } catch (x) {}
}
function testar() {
  const url = (location.protocol === "https:" ? "wss://" : "ws://") + location.host + "/eco";
  r.textContent = "Conectando…";
  const t0 = performance.now();
  const ws = new WebSocket(url);
  const tempos = [];
  let con = 0, ida = 0;
  ws.onopen = () => {
    con = Math.round(performance.now() - t0);
    r.textContent = "Conectado em " + con + " ms (" + url.split(":")[0] + "). Medindo…";
    ida = performance.now();
    ws.send("eco 0");
  };
  ws.onmessage = () => {
    tempos.push(performance.now() - ida);
    if (tempos.length < 20) { ida = performance.now(); ws.send("eco " + tempos.length); return; }
    ws.close();
    tempos.sort((a, b) => a - b);
    const m = (x) => Math.round(x);
    r.textContent += "\\nIda e volta (20 mensagens):\\nmínimo " + m(tempos[0]) + " ms, mediana "
      + m(tempos[10]) + " ms, máximo " + m(tempos[19]) + " ms";
    fetch("/registro?con=" + con + "&min=" + m(tempos[0]) + "&med=" + m(tempos[10]) + "&max="
      + m(tempos[19]), {cache: "no-store"}).catch(() => {});
  };
  ws.onerror = () => { r.textContent = "Não conectou em " + url; };
}
document.getElementById("b").onclick = testar;
estado();
setInterval(estado, 5000);
</script></body></html>
"""
