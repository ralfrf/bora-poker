extends "res://ui/screens/screen.gd"
## Amigos à distância, primeiro passo (SPEC 9.3): os servidores, cada um com a % de
## lotação. A pergunta ao Servidor 1 começa assim que a tela abre, o que também o acorda
## (ele dorme depois de 15 minutos sem ninguém); sem resposta em 3 s
## aparece "Conectando ao servidor…" com o aviso. Cheio: "Cheio" (e a frase embaixo); sem
## resposta depois de 2 minutos: "Em manutenção". O Servidor 2 ainda não existe e aparece
## sempre "Em breve".
## Em "Avançado" dá para usar um servidor WebSocket próprio; o endereço do oficial não
## aparece na tela.

signal back
## Escolheu um servidor: endereço do WebSocket e o nome para mostrar.
signal chosen(address: String, server_name: String)

const Profile := preload("res://ui/app/profile.gd")
const LoadProbe := preload("res://net/load_probe.gd")
const RemoteGame := preload("res://ui/app/remote_game.gd")
const RoomRow := preload("res://ui/widgets/room_row.gd")
const EntryPanel := preload("res://ui/widgets/entry_panel.gd")
const AdBox := preload("res://ui/widgets/ad_box.gd")

const ROW_H: float = 62.0
const NAMES: Array[String] = ["Servidor 1", "Servidor 2"]

var profile: Profile = null
## A sonda do Servidor 1 (os testes e as fotos podem trocar).
var probe: LoadProbe = null

var _back: Button = null
var _title: Label = null
var _status: Label = null
var _rows: Array[RoomRow] = []
var _hint: Label = null
var _ad: AdBox = null
var _advanced: Button = null
var _enter: Button = null
var _panel: EntryPanel = null
var _notice: String = ""
var _shown: String = ""


## notice: aviso para mostrar ao abrir (por exemplo, a conexão que caiu).
func _init(owner_profile: Profile, notice: String = "") -> void:
	profile = owner_profile
	_notice = notice


func _build() -> void:
	probe = LoadProbe.new(profile.server_url)
	_back = Button.new()
	_back.text = "‹"
	_back.theme_type_variation = "QuietButton"
	_back.focus_mode = Control.FOCUS_NONE
	_back.pressed.connect(func() -> void: back.emit())
	add_child(_back)
	_title = Label.new()
	_title.theme_type_variation = "TitleLabel"
	_title.text = "Online"
	add_child(_title)
	_status = Label.new()
	_status.theme_type_variation = "StrongLabel"
	_status.text = "Escolha um servidor"
	add_child(_status)
	for i in NAMES.size():
		var row: RoomRow = RoomRow.new()
		row.title = NAMES[i]
		row.pressed.connect(_on_row.bind(i))
		add_child(row)
		_rows.append(row)
	_hint = Label.new()
	_hint.theme_type_variation = "SmallLabel"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_hint)
	_ad = AdBox.new()
	add_child(_ad)
	_advanced = action_button("Avançado", false)
	_advanced.pressed.connect(_open_advanced)
	add_child(_advanced)
	_enter = action_button("Entrar", true)
	_enter.pressed.connect(_on_row.bind(0))
	add_child(_enter)
	# O endereço do servidor oficial não aparece na tela: o campo fica vazio quando é ele.
	_panel = EntryPanel.new("Servidor próprio",
		"Para quem deseja conectar um serviço próprio de WebSocket (WS). Deixe vazio " \
		+ "para usar os servidores do Bora Poker.",
		"wss://seu-servidor.com", 200, LineEdit.KEYBOARD_TYPE_URL, "Salvar", 420.0)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.entered.connect(_on_address)
	add_child(_panel)
	_refresh()


func _exit_tree() -> void:
	if probe != null:
		probe.close()


func _process(delta: float) -> void:
	super(delta)
	if probe == null:
		return
	probe.poll()
	var key: String = "%d/%d/%s" % [probe.state, probe.pct, probe.full]
	if key != _shown:
		_refresh()


## O Servidor 1 aceita gente agora.
func available() -> bool:
	return probe != null and probe.state == LoadProbe.State.READY and not probe.full


func _refresh() -> void:
	_shown = "%d/%d/%s" % [probe.state, probe.pct, probe.full]
	var first: RoomRow = _rows[0]
	first.badge = ""
	match probe.state:
		LoadProbe.State.ASKING:
			first.detail = "Conectando ao servidor…"
		LoadProbe.State.WAKING:
			first.detail = "Conectando ao servidor…"
		LoadProbe.State.READY:
			if probe.full:
				first.detail = "Cheio agora. Tente de novo daqui a pouco."
			else:
				first.detail = "%d%% de lotação" % probe.pct
				first.badge = "%d%%" % probe.pct
		LoadProbe.State.DOWN:
			first.detail = "Em manutenção. Confira a internet do celular e tente de novo mais tarde."
		LoadProbe.State.OFFLINE:
			first.detail = "Sem internet. Confira o Wi-Fi ou os dados móveis."
		LoadProbe.State.OLD:
			first.detail = "Atualize o app para usar este servidor"
	if profile.server_url != "" and LoadProbe.normalize(profile.server_url) != LoadProbe.DEFAULT_URL:
		first.detail += " · servidor próprio"
	first.disabled = not available()
	first.queue_redraw()
	var second: RoomRow = _rows[1]
	second.detail = "Em breve"
	second.disabled = true
	second.queue_redraw()
	_enter.disabled = not available()
	# O aviso fixo fica sempre (pedido do dono, 18/11/2026); cheio e sem resposta vão
	# na linha do servidor, para caber ao lado do quadro de anúncio.
	var tips: Array[String] = []
	if _notice != "":
		tips.append(_notice)
	tips.append(RemoteGame.wake_tip())
	_hint.text = "\n".join(tips)
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
	for i in _rows.size():
		place(_rows[i], Rect2(b.position.x, top + i * (ROW_H + 8.0), b.size.x, ROW_H))
	var hint_top: float = top + _rows.size() * (ROW_H + 8.0)
	# Quadro de anúncio no canto de baixo, embaixo da lista; o aviso fica ao lado dele.
	var ad_size: Vector2 = AdBox.SIZE
	place(_ad, Rect2(b.position.x, b.end.y - ad_size.y, ad_size.x, ad_size.y))
	var hint_left: float = b.position.x + ad_size.x + 14.0
	place(_hint, Rect2(hint_left, hint_top, maxf(40.0, b.end.x - hint_left),
		maxf(20.0, b.end.y - hint_top)))
	place(_enter, Rect2(col.position.x, col.end.y - BUTTON_H, col.size.x, BUTTON_H))
	place(_advanced, Rect2(col.position.x, col.end.y - BUTTON_H * 2.0 - 10.0, col.size.x, BUTTON_H))


func _on_row(index: int) -> void:
	if index == 0 and available():
		chosen.emit(probe.url, NAMES[0])


func _open_advanced() -> void:
	_panel.open(profile.server_url)


func _on_address(text: String) -> void:
	var clean: String = text.strip_edges()
	if clean != "" and not LoadProbe.is_valid(clean):
		_panel.show_error("Endereço inválido. Exemplo: wss://seu-servidor.com")
		return
	_panel.close()
	var normalized: String = LoadProbe.normalize(clean)
	profile.server_url = "" if normalized == LoadProbe.DEFAULT_URL else normalized
	profile.save()
	_notice = ""
	probe.close()
	probe = LoadProbe.new(profile.server_url)
	_refresh()


func go_back() -> bool:
	if _panel.visible:
		_panel.close()
	else:
		back.emit()
	return true
