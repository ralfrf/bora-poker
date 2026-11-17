extends RefCounted
## Servidor de salas: liga as conexões de um transporte às salas (SPEC 8 e 9.1).
##
## É o mesmo nos três modos. No offline fica dentro do app, com o transporte local e
## uma sala só; no Wi-Fi e no Render o transporte é de rede. Quem hospeda chama tick()
## de tempos em tempos.
##
## O transporte só precisa ter: poll() -> [{type, peer, data}], send(peer, mensagem) e
## drop(peer). O de rede tem também send_state(peer, mensagem, pacote), que manda o
## `state` pelo protocolo enxuto (server/wire.gd).

const Room := preload("res://server/room.gd")
const Protocol := preload("res://server/protocol.gd")
const Clock := preload("res://server/clock.gd")
const Wire := preload("res://server/wire.gd")
const Load := preload("res://server/load.gd")
const PasswordGuard := preload("res://server/password_guard.gd")
const Summary := preload("res://server/summary.gd")

const DEFAULT_MAX_ROOMS: int = 20
const MAX_DEVICE: int = 64
const CODE_CHARS: String = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   # sem 0, O, 1 e I
const CODE_LENGTH: int = 4
## Limite de mensagens por conexão: até RATE_BURST de uma vez, repostas a `rate` por
## segundo (SPEC 9.3). Quem passa disso é desconectado.
const RATE_BURST: int = 40
## Com a CPU do último minuto acima disso, sala nova é recusada (SPEC 9.3).
const CPU_FULL: int = 90
## A lista de salas à distância leva no máximo isso (só as que aceitam gente nova).
const MAX_LISTED: int = 60
const MAX_PASSWORD: int = 8
## Recuperação depois de um reinício (SPEC 9.4): quanto o servidor espera pelos outros
## celulares da sala, a partir do primeiro resumo, antes de recriá-la.
const RESUME_WAIT_MS: int = 6000


class Session:
	extends RefCounted

	var peer: int = 0
	var greeted: bool = false
	var nick: String = ""
	var avatar: int = 0
	var device: String = ""
	var room_id: String = ""
	var member_id: String = ""
	var tokens: int = RATE_BURST * 1000   ## milésimos de mensagem
	var tokens_ms: int = -1             ## -1 = ainda não mandou nada
	var recovering: String = ""         ## apresentou o resumo dessa sala e espera a recriação


## Uma sala por recriar (SPEC 9.4): o resumo mais recente apresentado e quem espera.
class Recovery:
	extends RefCounted

	var data: Dictionary = {}     ## o resumo aberto (Summary.open)
	var peers: Dictionary = {}    ## conexão -> senha que o celular sabia ("" se nenhuma)
	var due: int = 0


var rooms: Dictionary = {}   ## código da sala -> Room
## Vagas de carga e CPU (servidor à distância). Sem "slots" na configuração, não limita.
var capacity: Load = null

var _transport: Object = null
var _clock: Clock = null
var _max_rooms: int = DEFAULT_MAX_ROOMS
var _room_config: Dictionary = {}
var _rate: int = 0   # mensagens por segundo por conexão; 0 = sem limite
var _seed_source: Callable = Callable()
var _sessions: Dictionary = {}   # peer -> Session
var _routes: Dictionary = {}     # "sala/participante" -> peer
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _guard: PasswordGuard = null
var _open_only: bool = false     # a lista mostra só as salas que aceitam gente nova
## Resumo assinado (só à distância, SPEC 9.4). Sem ele, nada de resumo nem recuperação.
var _summary: Summary = null
var _resume_wait: int = RESUME_WAIT_MS
var _issued: Dictionary = {}      # sala -> {rev, at}: o último resumo mandado
var _recoveries: Dictionary = {}  # sala -> Recovery
## Salas que acabaram neste processo -> quando (now_ms): resumo nenhum as recria (nem
## um de antes do reinício) enquanto ele ainda poderia valer.
var _ended: Dictionary = {}


