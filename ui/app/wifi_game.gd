extends "res://ui/app/game_session.gd"
## Partida no Mesmo Wi-Fi (SPEC 9.2).
##
## Anfitrião: o servidor de mesa roda neste celular. Ele joga pelo transporte local e os
## convidados chegam por WebSocket; os dois entram no servidor por um mux. A sala é
## anunciada por broadcast UDP.
##
## Convidado: conecta por WebSocket no celular do anfitrião, apresenta-se, pede a lista
## (há uma sala só) e entra. Se a conexão cai, tenta de novo por até 2 minutos e volta
## para o mesmo lugar (SPEC 6.2 e 6.4).
##
## Anfitrião sai pelo botão (SPEC 6.4): se há outro humano conectado, a sala passa para
## o celular dele. Espera a mão em andamento acabar (o anfitrião desiste dela), manda o
## retrato da sala só para o herdeiro e o novo endereço para todos; o herdeiro abre o
## servidor com a sala e os outros reconectam nele.
##
## Anfitrião some sem tocar em "Sair" (SPEC 6.4): bloqueou a tela, atendeu uma ligação,
## o Android fechou o app. O tempo em que o app ficou parado não conta para a sala (os
## relógios ficam parados); passando de 10 s, ele desiste da mão em andamento. A sala é
## gravada no celular dele a cada jogada (com a mão e o baralho: o arquivo não sai do
## aparelho), para voltar mesmo se o app for fechado. Os convidados mostram "Aguardando o
## anfitrião…" e tentam por 2 minutos; sem volta, cada um encerra com o placar calculado
## do último state (net/host_lost.gd).

const Server := preload("res://server/server.gd")
const Clock := preload("res://server/clock.gd")
const LocalTransport := preload("res://net/local_transport.gd")
const WsServer := preload("res://net/ws_server.gd")
const WsClient := preload("res://net/ws_client.gd")
const Mux := preload("res://net/mux.gd")
const Discovery := preload("res://net/discovery.gd")
const RoomCode := preload("res://net/room_code.gd")
const HostLost := preload("res://net/host_lost.gd")
const Codec := preload("res://net/codec.gd")

enum Link { CONNECTING, ONLINE, RECONNECTING, FAILED }

const RETRY_MS: int = 2000
const RECONNECT_MS: int = 120000   ## 2 minutos (SPEC 6.4)
const HOST_NOTICE_MS: int = 6000
## Um quadro que demora mais do que isto: o app ficou parado (tela bloqueada, ligação).
const STALL_MS: int = 3000
## Interrupção do anfitrião que não conta (SPEC 6.4, sugestão de 10 s).
const GRACE_MS: int = 10000
## Onde o anfitrião grava a sala; e de quanto em quanto tempo, além de a cada jogada.
const SAVE_PATH: String = "user://sala_wifi.json"
const SAVE_EVERY_MS: int = 5000
## Um arquivo de sala mais velho do que isto nem é lido (o placar já não interessa).
const SAVE_MAX_AGE_MS: int = 1800000

var link: Link = Link.CONNECTING
## Saiu da sala por pedido próprio ou expulso ("left" ou "kicked").
var left_reason: String = ""
## O código da sala e o IP do anfitrião na rede.
var code: String = ""
var host_ip: String = ""
var port: int = WsServer.PORT
## Para quem a sala passou (apelido), quando o anfitrião sai.
var heir_nick: String = ""
## Ajustes de quando este celular assume a sala (os testes mudam):
## listen_port, announce_to, announce_port, room_config, seed_source.
var takeover: Dictionary = {}
## Quanto tempo esperar pelo anfitrião que sumiu (os testes encurtam).
var wait_host_ms: int = RECONNECT_MS
## Arquivo onde o anfitrião grava a sala; vazio = não grava (testes, salvo quando pedem).
var save_path: String = ""

