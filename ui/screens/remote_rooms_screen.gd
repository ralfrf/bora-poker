extends "res://ui/screens/screen.gd"
## Salas de um servidor à distância (SPEC 9.3 e 11.1): as que esperam jogadores e as em
## partida com vaga e "manter sala aberta". Cada linha mostra o dono, o formato, os
## lugares e os blinds; sala com senha tem cadeado e pede os 4 números antes de entrar.
## Na coluna, "Usar código" (para achar a sala de um amigo direto) e "Criar sala".
##
## A sessão (ui/app/remote_game.gd) já vem conectando: enquanto o servidor acorda,
## aparece "Conectando ao servidor…" com o aviso. Ao entrar numa sala, a mesma sessão segue para a sala
## de espera (sinal entered).

signal back
signal create
## Entrou numa sala: a sessão segue para a sala de espera.
signal entered
## A conexão falhou de vez: volta para os servidores com o aviso.
signal lost(notice: String)

const RemoteGame := preload("res://ui/app/remote_game.gd")
const Protocol := preload("res://server/protocol.gd")
const Money := preload("res://engine/money.gd")
const Room := preload("res://server/room.gd")
const RoomRow := preload("res://ui/widgets/room_row.gd")
const EntryPanel := preload("res://ui/widgets/entry_panel.gd")
const Dialog := preload("res://ui/widgets/dialog.gd")

const ROW_H: float = 58.0
## A lista inteira (até 60 salas) gasta banda do plano gratuito: pergunta a cada 10 s.
const REFRESH_MS: int = 10000

var _game: RemoteGame = null
var _server_name: String = ""
var _back: Button = null
var _title: Label = null
var _status: Label = null
var _scroll: ScrollContainer = null
var _list: VBoxContainer = null
var _hint: Label = null
var _code: Button = null
var _create: Button = null
var _code_panel: EntryPanel = null
var _password_panel: EntryPanel = null
var _dialog: Dialog = null
var _notice: String = ""
var _rooms: Array = []
var _target: Dictionary = {}     ## a sala escolhida (para a pergunta e a senha)
var _from_code: bool = false     ## a tentativa veio do código digitado
var _asked_at: int = -1
var _last_key: String = ""
var _done: bool = false


func _init(game: RemoteGame, server_name: String, notice: String = "") -> void:
	_game = game
	_server_name = server_name
	_notice = notice


func _build() -> void:
	_back = Button.new()
	_back.text = "‹"
	_back.theme_type_variation = "QuietButton"
	_back.focus_mode = Control.FOCUS_NONE
	_back.pressed.connect(func() -> void: back.emit())
	add_child(_back)
	_title = Label.new()
	_title.theme_type_variation = "TitleLabel"
	_title.text = _server_name
	add_child(_title)
	_status = Label.new()
	_status.theme_type_variation = "StrongLabel"
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_status)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	_scroll.add_child(_list)
	_hint = Label.new()
	_hint.theme_type_variation = "SmallLabel"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_hint)
	_code = action_button("Usar código", false)
	_code.pressed.connect(func() -> void: _code_panel.open())
	add_child(_code)
	_create = action_button("Criar sala", true)
	_create.pressed.connect(func() -> void: create.emit())
	add_child(_create)
	_dialog = Dialog.new()
	_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dialog.chosen.connect(_on_dialog)
	add_child(_dialog)
	_code_panel = EntryPanel.new("Código da sala", "Aparece na sala de espera de quem criou.",
		"Ex.: K7MP", 5)
	_code_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_code_panel.entered.connect(_on_code)
	add_child(_code_panel)
	_password_panel = EntryPanel.new("Senha da sala", "Peça os 4 números a quem criou a sala.",
		"Ex.: 2580", 4, LineEdit.KEYBOARD_TYPE_NUMBER)
	_password_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_password_panel.entered.connect(_on_password)
	add_child(_password_panel)
	_rooms = _game.rooms
	_refresh()


