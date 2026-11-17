extends "res://ui/screens/screen.gd"
## Sala de espera do Wi-Fi e à distância (SPEC 11.1, item 5): quem já entrou, os bots, as opções e o
## código da sala. O dono põe e tira bots, expulsa e começa a partida; os outros
## esperam. Cada um troca o próprio avatar tocando no seu lugar. Quando a partida
## começa, a mesa abre (sinal started).

signal started
## Saiu da sala, foi expulso, a sala fechou ou a conexão falhou. notice: o porquê.
signal finished(notice: String)
## Trocou o avatar (quem abriu a tela guarda no perfil).
signal avatar_changed(avatar: int)

const GameSession := preload("res://ui/app/game_session.gd")
const Dialog := preload("res://ui/widgets/dialog.gd")
const Paint := preload("res://ui/widgets/paint.gd")
const AvatarButton := preload("res://ui/widgets/avatar_button.gd")
const Roster := preload("res://bots/roster.gd")
const Money := preload("res://engine/money.gd")
const Protocol := preload("res://server/protocol.gd")
const AvatarPicker := preload("res://ui/widgets/avatar_picker.gd")

const CHIP_H: float = 46.0
const TURN_TEXT: Dictionary = {0: "sem limite de tempo", 15: "15 s por jogada",
	30: "30 s por jogada", 60: "60 s por jogada"}


## Um lugar da mesa: avatar, apelido e, embaixo, quem é (você, dono, bot) ou "Lugar livre".
class SeatChip:
	extends Button

	var nick: String = ""
	var avatar: int = 0
	var detail: String = ""
	var empty: bool = true

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE

	func _draw() -> void:
		var box: StyleBoxFlat = StyleBoxFlat.new()
		var alpha: float = 0.35 if empty else (0.92 if not is_pressed() else 0.6)
		box.bg_color = Color(get_theme_color("surface", "Tokens"), alpha)
		box.border_color = get_theme_color("surface_line", "Tokens")
		box.set_border_width_all(1)
		box.set_corner_radius_all(int(size.y / 2.0))
		box.anti_aliasing = true
		draw_style_box(box, Rect2(Vector2.ZERO, size))
		var small: int = get_theme_font_size("small", "Tokens")
		if empty:
			draw_string(get_theme_font("text", "Tokens"), Vector2(16, size.y / 2.0 + small / 2.0 - 1.0),
				"Lugar livre", HORIZONTAL_ALIGNMENT_LEFT, size.x - 24.0, small,
				get_theme_color("text_dim", "Tokens"))
			return
		var r: float = size.y / 2.0 - 5.0
		var center: Vector2 = Vector2(size.y / 2.0, size.y / 2.0)
		Paint.avatar(self, Rect2(center - Vector2.ONE * r, Vector2.ONE * r * 2.0), avatar,
			AvatarButton.colors_of(self), 0, 0.0)
		var left: float = size.y + 2.0
		var width: float = size.x - left - 12.0
		draw_string(get_theme_font("strong", "Tokens"), Vector2(left, size.y / 2.0 - 2.0),
			nick, HORIZONTAL_ALIGNMENT_LEFT, width, small, get_theme_color("text", "Tokens"))
		draw_string(get_theme_font("text", "Tokens"), Vector2(left, size.y / 2.0 + small + 1.0),
			detail, HORIZONTAL_ALIGNMENT_LEFT, width, small, get_theme_color("text_dim", "Tokens"))


var _game: GameSession = null
var _back: Button = null
var _title: Label = null
var _summary: Label = null
var _code_title: Label = null
var _code: Label = null
var _hint: Label = null
var _chips: Array[SeatChip] = []
var _watching: Label = null
var _bot_title: Label = null
var _bot_buttons: Array[Button] = []
var _status: Label = null
var _start: Button = null
var _dialog: Dialog = null
## Mostrando a pergunta "Quer entrar e jogar?" (partida em andamento com vaga).
var _asking_seat: bool = false
var _picker: AvatarPicker = null
var _seat_ids: Array[String] = []
var _pending_kick: String = ""
var _done: bool = false
var _last_status: String = ""


## game: a sessão já aberta (anfitrião) ou conectando (convidado).
func _init(game: GameSession) -> void:
	_game = game