var _clock: Clock = null
var _room_clock: Clock = null    ## relógio da sala no anfitrião: sem o tempo de app parado
var _last_real: int = -1
var _last_wall: int = -1
var _stall_extra: int = 0        ## testes: uma parada simulada
var _was_paused: bool = false    ## o Android avisou que o app foi para segundo plano
var _saved_at: int = -1
var _dirty: bool = false
var _local: Array[Dictionary] = []   ## mensagens geradas aqui (placar sem o anfitrião)
var _notice: String = ""         ## aviso passageiro na mesa
var _notice_until: int = -1
var _profile: Dictionary = {}
# Anfitrião
var _server: Server = null
var _ws_server: WsServer = null
var _announcer: Discovery.Announcer = null
var _exiting: bool = false       ## saiu e espera a mão acabar para passar a sala
var _exited: bool = false        ## a sala já passou (ou fechou)
var _host_since: int = -1        ## quando este celular assumiu a sala de outro
# Convidado
var _ws: WsClient = null
var _joined_once: bool = false
var _joining: bool = false
var _pending_room: String = ""
var _lost_at: int = -1
var _retry_at: int = 0
var _moving_to: String = ""      ## a sala está passando para o celular deste apelido


func _init(clock: Clock = null) -> void:
	_clock = clock if clock != null else Clock.new()


## Abre a sala neste celular. Devolve falso (com error_text) se não deu.
## room_config e seed_source: só nos testes. announce_to: para onde mandar os anúncios
## (testes); vazio = broadcast da rede. listen_port 0 = porta livre qualquer (testes).
func host(nick: String, avatar: int, device: String, options: Dictionary,
		room_config: Dictionary = {}, seed_source: Callable = Callable(),
		announce_to: Array[String] = [], listen_port: int = WsServer.PORT,
		announce_port: int = Discovery.PORT) -> bool:
	_profile = {"nick": nick, "avatar": avatar, "device": device}
	var ip: String = RoomCode.local_ip()
	if ip == "" and announce_to.is_empty():
		_fail("Conecte o celular a uma rede Wi-Fi ou ligue o ponto de acesso.")
		return false
	if not _open_server(ip, listen_port, announce_to, announce_port, room_config, seed_source):
		return false
	_hello()
	send({"t": Protocol.CREATE_ROOM, "options": options})
	return true


## Entra na sala de outro celular.
func join(ip: String, room_port: int, nick: String, avatar: int, device: String) -> void:
	is_host = false
	host_ip = ip
	port = room_port
	_profile = {"nick": nick, "avatar": avatar, "device": device}
	_ws = WsClient.new(_clock)
	_client = _ws
	_ws.open(ip, room_port)
	link = Link.CONNECTING


## Servidor, transportes e anúncios deste celular, que passa a ser o anfitrião.
func _open_server(ip: String, listen_port: int, announce_to: Array[String],
		announce_port: int, room_config: Dictionary, seed_source: Callable) -> bool:
	is_host = true
	_ws_server = WsServer.new(_clock)
	if _ws_server.listen(listen_port) != OK:
		_ws_server = null
		_fail("Não foi possível abrir a sala neste celular. Feche e abra o app.")
		return false
	host_ip = ip
	port = _ws_server.port
	code = RoomCode.encode(ip)
	var local: LocalTransport = LocalTransport.new()
	var mux: Mux = Mux.new()
	mux.add(local)
	mux.add(_ws_server)
	_room_clock = _clock if _clock.manual else Clock.new()
	_last_real = -1
	_server = Server.new(mux, _room_clock, {"max_rooms": 1, "room": room_config}, seed_source)
	_client = local.connect_client()
	_announcer = Discovery.Announcer.new(_clock, announce_to, announce_port)
	link = Link.ONLINE
	return true


func _pump() -> void:
	if is_host:
		_pump_host()
	elif _ws != null:
		_pump_guest()


