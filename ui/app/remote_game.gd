extends "res://ui/app/game_session.gd"
## Partida à distância (SPEC 9.3): a mesa roda no servidor (Servidor 1, no Render) e o
## app só conversa com ele por WebSocket seguro (wss://).
##
## Uma sessão vale da lista de salas até o fim da partida: conecta, apresenta-se, pede a
## lista, cria ou entra numa sala e joga. Se a conexão cai (troca do Wi-Fi para os dados
## móveis, túnel, servidor reiniciando), tenta de novo com espera crescente (1, 2, 4, 8 e
## depois a cada 10 s) e, já numa sala, volta para ela pelo código da sala: o servidor
## reconhece o apelido e o código do aparelho e devolve o mesmo lugar (SPEC 6.1 e 6.2).
## Desiste depois de 2 minutos sem conseguir.
##
## A primeira conexão também insiste por 2 minutos: o servidor pode estar acordando.
##
## Entre as mãos o servidor manda o resumo assinado da sala (SPEC 9.4). Se o servidor
## reiniciou e a sala sumiu da memória, a volta leva o resumo (resume_room) e o servidor
## recria a sala; a mão que estava em andamento é cancelada (SPEC 6.6).

const WsClient := preload("res://net/ws_client.gd")
const Clock := preload("res://server/clock.gd")

enum Link { CONNECTING, ONLINE, RECONNECTING, FAILED }

const WAKE_NOTICE_MS: int = 3000
const GIVE_UP_MS: int = 120000
const BACKOFF_MS: Array[int] = [1000, 2000, 4000, 8000]
const MAX_BACKOFF_MS: int = 10000
## Batimento à distância (net/remote_host.gd espera até 16 s): mais espaçado que no
## Wi-Fi, para gastar menos banda do plano gratuito.
const PING_MS: int = 5000
const SILENCE_MS: int = 13000
const CONNECT_MS: int = 15000
## Na saída, espera a resposta (e o placar, se a sala fechar) pela internet.
const FLUSH_MS: int = 1500
## Quanto tempo o aviso da sala recuperada fica na mesa.
const NOTICE_MS: int = 8000
const RESTORED_NOTICE: String = "O servidor reiniciou e a sala voltou. Se havia uma mão " \
	+ "em andamento, ela foi cancelada e as apostas voltaram."

var link: Link = Link.CONNECTING
var url: String = ""
## A última lista de salas recebida (só as que aceitam gente nova).
var rooms: Array = []
## A senha da sala, quando tem (quem criou ou digitou): para voltar depois de uma queda
## e para o dono ver na sala de espera. Nunca vem do servidor.
var password: String = ""
## Saiu da sala por pedido próprio ou expulso ("left" ou "kicked").
var left_reason: String = ""
## Quantas vezes já reconectou (testes e diagnóstico).
var reconnects: int = 0

var _clock: Clock = null
var _ws: WsClient = null
var _profile: Dictionary = {}
var _greeted: bool = false
var _ever_open: bool = false
var _want: Dictionary = {}      ## pedido que espera a apresentação (criar ou entrar)
var _joining: bool = false      ## pediu para criar ou entrar e espera a resposta
var _want_sent: bool = false    ## o pedido já saiu por uma conexão
var _resuming: bool = false     ## voltando para a sala depois de uma queda
var _started: int = 0
var _lost_at: int = -1
var _retry_at: int = -1
var _attempt: int = 0
var _summary: String = ""       ## o último resumo assinado da sala (opaco para o app)
var _notice_until: int = -1


func _init(clock: Clock = null) -> void:
	_clock = clock if clock != null else Clock.new()


## Começa a conectar ao servidor (wss://… ou ws://…).
func open(address: String, nick: String, avatar: int, device: String) -> void:
	url = address
	_profile = {"nick": nick, "avatar": avatar, "device": device}
	_ws = WsClient.new(_clock)
	_ws.ping_ms = PING_MS
	_ws.silence_ms = SILENCE_MS
	_ws.connect_ms = CONNECT_MS
	_client = _ws
	_started = _clock.now_ms()
	link = Link.CONNECTING
	_ws.open_url(url)


