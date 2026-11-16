extends Control
## Fichas em voo: uma pequena pilha que vai de um ponto a outro e some (apostas indo
## para o pote, pote indo para quem ganhou). Criada e apagada pela mesa.

const Paint := preload("res://ui/widgets/paint.gd")
const T: String = "Tokens"

var chips: int = 3


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2.ZERO


## Voa de from até to (coordenadas do pai), depois de delay segundos.
func launch(from: Vector2, to: Vector2, delay: float, duration: float = 0.38) -> void:
	position = from
	modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_interval(delay)
	tween.tween_property(self, "modulate:a", 1.0, 0.06)
	tween.tween_property(self, "position", to, duration).set_trans(Tween.TRANS_CUBIC) \
		.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "modulate:a", 0.0, 0.12)
	tween.tween_callback(queue_free)


func _draw() -> void:
	var fills: Array[Color] = []
	for i in chips:
		fills.append(get_theme_color("chip_0", T))
	Paint.chip_stack(self, Vector2(0, 3.0), 6.5, fills, get_theme_color("chip_mark", T))
