extends RefCounted
## Pergunta a lotação de um servidor à distância (SPEC 9.3) com GET /lotacao, na mesma
## porta do WebSocket. A pergunta também acorda o servidor do Render, que dorme depois de
## 15 minutos sem ninguém: por isso começa assim que a pessoa escolhe "Amigos à
## distância". Sem resposta em 3 s, o estado vira WAKING ("Conectando ao servidor…" com o aviso); a
## sonda insiste por até 1 minuto e, sem resposta, o servidor fica DOWN ("Em
## manutenção"). Respondendo, repete a pergunta de tempos em tempos.
##
## O endereço do servidor não encontrado vira OFFLINE na hora ("Sem internet"), sem
## esperar o 1 minuto: o Render, mesmo dormindo, sempre tem o endereço. Recusar a
## conexão não conta, porque um servidor parado também recusa. Sem internet a sonda
## tenta a cada 2 s e, quando a internet volta, o 1 minuto conta do zero.
##
## Sem nós: quem usa chama poll() a cada quadro. O relógio é injetável.

const Clock := preload("res://server/clock.gd")
const Protocol := preload("res://server/protocol.gd")

enum State { ASKING, WAKING, READY, DOWN, OLD, OFFLINE }

const DEFAULT_URL: String = "wss://bora-poker.onrender.com"
const WAKE_NOTICE_MS: int = 3000
const GIVE_UP_MS: int = 60000
## Uma tentativa pode demorar: o Render segura o pedido enquanto o servidor acorda.
const ATTEMPT_MS: int = 20000
const RETRY_MS: int = 2000
const REFRESH_MS: int = 20000
## Em manutenção: pergunta de novo a cada 10 s (pedido do dono, 18/11/2026).
const DOWN_RETRY_MS: int = 10000
const MAX_BODY: int = 4096

var state: State = State.ASKING
## % de lotação (o maior entre a CPU do último minuto e as vagas) e se cabe sala nova.
var pct: int = 0
var full: bool = false
var url: String = ""

var _clock: Clock = null
var _http: HTTPClient = null
var _host: String = ""
var _port: int = 80
var _tls: bool = false
var _path: String = "/lotacao"
var _started: int = 0
var _attempt_at: int = -1     ## quando começou a tentativa atual (-1 = nenhuma)
var _next_at: int = 0         ## quando começar a próxima
var _sent: bool = false
var _body: PackedByteArray = PackedByteArray()
var _answered: bool = false   ## já respondeu alguma vez


## address: o endereço do WebSocket (wss://… ou ws://…), como aparece em "Avançado".
func _init(address: String, clock: Clock = null) -> void:
	_clock = clock if clock != null else Clock.new()
	url = normalize(address)
	var parts: Dictionary = split(url)
	_tls = parts["tls"]
	_host = parts["host"]
	_port = parts["port"]
	_path = parts["path"].trim_suffix("/") + "/lotacao"
	_started = _clock.now_ms()
	_next_at = _started


## Endereço como o app usa: sem espaços, com wss:// quando a pessoa não escreveu o começo.
## "" vira o endereço padrão. http(s):// vira ws(s)://.
static func normalize(address: String) -> String:
	var text: String = address.strip_edges()
	if text == "":
		return DEFAULT_URL
	if text.begins_with("https://"):
		text = "wss://" + text.substr(8)
	elif text.begins_with("http://"):
		text = "ws://" + text.substr(7)
	elif not (text.begins_with("wss://") or text.begins_with("ws://")):
		text = "wss://" + text
	return text.trim_suffix("/")


## {tls, host, port, path} de um endereço ws:// ou wss://.
static func split(address: String) -> Dictionary:
	var tls: bool = address.begins_with("wss://")
	var rest: String = address.substr(6 if tls else 5)
	var path: String = ""
	var slash: int = rest.find("/")
	if slash >= 0:
		path = rest.substr(slash)
		rest = rest.left(slash)
	var port: int = 443 if tls else 80
	var colon: int = rest.rfind(":")
	if colon > 0 and rest.substr(colon + 1).is_valid_int():
		port = rest.substr(colon + 1).to_int()
		rest = rest.left(colon)
	return {"tls": tls, "host": rest, "port": port, "path": path}


## Endereço válido o bastante para tentar.
static func is_valid(address: String) -> bool:
	var parts: Dictionary = split(normalize(address))
	return parts["host"] != "" and not (parts["host"] as String).contains(" ") \
		and int(parts["port"]) > 0 and int(parts["port"]) < 65536


