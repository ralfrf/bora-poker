extends "res://ui/screens/screen.gd"
## Mesmo Wi-Fi (SPEC 9.2 e 11.1): as salas anunciadas na rede aparecem sozinhas; tocar
## numa entra nela. Na coluna, "Criar sala" e "Entrar por código" (para quando a sala
## não aparece: rede que bloqueia broadcast, ou iPhone).

signal back
signal create
signal join(ip: String, port: int)

const Discovery := preload("res://net/discovery.gd")
const RoomCode := preload("res://net/room_code.gd")
const WsServer := preload("res://net/ws_server.gd")
const Dialog := preload("res://ui/widgets/dialog.gd")

const ROW_H: float = 58.0
const MAX_ROWS: int = 4
const FORMAT_NAMES: Dictionary = {"classic": "Clássico", "tournament": "Torneio"}


## Uma sala da lista: nome e, embaixo, formato, ocupação e se já está em partida.
class RoomRow:
	extends Button

	var title: String = ""
	var detail: String = ""

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE

	func _draw() -> void:
		var box: StyleBoxFlat = StyleBoxFlat.new()
		box.bg_color = Color(get_theme_color("surface", "Tokens"), 0.92 if not is_pressed() else 0.6)
		box.border_color = get_theme_color("surface_line", "Tokens")
		box.set_border_width_all(1)
		box.set_corner_radius_all(12)
		box.anti_aliasing = true
		draw_style_box(box, Rect2(Vector2.ZERO, size))
		var body: int = get_theme_font_size("body", "Tokens")
		var small: int = get_theme_font_size("small", "Tokens")
		var width: float = size.x - 32.0
		draw_string(get_theme_font("strong", "Tokens"), Vector2(16, size.y / 2.0 - 3.0), title,
			HORIZONTAL_ALIGNMENT_LEFT, width, body, get_theme_color("text", "Tokens"))
		draw_string(get_theme_font("text", "Tokens"), Vector2(16, size.y / 2.0 + small + 2.0),
			detail, HORIZONTAL_ALIGNMENT_LEFT, width, small, get_theme_color("text_dim", "Tokens"))
		draw_string(get_theme_font("strong", "Tokens"), Vector2(size.x - 40.0, size.y / 2.0 + 7.0),
			"›", HORIZONTAL_ALIGNMENT_LEFT, -1, body + 6, get_theme_color("accent", "Tokens"))


## Entrada do código: caixa de texto e dois botões, por cima da tela.
class CodePanel:
	extends Control

	signal entered(code: String)

	var field: LineEdit = null
	var _panel: PanelContainer = null
	var _error: Label = null

	func _init() -> void:
		visible = false
		mouse_filter = Control.MOUSE_FILTER_STOP
		_panel = PanelContainer.new()
		_panel.theme_type_variation = "DialogPanel"
		add_child(_panel)
		var rows: VBoxContainer = VBoxContainer.new()
		rows.add_theme_constant_override("separation", 10)
		_panel.add_child(rows)
		var title: Label = Label.new()
		title.theme_type_variation = "TitleLabel"
		title.text = "Código da sala"
		rows.add_child(title)
		var hint: Label = Label.new()
		hint.theme_type_variation = "DimLabel"
		hint.text = "Aparece na sala de espera do anfitrião."
		rows.add_child(hint)
		field = LineEdit.new()
		field.placeholder_text = "Ex.: K7 MP"
		field.max_length = 5
		field.alignment = HORIZONTAL_ALIGNMENT_CENTER
		field.context_menu_enabled = false
		field.custom_minimum_size = Vector2(320, 52)
		field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
		field.text_submitted.connect(func(text: String) -> void: entered.emit(text))
		field.text_changed.connect(func(_text: String) -> void: _error.text = "")
		rows.add_child(field)
		_error = Label.new()
		_error.theme_type_variation = "SmallLabel"
		rows.add_child(_error)
		var buttons: HBoxContainer = HBoxContainer.new()
		buttons.alignment = BoxContainer.ALIGNMENT_END
		buttons.add_theme_constant_override("separation", 10)
		rows.add_child(buttons)
		var cancel: Button = Button.new()
		cancel.text = "Cancelar"
		cancel.focus_mode = Control.FOCUS_NONE
		cancel.custom_minimum_size = Vector2(136, 48)
		cancel.pressed.connect(close)
		buttons.add_child(cancel)
		var ok: Button = Button.new()
		ok.text = "Entrar"
		ok.theme_type_variation = "PrimaryButton"
		ok.focus_mode = Control.FOCUS_NONE
		ok.custom_minimum_size = Vector2(136, 48)
		ok.pressed.connect(func() -> void: entered.emit(field.text))
		buttons.add_child(ok)

	func open() -> void:
		field.text = ""
		_error.text = ""
		_error.add_theme_color_override("font_color", get_theme_color("danger", "Tokens"))
		visible = true
		_place()
		field.grab_focus()

	func close() -> void:
		field.release_focus()
		visible = false

	func show_error(text: String) -> void:
		_error.text = text

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED and visible:
			_place()

	func _place() -> void:
		_panel.reset_size()
		var panel_size: Vector2 = _panel.get_combined_minimum_size()
		_panel.size = panel_size
		# No alto, para o teclado do celular não cobrir.
		_panel.position = Vector2(((size.x - panel_size.x) / 2.0), maxf(12.0, size.y * 0.06)).round()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(get_theme_color("shadow", "Tokens"), 0.6))


