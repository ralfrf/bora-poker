extends RefCounted
## Desenho vetorial das peças pequenas: naipes, fichas, avatares e verso das cartas.
## Tudo recebe as cores de quem chama (que as lê do tema); aqui só há preto e branco
## para sombras e brilhos.

const TAU_STEPS: int = 48

static var _heart: PackedVector2Array = PackedVector2Array()


## Naipe (0 paus, 1 ouros, 2 copas, 3 espadas) centrado em center, com altura size.
static func suit(ci: CanvasItem, suit_index: int, center: Vector2, size: float,
		color: Color) -> void:
	match suit_index:
		0:
			var r: float = size * 0.235
			_disc(ci, center + Vector2(0, -size * 0.22), r, color)
			_disc(ci, center + Vector2(-size * 0.25, size * 0.07), r, color)
			_disc(ci, center + Vector2(size * 0.25, size * 0.07), r, color)
			_disc(ci, center + Vector2(0, size * 0.0), r * 0.7, color)
			_stem(ci, center, size, color)
		1:
			var points: PackedVector2Array = PackedVector2Array()
			var corners: Array[Vector2] = [Vector2(0, -0.5), Vector2(0.4, 0),
				Vector2(0, 0.5), Vector2(-0.4, 0)]
			for i in 4:
				var a: Vector2 = corners[i]
				var b: Vector2 = corners[(i + 1) % 4]
				var control: Vector2 = (a + b) * 0.5 * 0.78
				for step in 10:
					var t: float = step / 10.0
					var p: Vector2 = a.lerp(control, t).lerp(control.lerp(b, t), t)
					points.append(center + p * size)
			_polygon(ci, points, color)
		2:
			_polygon(ci, _heart_points(center, size, false), color)
		3:
			_polygon(ci, _heart_points(center + Vector2(0, -size * 0.06), size * 0.9, true),
				color)
			_stem(ci, center, size, color)


## Ficha vista de cima, com sombra curta e um brilho no alto.
static func chip(ci: CanvasItem, center: Vector2, radius: float, fill: Color,
		mark: Color, style: int) -> void:
	_disc(ci, center + Vector2(0, maxf(radius * 0.1, 0.6)), radius, Color(0, 0, 0, 0.35))
	var edge: Color = fill.darkened(0.3)
	_disc(ci, center, radius, edge)
	_disc(ci, center, radius * 0.9, fill)
	match style:
		0:
			for i in 6:
				var angle: float = TAU * i / 6.0
				_arc(ci, center, radius * 0.78, angle - 0.17, angle + 0.17, radius * 0.22, mark)
			_disc(ci, center, radius * 0.5, fill.lightened(0.08))
			_ring(ci, center, radius * 0.5, maxf(radius * 0.08, 0.8), Color(mark, 0.85))
		1:
			_ring(ci, center, radius * 0.62, maxf(radius * 0.12, 0.9), Color(mark, 0.9))
		2:
			for i in 4:
				var angle: float = TAU * i / 4.0 + TAU / 8.0
				_arc(ci, center, radius * 0.76, angle - 0.36, angle + 0.36, radius * 0.26, mark)
		3:
			_ring(ci, center, radius * 0.9, maxf(radius * 0.1, 0.8), Color(mark, 0.35))
			_disc(ci, center, radius * 0.28, Color(mark, 0.9))
	if radius >= 4.0:
		ci.draw_arc(center, radius * 0.9, PI * 1.12, PI * 1.88, 12, Color(1, 1, 1, 0.35),
			maxf(radius * 0.1, 0.8), true)


