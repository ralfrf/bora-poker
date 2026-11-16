extends Control
## Base das telas deitadas fora da mesa. Segue o desenho da mesa: o conteúdo à
## esquerda e, à direita, a coluna estreita de ações, com o botão principal embaixo,
## ao alcance do polegar. Respeita o furo da câmera (área segura) e se reorganiza ao
## girar o celular.
##
## Cada tela monta as peças em _build() e as posiciona em _layout(), usando body() e
## column(). go_back() responde ao botão "voltar" do Android.

const SafeArea := preload("res://ui/theme/safe_area.gd")
const Backdrop := preload("res://ui/widgets/backdrop.gd")
const T: String = "Tokens"

const MARGIN: float = 16.0
const COLUMN_W: float = 136.0
const GAP: float = 16.0
const BUTTON_H: float = 52.0

var _safe_seen: Rect2i = Rect2i()
var _safe_check: float = 0.0


func _ready() -> void:
	var backdrop: Backdrop = Backdrop.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	_build()
	resized.connect(_layout)
	_layout()


func _process(delta: float) -> void:
	_safe_check -= delta
	if _safe_check <= 0.0:
		_safe_check = 0.5
		var safe: Rect2i = SafeArea.current()
		if safe != _safe_seen:
			_safe_seen = safe
			_layout()


## Monta as peças (uma vez).
func _build() -> void:
	pass


## Posiciona as peças (a cada mudança de tamanho).
func _layout() -> void:
	pass


## Botão "voltar" do Android. Devolve verdadeiro se a tela tratou.
func go_back() -> bool:
	return false


func content() -> Rect2:
	return SafeArea.content(self).grow(-MARGIN)


func column() -> Rect2:
	var c: Rect2 = content()
	return Rect2(c.end.x - COLUMN_W, c.position.y, COLUMN_W, c.size.y)


func body() -> Rect2:
	var c: Rect2 = content()
	return Rect2(c.position, Vector2(c.size.x - COLUMN_W - GAP, c.size.y))


## Coloca um controle num retângulo.
static func place(control: Control, rect: Rect2) -> void:
	control.position = rect.position.round()
	control.size = rect.size.round()


## Botão de ação da coluna (principal ou não), com a altura dos botões da mesa.
static func action_button(text: String, primary: bool) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.theme_type_variation = "PrimaryButton" if primary else ""
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, BUTTON_H)
	return button