func _build() -> void:
	_back = Button.new()
	_back.text = "‹"
	_back.theme_type_variation = "QuietButton"
	_back.focus_mode = Control.FOCUS_NONE
	_back.pressed.connect(_ask_leave)
	add_child(_back)
	_title = Label.new()
	_title.theme_type_variation = "TitleLabel"
	_title.text = "Entrando na sala…"
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_title)
	_summary = Label.new()
	_summary.theme_type_variation = "SmallLabel"
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_summary)
	_code_title = Label.new()
	_code_title.theme_type_variation = "SmallLabel"
	_code_title.text = "Código da sala"
	_code_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_code_title)
	_code = Label.new()
	_code.theme_type_variation = "TitleLabel"
	_code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_code)
	_hint = Label.new()
	_hint.theme_type_variation = "SmallLabel"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_hint)
	for i in 9:
		var chip: SeatChip = SeatChip.new()
		chip.visible = false
		chip.pressed.connect(_on_seat.bind(i))
		add_child(chip)
		_chips.append(chip)
	_watching = Label.new()
	_watching.theme_type_variation = "SmallLabel"
	_watching.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_watching)
	_bot_title = Label.new()
	_bot_title.theme_type_variation = "SmallLabel"
	_bot_title.text = "Pôr bot"
	add_child(_bot_title)
	for level: int in Roster.LEVELS:
		var button: Button = Button.new()
		button.text = Roster.LEVEL_NAMES[level]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void:
			_game.owner(Protocol.CMD_ADD_BOT, {"level": level}))
		add_child(button)
		_bot_buttons.append(button)
	_status = Label.new()
	_status.theme_type_variation = "SmallLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_status)
	_start = action_button("Começar", true)
	_start.pressed.connect(func() -> void: _game.start())
	add_child(_start)
	_dialog = Dialog.new()
	_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dialog.chosen.connect(_on_dialog)
	add_child(_dialog)
	_picker = AvatarPicker.new()
	_picker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_picker.picked.connect(func(avatar: int) -> void:
		_game.set_avatar(avatar)
		avatar_changed.emit(avatar))
	add_child(_picker)
	_refresh()


func _process(delta: float) -> void:
	super(delta)
	if _done:
		return
	# O state da partida em andamento pode ter chegado junto com o "joined", ainda na
	# lista de salas (à distância, sala aberta em partida).
	if _game.last_state.get("room", {}).get("phase") == Protocol.PLAYING:
		_done = true
		started.emit()
		return
	var changed: bool = false
	for message: Dictionary in _game.update():
		match message.get("t"):
			Protocol.STATE:
				changed = true
				if message.get("room", {}).get("phase") == Protocol.PLAYING:
					_done = true
					started.emit()
					return
			Protocol.CLOSED:
				_finish(_game.closed_notice())
				return
			Protocol.LEFT:
				if message.get("reason") == Protocol.R_KICKED:
					_finish("O dono da sala tirou você da sala.")
					return
				if not _game.pending_exit():
					_finish(_game.failure())
					return
			Protocol.ERROR:
				if not _game.failed():
					_status.text = str(message.get("text", ""))
	if _game.failed():
		_finish(_game.error_text)
		return
	if _game.confirm_seat and not _asking_seat:
		_asking_seat = true
		_dialog.dismissable = false
		_dialog.ask("A partida já começou", "Há lugar livre na mesa. Quer entrar e jogar?",
			["Entrar", "Voltar"])
	if _game.status_text() != _last_status:
		_last_status = _game.status_text()
		changed = true
	if changed:
		_refresh()


func _finish(notice: String) -> void:
	if _done:
		return
	_done = true
	_game.shutdown()
	finished.emit(notice)