func _process(delta: float) -> void:
	super(delta)
	if _done or _game == null:
		return
	var changed: bool = false
	for message: Dictionary in _game.update():
		match message.get("t"):
			Protocol.ROOMS:
				_rooms = _game.rooms
				changed = true
			Protocol.JOINED:
				_done = true
				entered.emit()
				return
			Protocol.ERROR:
				_on_error(message)
				changed = true
	if _game.failed():
		_done = true
		lost.emit(_game.error_text)
		return
	var now: int = Time.get_ticks_msec()
	if _game.link == RemoteGame.Link.ONLINE and not _game.joining() \
			and (_asked_at < 0 or now - _asked_at >= REFRESH_MS):
		_asked_at = now
		_game.list_rooms()
	var key: String = "%d/%s/%s" % [_game.link, _game.waking(), _game.joining()]
	if changed or key != _last_key:
		_last_key = key
		_refresh()


func _refresh() -> void:
	match _game.link:
		RemoteGame.Link.ONLINE:
			if _game.joining():
				_status.text = "Entrando na sala…"
			elif _rooms.is_empty():
				_status.text = "Nenhuma sala aberta agora"
			else:
				_status.text = "Salas abertas"
		_:
			_status.text = _game.status_text()
	var tips: Array[String] = []
	if _notice != "":
		tips.append(_notice)
	# Sem o aviso fixo dos servidores: a lista fica limpa (pedido do dono, 18/11/2026).
	if _game.link == RemoteGame.Link.ONLINE and _rooms.is_empty():
		tips.append("Crie uma sala e passe o código aos amigos, ou espere a sala deles " \
			+ "aparecer aqui.")
		# Para juntar jogadores (pedido do dono, 18/11/2026): a sala aberta aparece para
		# todos e os bots só seguram a partida até o pessoal chegar.
		tips.append("Dica: no Clássico, deixe \"Manter sala aberta\" em Sim e lugares livres. " \
			+ "Sua sala aparece aqui para todo mundo e, enquanto o pessoal não chega, você " \
			+ "vai jogando com bots.")
	_hint.text = "\n".join(tips)
	_fill_rows()
	_layout()


func _fill_rows() -> void:
	while _list.get_child_count() < _rooms.size():
		var row: RoomRow = RoomRow.new()
		row.custom_minimum_size = Vector2(0, ROW_H)
		row.pressed.connect(_on_row.bind(_list.get_child_count()))
		_list.add_child(row)
	for i in _list.get_child_count():
		var row: RoomRow = _list.get_child(i)
		row.visible = i < _rooms.size()
		if not row.visible:
			continue
		var room: Dictionary = _rooms[i]
		row.title = room_title(room)
		row.detail = room_detail(room)
		row.locked = bool(room.get("locked", false))
		row.disabled = _game.joining()
		row.queue_redraw()


## "Sala de Bia" (o dono de agora).
static func room_title(room: Dictionary) -> String:
	var owner: String = str(room.get("owner", ""))
	return "Sala de " + owner if owner != "" else str(room.get("name", "Sala"))


## "Clássico · 3 de 6 lugares · blinds 0,10/0,20 · em partida, com vaga".
static func room_detail(room: Dictionary) -> String:
	var parts: Array[String] = [RoomRow.FORMAT_NAMES.get(room.get("format"), ""),
		"%d de %d lugares" % [int(room.get("players", 0)), int(room.get("seats", 0))]]
	if room.get("format") == "tournament":
		parts.append("blinds sobem a cada %d min" % int(room.get("level_minutes", 5)))
	else:
		parts.append("blinds %s/%s" % [Money.format(int(room.get("small_blind", 0))),
			Money.format(int(room.get("big_blind", 0)))])
	if room.get("back", false):
		# Caiu ou fechou o app: a sala aparece mesmo sem aceitar gente nova.
		return "Você está nesta partida · toque para voltar"
	if room.get("phase") == Protocol.PLAYING:
		parts.append("em partida, com vaga")
	return " · ".join(parts)