## config: {max_rooms, room: ajustes repassados a cada sala, slots: vagas em
## centésimos (0 = sem limite), rate: mensagens por segundo por conexão (0 = sem
## limite), cpu_reader e cpu_share: a CPU do serviço (server/load.gd), summary: o
## assinador do resumo (server/summary.gd), resume_wait_ms}.
## seed_source: só nos testes; repassado às salas.
func _init(transport: Object, clock: Clock = null, config: Dictionary = {},
		seed_source: Callable = Callable()) -> void:
	_transport = transport
	_clock = clock if clock != null else Clock.new()
	_max_rooms = int(config.get("max_rooms", DEFAULT_MAX_ROOMS))
	_room_config = config.get("room", {})
	_rate = int(config.get("rate", 0))
	_open_only = bool(config.get("list_open_only", false))
	_guard = PasswordGuard.new(_clock)
	_summary = config.get("summary")
	_resume_wait = int(config.get("resume_wait_ms", RESUME_WAIT_MS))
	capacity = Load.new(int(config.get("slots", 0)), _clock, config.get("cpu_reader", Callable()),
		float(config.get("cpu_share", 1.0)))
	_seed_source = seed_source
	if seed_source.is_valid():
		_rng.seed = int(seed_source.call())
	else:
		_rng.randomize()


## Lê o que chegou, faz o tempo das salas andar e apaga as salas encerradas.
func tick() -> void:
	for event: Dictionary in _transport.call("poll"):
		var peer: int = event["peer"]
		match event["type"]:
			"connect":
				var session: Session = Session.new()
				session.peer = peer
				_sessions[peer] = session
			"disconnect":
				_disconnected(peer)
			"message":
				var session: Session = _sessions.get(peer)
				if session != null and typeof(event["data"]) == TYPE_DICTIONARY:
					_message(session, event["data"])
	for room: Room in rooms.values():
		room.tick()
	for room_id: String in rooms.keys():
		if rooms[room_id].is_closed():
			rooms.erase(room_id)
			_issued.erase(room_id)
			_guard.forget_room(room_id)
			if _summary != null:
				_forget_ended()
				_ended[room_id] = _clock.now_ms()
	_send_summaries()
	_finish_recoveries()
	capacity.sample()


## Vagas em uso, em centésimos: cada sala pelo tamanho e pelos espectadores que contam.
func used_slots() -> int:
	var used: int = 0
	for room: Room in rooms.values():
		if not room.is_closed():
			used += Load.room_weight(int(room.options["seats"]), room.watchers())
	return used


## A lotação para o app (SPEC 9.3): % e se cabe sala nova.
func load_info() -> Dictionary:
	return {"pct": capacity.percent(used_slots()),
		"full": not _has_room_for(Load.room_weight(Room.MIN_SEATS, 0))}


## Cabe mais esse peso (sala nova ou espectador)? Também conta o teto de salas e a CPU.
func _has_room_for(weight: int, new_room: bool = true) -> bool:
	return ((not new_room or rooms.size() + _recoveries.size() < _max_rooms)
		and capacity.cpu_percent() < CPU_FULL and capacity.fits(used_slots(), weight))


## Quantas conexões estão apresentadas (para o diagnóstico).
func session_count() -> int:
	return _sessions.size()


## Continua uma sala a partir do retrato de outro servidor (Wi-Fi: o anfitrião saiu e
## este celular assumiu). Devolve "" ou o motivo da recusa.
func restore_room(saved: Dictionary) -> String:
	var room_id: String = str(saved.get("id", ""))
	if room_id == "" or rooms.has(room_id) or rooms.size() >= _max_rooms:
		return "não dá para continuar a sala aqui"
	var raw: Dictionary = saved.get("options", {}).duplicate(true)
	raw["bots"] = []
	var checked: Dictionary = Room.normalize_options(raw)
	if not checked["ok"]:
		return checked["error"]
	var room: Room = Room.new(room_id, checked["options"], _clock, _deliver.bind(room_id),
		_room_config, _seed_source)
	room.send_state = _deliver_state.bind(room_id)
	var problem: String = room.restore(saved)
	if problem != "":
		return problem
	room.options["bots"] = saved["options"].get("bots", [])
	rooms[room_id] = room
	return ""