func _refresh() -> void:
	var state: Dictionary = _game.last_state
	var room: Dictionary = state.get("room", {})
	var owner: bool = _game.is_owner()
	var options: Dictionary = room.get("options", {})
	var seats: int = int(options.get("seats", 0))
	_title.text = str(room.get("name", "Entrando na sala…"))
	_summary.text = _options_text(options) if not options.is_empty() else ""
	_code.text = _game.room_code()
	_code_title.visible = _code.text != ""
	_hint.text = _game.waiting_hint()
	var by_seat: Dictionary = {}
	var watchers: Array[String] = []
	for member: Dictionary in room.get("members", []):
		if int(member.get("seat", -1)) >= 0:
			by_seat[int(member["seat"])] = member
		elif not member.get("bot", false):
			watchers.append(str(member.get("nick", "")))
	_seat_ids.clear()
	var players: int = 0
	var can_sit: bool = bool(state.get("you", {}).get("can_sit", false))
	for i in _chips.size():
		var chip: SeatChip = _chips[i]
		chip.visible = i < seats
		var member: Dictionary = by_seat.get(i, {})
		chip.empty = member.is_empty()
		_seat_ids.append(str(member.get("id", "")))
		if not chip.empty:
			players += 1
			chip.nick = str(member.get("nick", ""))
			chip.avatar = int(member.get("avatar", 0))
			chip.detail = _member_text(member, room)
		# Quem assiste (entrou com a sala cheia) toca num lugar livre para sentar.
		chip.disabled = (chip.empty and not can_sit) \
			or (not chip.empty and not owner and member.get("id") != _game.my_id)
		chip.queue_redraw()
	_watching.text = "Assistindo: " + ", ".join(watchers) if not watchers.is_empty() else ""
	var can_add: bool = owner and players < seats
	_bot_title.visible = owner
	for button: Button in _bot_buttons:
		button.visible = owner
		button.disabled = not can_add
	_start.visible = owner
	_start.disabled = players < 2
	if _game.status_text() != "":
		_status.text = _game.status_text()
	elif state.is_empty():
		_status.text = "Conectando…"
	elif owner:
		_status.text = ("Precisa de pelo menos 2 na mesa (bots contam). " if players < 2
			else "Toque num bot ou jogador para tirar da sala. ") \
			+ "No seu lugar, para trocar o avatar."
	elif int(state.get("you", {}).get("seat", -1)) < 0:
		_status.text = "Toque num lugar livre para sentar." if can_sit \
			else "A sala está cheia: você está assistindo. Quando abrir um lugar, toque nele."
	else:
		_status.text = "Esperando o dono começar a partida. Toque no seu lugar para " \
			+ "trocar o avatar."
	_layout()


func _member_text(member: Dictionary, room: Dictionary) -> String:
	if member.get("bot", false):
		return "Bot " + str(Roster.LEVEL_NAMES.get(int(member.get("level", 0)), "")).to_lower()
	var parts: Array[String] = []
	if member.get("id") == _game.my_id:
		parts.append("Você")
	if member.get("id") == room.get("owner"):
		parts.append("dono da sala")
	if not member.get("connected", true):
		parts.append("reconectando…")
	return " · ".join(parts) if not parts.is_empty() else "Na mesa"


static func _options_text(options: Dictionary) -> String:
	var parts: Array[String] = []
	var tournament: bool = options.get("format") == "tournament"
	parts.append("Torneio" if tournament else "Clássico")
	parts.append("fichas iniciais " + Money.format(int(options.get("starting_stack", 0))))
	if tournament:
		parts.append("blinds sobem a cada %d min" % int(options.get("level_minutes", 5)))
	else:
		parts.append("blinds %s/%s" % [Money.format(int(options.get("small_blind", 0))),
			Money.format(int(options.get("big_blind", 0)))])
		var limit: int = int(options.get("rebuy_limit", -1))
		parts.append("recompra sem limite" if limit < 0 else ("sem recompra" if limit == 0
			else "%d %s" % [limit, "recompra" if limit == 1 else "recompras"]))
		if options.get("keep_open", false):
			parts.append("sala aberta")
	parts.append(TURN_TEXT.get(int(options.get("turn_seconds", 30)), ""))
	return " · ".join(parts)