var _listener: Discovery.Listener = null
var _back: Button = null
var _title: Label = null
var _status: Label = null
var _hint: Label = null
var _rows: Array[RoomRow] = []
var _create: Button = null
var _code: Button = null
var _panel: CodePanel = null
var _rooms: Array = []
var _notice: String = ""


## notice: aviso para mostrar ao abrir (por exemplo, "A sala foi encerrada").
func _init(notice: String = "") -> void:
	_notice = notice


func _build() -> void:
	_listener = Discovery.Listener.new()
	var listening: bool = _listener.listen() == OK
	_back = Button.new()
	_back.text = "‹"
	_back.theme_type_variation = "QuietButton"
	_back.focus_mode = Control.FOCUS_NONE
	_back.pressed.connect(func() -> void: back.emit())
	add_child(_back)
	_title = Label.new()
	_title.theme_type_variation = "TitleLabel"
	_title.text = "Mesma rede"
	add_child(_title)
	_status = Label.new()
	_status.theme_type_variation = "StrongLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	_hint = Label.new()
	_hint.theme_type_variation = "SmallLabel"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_hint)
	for i in MAX_ROWS:
		var row: RoomRow = RoomRow.new()
		row.visible = false
		row.pressed.connect(_on_row.bind(i))
		add_child(row)
		_rows.append(row)
	_code = action_button("Usar código", false)
	_code.pressed.connect(func() -> void: _panel.open())
	add_child(_code)
	_create = action_button("Criar sala", true)
	_create.pressed.connect(func() -> void: create.emit())
	add_child(_create)
	_panel = CodePanel.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.entered.connect(_on_code)
	add_child(_panel)
	if not listening:
		_notice = "Não deu para procurar salas neste celular. Use o código da sala."
	_refresh()


func _exit_tree() -> void:
	if _listener != null:
		_listener.close()


func _process(delta: float) -> void:
	super(delta)
	if _listener != null and _listener.poll():
		_refresh()


func _refresh() -> void:
	_rooms = _listener.list() if _listener != null else []
	var no_wifi: bool = RoomCode.local_ip() == ""
	if _rooms.is_empty():
		_status.text = "Sem Wi-Fi." if no_wifi else "Procurando salas nesta rede…"
	else:
		_status.text = "Salas nesta rede"
	var tips: Array[String] = []
	if _notice != "":
		tips.append(_notice)
	if no_wifi:
		tips.append("Conecte o celular ao mesmo Wi-Fi dos amigos ou ao ponto de acesso de um deles.")
	elif _rooms.is_empty():
		tips.append("Se a sala do seu amigo não aparecer, peça o código a ele. Redes de convidados " \
			+ "e alguns roteadores bloqueiam a conversa entre celulares; aí o anfitrião pode " \
			+ "ligar o ponto de acesso do celular e os outros se conectam nele.")
	_hint.text = "\n".join(tips)
	for i in MAX_ROWS:
		var row: RoomRow = _rows[i]
		row.visible = i < _rooms.size()
		if row.visible:
			var room: Dictionary = _rooms[i]
			row.title = str(room["name"])
			var parts: Array[String] = [FORMAT_NAMES.get(room["format"], ""),
				"%d de %d lugares" % [int(room["players"]), int(room["seats"])]]
			if room["phase"] == "playing":
				# Só assiste quem já estava na sala: sem vaga, não dá para entrar (SPEC 4.3).
				parts.append("em partida" + (", com vaga" if room["open"] else ", sem vaga"))
			elif not room["open"]:
				parts.append("cheia")
			row.detail = " · ".join(parts)
			row.queue_redraw()
	_layout()


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
	var shown: int = 0
	for row: RoomRow in _rows:
		if row.visible:
			place(row, Rect2(b.position.x, top + shown * (ROW_H + 8.0), b.size.x, ROW_H))
			shown += 1
	var hint_top: float = top + shown * (ROW_H + 8.0)
	place(_hint, Rect2(b.position.x, hint_top, b.size.x, maxf(20.0, b.end.y - hint_top)))
	place(_create, Rect2(col.position.x, col.end.y - BUTTON_H, col.size.x, BUTTON_H))
	place(_code, Rect2(col.position.x, col.end.y - BUTTON_H * 2.0 - 10.0, col.size.x, BUTTON_H))


func _on_row(index: int) -> void:
	if index < _rooms.size():
		join.emit(str(_rooms[index]["ip"]), int(_rooms[index]["port"]))


func _on_code(text: String) -> void:
	var own: String = RoomCode.local_ip()
	if own == "":
		_panel.show_error("Conecte o celular ao Wi-Fi primeiro.")
		return
	var ip: String = RoomCode.decode(text, own)
	if ip == "":
		_panel.show_error("Código inválido. Confira as 4 letras e números.")
		return
	_panel.close()
	join.emit(ip, WsServer.PORT)


func go_back() -> bool:
	if _panel.visible:
		_panel.close()
	else:
		back.emit()
	return true
