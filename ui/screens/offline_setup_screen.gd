extends "res://ui/screens/screen.gd"
## Criar mesa offline (SPEC 4.1): formato, lugares de 2 a 9 (você e os bots), nível dos
## bots, fichas, blinds ou tempo por nível, tempo por jogada e recompra. As escolhas
## ficam guardadas para a próxima vez.
##
## A mesma tela cria a sala do Wi-Fi (wifi verdadeiro): sem bots (o dono põe na sala de
## espera) e com "Manter sala aberta" no clássico.

signal start(choice: Dictionary)
signal back

const Profile := preload("res://ui/app/profile.gd")
const OfflineOptions := preload("res://ui/app/offline_options.gd")
const ChoiceRow := preload("res://ui/widgets/choice_row.gd")
const Stepper := preload("res://ui/widgets/stepper.gd")
const Roster := preload("res://bots/roster.gd")

const ROW_H: float = 62.0
const PLURALS: Dictionary = {1: "fáceis", 2: "médios", 3: "difíceis"}

var profile: Profile = null
var choice: Dictionary = {}

var _back: Button = null
var _title: Label = null
var _format: ChoiceRow = null
var _seats: Stepper = null
var _bots: ChoiceRow = null
var _stack: ChoiceRow = null
var _blinds: ChoiceRow = null
var _minutes: ChoiceRow = null
var _turn: ChoiceRow = null
var _rebuys: ChoiceRow = null
var _keep: ChoiceRow = null
var _wifi: bool = false
var _summary_big: Label = null
var _summary: Label = null
var _start: Button = null


func _init(owner_profile: Profile, wifi: bool = false) -> void:
	profile = owner_profile
	_wifi = wifi


func _build() -> void:
	choice = OfflineOptions.clean(profile.wifi if _wifi else profile.offline)
	_back = Button.new()
	_back.text = "‹"
	_back.theme_type_variation = "QuietButton"
	_back.focus_mode = Control.FOCUS_NONE
	_back.pressed.connect(func() -> void: back.emit())
	add_child(_back)
	_title = Label.new()
	_title.theme_type_variation = "TitleLabel"
	_title.text = "Criar sala" if _wifi else "Mesa offline"
	add_child(_title)

	_format = ChoiceRow.new("Formato", OfflineOptions.FORMAT_LABELS, choice["format"])
	_format.changed.connect(_choose.bind("format"))
	_seats = Stepper.new("Lugares na mesa", choice["seats"], OfflineOptions.MIN_SEATS,
		OfflineOptions.MAX_SEATS, "lugares")
	_seats.changed.connect(_choose.bind("seats"))
	_bots = ChoiceRow.new("Nível dos bots", OfflineOptions.BOT_LABELS, choice["bots"])
	_bots.changed.connect(_choose.bind("bots"))
	_stack = ChoiceRow.new("Fichas iniciais", OfflineOptions.stack_labels(false), 0, true)
	_stack.changed.connect(_on_stack)
	_blinds = ChoiceRow.new("Blinds", OfflineOptions.blind_labels(), choice["blinds"], true,
		true)
	_blinds.changed.connect(_choose.bind("blinds"))
	_minutes = ChoiceRow.new("Blinds sobem a cada", OfflineOptions.minute_labels(),
		choice["minutes"])
	_minutes.changed.connect(_choose.bind("minutes"))
	_turn = ChoiceRow.new("Tempo por jogada", OfflineOptions.TURN_LABELS, choice["turn"])
	_turn.changed.connect(_choose.bind("turn"))
	_rebuys = ChoiceRow.new("Recompras", OfflineOptions.REBUY_LABELS, choice["rebuys"])
	_rebuys.changed.connect(_choose.bind("rebuys"))
	_keep = ChoiceRow.new("Manter sala aberta", OfflineOptions.KEEP_OPEN_LABELS,
		choice["keep_open"])
	_keep.changed.connect(_choose.bind("keep_open"))
	for row: Control in [_format, _seats, _bots, _turn, _stack, _blinds, _minutes, _rebuys, _keep]:
		add_child(row)
	_bots.visible = not _wifi

	_summary_big = Label.new()
	_summary_big.theme_type_variation = "TitleLabel"
	_summary_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_summary_big)
	_summary = Label.new()
	_summary.theme_type_variation = "SmallLabel"
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_summary)
	_start = action_button("Criar sala" if _wifi else "Começar", true)
	_start.pressed.connect(_on_start)
	add_child(_start)
	_refresh()