## Pede a lista de salas de novo (a resposta chega em update() como "rooms").
func list_rooms() -> void:
	if _greeted and room_id == "":
		send({"t": Protocol.LIST_ROOMS})


## Cria uma sala; room_password: "" ou 4 dígitos.
func create(options: Dictionary, room_password: String = "") -> void:
	password = room_password
	var sent: Dictionary = options.duplicate(true)
	sent["password"] = room_password
	_request({"t": Protocol.CREATE_ROOM, "options": sent})


## Entra numa sala da lista (ou pelo código).
func join_room(id: String, room_password: String = "") -> void:
	password = room_password
	_request({"t": Protocol.JOIN_ROOM, "room": id.strip_edges().to_upper(), "spectate": false,
		"password": room_password})


func joining() -> bool:
	return _joining


func _request(message: Dictionary) -> void:
	_want = message
	_joining = true
	_want_sent = false
	if _greeted:
		_send_want()


func _send_want() -> void:
	_want_sent = true
	send(_want)


func _pump() -> void:
	if _ws == null or link == Link.FAILED:
		return
	var now: int = _clock.now_ms()
	match _ws.status:
		WsClient.Status.OPEN:
			if link != Link.ONLINE:
				if _ever_open:
					reconnects += 1
				link = Link.ONLINE
				_ever_open = true
				_lost_at = -1
				_retry_at = -1
				_attempt = 0
				_greeted = false
				_hello()
		WsClient.Status.LOST, WsClient.Status.IDLE:
			_greeted = false
			if _joining and _want_sent and _want.get("t") == Protocol.CREATE_ROOM:
				# A sala pode ter sido criada sem a resposta chegar: pedir de novo criaria
				# outra. Quem criou tenta de novo pela lista (a sala vazia fecha sozinha).
				_fail("A conexão caiu enquanto a sala era criada. Tente de novo.")
				return
			if _lost_at < 0:
				_lost_at = now
				link = Link.RECONNECTING if _ever_open else Link.CONNECTING
			if _retry_at < 0:
				_retry_at = now + (BACKOFF_MS[_attempt] if _attempt < BACKOFF_MS.size()
					else MAX_BACKOFF_MS)
			var since: int = _lost_at if _ever_open else _started
			if now - since > GIVE_UP_MS:
				_fail("A conexão com o servidor caiu e não voltou." if _ever_open
					else "O servidor não respondeu. Tente de novo daqui a pouco.")
			elif now >= _retry_at:
				_attempt += 1
				_retry_at = -1
				_ws.open_url(url)


func _track(message: Dictionary) -> void:
	super(message)
	match message.get("t"):
		Protocol.WELCOME:
			_greeted = true
			if room_id != "" and final.is_empty() and left_reason == "":
				# Voltando depois de uma queda: a mesma sala, pelo código dela. Com o
				# resumo, o servidor também consegue recriá-la se tiver reiniciado.
				_resuming = true
				if _summary != "":
					send({"t": Protocol.RESUME_ROOM, "room": room_id, "summary": _summary,
						"password": password})
				else:
					send({"t": Protocol.JOIN_ROOM, "room": room_id, "spectate": false,
						"password": password})
			elif not _want.is_empty():
				_send_want()
			else:
				send({"t": Protocol.LIST_ROOMS})
		Protocol.ROOMS:
			rooms = message.get("rooms", [])
		Protocol.JOINED:
			_joining = false
			_resuming = false
			_want = {}
			if bool(message.get("restored", false)):
				_notice_until = _clock.now_ms() + NOTICE_MS
		Protocol.SUMMARY:
			if str(message.get("room", "")) == room_id and final.is_empty():
				_summary = str(message.get("s", ""))
		Protocol.LEFT:
			left_reason = str(message.get("reason", Protocol.R_LEFT))
			_summary = ""
		Protocol.CLOSED:
			_summary = ""
		Protocol.ERROR:
			_on_error(message)


