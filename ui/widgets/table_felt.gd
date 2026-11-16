extends Control
## Fundo da tela e a mesa (aro, feltro com luz no centro, linha interna). A forma da
## mesa vem do table_shape do tema. felt_rect é o retângulo do feltro, sem o aro.

const T: String = "Tokens"
const RAIL: float = 9.0

var felt_rect: Rect2 = Rect2(30, 70, 300, 440):
	set(value):
		felt_rect = value
		queue_redraw()

var _gradient: GradientTexture2D = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_gradient = null
		queue_redraw()


func _draw() -> void:
	var top: Color = get_theme_color("bg_top", T)
	var bottom: Color = get_theme_color("bg", T)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size,
		Vector2(0, size.y)]), PackedColorArray([top, top, bottom, bottom]))

	var shape: int = get_theme_constant("table_shape", T)
	var light: bool = bottom.get_luminance() > 0.5
	var shadow: Color = get_theme_color("shadow", T)
	# Sombra discreta sob a mesa, em camadas.
	for i in 4:
		var grow: float = RAIL + 2.0 + i * 3.0
		var points: PackedVector2Array = outline(felt_rect.grow(grow), shape, grow)
		var offset: Vector2 = Vector2(0, 4.0 + i * 1.5)
		for k in points.size():
			points[k] += offset
		draw_colored_polygon(points, Color(shadow, (0.07 if light else 0.16) - i * 0.012))

	draw_colored_polygon(outline(felt_rect.grow(RAIL), shape, RAIL),
		get_theme_color("rail", T))
	var felt: PackedVector2Array = outline(felt_rect, shape, 0.0)
	var uvs: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in felt:
		uvs.append((p - felt_rect.position) / felt_rect.size)
	draw_colored_polygon(felt, Color.WHITE, uvs, _felt_texture())
	var rim: PackedVector2Array = felt.duplicate()
	rim.append(felt[0])
	draw_polyline(rim, Color(get_theme_color("rail_line", T), 0.55 if not light else 1.0),
		1.5, true)
	if get_theme_constant("felt_lane", T) == 1:
		var lane: PackedVector2Array = outline(felt_rect.grow(-22.0), shape, -22.0)
		lane.append(lane[0])
		draw_polyline(lane, Color(get_theme_color("felt_line", T), 0.07), 1.5, true)


func _felt_texture() -> GradientTexture2D:
	if _gradient == null:
		var gradient: Gradient = Gradient.new()
		gradient.set_color(0, get_theme_color("felt_center", T))
		gradient.set_color(1, get_theme_color("felt_edge", T))
		_gradient = GradientTexture2D.new()
		_gradient.gradient = gradient
		_gradient.fill = GradientTexture2D.FILL_RADIAL
		_gradient.fill_from = Vector2(0.5, 0.45)
		_gradient.fill_to = Vector2(1.05, 0.45)
		_gradient.width = 256
		_gradient.height = 256
	return _gradient


## Contorno da mesa no retângulo. grow diz quanto o retângulo foi aumentado em relação
## ao feltro, para os cantos acompanharem o aro.
static func outline(rect: Rect2, shape: int, grow: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	var c: Vector2 = rect.get_center()
	match shape:
		1:
			for i in 96:
				var a: float = TAU * i / 96.0
				points.append(c + Vector2(cos(a) * rect.size.x / 2.0, sin(a) * rect.size.y / 2.0))
		3:
			var k: float = rect.size.x * 0.24 + grow * 0.4
			var p: Vector2 = rect.position
			var e: Vector2 = rect.end
			points = PackedVector2Array([Vector2(p.x + k, p.y), Vector2(e.x - k, p.y),
				Vector2(e.x, p.y + k), Vector2(e.x, e.y - k), Vector2(e.x - k, e.y),
				Vector2(p.x + k, e.y), Vector2(p.x, e.y - k), Vector2(p.x, p.y + k)])
		_:
			var r: float = rect.size.x / 2.0 if shape == 0 else rect.size.x * 0.24 + grow
			r = minf(r, minf(rect.size.x, rect.size.y) / 2.0)
			var corners: Array[Vector2] = [
				Vector2(rect.end.x - r, rect.position.y + r), Vector2(rect.end.x - r, rect.end.y - r),
				Vector2(rect.position.x + r, rect.end.y - r), Vector2(rect.position.x + r, rect.position.y + r)]
			for corner in 4:
				for step in 17:
					var a: float = -PI / 2.0 + PI / 2.0 * corner + PI / 2.0 * step / 16.0
					points.append(corners[corner] + Vector2(cos(a), sin(a)) * r)
	# Sem pontos repetidos: nas pontas redondas os cantos coincidem e a triangulação falha.
	var clean: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in points:
		if clean.is_empty() or clean[clean.size() - 1].distance_to(p) > 0.01:
			clean.append(p)
	if clean.size() > 1 and clean[0].distance_to(clean[clean.size() - 1]) <= 0.01:
		clean.remove_at(clean.size() - 1)
	return clean