## Manda uma mensagem a um participante, se ele estiver conectado. Devolve se mandou.
func send_to_member(room_id: String, member_id: String, message: Dictionary) -> bool:
	var key: String = _key(room_id, member_id)
	if not _routes.has(key):
		return false
	_transport.call("send", _routes[key], message)
	return true


## O IP da conexão de um participante ("" se não estiver conectado pela rede).
func member_ip(room_id: String, member_id: String) -> String:
	var key: String = _key(room_id, member_id)
	if not _routes.has(key) or not _transport.has_method("peer_ip"):
		return ""
	return str(_transport.call("peer_ip", _routes[key]))


func _message(session: Session, data: Dictionary) -> void:
	if not _within_rate(session):
		_refuse(session, Protocol.E_REFUSED, "mensagens demais")
		_disconnected(session.peer)
		_transport.call("drop", session.peer)
		return
	var type: Variant = data.get("t")
	if typeof(type) != TYPE_STRING:
		_refuse(session, Protocol.E_BAD_MESSAGE, "mensagem malformada")
		return
	if type == Protocol.PING:
		_reply(session, {"t": Protocol.PONG})
		return
	if type == Protocol.HELLO:
		_hello(session, data)
		return
	if not session.greeted:
		_refuse(session, Protocol.E_NO_HELLO, "falta a apresentação")
		return
	match type:
		Protocol.LIST_ROOMS:
			var list: Array = []
			for room: Room in rooms.values():
				if room.is_closed():
					continue
				var summary: Dictionary = room.summary()
				if _open_only and not summary["open"]:
					continue
				list.append(summary)
				if _open_only and list.size() >= MAX_LISTED:
					break
			_reply(session, {"t": Protocol.ROOMS, "rooms": list})
		Protocol.CREATE_ROOM:
			_create_room(session, data)
		Protocol.JOIN_ROOM:
			_join_room(session, data)
		Protocol.RESUME_ROOM:
			_resume_room(session, data)
		Protocol.LEAVE:
			_leave(session)
		_:
			var room: Room = rooms.get(session.room_id)
			if room == null:
				_refuse(session, Protocol.E_NO_ROOM, "você não está em uma sala")
			else:
				room.handle(session.member_id, data)


## Toda conexão começa pela versão do protocolo (SPEC 9.1).
func _hello(session: Session, data: Dictionary) -> void:
	var version: Variant = data.get("v")
	if typeof(version) != TYPE_INT or version != Protocol.VERSION:
		_refuse(session, Protocol.E_VERSION, "Atualize o app.")
		_sessions.erase(session.peer)
		_transport.call("drop", session.peer)
		return
	var nick: Variant = data.get("nick", "")
	var avatar: Variant = data.get("avatar", 0)
	var device: Variant = data.get("device", "")
	if typeof(nick) != TYPE_STRING or typeof(avatar) != TYPE_INT or typeof(device) != TYPE_STRING:
		_refuse(session, Protocol.E_BAD_MESSAGE, "apresentação malformada")
		return
	session.nick = Room.clean_nick(nick)
	session.avatar = clampi(avatar, 0, Room.AVATARS - 1)
	session.device = (device as String).left(MAX_DEVICE)
	session.greeted = true
	var welcome: Dictionary = {"t": Protocol.WELCOME, "v": Protocol.VERSION, "nick": session.nick}
	if capacity.total > 0:
		welcome["load"] = load_info()
	_reply(session, welcome)