func _pump_host() -> void:
	if _server == null:
		return
	if _check_stall():
		return
	_server.tick()
	var room: Object = _server.rooms.get(room_id)
	if room != null and my_id != "":
		room.set("host_id", my_id)
	_autosave(false)
	if _exiting:
		if not _exited:
			if room == null or room.call("is_closed"):
				_exited = true
			elif not room.get("table").call("hand_in_progress"):
				_hand_over(room)
		return
	if _announcer != null and room != null and not room.call("is_closed"):
		_announcer.poll(_announcement(room))


func _pump_guest() -> void:
	var now: int = _clock.now_ms()
	match _ws.status:
		WsClient.Status.OPEN:
			if link != Link.ONLINE and link != Link.FAILED:
				# Conectou (ou reconectou): apresenta-se e pede a sala.
				link = Link.ONLINE
				_lost_at = -1
				_hello()
				send({"t": Protocol.LIST_ROOMS})
		WsClient.Status.LOST:
			if link == Link.FAILED:
				return
			if not _joined_once:
				_fail("Não foi possível entrar na sala. Confira se os dois celulares estão na mesma rede.")
				return
			if _lost_at < 0:
				_lost_at = now
				_retry_at = now + RETRY_MS
				link = Link.RECONNECTING
			if now - _lost_at > wait_host_ms:
				_host_gone()
			elif now >= _retry_at:
				_retry_at = now + RETRY_MS
				_ws.open(host_ip, port)
		WsClient.Status.CONNECTING:
			if _lost_at >= 0:
				link = Link.RECONNECTING


func _track(message: Dictionary) -> void:
	super(message)
	match message.get("t"):
		Protocol.STATE:
			_dirty = true
		Protocol.CLOSED:
			_delete_save()
		Protocol.ROOMS:
			if not is_host:
				_pick_room(message.get("rooms", []))
		Protocol.JOINED:
			_joined_once = true
			_joining = false
			_moving_to = ""
		Protocol.LEFT:
			left_reason = str(message.get("reason", Protocol.R_LEFT))
		Protocol.MOVE:
			if not is_host:
				_on_move(message)
		Protocol.ERROR:
			var code_name: String = str(message.get("code", ""))
			var text: String = str(message.get("text", ""))
			if code_name == Protocol.E_VERSION:
				_fail("A versão do app do anfitrião é diferente. Atualizem o app nos dois celulares.")
			elif _joining:
				_fail(sentence(text))


## Convidado: entra na sala de antes (reconexão) ou na única que houver.
func _pick_room(rooms: Array) -> void:
	if rooms.is_empty():
		_fail("A sala foi encerrada.")
		return
	var target: String = str(rooms[0].get("id", ""))
	for room: Dictionary in rooms:
		if str(room.get("id", "")) == room_id and room_id != "":
			target = room_id
	if room_id != "" and target != room_id:
		_fail("A sala foi encerrada.")
		return
	_pending_room = target
	# Entrada nova numa partida em andamento com vaga: pergunta antes de sentar (pedido do
	# dono, 16/11/2026). Sem vaga, o servidor recusa e o motivo aparece na lista de salas.
	for room: Dictionary in rooms:
		if (room_id == "" and str(room.get("id", "")) == target
				and room.get("phase") == Protocol.PLAYING and bool(room.get("keep_open", false))
				and int(room.get("players", 0)) < int(room.get("seats", 0))):
			confirm_seat = true
			return
	confirm_join()


## Convidado: confirma a entrada (depois da pergunta, ou direto).
func confirm_join() -> void:
	confirm_seat = false
	if _pending_room == "" or link == Link.FAILED:
		return
	_joining = true
	send({"t": Protocol.JOIN_ROOM, "room": _pending_room, "spectate": false})


func failed() -> bool:
	return link == Link.FAILED


## O código derivado do IP do anfitrião (SPEC 9.2).
func room_code() -> String:
	return RoomCode.pretty(RoomCode.encode(host_ip)) if host_ip != "" else ""