func _layout() -> void:
	if _title == null:
		return
	var b: Rect2 = body()
	var col: Rect2 = column()
	place(_back, Rect2(b.position.x, b.position.y - 2.0, 44, 40))
	place(_title, Rect2(b.position.x + 56.0, b.position.y, b.size.x - 56.0, 36))
	var top: float = b.position.y + 50.0
	place(_status, Rect2(b.position.x, top, b.size.x, 26))
	top += 34.0
	var hint_h: float = 0.0
	if _hint.text != "":
		hint_h = _hint.get_minimum_size().y if _rooms.is_empty() else minf(54.0, b.end.y - top)
	var list_h: float = maxf(0.0, b.end.y - top - hint_h - (8.0 if hint_h > 0.0 else 0.0))
	if _rooms.is_empty():
		list_h = 0.0
	_scroll.visible = list_h > 0.0
	place(_scroll, Rect2(b.position.x, top, b.size.x, list_h))
	var hint_top: float = top + list_h + (8.0 if list_h > 0.0 else 0.0)
	place(_hint, Rect2(b.position.x, hint_top, b.size.x, maxf(20.0, b.end.y - hint_top)))
	place(_create, Rect2(col.position.x, col.end.y - BUTTON_H, col.size.x, BUTTON_H))
	place(_code, Rect2(col.position.x, col.end.y - BUTTON_H * 2.0 - 10.0, col.size.x, BUTTON_H))
	var busy: bool = _game.link != RemoteGame.Link.ONLINE or _game.joining()
	_create.disabled = _game.link != RemoteGame.Link.ONLINE
	_code.disabled = busy


func _on_row(index: int) -> void:
	if index >= _rooms.size() or _game.joining():
		return
	_target = _rooms[index]
	_from_code = false
	if _target.get("back", false):
		# A sala é sua: volta direto, sem pergunta nem senha (o servidor reconhece o aparelho).
		_notice = ""
		_game.join_room(str(_target.get("id", "")))
		_refresh()
		return
	if _target.get("phase") == Protocol.PLAYING:
		_dialog.ask("A partida já começou", "Há lugar livre na mesa. Quer entrar e jogar?",
			["Entrar", "Voltar"])
		return
	_go()


func _on_dialog(index: int) -> void:
	if index == 0:
		_go()


## Entra na sala escolhida: com cadeado, pede a senha antes.
func _go() -> void:
	if bool(_target.get("locked", false)):
		_password_panel.open()
		return
	_notice = ""
	_game.join_room(str(_target.get("id", "")))
	_refresh()


func _on_code(text: String) -> void:
	var code: String = text.strip_edges().replace(" ", "").to_upper()
	if code.length() != 4:
		_code_panel.show_error("O código tem 4 letras e números.")
		return
	_target = {"id": code}
	_from_code = true
	_notice = ""
	_game.join_room(code)
	_refresh()


func _on_password(text: String) -> void:
	var clean: String = text.strip_edges()
	if not Room.is_password(clean):
		_password_panel.show_error("A senha tem 4 números.")
		return
	_game.join_room(str(_target.get("id", "")), clean)
	_refresh()


func _on_error(message: Dictionary) -> void:
	var code: String = str(message.get("code", ""))
	var text: String = _game.sentence(str(message.get("text", "")))
	if code == Protocol.E_PASSWORD:
		_code_panel.close()
		if not _password_panel.visible:
			_password_panel.open()
		if _game.password != "" or int(message.get("wait_ms", 0)) > 0:
			_password_panel.show_error(text)
		return
	if _code_panel.visible and _from_code:
		_code_panel.show_error("Sala não encontrada. Confira o código." if code == Protocol.E_NO_ROOM
			else text)
		return
	_password_panel.close()
	_notice = text


func go_back() -> bool:
	if _password_panel.visible:
		_password_panel.close()
	elif _code_panel.visible:
		_code_panel.close()
	elif _dialog.visible:
		_dialog.visible = false
	else:
		back.emit()
	return true