## Pilha de fichas vista de lado (perspectiva leve), de baixo para cima, com sombra.
static func chip_stack(ci: CanvasItem, base: Vector2, radius: float,
		fills: Array[Color], mark: Color) -> void:
	var height: float = radius * 0.6
	var thick: float = maxf(radius * 0.32, 2.0)
	_ellipse(ci, base + Vector2(radius * 0.12, thick * 0.9), radius * 1.15, height * 1.1,
		Color(0, 0, 0, 0.3))
	for i in fills.size():
		var c: Vector2 = base + Vector2(0, -i * thick)
		var fill: Color = fills[i]
		var side: Color = fill.darkened(0.35)
		_ellipse(ci, c + Vector2(0, thick * 0.5), radius, height, side)
		ci.draw_rect(Rect2(c.x - radius, c.y, radius * 2.0, thick * 0.5), side)
		# Marcas na lateral, como as listras de uma ficha de verdade.
		for k in 3:
			var x: float = c.x + (k - 1) * radius * 0.62
			ci.draw_rect(Rect2(x - radius * 0.1, c.y + thick * 0.05, radius * 0.2,
				thick * 0.55), Color(mark, 0.75))
		_ellipse(ci, c, radius, height, fill)
		_ellipse_ring(ci, c, radius * 0.62, height * 0.62, maxf(radius * 0.08, 0.8),
			Color(mark, 0.6))
		if i == fills.size() - 1:
			_ellipse_ring(ci, c + Vector2(0, -height * 0.08), radius * 0.86, height * 0.8,
				maxf(radius * 0.07, 0.7), Color(1, 1, 1, 0.3))


## Avatar provisório: disco colorido com sombreado de esfera e um emblema simples.
static func avatar(ci: CanvasItem, rect: Rect2, index: int, colors: Array[Color],
		shape: int, radius: float) -> void:
	var color_index: int = index % colors.size()
	var emblem: int = index % 6
	# A estrela no vermelho saiu a pedido do dono; no lugar, espadas no dourado.
	if emblem == 0 and color_index == 0:
		emblem = 5
		color_index = 4 % colors.size()
	var fill: Color = colors[color_index]
	var ink: Color = Color(1, 1, 1, 0.96) if fill.get_luminance() < 0.6 \
		else Color(0.06, 0.08, 0.1, 0.9)
	var center: Vector2 = rect.get_center()
	var size: float = minf(rect.size.x, rect.size.y)
	if shape == 0:
		var r: float = size / 2.0
		_disc(ci, center, r, fill.darkened(0.35))
		_disc(ci, center + Vector2(-0.06, -0.09) * size, r * 0.84, fill)
		_disc(ci, center + Vector2(-0.14, -0.2) * size, r * 0.42, Color(fill.lightened(0.4), 0.35))
	else:
		gradient_rect(ci, rect, radius, fill.lightened(0.15), fill.darkened(0.25))
	var s: float = size * 0.42
	_emblem(ci, emblem, center + Vector2(0, s * 0.06), s, Color(0, 0, 0, 0.28))
	_emblem(ci, emblem, center, s, ink)


static func _emblem(ci: CanvasItem, kind: int, center: Vector2, s: float,
		ink: Color) -> void:
	match kind:
		0:
			_polygon(ci, _star(center, s * 0.62, s * 0.26, 5), ink)
		1:
			_disc(ci, center, s * 0.3, ink)
			for i in 8:
				var a: float = TAU * i / 8.0
				var d: Vector2 = Vector2(cos(a), sin(a))
				ci.draw_line(center + d * s * 0.46, center + d * s * 0.62, ink, s * 0.12, true)
		2:
			_polygon(ci, PackedVector2Array([center + Vector2(0.08, -0.6) * s,
				center + Vector2(-0.36, 0.08) * s, center + Vector2(-0.02, 0.08) * s,
				center + Vector2(-0.1, 0.6) * s, center + Vector2(0.36, -0.1) * s,
				center + Vector2(0.02, -0.1) * s]), ink)
		3:
			_polygon(ci, PackedVector2Array([center + Vector2(-0.62, 0.42) * s,
				center + Vector2(-0.16, -0.36) * s, center + Vector2(0.06, 0.0) * s,
				center + Vector2(0.24, -0.2) * s, center + Vector2(0.62, 0.42) * s]), ink)
		4:
			_ring(ci, center, s * 0.4, s * 0.2, ink)
		5:
			_polygon(ci, _heart_points(center + Vector2(0, s * 0.1), s * 1.1, true), ink)