func waiting_hint() -> String:
	if not is_host:
		return ""
	return "Os amigos precisam estar na mesma rede Wi-Fi. A sala aparece sozinha " \
		+ "para eles; se não aparecer, passe o código. Se a rede bloquear, ligue o ponto " \
		+ "de acesso deste celular e peça para eles se conectarem nele."


func closed_notice() -> String:
	return "O anfitrião fechou a sala."


# ---------------------------------------------------------------- a sala muda de celular


## Humano conectado pela rede, o mais antigo, que pode herdar a sala ("" se ninguém).
func _heir_of(room: Object) -> String:
	var best: Object = null
	for member: Object in (room.get("members") as Dictionary).values():
		if member.get("is_bot") or member.get("id") == my_id or not member.get("connected") \
				or int(member.get("offline_since")) >= 0:
			continue
		if _server.member_ip(room_id, member.get("id")) == "":
			continue
		if best == null or int(member.get("order")) < int(best.get("order")):
			best = member
	return str(best.get("id")) if best != null else ""


## O anfitrião já saiu e a mão acabou: manda o retrato ao herdeiro e o novo endereço a
## todos. Sem herdeiro, a sala fecha com placar.
func _hand_over(room: Object) -> void:
	_exited = true
	var heir: String = str(room.get("owner_id"))
	if _server.member_ip(room_id, heir) == "":
		heir = _heir_of(room)
	if heir == "" or not room.call("make_owner", heir):
		room.call("close", Protocol.R_OWNER)
		return
	var saved: Dictionary = room.call("snapshot")
	var ip: String = _server.member_ip(room_id, heir)
	heir_nick = str((room.get("members") as Dictionary)[heir].get("nick"))
	for member: Object in (room.get("members") as Dictionary).values():
		if member.get("is_bot"):
			continue
		var message: Dictionary = {"t": Protocol.MOVE, "ip": ip, "port": WsServer.PORT,
			"room": room_id, "nick": heir_nick}
		if member.get("id") == heir:
			message["snapshot"] = saved
		_server.send_to_member(room_id, str(member.get("id")), message)
	if _announcer != null:
		_announcer.close()
		_announcer = null


## Convidado: a sala mudou de celular. O herdeiro assume; os outros reconectam nele.
func _on_move(message: Dictionary) -> void:
	_moving_to = str(message.get("nick", ""))
	var ip: String = str(message.get("ip", ""))
	var new_port: int = int(message.get("port", WsServer.PORT))
	if typeof(message.get("snapshot")) == TYPE_DICTIONARY:
		_take_over(message["snapshot"], ip)
		return
	host_ip = ip
	port = new_port
	_ws.close()
	_ws = WsClient.new(_clock)
	_client = _ws
	var now: int = _clock.now_ms()
	_lost_at = now
	_retry_at = now + RETRY_MS
	link = Link.RECONNECTING
	_ws.open(ip, new_port)


func _take_over(saved: Dictionary, ip: String) -> void:
	if _ws != null:
		_ws.close()
		_ws = null
	var announce_to: Array[String] = []
	announce_to.assign(takeover.get("announce_to", []))
	if not _open_server(ip, int(takeover.get("listen_port", WsServer.PORT)), announce_to,
			int(takeover.get("announce_port", Discovery.PORT)),
			takeover.get("room_config", {}), takeover.get("seed_source", Callable())):
		return
	if _server.restore_room(saved) != "":
		_fail("Não deu para continuar a sala neste celular.")
		return
	_host_since = _clock.now_ms()
	_moving_to = ""
	_hello()
	_joining = true
	send({"t": Protocol.JOIN_ROOM, "room": room_id, "spectate": false})


# ---------------------------------------------------------------- anfitrião some (SPEC 6.4)


## As mensagens do servidor e as geradas aqui (o placar calculado sem o anfitrião).
func update() -> Array[Dictionary]:
	var messages: Array[Dictionary] = super()
	while not _local.is_empty():
		var message: Dictionary = _local.pop_front()
		_track(message)
		messages.append(message)
	return messages