func _on_error(message: Dictionary) -> void:
	var code: String = str(message.get("code", ""))
	var text: String = sentence(str(message.get("text", "")))
	if code == Protocol.E_VERSION:
		_fail("A versão do servidor é diferente da deste app. Atualize o app.")
	elif _resuming:
		_resuming = false
		_fail("A sala foi encerrada." if code == Protocol.E_NO_ROOM else text)
	elif _joining:
		_joining = false
		var creating: bool = _want.get("t") == Protocol.CREATE_ROOM
		_want = {}
		if creating:
			# Criar sala acontece já na sala de espera: o erro encerra a tentativa.
			_fail("O servidor está cheio agora. Tente mais tarde." if code == Protocol.E_FULL
				else text)


func _hello() -> void:
	send({"t": Protocol.HELLO, "v": Protocol.VERSION, "nick": _profile["nick"],
		"avatar": _profile["avatar"], "device": _profile["device"]})


func _fail(text: String) -> void:
	error_text = text
	link = Link.FAILED
	if _ws != null:
		_ws.close()


func failed() -> bool:
	return link == Link.FAILED


## Ainda conectando pela primeira vez há mais de 3 s: o servidor está acordando.
func waking() -> bool:
	return link == Link.CONNECTING and _clock.now_ms() - _started >= WAKE_NOTICE_MS


func room_code() -> String:
	return room_id


func waiting_hint() -> String:
	var text: String = "Seus amigos acham a sala na lista de salas do servidor, ou pelo código."
	if password != "":
		text += " Senha da sala: %s." % password
	return text


func set_avatar(avatar: int) -> void:
	_profile["avatar"] = avatar
	super(avatar)


## Sai da mesa: as fichas ficam guardadas por 5 minutos no servidor (SPEC 6.2).
func leave() -> Dictionary:
	if not final.is_empty():
		return final
	send({"t": Protocol.LEAVE})
	var until: int = Time.get_ticks_msec() + FLUSH_MS
	while Time.get_ticks_msec() < until and _ws != null and _ws.is_open():
		for message: Dictionary in _ws.poll():
			_track(message)
			if message.get("t") in [Protocol.LEFT, Protocol.CLOSED]:
				return final
		OS.delay_msec(10)
	return final


func shutdown() -> void:
	if _ws != null:
		_ws.close()
		_ws = null
	_client = null


func status_text() -> String:
	match link:
		Link.RECONNECTING:
			return "Conexão perdida. Reconectando…"
		Link.CONNECTING:
			return "Conectando ao servidor…"
	if _resuming:
		return "Voltando para a sala…"
	if _notice_until >= 0 and _clock.now_ms() < _notice_until:
		return RESTORED_NOTICE
	return ""


## Enquanto reconecta, a mesa fica parada na tela (o que aparece já não vale).
func waiting_host() -> bool:
	return link == Link.RECONNECTING or _resuming


func failure() -> String:
	if link == Link.FAILED:
		return error_text
	if left_reason == Protocol.R_KICKED:
		return "O dono da sala tirou você da sala."
	if left_reason == Protocol.R_AWAY:
		return AWAY_TEXT
	return ""


func leave_question() -> Array[String]:
	if str(last_state.get("room", {}).get("phase", "")) == Protocol.PLAYING and not others_here():
		return ["Encerrar a sala?", "Você é o último jogador. A sala fecha e o placar aparece.",
			"Encerrar"]
	return ["Sair da mesa?", "Suas fichas ficam guardadas por 5 minutos, se quiser voltar.",
		"Sair"]


func has_rebuy_ads() -> bool:
	return true


func has_reactions() -> bool:
	return true


## Aviso fixo das telas de servidores e de salas, com o servidor acordando ou não. A
## frase do anúncio aparece mesmo antes de haver anúncio de verdade (pedido do dono,
## 18/11/2026).
static func wake_tip() -> String:
	return "O Bora Poker está em desenvolvimento, melhorando a cada versão. " \
		+ "Pode levar alguns segundos para o servidor aparecer. Enquanto isso, se quiser, " \
		+ "assista a um anúncio e ajude a melhorar os nossos servidores."