func poll() -> void:
	var now: int = _clock.now_ms()
	if state == State.OLD:
		return
	if not _answered and state == State.ASKING and now - _started >= WAKE_NOTICE_MS:
		state = State.WAKING
	if _attempt_at < 0:
		if now >= _next_at:
			_begin(now)
		return
	if now - _attempt_at > ATTEMPT_MS:
		# 20 s procurando o endereço: a rede não tem saída.
		if _http.get_status() == HTTPClient.STATUS_RESOLVING:
			_offline(now)
		else:
			_failed(now)
		return
	var error: Error = _http.poll()
	var status: int = _http.get_status()
	if status == HTTPClient.STATUS_CANT_RESOLVE:
		_offline(now)
		return
	match status:
		HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_REQUESTING:
			if error != OK:
				_failed(now)
		HTTPClient.STATUS_CONNECTED:
			if not _sent:
				_sent = true
				var headers: PackedStringArray = ["Accept: application/json"]
				if _http.request(HTTPClient.METHOD_GET, _path, headers) != OK:
					_failed(now)
			else:
				_finish(now)
		HTTPClient.STATUS_BODY:
			var chunk: PackedByteArray = _http.read_response_body_chunk()
			_body.append_array(chunk)
			if _body.size() > MAX_BODY:
				_failed(now)
			elif _http.get_status() != HTTPClient.STATUS_BODY:
				_finish(now)
		HTTPClient.STATUS_DISCONNECTED, HTTPClient.STATUS_CONNECTION_ERROR:
			# O servidor fecha a conexão logo depois de responder.
			if _sent and not _body.is_empty():
				_finish(now)
			else:
				_failed(now)
		HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CANT_CONNECT, \
				HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
			_failed(now)


## Uma pergunta só (a tela inicial acorda o servidor sem insistir): depois da primeira
## resposta ou da primeira falha, para.
var once: bool = false


## Já parou de perguntar (só com once).
func finished() -> bool:
	return once and _attempt_at < 0 and _next_at == 1 << 62


## Fotos e testes de tela: fixa um estado e para de perguntar.
func pretend(new_state: State, new_pct: int = 0, new_full: bool = false) -> void:
	close()
	state = new_state
	pct = new_pct
	full = new_full
	_answered = new_state == State.READY
	_next_at = 1 << 62


## Para de perguntar (a tela fechou).
func close() -> void:
	if _http != null:
		_http.close()
		_http = null
	_attempt_at = -1


func _begin(now: int) -> void:
	_http = HTTPClient.new()
	_sent = false
	_body = PackedByteArray()
	_attempt_at = now
	var options: TLSOptions = TLSOptions.client() if _tls else null
	if _host == "" or _http.connect_to_host(_host, _port, options) != OK:
		_failed(now)


## A resposta terminou de chegar: confere e guarda.
func _finish(now: int) -> void:
	if _http.get_response_code() != 200:
		_failed(now)
		return
	var data: Variant = JSON.parse_string(_body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY or not (data as Dictionary).has("pct"):
		_failed(now)   # o Render ainda mostra a página de "acordando"
		return
	_close_attempt()
	_answered = true
	if int(data.get("v", 0)) != Protocol.VERSION:
		state = State.OLD
		return
	pct = clampi(int(data.get("pct", 0)), 0, 100)
	full = bool(data.get("full", false))
	state = State.READY
	_next_at = 1 << 62 if once else now + REFRESH_MS


## O endereço não foi encontrado: sem internet. Tenta de novo logo e, quando a internet
## voltar, o 1 minuto até "Em manutenção" conta do zero.
func _offline(now: int) -> void:
	if once:
		_failed(now)
		return
	_close_attempt()
	_answered = false
	_started = now
	state = State.OFFLINE
	_next_at = now + RETRY_MS


func _failed(now: int) -> void:
	_close_attempt()
	if once:
		_next_at = 1 << 62
		return
	if state == State.OFFLINE:
		# A internet voltou e o servidor ainda não respondeu: acordando.
		state = State.WAKING
	if _answered:
		# Respondia e parou (reiniciou, ou foi suspenso): volta a "acordando" e conta de
		# novo o 1 minuto até "Em manutenção".
		_answered = false
		_started = now
		state = State.WAKING
		_next_at = now + RETRY_MS
		return
	if now - _started >= GIVE_UP_MS:
		state = State.DOWN
		_next_at = now + DOWN_RETRY_MS
		return
	_next_at = now + RETRY_MS


func _close_attempt() -> void:
	if _http != null:
		_http.close()
		_http = null
	_attempt_at = -1
