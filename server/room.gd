extends RefCounted
## Uma sala: o servidor de mesa autoritativo (SPEC 4, 5 e 8). É o mesmo código no
## offline, no Wi-Fi e no Render.
##
## Embrulha a mesa pura (engine/table.gd) com as pessoas, o dono, os relógios, a
## ausência, a recompra, os bots e a visão de cada um. Não conhece conexões: fala com
## cada participante pelo `send` recebido de fora, e o tempo vem do relógio injetado.
##
## Quem chama: join/leave/handle para o que chega dos participantes e tick() de tempos
## em tempos, para os prazos e os bots.

const Table := preload("res://engine/table.gd")
const Hand := preload("res://engine/hand.gd")
const Tournament := preload("res://engine/tournament.gd")
const View := preload("res://server/view.gd")
const HandLog := preload("res://server/hand_log.gd")
const Protocol := preload("res://server/protocol.gd")
const Clock := preload("res://server/clock.gd")
const Wire := preload("res://server/wire.gd")
const Bot := preload("res://bots/bot.gd")
const Roster := preload("res://bots/roster.gd")

const MIN_SEATS: int = 2
const DEFAULT_SEATS: int = 4
const TURN_SECONDS: Array[int] = [0, 15, 30, 60]   ## 0 = sem limite
const DEFAULT_TURN_SECONDS: int = 30
const MAX_STACK: int = 100_000_000
## Mesas que o dono da sala pode escolher (as mesmas de ui/theme/tables.gd); todos veem a
## dele. Nome desconhecido (app mais novo) vira a Salão.
const FELTS: Array[String] = ["salao", "rubi", "safira", "perola"]
const DEFAULT_FELT: String = "salao"
const MAX_NICK: int = 16
const DEFAULT_NICK: String = "Jogador"
const AVATARS: int = 29
const AWAY_AFTER_TIMEOUTS: int = 2
const MAX_STEPS_PER_TICK: int = 64
## Senha da sala, só à distância (SPEC 4.1 e 9.3): 4 dígitos, ou vazia.
const PASSWORD_DIGITS: int = 4
## O placar mostra no máximo esse tanto de gente (SPEC 11.2).
const SCORE_ROWS: int = 10
## Senha que ninguém acerta (não são 4 dígitos): sala recriada sem saber a senha.
const LOCKED: String = "trancada"

## Prazos e ajustes que não são opção da sala. As simulações zeram as esperas.
const DEFAULT_CONFIG: Dictionary = {
	"hand_gap_ms": 4000,        # espera entre mãos, para a tela mostrar o resultado
	"showdown_gap_ms": 7000,    # a mesma espera, depois de um showdown
	"bot_min_ms": 1000,         # o bot demora de 1 a 3 s para agir (SPEC 7)
	"bot_max_ms": 3000,
	"rebuy_ms": 0,              # prazo da oferta de recompra; 0 = sem prazo (SPEC 3.4)
	"held_ms": 300000,          # fichas guardadas de quem saiu: 5 min (SPEC 6.2)
	"offline_ms": 60000,        # lugar guardado de quem caiu (SPEC 6.2 e 6.3)
	"return_ms": 120000,        # torneio: quem saiu ou caiu tem 2 min para voltar (SPEC 6.3)
	"away_ms": 0,               # Online: ausente tem esse prazo para tocar em "Voltei"; 0 = sem prazo
	"allow_empty": false,       # sala sem humanos continua aberta (simulações)
	"bot_evaluations": 0,       # teto de simulação do Difícil (0 = o padrão)
	"bot_style": "",            # força um estilo para todos os bots (simulações)
	"watcher_cap": 0,           # teto de espectadores que contam (SPEC 4.3); 0 = sem teto
	"empty_close_ms": 0,        # partida sem humanos espera isso antes de fechar (SPEC 6.5)
	"ad_max_ms": 30000,         # "Em anúncio" some sozinho depois disso, se o app não avisar o fim
}


class Member:
	extends RefCounted

	var id: String = ""
	var nick: String = ""
	var base_nick: String = ""     ## o apelido como chegou, sem o número de repetido
	var avatar: int = 0
	var device: String = ""        ## código secreto do aparelho; nunca sai do servidor
	var is_bot: bool = false
	var level: int = 0
	var style: String = ""
	var bot: Bot = null
	var view: Dictionary = {}      ## bot: a última mensagem "state" que recebeu
	var seat: int = -1             ## -1 = espectador
	var order: int = 0             ## ordem de chegada
	var connected: bool = true     ## falso depois que saiu de vez (ou o prazo da queda venceu)
	var offline_since: int = -1    ## relógio real da queda ou da saída; -1 = conectado
	var return_offer: bool = false ## voltou com fichas guardadas e ainda não escolheu
	var away: bool = false
	var timeouts: int = 0          ## estouros de tempo seguidos
	var leaving: bool = false      ## saiu no meio de uma mão: deixa o lugar quando ela acabar
	var gone: bool = false         ## torneio: saiu, mas o lugar fica e paga os blinds
	var forfeit: bool = false      ## as fichas saem da mesa de vez (expulso, bot retirado)
	var rebuy_offer: bool = false  ## oferta de recompra pendente
	var rebuy_deadline: int = -1   ## prazo da oferta (tempo da sala); -1 sem prazo
	var folds_hand: int = 0        ## desiste da mão com este número (Wi-Fi: o anfitrião sumiu)
	var reacted_at: int = -1       ## relógio real da última reação (limite de frequência)
	var watcher: bool = false      ## assiste por escolha ou voltou sem lugar: conta no teto (SPEC 4.3)
	var quit: bool = false         ## tocou em "Sair" (não caiu): os outros veem "Saiu", não "Reconectando…"
	var away_since: int = -1       ## relógio real desde quando está ausente; -1 = presente
	var ad_since: int = -1         ## relógio real desde quando vê um anúncio na sala de espera; -1 = não vê


var id: String = ""
var name: String = ""
var options: Dictionary = {}
var table: Table = Table.new()
var phase: String = Protocol.LOBBY
var paused: bool = false
var owner_id: String = ""
var members: Dictionary = {}       ## id -> Member, na ordem de chegada
var final: Dictionary = {}         ## a mensagem "closed", depois que a sala encerra
var bot_errors: int = 0            ## jogadas de bot recusadas; tem de ficar em zero
var hold_hands: bool = false       ## não começa mão nova (Wi-Fi: a sala vai mudar de celular)
var host_id: String = ""            ## Wi-Fi: o participante em cujo celular a sala roda
var tap: Callable = Callable()     ## testes: vê tudo o que a sala entrega (id, mensagem)

var _clock: Clock = null
var _send: Callable = Callable()
## func(participante, mensagem, pacote): o servidor de salas liga isto para o `state`
## ir pelo protocolo enxuto (server/wire.gd). Sem ele, vai por _send.
var send_state: Callable = Callable()
var _seed_source: Callable = Callable()
var _config: Dictionary = {}
var _crypto: Crypto = Crypto.new()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _next_member: int = 1
var _seq: int = 0                  ## número da vez; o app devolve na jogada
var _turn_deadline: int = -1
var _bot_due: int = 0
var _next_hand_at: int = 0
var _play_started: int = 0
var _pause_started: int = 0
var _paused_total: int = 0
var _hand_ids: Dictionary = {}     ## lugar -> id de quem recebeu cartas na mão atual
var _names: Dictionary = {}        ## id -> apelido de todos os que já sentaram
var _banned: Dictionary = {}       ## aparelhos expulsos
var _held_until: Dictionary = {}   ## id -> fim do prazo das fichas guardadas (relógio real)
var _held_by: Dictionary = {}      ## id -> {device, nick} de quem tem fichas guardadas
var _pending_settings: Dictionary = {}
var history: HandLog = HandLog.new()   ## as últimas mãos terminadas (SPEC 11.2)
var _empty_since: int = -1         ## relógio real desde quando a partida está sem humanos
var _last_offline: int = -1        ## relógio real da queda ou saída do último humano que saiu
var _notes: Array = []             ## avisos da sala que vão na próxima mensagem "state"
var _departed: Dictionary = {}     ## id -> {at, avatar} de quem saiu da mesa (placar, SPEC 11.2)
## Senha (SPEC 9.3): fica só aqui; não vai nas opções, no state, na lista nem no retrato.
var _password: String = ""
## Resumo para recuperar a sala depois de um reinício (SPEC 9.4), só à distância: entre
## as mãos, quando algo mudou, a sala guarda o retrato (last_summary) e soma 1 em
## summary_rev; o servidor assina e manda a cada celular.
var summaries: bool = false
var summary_rev: int = 0
var last_summary: Dictionary = {}
var _summary_print: String = ""
## Sala recriada sem ninguém devolver a senha: a marca da senha do resumo antigo, para
## os resumos seguintes continuarem trancados.
var kept_lock: String = ""


