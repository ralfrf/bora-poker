extends Control
## Painel das reações (SPEC 11.2), aberto pelo botão de balão na mesa: as carinhas numa
## linha e as frases prontas embaixo. Um toque manda a reação e fecha; tocar fora fecha.
## Ocupa a tela toda (invisível) só para pegar o toque fora do painel.

signal chosen(index: int)

const Protocol := preload("res://server/protocol.gd")
const ReactionView := preload("res://ui/widgets/reaction_view.gd")

const FACE_BUTTON: float = 40.0
const PHRASE_H: float = 34.0

var _panel: PanelContainer = null


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_panel = PanelContainer.new()
	_panel.theme_type_variation = "DialogPanel"
	add_child(_panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	var faces: HBoxContainer = HBoxContainer.new()
	faces.add_theme_constant_override("separation", 6)
	box.add_child(faces)
	for i in Protocol.REACTION_FACES:
		var button: Button = Button.new()
		button.theme_type_variation = "QuietButton"
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(FACE_BUTTON, FACE_BUTTON)
		button.tooltip_text = Protocol.REACTIONS[i]
		var face: ReactionView = ReactionView.new()
		face.bare = true
		face.index = i
		face.size = Vector2(FACE_BUTTON, FACE_BUTTON)
		button.add_child(face)
		button.pressed.connect(_pick.bind(i))
		faces.add_child(button)
	var phrases: GridContainer = GridContainer.new()
	phrases.columns = 2
	phrases.add_theme_constant_override("h_separation", 6)
	phrases.add_theme_constant_override("v_separation", 6)
	box.add_child(phrases)
	for i in range(Protocol.REACTION_FACES, Protocol.REACTIONS.size()):
		var button: Button = Button.new()
		button.theme_type_variation = "QuietButton"
		button.focus_mode = Control.FOCUS_NONE
		button.text = Protocol.REACTIONS[i]
		button.custom_minimum_size = Vector2(0, PHRASE_H)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_pick.bind(i))
		phrases.add_child(button)


## Abre o painel com o canto de baixo à direita em corner (perto do botão).
func open(corner: Vector2) -> void:
	visible = true
	_panel.reset_size()
	var panel: Vector2 = _panel.get_combined_minimum_size()
	_panel.size = panel
	var spot: Vector2 = corner - panel
	spot.x = clampf(spot.x, 8.0, maxf(8.0, size.x - panel.x - 8.0))
	spot.y = clampf(spot.y, 8.0, maxf(8.0, size.y - panel.y - 8.0))
	_panel.position = spot.round()


func close() -> void:
	visible = false


func _pick(index: int) -> void:
	close()
	chosen.emit(index)


func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch
			and event.pressed):
		close()
		accept_event()