func _create_room(session: Session, data: Dictionary) -> void:
	if session.room_id != "" or session.recovering != "":
		_refuse(session, Protocol.E_REFUSED, "você já está em uma sala")
		return
	if rooms.size() + _recoveries.size() >= _max_rooms:
		_refuse(session, Protocol.E_FULL, "o servidor está cheio; tente mais tarde")
		return
	var checked: Dictionary = Room.normalize_options(data.get("options", {}))
	if not checked["ok"]:
		_refuse(session, Protocol.E_REFUSED, checked["error"])
		return
	var options: Dictionary = checked["options"]
	if not _has_room_for(Load.room_weight(int(options["seats"]), 0)):
		_refuse(session, Protocol.E_FULL, "o servidor está cheio; tente mais tarde")
		return
	if (options["bots"] as Array).size() >= int(options["seats"]):
		_refuse(session, Protocol.E_REFUSED, "deixe um lugar para você")
		return
	var room_id: String = _new_code()
	var room: Room = Room.new(
		room_id, options, _clock, _deliver.bind(room_id), _room_config, _seed_source)
	room.send_state = _deliver_state.bind(room_id)
	room.summaries = _summary != null
	rooms[room_id] = room
	_enter(session, room, false)


func _join_room(session: Session, data: Dictionary) -> void:
	if session.room_id != "" or session.recovering != "":
		_refuse(session, Protocol.E_REFUSED, "você já está em uma sala")
		return
	var room_id: Variant = data.get("room")
	var spectate: Variant = data.get("spectate", false)
	if typeof(room_id) != TYPE_STRING or typeof(spectate) != TYPE_BOOL:
		_refuse(session, Protocol.E_BAD_MESSAGE, "pedido malformado")
		return
	var room: Room = rooms.get((room_id as String).to_upper())
	if room == null or room.is_closed():
		_refuse(session, Protocol.E_NO_ROOM, "sala não encontrada")
		return
	if not _password_ok(session, room, data.get("password", "")):
		return
	if spectate and not _has_room_for(Load.WATCHER_WEIGHT, false):
		_refuse(session, Protocol.E_FULL, "o servidor está cheio; tente mais tarde")
		return
	_enter(session, room, spectate)


## Sala com senha (SPEC 9.3): confere e conta as erradas. Responde o erro e devolve
## falso quando não pode entrar. Senha vazia é só o pedido dela: não conta como errada.
func _password_ok(session: Session, room: Room, raw: Variant) -> bool:
	if not room.needs_password(_device_for(room.id, session), session.nick):
		return true
	var password: String = (raw as String).left(MAX_PASSWORD) if typeof(raw) == TYPE_STRING else ""
	var ip: String = str(_transport.call("peer_ip", session.peer)) \
		if _transport.has_method("peer_ip") else ""
	var wait: int = _guard.wait_ms(room.id, session.device, ip)
	if wait > 0:
		_refuse_password(session, "muitas tentativas erradas; espere %d s" % ceili(wait / 1000.0), wait)
		return false
	if password == "":
		_refuse_password(session, "esta sala tem senha", 0)
		return false
	if room.password_matches(password):
		return true
	wait = _guard.failed(room.id, session.device, ip)
	_refuse_password(session, "senha errada" if wait == 0
		else "senha errada; espere %d s para tentar de novo" % ceili(wait / 1000.0), wait)
	return false


func _refuse_password(session: Session, text: String, wait: int) -> void:
	var message: Dictionary = Protocol.error(Protocol.E_PASSWORD, text)
	message["wait_ms"] = wait
	_reply(session, message)