## Verso da carta: borda clara como numa carta de baralho, painel com degradê,
## padrão, moldura e, nas cartas maiores, um medalhão com espadas no meio.
static func card_back(ci: CanvasItem, rect: Rect2, top: Color, fill: Color, ink: Color,
		edge: Color, pattern: int, radius: float) -> void:
	gradient_rect(ci, rect, radius, edge, edge.darkened(0.08))
	var border: float = maxf(rect.size.x * 0.07, 1.2)
	var panel: Rect2 = rect.grow(-border)
	var panel_r: float = maxf(radius - border * 0.6, 1.0)
	gradient_rect(ci, panel, panel_r, top, fill)
	if rect.size.x < 24.0:
		return
	var pad: float = maxf(rect.size.x * 0.06, 1.5)
	var inner: Rect2 = panel.grow(-pad)
	var line: float = maxf(rect.size.x * 0.022, 0.7)
	var soft: Color = Color(ink, 0.34)
	match pattern:
		0:
			var step: float = inner.size.x / 4.5
			var k: float = -inner.size.y
			while k < inner.size.x + inner.size.y:
				for dir: int in [1, -1]:
					var a: Vector2 = Vector2(inner.position.x + k, inner.end.y) if dir == 1 \
						else Vector2(inner.position.x + k, inner.position.y)
					var b: Vector2 = a + Vector2(inner.size.y, -inner.size.y * dir)
					var segment: PackedVector2Array = _clip_line(inner, a, b)
					if segment.size() == 2:
						ci.draw_line(segment[0], segment[1], soft, line, true)
				k += step
		1:
			var step: float = inner.size.x / 4.0
			var y: float = inner.position.y + step * 0.5
			while y < inner.end.y:
				var x: float = inner.position.x + step * 0.5
				while x < inner.end.x:
					_disc(ci, Vector2(x, y), step * 0.18, soft)
					x += step
				y += step
		2:
			var step: float = inner.size.y / 6.0
			var y: float = inner.position.y + step * 0.6
			while y < inner.end.y:
				ci.draw_polyline(PackedVector2Array([
					Vector2(inner.position.x + line, y),
					Vector2(inner.get_center().x, y - step * 0.45),
					Vector2(inner.end.x - line, y)]), soft, line * 1.6, true)
				y += step
		3:
			var step: float = inner.size.x / 5.0
			var k: float = -inner.size.y
			while k < inner.size.x:
				var segment: PackedVector2Array = _clip_line(inner.grow(-line * 1.5),
					Vector2(inner.position.x + k, inner.end.y),
					Vector2(inner.position.x + k + inner.size.y, inner.position.y))
				if segment.size() == 2:
					ci.draw_line(segment[0], segment[1], soft, line * 2.0, true)
				k += step
	var frame: StyleBoxFlat = StyleBoxFlat.new()
	frame.draw_center = false
	frame.set_border_width_all(maxi(int(line), 1))
	frame.border_color = Color(ink, 0.8)
	frame.set_corner_radius_all(int(maxf(panel_r - pad * 0.5, 1.0)))
	frame.anti_aliasing = true
	ci.draw_style_box(frame, inner)
	var c: Vector2 = inner.get_center()
	var m: float = inner.size.x * 0.27
	_disc(ci, c, m, fill.darkened(0.25))
	_ring(ci, c, m, line * 1.4, Color(ink, 0.9))
	_ring(ci, c, m * 0.78, line * 0.8, Color(ink, 0.5))
	suit(ci, 3, c + Vector2(0, m * 0.04), m * 0.95, ink)


## Anel de tempo: arco de 0 a fraction, começando no alto e andando no sentido horário.
static func timer_ring(ci: CanvasItem, center: Vector2, radius: float, width: float,
		fraction: float, color: Color, track: Color) -> void:
	ci.draw_arc(center, radius, 0.0, TAU, 64, track, width, true)
	if fraction > 0.0:
		var start: float = -PI / 2.0
		ci.draw_arc(center, radius, start, start + TAU * clampf(fraction, 0.0, 1.0),
			64, color, width, true)