## Anfitrião: um quadro que demorou demais quer dizer que o app ficou parado. Esse tempo
## não conta para a sala; passando de 10 s, ele desiste da mão; passando de 2 minutos, os
## convidados já desistiram dele e a sala acaba. Devolve verdadeiro se a sala acabou.
func _check_stall() -> bool:
	var real: int = _clock.now_ms()
	var wall: int = _wall_ms()
	var stalled: int = 0
	var gap: int = 0
	if _last_real >= 0:
		stalled = real - _last_real
		gap = stalled
		# O relógio do sistema conta também o celular dormindo, que o outro pode não contar.
		# Só vale quando o app de fato parou (o Android avisou, ou o quadro travou): um
		# acerto da hora do celular no meio do jogo não pode parecer ausência.
		if _was_paused or stalled > 1000:
			gap = maxi(stalled, wall - _last_wall)
		gap += _stall_extra
	_stall_extra = 0
	_was_paused = false
	if gap > STALL_MS:
		_room_clock.skip(stalled)
	_last_real = _clock.now_ms()
	_last_wall = wall
	if gap <= STALL_MS:
		return false
	return _after_absence(gap)


## O anfitrião voltou depois de gap ms fora. Devolve verdadeiro se a sala acabou.
func _after_absence(gap: int) -> bool:
	if gap > wait_host_ms:
		_abandon()
		return true
	if gap > GRACE_MS and my_id != "":
		_forfeit(_server.rooms.get(room_id), my_id)
	return false


## Fora por mais de 10 s: o anfitrião desiste da mão em andamento, se ainda estava nela.
func _forfeit(room: Object, member_id: String) -> void:
	if room != null and room.call("forfeit_hand", member_id):
		_note("Você ficou fora por mais de 10 segundos e desistiu desta mão.")


## Anfitrião fora por mais de 2 minutos: a sala acaba aqui também, com o mesmo placar que
## os convidados calcularam.
func _abandon() -> void:
	var closed: Dictionary = HostLost.final_from(last_state, my_id)
	_stop_hosting()
	if closed.is_empty():
		_fail("A sala acabou: o app ficou fechado por mais de 2 minutos.")
	else:
		_local.append(closed)


## Convidado: o anfitrião não voltou em 2 minutos. Com a partida em andamento, encerra
## com o placar calculado do último state; na sala de espera, só avisa.
func _host_gone() -> void:
	var room: Dictionary = last_state.get("room", {})
	var host: String = str(room.get("host", ""))
	if host == "":
		host = str(room.get("owner", ""))
	var closed: Dictionary = HostLost.final_from(last_state, host)
	_fail("O anfitrião não voltou.")
	if not closed.is_empty():
		_local.append(closed)


func _stop_hosting() -> void:
	_delete_save()
	if _announcer != null:
		_announcer.close()
		_announcer = null
	if _ws_server != null:
		_ws_server.stop()
		_ws_server = null
	_server = null


## Grava a sala no celular do anfitrião: a cada jogada e a cada SAVE_EVERY_MS.
func _autosave(force: bool) -> void:
	if save_path == "" or not is_host or _server == null or _exiting or room_id == "" \
			or my_id == "":
		return
	var now: int = _clock.now_ms()
	if not force and not _dirty and _saved_at >= 0 and now - _saved_at < SAVE_EVERY_MS:
		return
	var room: Object = _server.rooms.get(room_id)
	if room == null or room.call("is_closed"):
		return
	var data: Dictionary = {"v": 1, "at": _unix_ms(), "room": room.call("snapshot", true),
		"state": last_state, "profile": _profile, "port": port, "host_id": my_id}
	var file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	if file != null:
		file.store_string(Codec.encode(data))
		file.close()
	_saved_at = now
	_dirty = false


func _delete_save() -> void:
	if save_path != "" and FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)