func _enter(session: Session, room: Room, spectate: bool, restored: bool = false) -> void:
	var result: Dictionary = room.join({"nick": session.nick, "avatar": session.avatar,
		"device": _device_for(room.id, session)}, spectate)
	if not result["ok"]:
		_refuse(session, Protocol.E_REFUSED, result["error"])
		return
	session.room_id = room.id
	session.member_id = result["id"]
	var key: String = _key(room.id, session.member_id)
	var old_peer: int = int(_routes.get(key, -1))
	if old_peer >= 0 and old_peer != session.peer:
		# O mesmo jogador chegou por uma conexão nova antes de a antiga cair: a antiga
		# deixa de responder por ele e é encerrada.
		var old: Session = _sessions.get(old_peer)
		if old != null:
			old.room_id = ""
			old.member_id = ""
		_transport.call("drop", old_peer)
	_routes[key] = session.peer
	var joined: Dictionary = {"t": Protocol.JOINED, "room": room.id, "you": session.member_id,
		"resumed": result.get("resumed", false)}
	if restored:
		joined["restored"] = true
	_reply(session, joined)
	if _issued.has(room.id):
		# Quem entra depois do envio também precisa do resumo (SPEC 9.4).
		_reply(session, _issued[room.id]["message"])
	room.announce()


## O código do aparelho que a sala guarda: à distância, a marca da sala (o resumo vai aos
## celulares e não pode levar o código de ninguém); nos outros modos, o próprio código.
func _device_for(room_id: String, session: Session) -> String:
	if _summary == null:
		return session.device
	return _summary.device_tag(room_id, session.device)


# ---------------------------------------------------------------- resumo (SPEC 9.4)


## Manda o resumo assinado a cada celular da sala quando a sala guardou um retrato novo,
## e de novo a cada Summary.REFRESH_S numa mão longa (o resumo vence).
func _send_summaries() -> void:
	if _summary == null:
		return
	var now_s: int = _clock.unix_s()
	for room_id: String in rooms:
		var room: Room = rooms[room_id]
		if room.is_closed() or room.last_summary.is_empty():
			continue
		var sent: Dictionary = _issued.get(room_id, {})
		if int(sent.get("rev", -1)) == room.summary_rev \
				and now_s - int(sent.get("at", 0)) < Summary.REFRESH_S:
			continue
		var message: Dictionary = {"t": Protocol.SUMMARY, "room": room_id,
			"s": _summary.sign(room.last_summary, room.summary_rev, room.kept_lock
				if room.kept_lock != "" else _summary.lock_tag(room_id, room.password_for_summary()),
				now_s)}
		_issued[room_id] = {"rev": room.summary_rev, "at": now_s, "message": message}
		for member_id: String in room.members:
			var key: String = _key(room_id, member_id)
			if _routes.has(key):
				_transport.call("send", _routes[key], message)


## O celular voltou depois de um reinício e devolveu o resumo da sala. Se a sala ainda
## existe, é só entrar nela. Senão, confere o resumo e espera RESUME_WAIT_MS pelos
## outros celulares; a sala é recriada do resumo mais recente apresentado.
func _resume_room(session: Session, data: Dictionary) -> void:
	if session.room_id != "" or session.recovering != "":
		_refuse(session, Protocol.E_REFUSED, "você já está em uma sala")
		return
	var raw_id: Variant = data.get("room")
	var token: Variant = data.get("summary")
	var password: Variant = data.get("password", "")
	if typeof(raw_id) != TYPE_STRING or typeof(token) != TYPE_STRING \
			or typeof(password) != TYPE_STRING:
		_refuse(session, Protocol.E_BAD_MESSAGE, "pedido malformado")
		return
	var room_id: String = (raw_id as String).to_upper()
	var room: Room = rooms.get(room_id)
	if room != null and not room.is_closed():
		_join_room(session, {"room": room_id, "spectate": false, "password": password})
		return
	if _summary == null:
		_refuse(session, Protocol.E_NO_ROOM, "sala não encontrada")
		return
	var opened: Dictionary = _summary.open(token, _clock.unix_s())
	if not opened["ok"]:
		_refuse(session, Protocol.E_NO_ROOM, opened["error"])
		return
	var info: Dictionary = opened["data"]
	var saved: Dictionary = info["room"]
	if str(saved.get("id", "")) != room_id:
		_refuse(session, Protocol.E_NO_ROOM, "o resumo é de outra sala")
		return
	if str(info["boot"]) == _summary.boot or _ended_recently(room_id):
		# Emitido por este mesmo servidor, ou a sala já acabou depois do reinício: não
		# há o que recuperar.
		_refuse(session, Protocol.E_NO_ROOM, "sala não encontrada")
		return
	var tag: String = _summary.device_tag(room_id, session.device)
	if not _lists(saved, tag, session.nick):
		_refuse(session, Protocol.E_NO_ROOM, "você não consta nesta sala")
		return
	var recovery: Recovery = _recoveries.get(room_id)
	if recovery == null:
		if rooms.size() + _recoveries.size() >= _max_rooms:
			_refuse(session, Protocol.E_FULL, "o servidor está cheio; tente mais tarde")
			return
		recovery = Recovery.new()
		recovery.data = info
		recovery.due = _clock.now_ms() + _resume_wait
		_recoveries[room_id] = recovery
	elif int(info["rev"]) > int(recovery.data["rev"]):
		# Um resumo mais recente: ninguém volta com as fichas de uma mão antiga.
		recovery.data = info
	recovery.peers[session.peer] = (password as String).left(MAX_PASSWORD)
	session.recovering = room_id