## Fundo de salão: degradê escuro, uma luz larga e difusa, luzes desfocadas ao longe
## (bokeh) e uma vinheta que escurece os cantos. lights: [principal, clara, fria].
static func room(ci: CanvasItem, rect: Rect2, top: Color, bottom: Color,
		lights: Array[Color]) -> void:
	var p: Vector2 = rect.position
	var e: Vector2 = rect.end
	ci.draw_polygon(PackedVector2Array([p, Vector2(e.x, p.y), e, Vector2(p.x, e.y)]),
		PackedColorArray([top, top, bottom, bottom]))
	var soft: Texture2D = soft_disc()
	var unit: float = rect.size.y
	var wide: Vector2 = Vector2(rect.size.x * 1.2, unit * 1.5)
	var c: Vector2 = p + rect.size * Vector2(0.42, 0.38)
	ci.draw_texture_rect(soft, Rect2(c - wide / 2.0, wide), false, Color(lights[0], 0.13))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261116
	# Manchas grandes e bem difusas.
	for i in 7:
		var at: Vector2 = p + rect.size * Vector2(rng.randf(), rng.randf() * 0.7)
		var r: float = unit * rng.randf_range(0.18, 0.34)
		var color: Color = lights[0] if i % 3 != 2 else lights[2]
		ci.draw_texture_rect(soft, Rect2(at - Vector2.ONE * r, Vector2.ONE * r * 2.0), false,
			Color(color, rng.randf_range(0.06, 0.12)))
	# Luzes desfocadas, mais no alto, como lâmpadas ao fundo do salão.
	var bokeh: Texture2D = bokeh_disc()
	for i in 30:
		var at: Vector2 = p + rect.size * Vector2(rng.randf(), pow(rng.randf(), 1.8) * 0.85)
		var r: float = unit * rng.randf_range(0.018, 0.065)
		var pick: float = rng.randf()
		var color: Color = lights[0] if pick < 0.6 else (lights[1] if pick < 0.86 else lights[2])
		ci.draw_texture_rect(bokeh, Rect2(at - Vector2.ONE * r, Vector2.ONE * r * 2.0), false,
			Color(color, rng.randf_range(0.05, 0.2) * (1.0 - 0.6 * (at.y - p.y) / rect.size.y)))
	ci.draw_texture_rect(vignette(), rect, false, Color(0, 0, 0, 0.8))


## Retângulo de cantos redondos com degradê vertical e borda suavizada.
static func gradient_rect(ci: CanvasItem, rect: Rect2, radius: float, top: Color,
		bottom: Color) -> void:
	gradient_rect_rid(ci.get_canvas_item(), rect, radius, top, bottom)


static func gradient_rect_rid(item: RID, rect: Rect2, radius: float, top: Color,
		bottom: Color) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var points: PackedVector2Array = rounded_points(rect, radius)
	var colors: PackedColorArray = PackedColorArray()
	for point: Vector2 in points:
		colors.append(top.lerp(bottom, clampf((point.y - rect.position.y) / rect.size.y, 0.0, 1.0)))
	RenderingServer.canvas_item_add_polygon(item, points, colors)
	var outline: PackedVector2Array = points.duplicate()
	outline.append(points[0])
	var outline_colors: PackedColorArray = colors.duplicate()
	outline_colors.append(colors[0])
	RenderingServer.canvas_item_add_polyline(item, outline, outline_colors, 1.0, true)


## Contorno de um retângulo de cantos redondos, no sentido horário.
static func rounded_points(rect: Rect2, radius: float) -> PackedVector2Array:
	var r: float = clampf(radius, 0.0, minf(rect.size.x, rect.size.y) / 2.0)
	if r < 0.5:
		return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y),
			rect.end, Vector2(rect.position.x, rect.end.y)])
	var points: PackedVector2Array = PackedVector2Array()
	var steps: int = clampi(int(r * 0.7), 3, 10)
	var corners: Array[Vector2] = [Vector2(rect.end.x - r, rect.position.y + r),
		Vector2(rect.end.x - r, rect.end.y - r), Vector2(rect.position.x + r, rect.end.y - r),
		Vector2(rect.position.x + r, rect.position.y + r)]
	for corner in 4:
		for step in steps + 1:
			var a: float = -PI / 2.0 + PI / 2.0 * corner + PI / 2.0 * step / steps
			points.append(corners[corner] + Vector2(cos(a), sin(a)) * r)
	return points


static var _soft: Texture2D = null
static var _bokeh: Texture2D = null
static var _vignette: Texture2D = null


## Disco branco que some suavemente até a borda (luz difusa, brilho, halo).
static func soft_disc() -> Texture2D:
	if _soft == null:
		_soft = _radial(64, 0)
	return _soft


## Disco de luz desfocada: cheio, com a borda um pouco mais viva e macia.
static func bokeh_disc() -> Texture2D:
	if _bokeh == null:
		_bokeh = _radial(64, 1)
	return _bokeh


## Vinheta: transparente no meio, escura nos cantos.
static func vignette() -> Texture2D:
	if _vignette == null:
		_vignette = _radial(96, 2)
	return _vignette


