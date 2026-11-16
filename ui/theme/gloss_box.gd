extends StyleBox
## Caixa com volume para botões, placas e painéis: sombra embaixo, degradê vertical
## (top em cima, bottom embaixo), contorno e um fio de brilho na borda de cima, como a
## luz batendo numa peça de verdade. Desenhada em vetor, nítida em qualquer escala.
## Funciona também translúcida (painéis de vidro escuro).

const Paint := preload("res://ui/widgets/paint.gd")

@export var top: Color = Color.WHITE
@export var bottom: Color = Color.GRAY
## Contorno; transparente para não ter.
@export var rim: Color = Color(0, 0, 0, 0)
@export var rim_width: int = 1
## Opacidade do fio de brilho no alto (0 para não ter).
@export var shine: float = 0.3
@export var radius: float = 12.0
@export var shadow_color: Color = Color(0, 0, 0, 0)
@export var shadow_size: int = 0
@export var shadow_offset: Vector2 = Vector2.ZERO
## Brilho em volta, da cor dada; transparente para não ter.
@export var glow: Color = Color(0, 0, 0, 0)


func _draw(item: RID, rect: Rect2) -> void:
	for halo: Array in [[glow, 12, Vector2.ZERO], [shadow_color, shadow_size, shadow_offset]]:
		if halo[0].a > 0.0 and halo[1] > 0:
			var box: StyleBoxFlat = StyleBoxFlat.new()
			box.bg_color = Color(0, 0, 0, 0)
			box.shadow_color = halo[0]
			box.shadow_size = halo[1]
			box.shadow_offset = halo[2]
			box.set_corner_radius_all(int(radius))
			box.draw(item, rect)
	Paint.gradient_rect_rid(item, rect, radius, top, bottom)
	if rim.a > 0.0 and rim_width > 0:
		var line: StyleBoxFlat = StyleBoxFlat.new()
		line.draw_center = false
		line.set_border_width_all(rim_width)
		line.border_color = rim
		line.set_corner_radius_all(int(radius))
		line.anti_aliasing = true
		line.corner_detail = 10
		line.draw(item, rect)
	if shine > 0.0:
		var inner: Rect2 = rect.grow(-float(rim_width) if rim.a > 0.0 else 0.0)
		var line: StyleBoxFlat = StyleBoxFlat.new()
		line.draw_center = false
		line.border_width_top = 1
		line.border_color = Color(1, 1, 1, shine)
		line.set_corner_radius_all(int(maxf(radius - rim_width, 0.0)))
		line.anti_aliasing = true
		line.draw(item, inner)


## Cópia com as cores de outro estado (apertado, desativado).
func tinted(new_top: Color, new_bottom: Color, new_shadow: int = -1) -> StyleBox:
	var copy = duplicate()
	copy.top = new_top
	copy.bottom = new_bottom
	if new_shadow >= 0:
		copy.shadow_size = new_shadow
	return copy