func _ended_recently(room_id: String) -> bool:
	_forget_ended()
	return _ended.has(room_id)


## Esquece as salas encerradas há mais tempo do que um resumo vale.
func _forget_ended() -> void:
	var now: int = _clock.now_ms()
	for ended_id: String in _ended.keys():
		if now - int(_ended[ended_id]) > (Summary.VALID_S + Summary.SKEW_S) * 1000:
			_ended.erase(ended_id)


## O resumo traz essa pessoa (humana) entre os participantes, ou com fichas guardadas?
## A mesma regra de Room._same_person e Room._held_id: marca do aparelho e apelido.
static func _lists(saved: Dictionary, tag: String, nick: String) -> bool:
	if tag == "":
		return false
	var people: Array = []
	var members: Variant = saved.get("members", [])
	if typeof(members) == TYPE_ARRAY:
		for raw: Variant in members:
			if typeof(raw) == TYPE_DICTIONARY and not bool(raw.get("bot", false)):
				people.append([str(raw.get("device", "")), str(raw.get("base_nick", ""))])
	var held: Variant = saved.get("held_by", {})
	if typeof(held) == TYPE_DICTIONARY:
		for who: Variant in held.values():
			if typeof(who) == TYPE_DICTIONARY:
				people.append([str(who.get("device", "")), str(who.get("nick", ""))])
	return people.has([tag, nick])


## Passada a espera, recria as salas e põe nelas quem ainda espera. A mão que estava
## em andamento não existe no resumo: as apostas dela voltaram (SPEC 6.6).
func _finish_recoveries() -> void:
	var now: int = _clock.now_ms()
	for room_id: String in _recoveries.keys():
		var recovery: Recovery = _recoveries[room_id]
		if now < recovery.due:
			continue
		_recoveries.erase(room_id)
		var waiting: Array[Session] = []
		for peer: int in recovery.peers:
			var session: Session = _sessions.get(peer)
			if session != null and session.recovering == room_id:
				session.recovering = ""
				waiting.append(session)
		if waiting.is_empty():
			continue
		var problem: String = restore_room(recovery.data["room"])
		if problem != "":
			for session: Session in waiting:
				_refuse(session, Protocol.E_NO_ROOM, problem)
			continue
		var room: Room = rooms[room_id]
		room.summaries = true
		room.summary_rev = int(recovery.data["rev"])
		# O mesmo retrato vai de novo, assinado por este processo: a validade recomeça
		# e quem voltou fica com um resumo para um próximo reinício.
		room.last_summary = recovery.data["room"]
		room.after_restart()
		var lock: String = str(recovery.data["lock"])
		if lock != "":
			room.set_password(_known_password(room_id, lock, recovery))
			if room.password_for_summary() == "":
				room.kept_lock = lock
		for session: Session in waiting:
			_enter(session, room, false, true)


