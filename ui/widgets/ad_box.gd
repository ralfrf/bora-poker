extends Control
## Quadro de anúncio embaixo da lista de servidores (pedido do dono, 17/11/2026), no
## tamanho do banner grande (320x100). Enquanto não há anúncio carregado (hoje não há
## SDK), mostra a ficha do jogo girando e um brilho que passa pelo quadro; quando houver,
## o banner do serviço de anúncios fica por cima deste retângulo.

const Paint := preload("res://ui/widgets/paint.gd")
const T: String = "Tokens"
const SIZE: Vector2 = Vector2(320, 100)
const SWEEP_S: float = 2.6     ## uma passada do brilho, em segundos
const SPIN_S: float = 3.2      ## uma volta da ficha

var _time: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	queue_redraw()


func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color(get_theme_color("surface", T), 0.92)
	box.border_color = Color(get_theme_color("accent", T), 0.45)
	box.set_border_width_all(1)
	box.set_corner_radius_all(12)
	box.anti_aliasing = true
	draw_style_box(box, rect)
	# Brilho em faixa inclinada que atravessa o quadro e some antes de voltar.
	var phase: float = fmod(_time, SWEEP_S) / SWEEP_S
	var x: float = lerpf(-80.0, size.x + 80.0, phase)
	var glow: Color = Color(get_theme_color("accent", T), 0.13)
	var clear: Color = Color(glow, 0.0)
	draw_polygon(PackedVector2Array([Vector2(x - 40.0, size.y), Vector2(x, 0),
		Vector2(x + 30.0, 0), Vector2(x - 10.0, size.y)]),
		PackedColorArray([clear, glow, clear, glow]))
	# Ficha girando no próprio eixo (achata e volta) à esquerda do nome do jogo.
	var radius: float = minf(26.0, size.y * 0.28)
	var center: Vector2 = Vector2(size.x * 0.5 - 62.0, size.y * 0.5)
	var squash: float = maxf(0.12, absf(cos(_time * TAU / SPIN_S)))
	draw_set_transform(center, 0.0, Vector2(squash, 1.0))
	Paint.chip(self, Vector2.ZERO, radius, get_theme_color("chip_0", T),
		get_theme_color("chip_mark", T), get_theme_constant("chip_style", T))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var font: Font = get_theme_font("display", T)
	var body: int = get_theme_font_size("body", T)
	draw_string(font, Vector2(center.x + radius + 14.0, size.y * 0.5 + body * 0.36),
		"Bora Poker", HORIZONTAL_ALIGNMENT_LEFT, -1, body + 2,
		Color(get_theme_color("text", T), 0.8))
	var small: int = get_theme_font_size("small", T)
	var tag: String = "Anúncio"
	var tag_w: float = font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, small - 2).x
	draw_string(font, Vector2(size.x - tag_w - 10.0, small + 2.0), tag,
		HORIZONTAL_ALIGNMENT_LEFT, -1, small - 2, get_theme_color("text_dim", T))