func _layout() -> void:
	if _title == null:
		return
	var b: Rect2 = body()
	var col: Rect2 = column()
	place(_back, Rect2(b.position.x, b.position.y - 2.0, 44, 40))
	var code_w: float = 120.0 if _code.text != "" else 0.0
	place(_title, Rect2(b.position.x + 56.0, b.position.y, b.size.x - 56.0 - code_w, 36))
	place(_code_title, Rect2(b.end.x - code_w, b.position.y - 4.0, code_w, 18))
	place(_code, Rect2(b.end.x - code_w, b.position.y + 12.0, code_w, 34))
	place(_summary, Rect2(b.position.x + 56.0, b.position.y + 36.0, b.size.x - 56.0 - code_w, 34))
	var top: float = b.position.y + 76.0
	var cols: int = 3
	var gap: float = 8.0
	var w: float = (b.size.x - gap * (cols - 1)) / cols
	var visible_count: int = 0
	for i in _chips.size():
		if not _chips[i].visible:
			continue
		@warning_ignore("integer_division")
		var row: int = visible_count / cols
		var c: int = visible_count % cols
		place(_chips[i], Rect2(b.position.x + c * (w + gap), top + row * (CHIP_H + gap), w, CHIP_H))
		visible_count += 1
	@warning_ignore("integer_division")
	var rows: int = (visible_count + cols - 1) / cols
	var after: float = top + rows * (CHIP_H + gap)
	place(_watching, Rect2(b.position.x, after, b.size.x, 20))
	place(_hint, Rect2(b.position.x, after + (24.0 if _watching.text != "" else 0.0), b.size.x,
		maxf(20.0, b.end.y - after)))
	var y: float = col.position.y
	place(_bot_title, Rect2(col.position.x, y, col.size.x, 18))
	y += 22.0
	for button: Button in _bot_buttons:
		place(button, Rect2(col.position.x, y, col.size.x, 40))
		y += 46.0
	place(_start, Rect2(col.position.x, col.end.y - BUTTON_H, col.size.x, BUTTON_H))
	var status_top: float = y + 4.0 if _game.is_owner() else col.position.y + 40.0
	place(_status, Rect2(col.position.x, status_top, col.size.x,
		maxf(20.0, col.end.y - BUTTON_H - 8.0 - status_top)))


func _on_seat(index: int) -> void:
	if index >= _seat_ids.size():
		return
	if _seat_ids[index] == "":
		# Lugar livre: quem está assistindo senta nele.
		if _game.last_state.get("you", {}).get("can_sit", false):
			_game.sit_at(index)
		return
	var target: String = _seat_ids[index]
	if target == _game.my_id:
		for member: Dictionary in _game.last_state.get("room", {}).get("members", []):
			if member.get("id") == target:
				_picker.open(int(member.get("avatar", 0)))
		return
	for member: Dictionary in _game.last_state.get("room", {}).get("members", []):
		if member.get("id") != target:
			continue
		if member.get("bot", false):
			_game.owner(Protocol.CMD_REMOVE_BOT, {"id": target})
		else:
			_pending_kick = target
			_dialog.ask("Tirar %s da sala?" % member.get("nick", ""),
				"Quem sai assim não consegue entrar de novo nesta sala.", ["Tirar", "Cancelar"])
		return


func _ask_leave() -> void:
	_pending_kick = ""
	if _game.is_host and not _game.failed():
		var question: Array[String] = _game.leave_question()
		if question[2] == "Sair":
			_dialog.ask("Sair da sala?", "A sala continua no celular de outro jogador.",
				["Sair", "Continuar"])
		else:
			_dialog.ask("Fechar a sala?", "Quem já entrou volta para a lista de salas.",
				["Fechar", "Continuar"])
	else:
		_game.leave()
		_finish("")


func _on_dialog(index: int) -> void:
	if _asking_seat:
		_asking_seat = false
		_dialog.dismissable = true
		if index == 0:
			_game.confirm_join()
		else:
			_game.leave()
			_finish("")
		return
	if index != 0:
		_pending_kick = ""
		return
	if _pending_kick != "":
		_game.owner(Protocol.CMD_KICK, {"id": _pending_kick})
		_pending_kick = ""
		return
	_game.leave()
	_finish(_game.failure() if _game.is_host else "")


func go_back() -> bool:
	if _asking_seat:
		_dialog.visible = false
		_on_dialog(1)
	elif _picker.visible:
		_picker.close()
	elif _dialog.visible:
		_dialog.visible = false
	else:
		_ask_leave()
	return true