static func _radial(size: int, kind: int) -> Texture2D:
	var image: Image = Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var half: float = size / 2.0
	for y in size:
		for x in size:
			var d: float = Vector2(x + 0.5 - half, y + 0.5 - half).length() / half
			var a: float = 0.0
			match kind:
				0:
					a = pow(clampf(1.0 - d, 0.0, 1.0), 2.0)
				1:
					a = (0.55 + 0.35 * smoothstep(0.55, 0.9, d)) * (1.0 - smoothstep(0.86, 1.0, d))
				2:
					a = smoothstep(0.55, 1.45, d)
			image.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(image)


# --- formas básicas -----------------------------------------------------------------

static func _disc(ci: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	ci.draw_circle(center, radius, color, true, -1.0, true)


static func _ring(ci: CanvasItem, center: Vector2, radius: float, width: float,
		color: Color) -> void:
	ci.draw_arc(center, radius, 0.0, TAU, TAU_STEPS, color, width, true)


static func _arc(ci: CanvasItem, center: Vector2, radius: float, from: float, to: float,
		width: float, color: Color) -> void:
	ci.draw_arc(center, radius, from, to, 8, color, width, true)


static func _ellipse(ci: CanvasItem, center: Vector2, rx: float, ry: float,
		color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for i in TAU_STEPS:
		var a: float = TAU * i / TAU_STEPS
		points.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	_polygon(ci, points, color)


static func _ellipse_ring(ci: CanvasItem, center: Vector2, rx: float, ry: float,
		width: float, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for i in TAU_STEPS + 1:
		var a: float = TAU * i / TAU_STEPS
		points.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	ci.draw_polyline(points, color, width, true)


## Polígono preenchido com a borda suavizada por uma linha fina da mesma cor.
static func _polygon(ci: CanvasItem, points: PackedVector2Array, color: Color) -> void:
	ci.draw_colored_polygon(points, color)
	var outline: PackedVector2Array = points.duplicate()
	outline.append(points[0])
	ci.draw_polyline(outline, color, 0.8, true)


static func _stem(ci: CanvasItem, center: Vector2, size: float, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	var top: Vector2 = center + Vector2(0, size * 0.05)
	for step in 9:
		var t: float = step / 8.0
		points.append(top + Vector2(-lerpf(0.03, 0.2, t * t), lerpf(0.0, 0.45, t)) * size)
	for step in 9:
		var t: float = 1.0 - step / 8.0
		points.append(top + Vector2(lerpf(0.03, 0.2, t * t), lerpf(0.0, 0.45, t)) * size)
	_polygon(ci, points, color)


## Coração (ou espada, de ponta-cabeça) pela curva clássica, normalizado para a altura.
static func _heart_points(center: Vector2, size: float, flip: bool) -> PackedVector2Array:
	if _heart.is_empty():
		for i in 64:
			var t: float = TAU * i / 64.0
			var x: float = 16.0 * pow(sin(t), 3)
			var y: float = -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))
			_heart.append(Vector2(x, y - 2.5) / 30.0)
	var points: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in _heart:
		points.append(center + Vector2(p.x, -p.y if flip else p.y) * size)
	return points


static func _star(center: Vector2, outer: float, inner: float, tips: int) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for i in tips * 2:
		var a: float = -PI / 2.0 + PI * i / tips
		var r: float = outer if i % 2 == 0 else inner
		points.append(center + Vector2(cos(a), sin(a)) * r)
	return points


## Recorta o segmento a-b ao retângulo (Liang-Barsky). Vazio se ficar todo fora.
static func _clip_line(rect: Rect2, a: Vector2, b: Vector2) -> PackedVector2Array:
	var t0: float = 0.0
	var t1: float = 1.0
	var d: Vector2 = b - a
	var checks: Array = [[-d.x, a.x - rect.position.x], [d.x, rect.end.x - a.x],
		[-d.y, a.y - rect.position.y], [d.y, rect.end.y - a.y]]
	for check: Array in checks:
		var p: float = check[0]
		var q: float = check[1]
		if is_zero_approx(p):
			if q < 0.0:
				return PackedVector2Array()
			continue
		var r: float = q / p
		if p < 0.0:
			t0 = maxf(t0, r)
		else:
			t1 = minf(t1, r)
		if t0 > t1:
			return PackedVector2Array()
	return PackedVector2Array([a + d * t0, a + d * t1])