## A senha que algum celular devolveu e que bate com a marca do resumo ("" = nenhuma).
func _known_password(room_id: String, lock: String, recovery: Recovery) -> String:
	for peer: int in recovery.peers:
		var known: String = str(recovery.peers[peer])
		if Room.is_password(known) and _summary.lock_tag(room_id, known) == lock:
			return known
	return ""


func _leave(session: Session) -> void:
	var room: Room = rooms.get(session.room_id)
	if room == null:
		_refuse(session, Protocol.E_NO_ROOM, "você não está em uma sala")
		return
	var member_id: String = session.member_id
	_routes.erase(_key(room.id, member_id))
	session.room_id = ""
	session.member_id = ""
	room.leave(member_id)
	if room.is_closed() and not room.final.is_empty():
		# Era o último humano: a sala fechou e quem saiu também vê o placar.
		_reply(session, room.final)
	_reply(session, {"t": Protocol.LEFT, "reason": Protocol.R_LEFT})


## A conexão caiu: a sala guarda o lugar por 60 s e reconhece a volta (SPEC 6).
func _disconnected(peer: int) -> void:
	var session: Session = _sessions.get(peer)
	if session == null:
		return
	_sessions.erase(peer)
	session.recovering = ""
	var room: Room = rooms.get(session.room_id)
	if room != null:
		var key: String = _key(room.id, session.member_id)
		if int(_routes.get(key, -1)) == peer:
			_routes.erase(key)
		room.drop_connection(session.member_id)


## A saída das salas: entrega a mensagem à conexão do participante.
func _deliver(member_id: String, message: Dictionary, room_id: String) -> void:
	var key: String = _key(room_id, member_id)
	if not _routes.has(key):
		return
	var peer: int = _routes[key]
	_transport.call("send", peer, message)
	if message["t"] == Protocol.LEFT or message["t"] == Protocol.CLOSED:
		# Expulso, ou a sala encerrou: a conexão fica livre para outra sala.
		_routes.erase(key)
		var session: Session = _sessions.get(peer)
		if session != null:
			session.room_id = ""
			session.member_id = ""


## O `state` de um participante, com as partes públicas do lance já prontas.
func _deliver_state(member_id: String, message: Dictionary, pack: Wire.StatePack,
		room_id: String) -> void:
	var key: String = _key(room_id, member_id)
	if not _routes.has(key):
		return
	if _transport.has_method("send_state"):
		_transport.call("send_state", _routes[key], message, pack)
	else:
		_transport.call("send", _routes[key], message)


## Repõe as mensagens da conexão e gasta uma. Falso: passou do limite.
func _within_rate(session: Session) -> bool:
	if _rate <= 0:
		return true
	var now: int = _clock.now_ms()
	if session.tokens_ms >= 0:
		session.tokens = mini(RATE_BURST * 1000, session.tokens + (now - session.tokens_ms) * _rate)
	session.tokens_ms = now
	if session.tokens < 1000:
		return false
	session.tokens -= 1000
	return true


func _reply(session: Session, message: Dictionary) -> void:
	_transport.call("send", session.peer, message)


func _refuse(session: Session, code: String, text: String) -> void:
	_reply(session, Protocol.error(code, text))


func _key(room_id: String, member_id: String) -> String:
	return room_id + "/" + member_id


## Código curto da sala, fácil de ditar. No Wi-Fi quem digita usa o código do IP
## (net/room_code.gd); este identifica a sala dentro do servidor.
func _new_code() -> String:
	while true:
		var code: String = ""
		for _i in CODE_LENGTH:
			code += CODE_CHARS[_rng.randi_range(0, CODE_CHARS.length() - 1)]
		if not rooms.has(code) and not _recoveries.has(code) and not _ended.has(code):
			return code
	return ""