## Confere as opções de criação (SPEC 4.1). Devolve {ok, error, options}, com os
## padrões preenchidos.
static func normalize_options(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return _bad_options("opções inválidas")
	var seats: Variant = raw.get("seats", DEFAULT_SEATS)
	if typeof(seats) != TYPE_INT or seats < MIN_SEATS or seats > Table.MAX_SEATS:
		return _bad_options("número de lugares inválido")
	var turn: Variant = raw.get("turn_seconds", DEFAULT_TURN_SECONDS)
	if typeof(turn) != TYPE_INT or not TURN_SECONDS.has(turn):
		return _bad_options("tempo por jogada inválido")
	var keep_open: Variant = raw.get("keep_open", false)
	if typeof(keep_open) != TYPE_BOOL:
		return _bad_options("opção de sala aberta inválida")
	var password: Variant = raw.get("password", "")
	if typeof(password) != TYPE_STRING or not (password == "" or is_password(password)):
		return _bad_options("a senha precisa ter 4 números")
	var table_options: Dictionary = {"format": raw.get("format", Table.CLASSIC)}
	for key: String in ["starting_stack", "small_blind", "big_blind", "rebuy_limit", "level_minutes"]:
		if raw.has(key):
			table_options[key] = raw[key]
	var probe: Table = Table.new()
	var problem: String = probe.configure(table_options)
	if problem != "":
		return _bad_options(problem)
	if probe.starting_stack > MAX_STACK or probe.big_blind > probe.starting_stack:
		return _bad_options("fichas iniciais ou blinds fora do limite")
	var bots: Array = []
	var raw_bots: Variant = raw.get("bots", [])
	if typeof(raw_bots) != TYPE_ARRAY or raw_bots.size() > seats:
		return _bad_options("lista de bots inválida")
	for level: Variant in raw_bots:
		if not Roster.is_level(level):
			return _bad_options("nível de bot inválido")
		bots.append(level)
	var felt: Variant = raw.get("felt", DEFAULT_FELT)
	if typeof(felt) != TYPE_STRING or not FELTS.has(felt):
		felt = DEFAULT_FELT
	return {"ok": true, "error": "", "options": {
		"format": probe.format,
		"seats": seats,
		"starting_stack": probe.starting_stack,
		"small_blind": probe.small_blind,
		"big_blind": probe.big_blind,
		"rebuy_limit": probe.rebuy_limit,
		"level_minutes": probe.level_minutes,
		"turn_seconds": turn,
		"keep_open": keep_open and probe.format == Table.CLASSIC,
		"bots": bots,
		"password": password,
		"felt": felt,
	}}


## Senha válida: exatamente 4 dígitos de 0 a 9.
static func is_password(text: String) -> bool:
	if text.length() != PASSWORD_DIGITS:
		return false
	for i in text.length():
		if text.unicode_at(i) < 48 or text.unicode_at(i) > 57:
			return false
	return true


## Apelido como vai aparecer: sem espaços nas pontas, sem caracteres de controle e com
## tamanho limitado. O filtro de palavrões vem na etapa 6 (SPEC 4.4).
static func clean_nick(raw: String) -> String:
	var text: String = ""
	for i in raw.length():
		var code: int = raw.unicode_at(i)
		text += " " if code < 32 or code == 127 else raw[i]
	text = text.strip_edges().left(MAX_NICK).strip_edges()
	return text if text != "" else DEFAULT_NICK


## room_options: as opções já conferidas por normalize_options.
## send: Callable(id do participante, mensagem). seed_source: Callable() -> int, só nos
## testes; no jogo a semente de cada mão vem do gerador forte do sistema.
func _init(room_id: String, room_options: Dictionary, clock: Clock, send: Callable,
		config: Dictionary = {}, seed_source: Callable = Callable()) -> void:
	id = room_id
	options = room_options.duplicate(true)
	_password = str(options.get("password", ""))
	options.erase("password")
	_clock = clock
	_send = send
	_seed_source = seed_source
	_config = DEFAULT_CONFIG.duplicate()
	_config.merge(config, true)
	table.configure({
		"format": options["format"], "starting_stack": options["starting_stack"],
		"small_blind": options["small_blind"], "big_blind": options["big_blind"],
		"rebuy_limit": options["rebuy_limit"], "level_minutes": options["level_minutes"],
	})
	_rng.seed = _seed()
	for level: int in options["bots"]:
		add_bot(level)


## Entra na sala. profile: {nick, avatar, device}. Senta se houver lugar e a sala
## aceitar; senão recusa a entrada (spectate só vale na sala de espera). Devolve
## {ok, error, id, resumed}. Não avisa ninguém:
## quem chamou manda o "joined" e depois chama announce().
##
## Quem volta (SPEC 6.1 e 6.2) é reconhecido pelo apelido e pelo código do aparelho:
## ainda na sala (caiu há pouco, ou torneio), retoma o mesmo participante (resumed);
## com fichas guardadas, entra assistindo com a oferta de volta (you.return_offer), que
## só pode ser aceita quando houver lugar livre.
func join(profile: Dictionary, spectate: bool = false) -> Dictionary:
	if phase == Protocol.ENDED:
		return {"ok": false, "error": "a sala já foi encerrada", "id": "", "resumed": false}
	var device: String = str(profile.get("device", ""))
	if device != "" and _banned.has(device):
		return {"ok": false, "error": "você foi expulso desta sala", "id": "", "resumed": false}
	var base: String = clean_nick(str(profile.get("nick", "")))
	var back: Member = _same_person(device, base)
	if back != null:
		back.connected = true
		back.offline_since = -1
		back.gone = false
		back.leaving = false
		back.forfeit = false
		back.quit = false
		if back.seat >= 0:
			_notes.append({"type": "online", "seat": back.seat})
		_check_owner()
		return {"ok": true, "error": "", "id": back.id, "resumed": true}
	# Só assiste quem já estava na sala: quem chega precisa de lugar (pedido do dono,
	# 16/11/2026). Exceções: quem caiu e tem fichas guardadas (entra assistindo e volta à
	# mesa quando abrir lugar) e quem pede para assistir na sala de espera.
	var held_id: String = _held_id(device, base)
	# Teto à distância (SPEC 4.3): conta quem entra para assistir e quem volta sem lugar
	# livre; não conta quem perdeu as fichas e continua assistindo.
	var watching: bool = (spectate and phase == Protocol.LOBBY) or (held_id != "" and _free_seat() < 0)
	if watching and int(_config["watcher_cap"]) > 0 and watchers() >= int(_config["watcher_cap"]):
		return {"ok": false, "error": "já há %d pessoas assistindo" % int(_config["watcher_cap"]),
			"id": "", "resumed": false}
	var member: Member = _new_member(base, int(profile.get("avatar", 0)), false, held_id)
	member.device = device
	member.base_nick = base
	member.watcher = watching
	if held_id != "":
		member.return_offer = true
	elif not (spectate and phase == Protocol.LOBBY):
		var refusal: String = _try_sit(member, -1)
		if refusal != "":
			members.erase(member.id)
			return {"ok": false, "error": _entry_error(refusal), "id": "", "resumed": false}
	if owner_id == "":
		_set_owner(member)
		_empty_since = -1
	return {"ok": true, "error": "", "id": member.id, "resumed": false}


## A sala tem senha e quem chega precisa dela: quem já está na sala (volta de uma
## queda) ou tem fichas guardadas aqui entra sem digitar de novo (SPEC 9.3).
func needs_password(device: String, nick: String) -> bool:
	if _password == "":
		return false
	var base: String = clean_nick(nick)
	return _same_person(device, base) == null and _held_id(device, base) == ""


## Essa pessoa pode voltar para esta sala: ainda é participante (caiu ou saiu e o lugar
## está guardado) ou tem fichas guardadas aqui. A lista de salas mostra a sala para ela
## mesmo quando não aceita gente nova (torneio em andamento).
func can_return(device: String, nick: String) -> bool:
	if phase == Protocol.ENDED or device == "":
		return false
	var base: String = clean_nick(nick)
	return _same_person(device, base) != null or _held_id(device, base) != ""


func password_matches(text: String) -> bool:
	return _password != "" and is_password(text) and text == _password


## Sala recriada de um resumo (SPEC 9.4): o resumo traz só uma marca da senha. Quem
## voltou e sabe a senha a devolve (já conferida com a marca); sem ela, a sala fica
## trancada para quem não estava nela.
func set_password(text: String) -> void:
	_password = text if is_password(text) else LOCKED


## A senha da sala, só para o servidor marcar o resumo (nunca vai a ninguém).
func password_for_summary() -> String:
	return _password if is_password(_password) else ""


func has_password() -> bool:
	return _password != ""


## Quantos espectadores contam no teto (SPEC 4.3).
func watchers() -> int:
	var count: int = 0
	for member: Member in members.values():
		# Quem voltou com fichas guardadas e ainda não escolheu também conta: o lugar
		# livre pode ser tomado antes.
		if ((member.watcher or member.return_offer) and member.seat < 0 and member.connected
				and not member.is_bot):
			count += 1
	return count


## A conexão caiu (SPEC 6.2 e 6.3). Quem está sentado tem o lugar guardado por
## offline_ms, com o relógio da vez correndo normalmente; quem só assistia sai.
func drop_connection(member_id: String) -> void:
	var member: Member = members.get(member_id)
	if member == null or member.is_bot or phase == Protocol.ENDED or not member.connected:
		return
	if member.seat < 0 and phase == Protocol.LOBBY:
		leave(member_id)
		return
	# Em partida, quem assiste também tem offline_ms para voltar: quem chega de fora não
	# entra mais só para assistir, então sair seria perder a vaga de espectador.
	if member.offline_since < 0:
		member.offline_since = _clock.now_ms()
		if member.seat >= 0:
			_notes.append({"type": "offline", "seat": member.seat})
		_broadcast([])


## Manda a todos a situação atual da sala.
func announce() -> void:
	_broadcast([])


## O participante saiu (botão "Sair"). Se era o último humano da sala (ninguém mais
## sentado, assistindo ou reconectando), a sala fecha na hora com o placar, em vez de
## esperar alguém voltar (pedido do dono, 17/11/2026).
func leave(member_id: String) -> void:
	var member: Member = members.get(member_id)
	if member == null or phase == Protocol.ENDED:
		return
	member.quit = true
	_drop_member(member, false)
	if phase == Protocol.PLAYING and not _config["allow_empty"] and not _other_humans(member_id):
		close(Protocol.R_EMPTY)
	if phase != Protocol.ENDED:
		_broadcast([])
		_run()


## Mensagem de um participante que já está na sala.
func handle(member_id: String, message: Dictionary) -> void:
	var member: Member = members.get(member_id)
	if member == null or member.is_bot or phase == Protocol.ENDED:
		return
	var problem: String = ""
	match message.get("t"):
		Protocol.HISTORY:
			# Qualquer um da sala, inclusive quem assiste, vê o histórico.
			_send_to(member, {"t": Protocol.HANDS, "hands": history.for_member(member.id)})
			return
		Protocol.START:
			problem = start() if member.id == owner_id else "só o dono começa a partida"
		Protocol.ACT:
			problem = _human_act(member, message)
		Protocol.REBUY:
			problem = _answer_rebuy(member, message)
		Protocol.SIT:
			problem = _sit(member, message)
		Protocol.AWAY:
			problem = _set_away(member, message)
		Protocol.AD:
			problem = _set_ad(member, message)
		Protocol.RETURN_CHOICE:
			problem = _return_choice(member, message)
		Protocol.PROFILE:
			problem = _change_profile(member, message)
		Protocol.REACT:
			_react(member, message)
			return
		Protocol.OWNER:
			problem = _owner_command(member, message)
		_:
			_send_to(member, Protocol.error(Protocol.E_BAD_MESSAGE, "mensagem desconhecida"))
			return
	if problem != "":
		_send_to(member, Protocol.error(Protocol.E_REFUSED, problem))
	_run()


## Faz o tempo da sala andar: estouros de tempo, prazos, bots e a mão seguinte.
func tick() -> void:
	if phase == Protocol.ENDED:
		return
	if _empty_since >= 0 and (not _other_humans("")
			or _clock.now_ms() - _empty_since >= int(_config["empty_close_ms"])):
		close(Protocol.R_EMPTY)
		return
	_expire_offline()
	if phase == Protocol.ENDED:
		return
	_expire_away()
	if phase == Protocol.ENDED:
		return
	_expire_ads()
	_expire_held()
	_run()


## Começa a partida, com 2 ou mais jogadores sentados (bots contam).
func start() -> String:
	if phase != Protocol.LOBBY:
		return "a partida já começou"
	if table.participants().size() < 2:
		return "faltam jogadores para começar"
	for member: Member in members.values():
		if _in_ad(member):
			return "espere: %s está vendo um anúncio" % member.nick
	phase = Protocol.PLAYING
	_play_started = _now()
	_next_hand_at = _play_started
	_notes.append({"type": "start"})
	_broadcast([])
	return ""


## Coloca um bot no primeiro lugar livre. Devolve "" ou o motivo da recusa.
func add_bot(level: int) -> String:
	if not Roster.is_level(level):
		return "nível de bot inválido"
	if phase == Protocol.ENDED:
		return "a sala já foi encerrada"
	if phase == Protocol.PLAYING and table.format == Table.TOURNAMENT:
		return "o torneio já começou"
	var seat: int = _free_seat()
	if seat < 0:
		return "não há lugar livre"
	var taken: Array = []
	for other: Member in members.values():
		taken.append(other.nick)
	var pick: Dictionary = Roster.pick(_rng, taken)
	var member: Member = _new_member(pick["name"], _rng.randi_range(0, AVATARS - 1), true)
	member.level = level
	member.style = pick["style"] if str(_config["bot_style"]) == "" else str(_config["bot_style"])
	member.bot = Bot.new(level, member.style, _rng.randi(), int(_config["bot_evaluations"]))
	var problem: String = table.add_player(seat, member.id)
	if problem != "":
		members.erase(member.id)
		return problem
	member.seat = seat
	_names[member.id] = member.nick
	return ""


## Encerra a sala e manda o placar final a todos (SPEC 4.2). Uma mão em andamento é
## cancelada e as apostas voltam para quem as fez.
func close(reason: String) -> void:
	if phase == Protocol.ENDED:
		return
	if table.hand_in_progress():
		_notes.append_array(table.cancel_hand()["events"])
	phase = Protocol.ENDED
	paused = false
	_turn_deadline = -1
	final = {
		"t": Protocol.CLOSED, "reason": reason,
		"scoreboard": _scoreboard(), "podium": _podium(),
	}
	_broadcast([])
	for member: Member in members.values():
		_send_to(member, final)


func is_closed() -> bool:
	return phase == Protocol.ENDED


## Passa a sala para esse participante (humano e presente). Devolve verdadeiro se deu.
func make_owner(member_id: String) -> bool:
	var member: Member = members.get(member_id)
	if member == null or member.is_bot or not _present(member):
		return false
	_set_owner(member)
	return true


## Retrato da sala para outro celular continuar com ela (Wi-Fi: o anfitrião saiu). Só
## entre mãos ({} durante uma mão). Os prazos vão como tempo que falta, porque cada aparelho tem o seu
## relógio. Leva o código secreto dos aparelhos: só pode ir para quem vira o servidor.
## O histórico das mãos não vai (como na recuperação da etapa 5).
##
## with_hand: leva também a mão em andamento, com as cartas fechadas e o baralho. Só para
## o anfitrião gravar no próprio celular (SPEC 6.4: o Android pode fechar o app); nunca
## pode sair do aparelho.
func snapshot(with_hand: bool = false) -> Dictionary:
	if table.hand_in_progress() and not with_hand:
		return {}
	var now: int = _clock.now_ms()
	var saved_table: Dictionary = table.to_dict()
	var hand_ids: Dictionary = {}
	if with_hand:
		for seat: int in _hand_ids:
			hand_ids[str(seat)] = _hand_ids[seat]
	else:
		# A última mão fica de fora: tem cartas que ninguém mostrou e o resto do baralho.
		saved_table["hand"] = null
	var list: Array = []
	for member: Member in members.values():
		list.append({
			"id": member.id, "nick": member.nick, "base_nick": member.base_nick,
			"avatar": member.avatar, "device": member.device, "bot": member.is_bot,
			"level": member.level, "style": member.style, "seat": member.seat,
			"order": member.order, "away": member.away, "timeouts": member.timeouts,
			"gone": member.gone, "connected": member.connected, "quit": member.quit,
			"offline_ms": now - member.offline_since if member.offline_since >= 0 else -1,
			"rebuy_offer": member.rebuy_offer,
			"rebuy_ms": member.rebuy_deadline - _now() if member.rebuy_deadline >= 0 else -1,
			"return_offer": member.return_offer, "folds_hand": member.folds_hand,
		})
	# Quem saiu, com o tempo desde a saída (cada servidor tem o seu relógio).
	var departed: Dictionary = {}
	for member_id: String in _departed:
		departed[member_id] = {"ago": now - int(_departed[member_id]["at"]),
			"avatar": _departed[member_id]["avatar"]}
	var held: Dictionary = {}
	for member_id: String in _held_until:
		held[member_id] = maxi(0, int(_held_until[member_id]) - now)
	return {
		"v": 1, "id": id, "name": name, "phase": phase, "owner": owner_id,
		"options": options.duplicate(true), "table": saved_table, "members": list,
		"next_member": _next_member, "seq": _seq,
		"play_ms": _now() - _play_started if phase == Protocol.PLAYING else 0,
		"next_hand_ms": maxi(0, _next_hand_at - _now()),
		"names": _names.duplicate(), "banned": _banned.keys(), "held": held,
		"held_by": _held_by.duplicate(true), "pending": _pending_settings.duplicate(),
		"paused": paused, "hand_ids": hand_ids,
		"turn_ms": maxi(0, _turn_deadline - _now()) if _turn_deadline >= 0 else -1,
		"bot_ms": maxi(0, _bot_due - _now()),
		"departed": departed,
	}


## Continua a sala a partir do retrato (numa sala recém-criada com as mesmas opções e
## sem bots). Quem estava conectado ganha os 60 s de queda para reconectar aqui.
## Devolve "" ou o motivo da recusa.
func restore(saved: Dictionary) -> String:
	if int(saved.get("v", 0)) != 1 or not table.load_dict(saved.get("table", {})):
		return "retrato da sala inválido"
	var now: int = _clock.now_ms()
	members.clear()
	name = str(saved.get("name", ""))
	phase = str(saved.get("phase", Protocol.LOBBY))
	owner_id = str(saved.get("owner", ""))
	_next_member = int(saved.get("next_member", 1))
	_seq = int(saved.get("seq", 0))
	paused = bool(saved.get("paused", false)) and phase == Protocol.PLAYING
	_paused_total = 0
	_pause_started = now
	for raw: Dictionary in saved.get("members", []):
		var member: Member = Member.new()
		member.id = str(raw["id"])
		member.nick = str(raw["nick"])
		member.base_nick = str(raw.get("base_nick", member.nick))
		member.avatar = clampi(int(raw.get("avatar", 0)), 0, AVATARS - 1)
		member.device = str(raw.get("device", ""))
		member.is_bot = bool(raw.get("bot", false))
		member.level = int(raw.get("level", 0))
		member.style = str(raw.get("style", ""))
		member.seat = int(raw.get("seat", -1))
		member.order = int(raw.get("order", 0))
		member.away = bool(raw.get("away", false))
		member.timeouts = int(raw.get("timeouts", 0))
		member.gone = bool(raw.get("gone", false))
		member.connected = bool(raw.get("connected", true))
		member.quit = bool(raw.get("quit", false))
		member.rebuy_offer = bool(raw.get("rebuy_offer", false))
		var rebuy_ms: int = int(raw.get("rebuy_ms", -1))
		member.rebuy_deadline = _now() + rebuy_ms if rebuy_ms >= 0 else -1
		member.return_offer = bool(raw.get("return_offer", false))
		member.folds_hand = int(raw.get("folds_hand", 0))
		# O prazo do ausente recomeça na sala retomada (cada aparelho tem o seu relógio).
		member.away_since = now if member.away and not member.is_bot else -1
		if member.is_bot:
			member.bot = Bot.new(member.level, member.style, _rng.randi(),
				int(_config["bot_evaluations"]))
		elif member.connected:
			member.offline_since = now
		else:
			member.offline_since = now - maxi(0, int(raw.get("offline_ms", 0)))
		members[member.id] = member
	_names = saved.get("names", {}).duplicate()
	_banned.clear()
	for device: Variant in saved.get("banned", []):
		_banned[str(device)] = true
	_held_until.clear()
	var held: Dictionary = saved.get("held", {})
	for member_id: String in held:
		_held_until[member_id] = now + int(held[member_id])
	_held_by = saved.get("held_by", {}).duplicate(true)
	_pending_settings = saved.get("pending", {}).duplicate()
	_departed.clear()
	var departed: Variant = saved.get("departed", {})
	if typeof(departed) == TYPE_DICTIONARY:
		for member_id: Variant in departed:
			var info: Variant = departed[member_id]
			if typeof(info) == TYPE_DICTIONARY:
				_departed[str(member_id)] = {"at": now - maxi(0, int(info.get("ago", 0))),
					"avatar": clampi(int(info.get("avatar", 0)), 0, AVATARS - 1)}
	_play_started = _now() - int(saved.get("play_ms", 0))
	_next_hand_at = _now() + int(saved.get("next_hand_ms", 0))
	_hand_ids.clear()
	_turn_deadline = -1
	_bot_due = _now()
	# Retrato com a mão (o anfitrião voltou depois de o Android fechar o app): a vez
	# continua com o tempo que faltava.
	var hand_ids: Dictionary = saved.get("hand_ids", {})
	for seat: String in hand_ids:
		_hand_ids[int(seat)] = str(hand_ids[seat])
	if table.hand_in_progress():
		var turn_ms: int = int(saved.get("turn_ms", -1))
		_turn_deadline = _now() + turn_ms if turn_ms >= 0 else -1
		_bot_due = _now() + int(saved.get("bot_ms", 0))
	return ""


## Sala recriada de um resumo depois de um reinício (SPEC 9.4 e 6.6): a mão seguinte
## espera o intervalo normal, para os celulares verem a mesa antes das cartas.
func after_restart() -> void:
	_next_hand_at = maxi(_next_hand_at, _now() + int(_config["hand_gap_ms"]))


func member_at(seat: int) -> Member:
	if seat < 0:
		return null
	for member: Member in members.values():
		if member.seat == seat:
			return member
	return null


## Há outro humano na sala além desse (sentado, assistindo ou reconectando)?
func _other_humans(member_id: String) -> bool:
	for other: Member in members.values():
		if not other.is_bot and other.id != member_id:
			return true
	return false


## Quantos humanos estão de fato na sala.
func humans() -> int:
	var count: int = 0
	for member: Member in members.values():
		if not member.is_bot and _present(member):
			count += 1
	return count


## Resumo para a lista de salas (SPEC 9.3): dono, formato, lugares, blinds, se tem
## senha (locked) e se aceita gente nova agora (open). Nunca a senha.
func summary() -> Dictionary:
	var players: int = table.seats.filter(func(seat: Table.Seat) -> bool:
		return seat.state != Table.OUT).size()
	var owner: Member = members.get(owner_id)
	return {
		"id": id, "name": name, "format": options["format"], "seats": options["seats"],
		"players": players, "phase": phase, "keep_open": options["keep_open"],
		"owner": owner.nick if owner != null else "",
		"small_blind": table.small_blind, "big_blind": table.big_blind,
		"level_minutes": options["level_minutes"], "locked": has_password(),
		"open": players < int(options["seats"])
			and (phase == Protocol.LOBBY or (phase == Protocol.PLAYING and options["keep_open"])),
	}


# ---------------------------------------------------------------- pedidos


func _human_act(member: Member, message: Dictionary) -> String:
	var action: Variant = message.get("action")
	var amount: Variant = message.get("amount", 0)
	var seq: Variant = message.get("seq")
	if typeof(action) != TYPE_STRING or typeof(amount) != TYPE_INT or typeof(seq) != TYPE_INT:
		return "jogada malformada"
	if phase != Protocol.PLAYING:
		return "a partida não está em andamento"
	if paused:
		return "a mesa está pausada"
	if seq != _seq:
		return "essa jogada chegou atrasada"
	var problem: String = _act(member, action, amount)
	if problem == "":
		member.timeouts = 0
	return problem


## O mesmo caminho para humanos e bots.
func _act(member: Member, action: String, amount: int) -> String:
	if member.seat < 0 or not table.hand_in_progress() or table.hand.to_act != member.seat:
		return "não é a sua vez"
	var response: Dictionary = table.apply_action(member.seat, action, amount)
	if not response["ok"]:
		return response["error"]
	_after(response["events"])
	return ""


func _answer_rebuy(member: Member, message: Dictionary) -> String:
	var accept: Variant = message.get("accept")
	if typeof(accept) != TYPE_BOOL:
		return "resposta malformada"
	if not member.rebuy_offer or member.seat < 0:
		return "não há recompra pendente"
	if accept:
		var problem: String = table.rebuy(member.seat)
		if problem != "":
			return problem
		member.rebuy_offer = false
		member.rebuy_deadline = -1
		_notes.append({"type": "rebuy", "seat": member.seat})
	else:
		_decline_rebuy(member)
	_broadcast([])
	return ""


func _sit(member: Member, message: Dictionary) -> String:
	var wanted: Variant = message.get("seat", -1)
	if typeof(wanted) != TYPE_INT:
		return "lugar inválido"
	if member.return_offer:
		return "escolha com quais fichas voltar"
	var problem: String = _try_sit(member, wanted)
	if problem == "":
		_broadcast([])
	return problem


## Troca de avatar, só na sala de espera.
func _change_profile(member: Member, message: Dictionary) -> String:
	var avatar: Variant = message.get("avatar")
	if typeof(avatar) != TYPE_INT or avatar < 0 or avatar >= AVATARS:
		return "avatar inválido"
	if phase != Protocol.LOBBY:
		return "o avatar só muda antes de a partida começar"
	member.avatar = avatar
	_broadcast([])
	return ""


## Reação (SPEC 11.2): só quem está sentado, no máximo uma a cada REACTION_GAP_MS. Vai
## direto a todos, fora do state; o excesso é ignorado sem aviso.
func _react(member: Member, message: Dictionary) -> void:
	var index: Variant = message.get("r")
	if typeof(index) != TYPE_INT or index < 0 or index >= Protocol.REACTIONS.size() \
			or member.seat < 0:
		return
	var now: int = _clock.now_ms()
	if member.reacted_at >= 0 and now - member.reacted_at < Protocol.REACTION_GAP_MS:
		return
	member.reacted_at = now
	var out: Dictionary = {"t": Protocol.REACTION, "seat": member.seat, "r": index}
	for other: Member in members.values():
		if not other.is_bot:
			_send_to(other, out)


## Wi-Fi (SPEC 6.4): o anfitrião sumiu por mais de 10 s no meio de uma mão; ele desiste
## dela (na hora, se for a vez dele; senão quando a vez chegar). Devolve verdadeiro se ele
## ainda tinha cartas na mão (e não estava all-in), isto é, se vai desistir.
func forfeit_hand(member_id: String) -> bool:
	var member: Member = members.get(member_id)
	if member == null or member.seat < 0 or not table.hand_in_progress() \
			or _hand_ids.get(member.seat, "") != member.id:
		return false
	var player: Hand.Player = table.hand.player_at(member.seat)
	if player == null or player.folded or player.all_in:
		return false
	member.folds_hand = table.hand_number
	_run()
	return true


## Volta com fichas guardadas (SPEC 6.2): keep verdadeiro = as fichas de antes; falso =
## as iniciais (recompra, se for mais do que ele tinha).
func _return_choice(member: Member, message: Dictionary) -> String:
	var keep: Variant = message.get("keep")
	if typeof(keep) != TYPE_BOOL:
		return "resposta malformada"
	if not member.return_offer:
		return "você não tem fichas guardadas"
	var seat: int = _free_seat()
	if seat < 0:
		return "não há lugar livre"
	var problem: String = table.add_player(seat, member.id, keep)
	if problem != "":
		return problem
	member.seat = seat
	member.return_offer = false
	member.away = false
	member.timeouts = 0
	_held_until.erase(member.id)
	_held_by.erase(member.id)
	_names[member.id] = member.nick
	_notes.append({"type": "returned", "seat": seat, "keep": keep})
	_broadcast([])
	return ""


func _set_away(member: Member, message: Dictionary) -> String:
	var on: Variant = message.get("on")
	if typeof(on) != TYPE_BOOL:
		return "pedido malformado"
	if member.seat < 0:
		return "só quem está sentado fica ausente"
	_mark_away(member, on)
	_broadcast([])
	return ""


## Anúncio de quem acabou de entrar na sala de espera: os outros veem "Em anúncio" e a
## partida não começa até ele acabar (pedido do dono, 17/11/2026). Fora da sala de espera
## o aviso não vale e é ignorado.
func _set_ad(member: Member, message: Dictionary) -> String:
	var on: Variant = message.get("on")
	if typeof(on) != TYPE_BOOL:
		return "pedido malformado"
	var now_on: bool = on and phase == Protocol.LOBBY
	if now_on == (member.ad_since >= 0):
		return ""
	member.ad_since = _clock.now_ms() if now_on else -1
	_broadcast([])
	return ""


## Vê um anúncio agora: conectado, na sala de espera e dentro do prazo.
func _in_ad(member: Member) -> bool:
	return (member.ad_since >= 0 and phase == Protocol.LOBBY and member.connected
		and member.offline_since < 0
		and _clock.now_ms() - member.ad_since < int(_config["ad_max_ms"]))


## Tira o "Em anúncio" de quem passou do prazo, caiu ou saiu sem avisar o fim.
func _expire_ads() -> void:
	var changed: bool = false
	for member: Member in members.values():
		if member.ad_since >= 0 and not _in_ad(member):
			member.ad_since = -1
			changed = true
	if changed and phase != Protocol.ENDED:
		_broadcast([])


func _owner_command(member: Member, message: Dictionary) -> String:
	if member.id != owner_id:
		return "só o dono da sala pode fazer isso"
	match message.get("cmd"):
		Protocol.CMD_PAUSE:
			if phase != Protocol.PLAYING or paused:
				return "não há partida para pausar"
			_pause_started = _clock.now_ms()
			paused = true
			_summary_point()
		Protocol.CMD_RESUME:
			if not paused:
				return "a mesa não está pausada"
			_paused_total += _clock.now_ms() - _pause_started
			paused = false
			_summary_point()
		Protocol.CMD_KICK:
			var target: Member = _target(message)
			if target == null or target == member:
				return "jogador não encontrado"
			if target.is_bot:
				return _remove_bot(target)
			if target.device != "":
				_banned[target.device] = true
			_send_to(target, {"t": Protocol.LEFT, "reason": Protocol.R_KICKED})
			_drop_member(target, true)
		Protocol.CMD_ADD_BOT:
			var level: Variant = message.get("level")
			if typeof(level) != TYPE_INT:
				return "nível de bot inválido"
			var problem: String = add_bot(level)
			if problem != "":
				return problem
		Protocol.CMD_REMOVE_BOT:
			var bot_member: Member = _target(message)
			if bot_member == null or not bot_member.is_bot:
				return "bot não encontrado"
			return _remove_bot(bot_member)
		Protocol.CMD_SETTINGS:
			var refusal: String = _change_settings(message)
			if refusal != "":
				return refusal
		Protocol.CMD_CLOSE:
			close(Protocol.R_OWNER)
			return ""
		_:
			return "comando desconhecido"
	_broadcast([])
	return ""


func _target(message: Dictionary) -> Member:
	var target_id: Variant = message.get("id")
	if typeof(target_id) != TYPE_STRING:
		return null
	return members.get(target_id)


func _remove_bot(member: Member) -> String:
	if table.format == Table.TOURNAMENT and table.hand_number > 0:
		return "o torneio já começou"
	_drop_member(member, true)
	_broadcast([])
	return ""


## Clássico: o dono muda blinds e tempo por jogada; vale entre uma mão e outra (SPEC 3.4).
func _change_settings(message: Dictionary) -> String:
	var pending: Dictionary = {}
	if message.has("turn_seconds"):
		var turn: Variant = message["turn_seconds"]
		if typeof(turn) != TYPE_INT or not TURN_SECONDS.has(turn):
			return "tempo por jogada inválido"
		pending["turn_seconds"] = turn
	if message.has("small_blind") or message.has("big_blind"):
		var small: Variant = message.get("small_blind")
		var big: Variant = message.get("big_blind")
		if table.format != Table.CLASSIC:
			return "no torneio os blinds seguem os níveis"
		if (typeof(small) != TYPE_INT or typeof(big) != TYPE_INT or small < 1 or big < small
				or big > int(options["starting_stack"])):
			return "blinds inválidos"
		pending["small_blind"] = small
		pending["big_blind"] = big
	if pending.is_empty():
		return "nada para mudar"
	_pending_settings.merge(pending, true)
	if not table.hand_in_progress():
		_apply_settings()
	return ""


func _apply_settings() -> void:
	if _pending_settings.has("turn_seconds"):
		options["turn_seconds"] = _pending_settings["turn_seconds"]
	if _pending_settings.has("small_blind"):
		var small: int = _pending_settings["small_blind"]
		var big: int = _pending_settings["big_blind"]
		if table.set_blinds(small, big) == "":
			options["small_blind"] = small
			options["big_blind"] = big
	_pending_settings.clear()


# ---------------------------------------------------------------- andamento


func _run() -> void:
	var steps: int = 0
	while phase == Protocol.PLAYING and not paused and steps < MAX_STEPS_PER_TICK and _step():
		steps += 1


## Um passo do jogo. Devolve falso quando não há mais nada a fazer agora.
func _step() -> bool:
	var now: int = _now()
	if _expire_rebuys(now):
		return true
	if table.hand_in_progress():
		return _step_turn(now)
	if now < _next_hand_at or hold_hands or _empty_since >= 0:
		return false
	if _walkover():
		return true
	if _check_over():
		return true
	if not table.can_start_hand():
		return false
	# Antes de dar as cartas: se algo mudou desde o fim da mão (recompra, alguém
	# sentou), o resumo novo garante que a recuperação repete esta mão.
	_summary_point()
	return _start_hand(now)


func _step_turn(now: int) -> bool:
	var seat: int = table.hand.to_act
	var member: Member = member_at(seat)
	# Ausente, de saída ou fora do torneio: desiste na hora (SPEC 5).
	if member == null or member.away or member.leaving or member.gone \
			or member.folds_hand == table.hand_number:
		_forced(seat, false)
		return true
	if member.is_bot:
		if now < _bot_due:
			return false
		_bot_turn(member)
		return true
	if _turn_deadline >= 0 and now >= _turn_deadline:
		# Estourou o tempo: passa se puder, senão desiste. Dois seguidos: ausente.
		member.timeouts += 1
		_notes.append({"type": "timeout", "seat": seat})
		if member.timeouts >= AWAY_AFTER_TIMEOUTS:
			_mark_away(member, true)
		_forced(seat, true)
		return true
	return false


## A sala joga pelo lugar: passa (se deixarem e puder) ou desiste.
func _forced(seat: int, may_check: bool) -> void:
	var action: String = Hand.FOLD
	if may_check and table.hand.legal_actions().get("can_check", false):
		action = Hand.CHECK
	_after(table.apply_action(seat, action)["events"])


func _bot_turn(member: Member) -> void:
	var view: Dictionary = member.view
	if view.is_empty() or int(view["table"]["seq"]) != _seq or not view["you"].has("legal"):
		view = _state_for(member, _room_info(), _table_view(), [])
	var choice: Dictionary = member.bot.decide(view)
	if _act(member, str(choice.get("action", "")), int(choice.get("amount", 0))) != "":
		bot_errors += 1
		_forced(member.seat, true)


func _start_hand(now: int) -> bool:
	var ids: Dictionary = {}
	for index in table.participants():
		ids[index] = table.seat_at(index).id
	var params: Dictionary = {"seed": _seed()}
	if table.format == Table.TOURNAMENT:
		params["elapsed_ms"] = now - _play_started
	var response: Dictionary = table.start_hand(params)
	if not response["ok"]:
		_next_hand_at = now + 1000
		return false
	_hand_ids = ids
	_after(response["events"])
	return true


## Depois de cada passo da mão: recompras, eliminações, a vez seguinte e o aviso a todos.
func _after(events: Array) -> void:
	var extra: Array = []
	for event: Dictionary in events:
		var member: Member = member_at(int(event.get("seat", -1)))
		if member == null:
			continue
		match event["type"]:
			"busted":
				if not event["can_rebuy"]:
					_to_spectator(member)
				elif member.leaving or member.gone:
					pass   # sai da mesa quando a mão acabar
				elif member.is_bot:
					if member.bot.wants_rebuy() and table.rebuy(member.seat) == "":
						extra.append({"type": "rebuy", "seat": member.seat})
					else:
						table.decline_rebuy(member.seat)
						_to_spectator(member)
				else:
					member.rebuy_offer = true
					var limit: int = int(_config["rebuy_ms"])
					member.rebuy_deadline = _now() + limit if limit > 0 else -1
			"eliminated":
				_to_spectator(member)
	var all: Array = []
	all.append_array(events)
	all.append_array(extra)
	if table.hand_in_progress():
		_begin_turn()
	else:
		_hand_finished()
	_broadcast(all)


func _begin_turn() -> void:
	_seq += 1
	var now: int = _now()
	_turn_deadline = -1
	_bot_due = now
	var member: Member = member_at(table.hand.to_act)
	if member == null:
		return
	if member.is_bot:
		var slowest: int = int(_config["bot_max_ms"])
		if slowest > 0:
			_bot_due = now + _rng.randi_range(mini(int(_config["bot_min_ms"]), slowest), slowest)
	elif int(options["turn_seconds"]) > 0:
		_turn_deadline = now + int(options["turn_seconds"]) * 1000


func _hand_finished() -> void:
	_seq += 1
	_turn_deadline = -1
	var showdown: bool = bool(table.hand.result.get("showdown", false))
	_next_hand_at = _now() + int(_config["showdown_gap_ms" if showdown else "hand_gap_ms"])
	for member: Member in members.values():
		if member.leaving and member.seat >= 0:
			_leave_table(member)
			members.erase(member.id)
	_apply_settings()
	_summary_point()


## Fim de mão ou mão por começar (SPEC 9.4): guarda o retrato para o resumo, se algo
## mudou desde o último.
func _summary_point() -> void:
	if not summaries or phase != Protocol.PLAYING or table.hand_in_progress():
		return
	# Primeiro a comparação, barata; o retrato inteiro só quando algo mudou.
	var table_now: Dictionary = table.to_dict()
	table_now["hand"] = null
	var people: Array = []
	for member: Member in members.values():
		people.append([member.id, member.seat, member.nick, member.avatar, member.away,
			member.gone, member.return_offer, member.rebuy_offer])
	var print_now: String = JSON.stringify([table_now, people, owner_id, _held_by.keys(),
		_pending_settings, _banned.keys(), options, paused, _departed.keys()])
	if print_now == _summary_print:
		return
	_summary_print = print_now
	summary_rev += 1
	last_summary = snapshot()


## Clássico: sobra um só com fichas e ninguém pode recomprar. Torneio: um tem tudo.
func _check_over() -> bool:
	if not table.is_over():
		return false
	if table.format == Table.CLASSIC:
		for member: Member in members.values():
			# Quem assiste e pode voltar recomprando, ou voltou com fichas guardadas e
			# ainda vai escolher, segura a partida.
			if (not member.is_bot and member.seat < 0 and _present(member)
					and (member.return_offer or table.can_return_with_rebuy(member.id))):
				return false
	close(Protocol.R_FINISHED)
	return true


## Torneio, entre mãos (SPEC 6.3): quem saiu ou caiu e não voltou em return_ms sai do
## torneio, e as fichas dele são divididas entre quem continua (no mano a mano, o outro
## é o campeão). Pedido do dono, 17/11/2026.
func _walkover() -> bool:
	if table.format != Table.TOURNAMENT or table.hand_number == 0:
		return false
	var alive: Array[int] = table.participants()
	if alive.size() < 2:
		return false
	var now: int = _clock.now_ms()
	for seat: int in alive:
		var member: Member = member_at(seat)
		if member == null or member.is_bot or member.offline_since < 0 \
				or now - member.offline_since < int(_config["return_ms"]):
			continue
		var response: Dictionary = table.concede(seat)
		if not response["ok"]:
			continue
		# Não voltou: deixa a sala (o placar guarda a colocação).
		_leave_table(member)
		members.erase(member.id)
		_check_owner()
		if phase == Protocol.ENDED:
			return true
		_broadcast(response["events"])
		return true
	return false


## Quem caiu e não voltou em offline_ms perde o lugar guardado: sai como quem toca em
## "Sair" (desiste da mão, se estiver nela). As fichas ficam guardadas desde a queda.
func _expire_offline() -> void:
	var limit: int = int(_config["offline_ms"])
	var now: int = _clock.now_ms()
	for member: Member in members.values():
		if member.connected and member.offline_since >= 0 and now - member.offline_since >= limit:
			_drop_member(member, false)
			if phase == Protocol.ENDED:
				return
			_broadcast([])


## Ausente há away_ms sem tocar em "Voltei": sai da sala como quem toca em "Sair" (pedido
## do dono, 17/11/2026; só no Online, que liga o prazo). No clássico as fichas ficam guardadas; no torneio, a saída conta
## desde que ficou ausente, então ele sai entre uma mão e outra e as fichas vão para
## quem continua. O anfitrião do Wi-Fi não sai (a sala roda no celular dele).
func _expire_away() -> void:
	var limit: int = int(_config["away_ms"])
	if limit <= 0 or phase != Protocol.PLAYING:
		return
	var now: int = _clock.now_ms()
	for member: Member in members.values():
		if (member.is_bot or not member.away or member.away_since < 0 or not member.connected
				or member.offline_since >= 0 or member.id == host_id
				or now - member.away_since < limit):
			continue
		_send_to(member, {"t": Protocol.LEFT, "reason": Protocol.R_AWAY})
		member.offline_since = member.away_since
		leave(member.id)
		return


func _expire_rebuys(now: int) -> bool:
	for member: Member in members.values():
		if member.rebuy_offer and member.rebuy_deadline >= 0 and now >= member.rebuy_deadline:
			_decline_rebuy(member)
			_broadcast([])
			return true
	return false


## Fichas guardadas de quem saiu: vencido o prazo, saem da mesa de vez (SPEC 6.2).
func _expire_held() -> void:
	if _held_until.is_empty():
		return
	var now: int = _clock.now_ms()
	for member_id: String in _held_until.keys():
		if now >= int(_held_until[member_id]):
			table.expire_held(member_id)
			_held_until.erase(member_id)
			_held_by.erase(member_id)
			var waiting: Member = members.get(member_id)
			if waiting != null and waiting.return_offer:
				waiting.return_offer = false
				_broadcast([])


## Participante ainda na sala com esse apelido e aparelho (quem caiu, ou saiu no meio de
## uma mão ou do torneio).
func _same_person(device: String, base: String) -> Member:
	if device == "":
		return null
	for member: Member in members.values():
		if not member.is_bot and member.device == device and member.base_nick == base:
			return member
	return null


## Quem saiu e ainda tem fichas guardadas, com esse apelido e aparelho: o id antigo.
func _held_id(device: String, base: String) -> String:
	if device == "":
		return ""
	var now: int = _clock.now_ms()
	for member_id: String in _held_by.keys():
		var who: Dictionary = _held_by[member_id]
		if (who["device"] == device and who["nick"] == base and not members.has(member_id)
				and now < int(_held_until.get(member_id, 0))):
			return member_id
	return ""


# ---------------------------------------------------------------- pessoas


## known_id: o id antigo de quem volta com fichas guardadas.
func _new_member(nick: String, avatar: int, is_bot: bool, known_id: String = "") -> Member:
	var member: Member = Member.new()
	member.id = known_id if known_id != "" else ("b%d" if is_bot else "p%d") % _next_member
	member.order = _next_member
	_next_member += 1
	member.is_bot = is_bot
	member.avatar = clampi(avatar, 0, AVATARS - 1)
	member.nick = _unique_nick(clean_nick(nick))
	members[member.id] = member
	return member


## Dois apelidos iguais na mesma sala: o segundo ganha um número (SPEC 4.4).
func _unique_nick(nick: String) -> String:
	var taken: Dictionary = {}
	for member: Member in members.values():
		taken[member.nick] = true
	if not taken.has(nick):
		return nick
	var number: int = 2
	while taken.has("%s %d" % [nick, number]):
		number += 1
	return "%s %d" % [nick, number]


func _set_owner(member: Member) -> void:
	owner_id = member.id
	if name == "":
		name = "Sala de " + member.nick


func _present(member: Member) -> bool:
	return member.connected and not member.leaving and not member.gone


func _free_seat() -> int:
	for index in int(options["seats"]):
		if table.seat_at(index) == null:
			return index
	return -1


## Senta o participante. wanted: o lugar pedido, ou -1 para o primeiro livre.
func _try_sit(member: Member, wanted: int) -> String:
	var refusal: String = _sit_refusal(member)
	if refusal != "":
		return refusal
	var seat: int = wanted if wanted >= 0 else _free_seat()
	if seat < 0 or seat >= int(options["seats"]):
		return "não há lugar livre"
	var problem: String = table.add_player(seat, member.id)
	if problem != "":
		return problem
	member.seat = seat
	member.away = false
	member.timeouts = 0
	_names[member.id] = member.nick
	return ""


## Sentar gasta recompra: já jogou aqui, o prazo de volta não venceu e as fichas guardadas
## não chegam às iniciais (a mesma conta de Table.add_player).
func _sit_spends_rebuy(member: Member) -> bool:
	return table.knows(member.id) and not table.is_expired(member.id) \
		and table.starting_stack > table.cashbox.held(member.id)


## O motivo da recusa na entrada, como o app mostra (com maiúscula e ponto final).
func _entry_error(refusal: String) -> String:
	match refusal:
		"não há lugar livre":
			return "a sala está cheia"
		"a sala não aceita novos jogadores":
			return "a partida já começou e a sala não aceita novos jogadores"
	return refusal


## Por que esse participante não pode sentar agora ("" = pode, num lugar livre qualquer).
func _sit_refusal(member: Member) -> String:
	if member.seat >= 0:
		return "você já está sentado"
	if phase == Protocol.PLAYING:
		if table.format == Table.TOURNAMENT:
			return "o torneio já começou"
		# Quem já jogou nesta mesa volta gastando recompra; gente nova (ou quem perdeu o
		# prazo de volta), só em sala aberta.
		var known: bool = table.knows(member.id) and not table.is_expired(member.id)
		if _sit_spends_rebuy(member) and not table.can_return_with_rebuy(member.id):
			return "sem recompras"
		if not known and not options["keep_open"]:
			return "a sala não aceita novos jogadores"
	if _free_seat() < 0:
		return "não há lugar livre"
	return ""


func _mark_away(member: Member, on: bool) -> void:
	member.away = on
	if on and member.away_since < 0:
		member.away_since = _clock.now_ms()
	if not on:
		member.timeouts = 0
		member.away_since = -1
	if table.format == Table.CLASSIC and member.seat >= 0:
		table.set_away(member.seat, on)
	_notes.append({"type": "away", "seat": member.seat, "on": on})


func _decline_rebuy(member: Member) -> void:
	table.decline_rebuy(member.seat)
	_notes.append({"type": "rebuy_declined", "seat": member.seat})
	_to_spectator(member)


## Perdeu o lugar: vira espectador. Bot e quem já tinha saído deixam a sala.
func _to_spectator(member: Member) -> void:
	member.seat = -1
	member.watcher = false   # perdeu as fichas e continua assistindo: não conta no teto
	member.rebuy_offer = false
	member.rebuy_deadline = -1
	member.away = false
	if member.is_bot or member.gone or member.leaving:
		members.erase(member.id)


## O participante deixa a sala. forfeit: as fichas dele saem da mesa de vez; senão
## ficam guardadas pelo prazo de volta.
func _drop_member(member: Member, forfeit: bool) -> void:
	member.connected = false
	member.forfeit = forfeit
	if member.offline_since < 0:
		member.offline_since = _clock.now_ms()
	if not member.is_bot:
		_last_offline = member.offline_since
	if member.seat < 0:
		members.erase(member.id)
	elif table.format == Table.TOURNAMENT and table.hand_number > 0:
		# No torneio o lugar fica: ele desiste a cada mão e paga os blinds (SPEC 6.3).
		member.gone = true
	elif table.hand_in_progress() and table.hand.player_at(member.seat) != null:
		member.leaving = true
	else:
		_leave_table(member)
		members.erase(member.id)
	_check_owner()


func _leave_table(member: Member) -> void:
	var seat: Table.Seat = table.seat_at(member.seat)
	if seat != null and seat.state == Table.BUSTED:
		table.decline_rebuy(member.seat)
	elif seat != null and table.remove_player(member.seat) == "":
		if table.cashbox.held(member.id) > 0:
			if member.forfeit:
				table.expire_held(member.id)
			else:
				# Os 5 minutos contam desde a queda (SPEC 6.2).
				var since: int = member.offline_since if member.offline_since >= 0 else _clock.now_ms()
				_held_until[member.id] = since + int(_config["held_ms"])
				_held_by[member.id] = {"device": member.device, "nick": member.base_nick}
	if member.seat >= 0:
		_departed[member.id] = {"at": _clock.now_ms(), "avatar": member.avatar}
	member.seat = -1
	member.rebuy_offer = false
	member.rebuy_deadline = -1


## Se o dono saiu, o humano mais antigo assume (SPEC 6.5). Sem nenhum humano, a sala fecha.
func _check_owner() -> void:
	var owner: Member = members.get(owner_id)
	if owner != null and _present(owner):
		return
	var oldest: Member = null
	for member: Member in members.values():
		if not member.is_bot and _present(member) and (oldest == null or member.order < oldest.order):
			oldest = member
	if oldest != null:
		_set_owner(oldest)
		_empty_since = -1
		return
	owner_id = ""
	if _config["allow_empty"]:
		return
	# À distância a partida espera até 5 min, sem começar mão nova, só enquanto ainda há
	# humano na sala (reconectando, ou no torneio, que guarda o lugar). Sem nenhum, fecha
	# na hora (pedido do dono, 17/11/2026).
	if phase == Protocol.PLAYING and int(_config["empty_close_ms"]) > 0 and _other_humans(""):
		if _empty_since < 0:
			# Conta desde a queda (o lugar guardado só vence offline_ms depois), como as
			# fichas guardadas.
			_empty_since = _clock.now_ms()
			if _last_offline >= 0:
				_empty_since = mini(_empty_since, _last_offline)
		return
	close(Protocol.R_EMPTY)


# ---------------------------------------------------------------- mensagens


func _broadcast(events: Array) -> void:
	var all: Array = _notes
	_notes = []
	all.append_array(events)
	history.note(all, table, _hand_ids, _names)
	var info: Dictionary = _room_info()
	var table_view: Dictionary = _table_view()
	# Protocolo enxuto (SPEC 9.1): a parte pública vai compactada uma vez para todos.
	var pack: Wire.StatePack = Wire.StatePack.new(info, table_view, all) if send_state.is_valid() else null
	for member: Member in members.values():
		_send_to(member, _state_for(member, info, table_view, all), pack)


func _state_for(member: Member, info: Dictionary, table_view: Dictionary, events: Array) -> Dictionary:
	var you: Dictionary = View.own(table, member.seat, member.id, _hand_ids)
	you["id"] = member.id
	you["seat"] = member.seat
	# return_offer: voltou com fichas guardadas; escolhe as de antes ou as iniciais.
	if member.return_offer:
		var held: int = table.cashbox.held(member.id)
		you["return_offer"] = {
			"before": held, "initial": table.starting_stack, "seat": _free_seat() >= 0,
			"can_initial": table.starting_stack <= held or table.can_return_with_rebuy(member.id),
		}
	# rebuy_ms: o que falta do prazo da oferta, ou -1 quando não há prazo.
	if member.rebuy_offer:
		you["rebuy_ms"] = maxi(0, member.rebuy_deadline - _now()) if member.rebuy_deadline >= 0 else -1
	# can_sit: quem assiste pode sentar agora (a mesa mostra "Sentar"); sit_rebuy: gasta
	# uma recompra para isso.
	if member.seat < 0 and not member.return_offer and not member.is_bot:
		you["can_sit"] = _sit_refusal(member) == ""
		you["sit_rebuy"] = _sit_spends_rebuy(member)
	return {"t": Protocol.STATE, "room": info, "table": table_view, "you": you, "events": events}


## A mesa pública, com os relógios da sala.
func _table_view() -> Dictionary:
	var view: Dictionary = View.public(table, _hand_ids)
	var now: int = _now()
	view["seq"] = _seq
	view["turn_ms"] = maxi(0, _turn_deadline - now) if _turn_deadline >= 0 else -1
	view["level_ms"] = -1
	if table.format == Table.TOURNAMENT and phase == Protocol.PLAYING:
		view["level_ms"] = Tournament.ms_to_next_level(now - _play_started, table.level_minutes)
	return view


## Quanto falta para o lugar ser liberado (a mesa mostra a contagem), ou -1: quem está
## ausente (away_ms); no torneio, quem saiu ou caiu (return_ms); no clássico, quem caiu
## (offline_ms).
func _remove_ms(member: Member) -> int:
	if member.is_bot or member.seat < 0 or phase != Protocol.PLAYING:
		return -1
	var away_limit: int = int(_config["away_ms"])
	if (member.away and member.away_since >= 0 and member.offline_since < 0 and away_limit > 0
			and member.id != host_id):
		return maxi(0, away_limit - (_clock.now_ms() - member.away_since))
	if member.offline_since < 0:
		return -1
	var away_for: int = _clock.now_ms() - member.offline_since
	if table.format == Table.TOURNAMENT:
		return maxi(0, int(_config["return_ms"]) - away_for)
	if member.connected and not member.quit:
		return maxi(0, int(_config["offline_ms"]) - away_for)
	return -1


func _room_info() -> Dictionary:
	var list: Array = []
	for member: Member in members.values():
		list.append({
			"id": member.id, "nick": member.nick, "avatar": member.avatar,
			"bot": member.is_bot, "level": member.level, "style": member.style,
			"seat": member.seat, "away": member.away or member.gone or member.leaving,
			"connected": member.connected and member.offline_since < 0,
			"rebuys": table.rebuys_of(member.id),
		})
		if _in_ad(member):
			list.back()["ad"] = true
		if member.quit:
			# Saiu pelo botão e o lugar ainda espera a mão acabar (ou o torneio guarda).
			list.back()["left"] = true
		var remove_ms: int = _remove_ms(member)
		if remove_ms >= 0:
			list.back()["remove_ms"] = remove_ms
	# score: o placar de agora (como se a mão fosse cancelada). No Wi-Fi, se o anfitrião
	# sumir, cada celular calcula o placar final a partir dele (SPEC 6.4).
	return {
		"id": id, "name": name, "phase": phase, "paused": paused, "owner": owner_id, "host": host_id,
		"options": options.duplicate(true), "members": list,
		"score": _scoreboard() if phase == Protocol.PLAYING else [],
	}


## pack: as partes públicas do lance, para o transporte de rede não montá-las de novo.
func _send_to(member: Member, message: Dictionary, pack: Wire.StatePack = null) -> void:
	if tap.is_valid():
		tap.call(member.id, message)
	if member.is_bot:
		if message["t"] == Protocol.STATE:
			member.view = message
			member.bot.observe(message)
	elif member.connected and member.offline_since < 0:
		if pack != null:
			send_state.call(member.id, message, pack)
		elif _send.is_valid():
			_send.call(member.id, message)


## O placar (SPEC 11.2): quem está na sala (na mesa ou assistindo) e quem já saiu dela
## (o motor guarda o registro com o que deixou), até os SCORE_ROWS mais recentes:
## primeiro quem está na sala, depois quem saiu por último. Cada linha leva o apelido e o
## avatar.
func _scoreboard() -> Array:
	var rows: Array = []
	var gone: Array = []
	for row: Dictionary in table.scoreboard():
		if members.has(str(row["id"])):
			rows.append(row)
		else:
			gone.append(row)
	gone.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(_departed.get(a["id"], {}).get("at", 0)) > int(_departed.get(b["id"], {}).get("at", 0)))
	rows.append_array(gone.slice(0, maxi(0, SCORE_ROWS - rows.size())))
	for row: Dictionary in rows:
		var key: String = str(row["id"])
		row["nick"] = _names.get(key, "")
		var member: Member = members.get(key)
		row["avatar"] = member.avatar if member != null \
			else int(_departed.get(key, {}).get("avatar", 0))
	Table.sort_scoreboard(rows, table.format == Table.TOURNAMENT)
	return rows


func _podium() -> Array:
	var rows: Array = []
	if table.format == Table.TOURNAMENT:
		for row: Dictionary in table.podium():
			row["nick"] = _names.get(row["id"], "")
			rows.append(row)
	return rows


# ---------------------------------------------------------------- apoio


## O tempo da sala: para enquanto a mesa está pausada (SPEC 3.5 e 4.2).
func _now() -> int:
	return (_pause_started if paused else _clock.now_ms()) - _paused_total


## Semente forte a cada mão (SPEC 8); nos testes vem de fora.
func _seed() -> int:
	if _seed_source.is_valid():
		return int(_seed_source.call())
	return _crypto.generate_random_bytes(8).decode_s64(0)


static func _bad_options(message: String) -> Dictionary:
	return {"ok": false, "error": message, "options": {}}