func _layout() -> void:
	var b: Rect2 = body()
	var col: Rect2 = column()
	place(_back, Rect2(b.position.x, b.position.y - 2.0, 44, 40))
	place(_title, Rect2(b.position.x + 56.0, b.position.y, b.size.x - 56.0, 36))
	var top: float = b.position.y + 50.0
	var gap: float = 20.0
	# A coluna da direita é mais larga: os blinds têm os textos mais longos.
	var w: float = (b.size.x - gap) * 0.46
	var right_w: float = b.size.x - gap - w
	var spare: float = b.end.y - top - ROW_H * 4.0
	var step: float = ROW_H + clampf(spare / 3.0, 0.0, 14.0)
	var left: Array[Control] = [_format, _seats, _bots, _turn]
	if _wifi:
		left = [_format, _seats, _turn]
		if not OfflineOptions.is_tournament(choice):
			left.append(_keep)
	var right: Array[Control] = [_stack]
	if OfflineOptions.is_tournament(choice):
		right.append(_minutes)
	else:
		right.append_array([_blinds, _rebuys])
	for i in left.size():
		place(left[i], Rect2(b.position.x, top + i * step, w, ROW_H))
	for i in right.size():
		place(right[i], Rect2(b.position.x + w + gap, top + i * step, right_w, ROW_H))
	place(_start, Rect2(col.position.x, col.end.y - BUTTON_H, col.size.x, BUTTON_H))
	place(_summary_big, Rect2(col.position.x, col.position.y + 44.0, col.size.x, 32))
	place(_summary, Rect2(col.position.x, col.position.y + 80.0, col.size.x, 60))


func _choose(value: int, key: String) -> void:
	choice[key] = value
	_refresh()


func _on_stack(index: int) -> void:
	choice["t_stack" if OfflineOptions.is_tournament(choice) else "stack"] = index
	_refresh()


func _refresh() -> void:
	var tournament: bool = OfflineOptions.is_tournament(choice)
	_stack.set_labels(OfflineOptions.stack_labels(tournament),
		choice["t_stack" if tournament else "stack"])
	_blinds.visible = not tournament
	_rebuys.visible = not tournament
	_minutes.visible = tournament
	_keep.visible = _wifi and not tournament
	var bots: int = int(choice["seats"]) - 1
	_summary_big.text = "%d lugares" % int(choice["seats"])
	if _wifi:
		_summary.text = "Você e até %d %s. Bots, se quiser, na sala de espera." % [
			bots, "amigo" if bots == 1 else "amigos"]
		if is_node_ready():
			_layout()
		return
	var level: int = OfflineOptions.BOT_LEVELS[int(choice["bots"])]
	var level_text: String = "de níveis variados" if level == 0 \
		else PLURALS[level]
	if bots == 1:
		level_text = Roster.LEVEL_NAMES[OfflineOptions.bot_levels(choice)[0]].to_lower()
	_summary.text = "Você e %s %s" % ["1 bot" if bots == 1 else "%d bots" % bots, level_text]
	if is_node_ready():
		_layout()


func _on_start() -> void:
	if _wifi:
		profile.wifi = choice.duplicate()
		profile.save()
		start.emit(choice.duplicate())
		return
	profile.offline = choice.duplicate()
	profile.last_mode = Profile.MODE_OFFLINE
	profile.save()
	start.emit(choice.duplicate())


func go_back() -> bool:
	back.emit()
	return true