## O Android vai pôr o app em segundo plano: grava a sala agora.
func app_paused() -> void:
	_was_paused = true
	_autosave(true)


## A sala gravada pelo anfitrião, se houver uma com menos de 30 minutos, com "age_ms" (há
## quanto tempo foi gravada). {} se não houver.
static func read_save(path: String = SAVE_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = Codec.decode(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or int(data.get("v", 0)) != 1 \
			or typeof(data.get("room")) != TYPE_DICTIONARY \
			or typeof(data.get("profile")) != TYPE_DICTIONARY:
		DirAccess.remove_absolute(path)
		return {}
	var age: int = _unix_ms() - int(data.get("at", 0))
	if age < 0 or age > SAVE_MAX_AGE_MS:
		DirAccess.remove_absolute(path)
		return {}
	data["age_ms"] = age
	return data


## O placar de uma sala gravada que não dá mais para retomar (o anfitrião ficou fora mais
## de 2 minutos); {} na sala de espera.
static func abandoned_final(saved: Dictionary) -> Dictionary:
	var state: Variant = saved.get("state", {})
	if typeof(state) != TYPE_DICTIONARY:
		return {}
	return HostLost.final_from(state, str(saved.get("host_id", "")))


## Anfitrião: volta à sala gravada depois de o Android fechar o app, gap_ms depois.
## Os convidados reconectam sozinhos. Devolve falso (com error_text) se não deu.
func resume(saved: Dictionary, gap_ms: int, room_config: Dictionary = {},
		seed_source: Callable = Callable(), announce_to: Array[String] = [],
		announce_port: int = Discovery.PORT) -> bool:
	var profile: Dictionary = saved["profile"]
	_profile = {"nick": str(profile.get("nick", "")), "avatar": int(profile.get("avatar", 0)),
		"device": str(profile.get("device", ""))}
	var room_saved: Dictionary = saved["room"]
	var host: String = str(saved.get("host_id", ""))
	var ip: String = RoomCode.local_ip()
	if ip == "" and announce_to.is_empty():
		_fail("Conecte o celular a uma rede Wi-Fi para voltar à sala.")
		return false
	if not _open_server(ip, int(saved.get("port", WsServer.PORT)), announce_to, announce_port,
			room_config, seed_source):
		return false
	if _server.restore_room(room_saved) != "":
		_stop_hosting()
		_fail("Não deu para voltar à sala.")
		return false
	room_id = str(room_saved.get("id", ""))
	var room: Object = _server.rooms[room_id]
	room.set("host_id", host)
	if gap_ms > GRACE_MS:
		_forfeit(room, host)
	var state: Variant = saved.get("state", {})
	if typeof(state) == TYPE_DICTIONARY:
		last_state = state
	_hello()
	_joining = true
	send({"t": Protocol.JOIN_ROOM, "room": room_id, "spectate": false})
	return true


## Testes: o próximo quadro do anfitrião chega como se o app tivesse ficado parado ms.
func simulate_stall(ms: int) -> void:
	_stall_extra = ms


func _note(text: String) -> void:
	_notice = text
	_notice_until = _clock.now_ms() + HOST_NOTICE_MS


func _wall_ms() -> int:
	return _clock.now_ms() if _clock.manual else _unix_ms()


static func _unix_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


# ---------------------------------------------------------------- apoio


func _hello() -> void:
	send({"t": Protocol.HELLO, "v": Protocol.VERSION, "nick": _profile["nick"],
		"avatar": _profile["avatar"], "device": _profile["device"]})


func _fail(text: String) -> void:
	error_text = text
	link = Link.FAILED
	if _ws != null:
		_ws.close()


## O anúncio da sala na rede (SPEC 9.2): nome, formato, lugares, ocupação e se aceita
## gente nova.
func _announcement(room: Object) -> Dictionary:
	var summary: Dictionary = room.call("summary")
	var seats: int = int(summary["seats"])
	var players: int = int(summary["players"])
	var open: bool = summary["open"]
	return {
		"name": summary["name"], "format": summary["format"], "seats": seats,
		"players": players, "phase": summary["phase"], "open": open, "port": port,
	}


## Troca de avatar (sala de espera). Vale também nas próximas reconexões.
func set_avatar(avatar: int) -> void:
	_profile["avatar"] = avatar
	super(avatar)


## Sai da mesa. Anfitrião com outro humano na sala: a sala passa para ele (na hora, ou
## quando a mão acabar) e devolve {}. Anfitrião sozinho: encerra e devolve o placar.
## Convidado: avisa o servidor (as fichas ficam guardadas por 5 minutos) e devolve {}.
func leave() -> Dictionary:
	if not final.is_empty():
		return final
	if is_host:
		var room: Object = _server.rooms.get(room_id) if _server != null else null
		if room != null and not room.call("is_closed") and _heir_of(room) != "":
			_exiting = true
			_delete_save()
			room.set("hold_hands", true)
			send({"t": Protocol.LEAVE})
			update()
			return {}
		owner(Protocol.CMD_CLOSE)
		for _i in 3:
			update()
		return final
	send({"t": Protocol.LEAVE})
	_flush(300)
	return final


func pending_exit() -> bool:
	return _exiting and not _exited


## Fecha a rede: o servidor (depois de entregar o que falta), os anúncios e a conexão.
func shutdown() -> void:
	_delete_save()
	if _announcer != null:
		_announcer.close()
		_announcer = null
	if _ws_server != null:
		_flush(250)
		_ws_server.stop()
		_ws_server = null
	if _ws != null:
		_ws.close()
		_ws = null
	_server = null
	_client = null


func status_text() -> String:
	if pending_exit():
		return "Você saiu. A sala passa para outro jogador quando esta mão acabar."
	if link == Link.RECONNECTING:
		if _moving_to != "":
			return "O anfitrião saiu. A sala está passando para o celular de %s…" % _moving_to
		return "Aguardando o anfitrião… tentando reconectar."
	if _host_since >= 0 and _clock.now_ms() - _host_since < HOST_NOTICE_MS:
		return "O anfitrião saiu. Agora a sala roda neste celular: mantenha o app aberto."
	if _notice_until >= 0 and _clock.now_ms() < _notice_until:
		return _notice
	return ""


## Verdadeiro enquanto espera o anfitrião voltar: os relógios da mesa ficam parados.
func waiting_host() -> bool:
	return link == Link.RECONNECTING


func failure() -> String:
	if link == Link.FAILED:
		return error_text
	if _exited:
		return "Você saiu. A sala ficou com %s." % heir_nick if heir_nick != "" \
			else "A sala foi encerrada."
	if left_reason == Protocol.R_KICKED:
		return "O dono da sala tirou você da sala."
	if left_reason == Protocol.R_AWAY:
		return AWAY_TEXT
	return ""


func leave_question() -> Array[String]:
	if is_host:
		var room: Object = _server.rooms.get(room_id) if _server != null else null
		if room != null and _heir_of(room) != "":
			return ["Sair da sala?", "A partida continua no celular de outro jogador. " \
				+ "Suas fichas ficam guardadas por 5 minutos.", "Sair"]
		return ["Encerrar a sala?", "A partida termina para todos e cada um vê o placar.",
			"Encerrar"]
	return ["Sair da mesa?", "Suas fichas ficam guardadas por 5 minutos, se quiser voltar.",
		"Sair"]


## Dá tempo para o que está na fila sair pela rede antes de fechar.
func _flush(ms: int) -> void:
	var until: int = Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < until:
		if is_host and _ws_server != null:
			_ws_server.poll()
		elif _ws != null:
			for message: Dictionary in _ws.poll():
				_track(message)
				if message.get("t") == Protocol.LEFT:
					return
		OS.delay_msec(10)


func has_rebuy_ads() -> bool:
	return true


func has_reactions() -> bool:
	return true
