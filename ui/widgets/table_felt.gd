extends Control
## Fundo de salão e a mesa: sombra no chão, borda acolchoada de couro com reflexo, fio
## dourado, feltro com luz no centro, textura de tecido e a sombra da borda caindo no
## feltro. A forma vem do table_shape do tema. felt_rect é o retângulo do feltro, sem a
## borda. Nada escrito no feltro.
##
## skin é a mesa escolhida (ui/theme/tables.gd): troca as cores da mesa, a borda (couro
## ou madeira) e a estampa do feltro; o que ela não diz vem do tema.

const Paint := preload("res://ui/widgets/paint.gd")
const T: String = "Tokens"
## Largura da borda acolchoada.
const RAIL: float = 15.0
## Pontos de cada contorno; o mesmo em todos, para ligar um contorno ao outro.
const ARC_POINTS: int = 40
const SIDE_POINTS: int = 16

var felt_rect: Rect2 = Rect2(30, 70, 300, 440):
	set(value):
		felt_rect = value
		queue_redraw()

var skin: Dictionary = {}:
	set(value):
		skin = value
		queue_redraw()

static var _weave: Texture2D = null
static var _wood: Texture2D = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var lights: Array[Color] = [get_theme_color("bokeh_0", T), get_theme_color("bokeh_1", T),
		get_theme_color("bokeh_2", T)]
	Paint.room(self, Rect2(Vector2.ZERO, size), get_theme_color("bg_top", T),
		get_theme_color("bg", T), lights)
	var shape: int = get_theme_constant("table_shape", T)
	var shadow: Color = get_theme_color("shadow", T)

	# Sombra da mesa no chão, larga e macia.
	for i in 10:
		var grow: float = RAIL + 26.0 - i * 2.4
		var points: PackedVector2Array = contour(felt_rect, shape, grow)
		var offset: Vector2 = Vector2(0, 10.0 - i * 0.5)
		for k in points.size():
			points[k] += offset
		draw_colored_polygon(points, Color(shadow, 0.075))

	if _style("rail_kind") == 1:
		_draw_wood(shape)
	else:
		_draw_rail(shape)
	_draw_trim(shape)
	_draw_felt(shape)


## Cor da mesa: a da skin, se ela disser, senão a do tema.
func _color(key: String) -> Color:
	var colors: Dictionary = skin.get("colors", {})
	if colors.has(key):
		return Color.html(colors[key])
	return get_theme_color(key, T)


func _style(key: String) -> int:
	var style: Dictionary = skin.get("style", {})
	if style.has(key):
		return int(style[key])
	return get_theme_constant(key, T) if has_theme_constant(key, T) else 0


## Borda acolchoada: faixas do lado de fora para dentro, com uma crista clara no meio
## (o couro estufado pegando luz) e mais luz na metade de cima.
func _draw_rail(shape: int) -> void:
	var rail: Color = _color("rail")
	var high: Color = _color("rail_hi")
	# Perfil da borda: posição (0 fora, 1 dentro) e quanto da luz pega.
	var profile: Array = [[0.0, 0.0], [0.12, 0.35], [0.32, 0.9], [0.5, 0.55], [0.75, 0.2],
		[1.0, 0.05]]
	var rings: Array[PackedVector2Array] = []
	var colors: Array[PackedColorArray] = []
	var top_y: float = felt_rect.position.y - RAIL
	var span: float = felt_rect.size.y + RAIL * 2.0
	for step: Array in profile:
		var points: PackedVector2Array = contour(felt_rect, shape, RAIL * (1.0 - step[0]))
		var row: PackedColorArray = PackedColorArray()
		for p: Vector2 in points:
			var above: float = 1.0 - clampf((p.y - top_y) / span, 0.0, 1.0)
			var light: float = float(step[1]) * (0.45 + 0.75 * above)
			var color: Color = rail.lerp(high, clampf(light, 0.0, 1.0))
			if step[0] == 0.0:
				color = rail.darkened(0.5)
			row.append(color)
		rings.append(points)
		colors.append(row)
	_strips(rings, colors)
	# Reflexo fino na crista do couro, só na metade de cima.
	var ridge: PackedVector2Array = contour(felt_rect, shape, RAIL * 0.7)
	var ridge_colors: PackedColorArray = PackedColorArray()
	for p: Vector2 in ridge:
		var above: float = 1.0 - clampf((p.y - top_y) / span, 0.0, 1.0)
		ridge_colors.append(Color(1, 1, 1, 0.3 * above * above))
	ridge.append(ridge[0])
	ridge_colors.append(ridge_colors[0])
	draw_polyline_colors(ridge, ridge_colors, 1.2, true)


## Borda de madeira envernizada: muitas faixas finas com o veio da madeira correndo ao
## longo da borda (textura), luz de um perfil arredondado e dois reflexos do verniz.
func _draw_wood(shape: int) -> void:
	var rail: Color = _color("rail")
	var high: Color = _color("rail_hi")
	# Perfil arredondado: posição (0 fora, 1 dentro) e quanto da luz pega.
	var profile: Array = [[0.0, 0.0], [0.1, 0.3], [0.25, 0.75], [0.4, 0.95], [0.55, 0.8],
		[0.7, 0.5], [0.85, 0.25], [1.0, 0.1]]
	var count: int = 16
	var top_y: float = felt_rect.position.y - RAIL
	var span: float = felt_rect.size.y + RAIL * 2.0
	# O veio segue o comprimento do meio da borda, igual em todas as faixas.
	var middle: PackedVector2Array = contour(felt_rect, shape, RAIL * 0.5)
	var along: PackedFloat32Array = PackedFloat32Array([0.0])
	for i in middle.size():
		along.append(along[i] + middle[i].distance_to(middle[(i + 1) % middle.size()]))
	var total: float = along[along.size() - 1]
	var tile: float = total / maxf(roundf(total / 220.0), 1.0)
	var rings: Array[PackedVector2Array] = []
	var colors: Array[PackedColorArray] = []
	var uvs: Array[PackedVector2Array] = []
	for r in count + 1:
		var t: float = float(r) / count
		var light: float = _profile_at(profile, t)
		var points: PackedVector2Array = contour(felt_rect, shape, RAIL * (1.0 - t))
		points.append(points[0])
		var row: PackedColorArray = PackedColorArray()
		var uv: PackedVector2Array = PackedVector2Array()
		for i in points.size():
			var p: Vector2 = points[i]
			var above: float = 1.0 - clampf((p.y - top_y) / span, 0.0, 1.0)
			var color: Color = rail.lerp(high, clampf(light * (0.4 + 0.8 * above), 0.0, 1.0))
			if r == 0:
				color = rail.darkened(0.55)
			row.append(color)
			uv.append(Vector2(along[i] / tile, t))
		rings.append(points)
		colors.append(row)
		uvs.append(uv)
	_strips_open(rings, colors, uvs, _wood_texture())
	# Reflexos do verniz: um fino e forte no alto do arredondado, outro largo e fraco.
	for gloss: Array in [[0.36, 1.4, 0.45], [0.62, 3.0, 0.1]]:
		var line: PackedVector2Array = contour(felt_rect, shape, RAIL * (1.0 - float(gloss[0])))
		var tints: PackedColorArray = PackedColorArray()
		for p: Vector2 in line:
			var above: float = 1.0 - clampf((p.y - top_y) / span, 0.0, 1.0)
			tints.append(Color(1, 0.93, 0.82, float(gloss[2]) * above * above))
		line.append(line[0])
		tints.append(tints[0])
		draw_polyline_colors(line, tints, float(gloss[1]), true)


static func _profile_at(profile: Array, t: float) -> float:
	for i in profile.size() - 1:
		var a: Array = profile[i]
		var b: Array = profile[i + 1]
		if t <= float(b[0]):
			return lerpf(float(a[1]), float(b[1]), (t - float(a[0])) / (float(b[0]) - float(a[0])))
	return float(profile[profile.size() - 1][1])


## Fio dourado entre a borda e o feltro, mais claro em cima.
func _draw_trim(shape: int) -> void:
	var trim: Color = _color("rail_line")
	var outer: PackedVector2Array = contour(felt_rect, shape, 2.6)
	var inner: PackedVector2Array = contour(felt_rect, shape, 0.0)
	var trim_outer: PackedColorArray = PackedColorArray()
	var trim_inner: PackedColorArray = PackedColorArray()
	for p: Vector2 in outer:
		var above: float = 1.0 - clampf((p.y - felt_rect.position.y) / felt_rect.size.y, 0.0, 1.0)
		trim_outer.append(trim.lightened(0.35 * above))
		trim_inner.append(trim.darkened(0.35 - 0.25 * above))
	_strips([outer, inner] as Array[PackedVector2Array],
		[trim_outer, trim_inner] as Array[PackedColorArray])
	var edge: PackedVector2Array = outer.duplicate()
	edge.append(outer[0])
	draw_polyline(edge, Color(trim.darkened(0.6), 0.8), 1.0, true)


## Feltro: degradê do centro (mais claro, um pouco acima do meio) para a borda,
## textura de tecido, sombra da borda e a linha interna.
func _draw_felt(shape: int) -> void:
	var center_color: Color = _color("felt_center")
	var edge_color: Color = _color("felt_edge")
	var outline: PackedVector2Array = contour(felt_rect, shape, 0.0)
	var focus: Vector2 = felt_rect.get_center() + Vector2(0, -felt_rect.size.y * 0.06)
	var stops: Array = [[1.0, 0.0], [0.9, 0.22], [0.74, 0.5], [0.52, 0.78], [0.28, 0.94],
		[0.0, 1.0]]
	var rings: Array[PackedVector2Array] = []
	var colors: Array[PackedColorArray] = []
	for stop: Array in stops:
		var points: PackedVector2Array = PackedVector2Array()
		var row: PackedColorArray = PackedColorArray()
		var color: Color = edge_color.lerp(center_color, stop[1])
		for p: Vector2 in outline:
			points.append(focus + (p - focus) * float(stop[0]))
			row.append(color)
		rings.append(points)
		colors.append(row)
	_strips(rings, colors)

	# Textura de tecido, bem leve.
	var uvs: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in outline:
		uvs.append(p / 64.0)
	draw_colored_polygon(outline, Color(1, 1, 1, 0.07), uvs, _weave_texture())

	match _style("felt_pattern"):
		1:
			_draw_suit_pattern(shape)
		2:
			_draw_diamond_pattern(shape)

	# Sombra que a borda faz no feltro.
	var shade_in: PackedVector2Array = contour(felt_rect, shape, -14.0)
	var dark: PackedColorArray = PackedColorArray()
	var clear: PackedColorArray = PackedColorArray()
	for p: Vector2 in outline:
		dark.append(Color(0, 0, 0, 0.42))
		clear.append(Color(0, 0, 0, 0.0))
	_strips([outline, shade_in] as Array[PackedVector2Array],
		[dark, clear] as Array[PackedColorArray])

	if _style("felt_lane") == 1:
		var lane: PackedVector2Array = contour(felt_rect, shape, -24.0)
		lane.append(lane[0])
		draw_polyline(lane, Color(_color("felt_line"), float(skin.get("lane_alpha", 0.08))),
			1.5, true)


## Estampa discreta de naipes: os quatro em fileiras desencontradas, em losango, só
## dentro do feltro.
func _draw_suit_pattern(shape: int) -> void:
	var ink: Color = _color("pattern")
	var inside: PackedVector2Array = contour(felt_rect, shape, -7.0)
	var step: float = 26.0
	var size: float = 9.0
	var c: Vector2 = felt_rect.get_center()
	var rows: int = int(felt_rect.size.y / (step * 0.62)) / 2 + 2
	var cols: int = int(felt_rect.size.x / step) / 2 + 2
	for row in range(-rows, rows + 1):
		for col in range(-cols, cols + 1):
			var at: Vector2 = c + Vector2((col + 0.5 * (row & 1)) * step, row * step * 0.62)
			if not Geometry2D.is_point_in_polygon(at, inside):
				continue
			Paint.suit(self, posmod(col * 2 + row, 4), at, size, ink)


## Treliça de losangos: linhas finas em diagonal e um naipe maior no meio de cada
## losango, só dentro do feltro.
func _draw_diamond_pattern(shape: int) -> void:
	var ink: Color = _color("pattern")
	var inside: PackedVector2Array = contour(felt_rect, shape, -7.0)
	var w: float = 48.0
	var h: float = 34.0
	var c: Vector2 = felt_rect.get_center()
	var reach: float = felt_rect.size.length()
	# Lados dos losangos: 2x/w ± 2y/h = n ímpar, contando do centro do feltro.
	var count: int = int(2.0 * (felt_rect.size.x / w + felt_rect.size.y / h)) + 2
	var line_color: Color = Color(ink, ink.a * 0.7)
	for n in range(-count, count + 1):
		if n % 2 == 0:
			continue
		var start: Vector2 = c + Vector2(n * w / 2.0, 0)
		for dir: Vector2 in [Vector2(w, -h).normalized(), Vector2(w, h).normalized()]:
			var segment: PackedVector2Array = PackedVector2Array([start - dir * reach,
				start + dir * reach])
			for piece: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(
					segment, inside):
				draw_polyline(piece, line_color, 1.0, true)
	# Naipes nos centros: (i·w/2, j·h/2) com i + j par.
	var cols: int = int(felt_rect.size.x / w) + 2
	var rows: int = int(felt_rect.size.y / h) + 2
	for j in range(-rows, rows + 1):
		for i in range(-cols, cols + 1):
			if (i + j) % 2 != 0:
				continue
			var at: Vector2 = c + Vector2(i * w / 2.0, j * h / 2.0)
			if not Geometry2D.is_point_in_polygon(at, inside):
				continue
			Paint.suit(self, posmod((i + 3 * j) / 2, 4), at, 12.0, ink)


## Liga contornos vizinhos (todos com o mesmo número de pontos) em faixas de
## triângulos, com as cores de cada ponto.
func _strips(rings: Array[PackedVector2Array], colors: Array[PackedColorArray]) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	var tints: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	var n: int = rings[0].size()
	for r in rings.size():
		points.append_array(rings[r])
		tints.append_array(colors[r])
	for r in rings.size() - 1:
		for i in n:
			var a: int = r * n + i
			var b: int = r * n + (i + 1) % n
			var c: int = (r + 1) * n + i
			var d: int = (r + 1) * n + (i + 1) % n
			indices.append_array(PackedInt32Array([a, b, c, b, d, c]))
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, points, tints)


## Liga contornos abertos (o primeiro ponto repetido no fim) em faixas com textura; o
## veio da madeira não volta para trás na emenda.
func _strips_open(rings: Array[PackedVector2Array], colors: Array[PackedColorArray],
		uvs: Array[PackedVector2Array], texture: Texture2D) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	var tints: PackedColorArray = PackedColorArray()
	var coords: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var n: int = rings[0].size()
	for r in rings.size():
		points.append_array(rings[r])
		tints.append_array(colors[r])
		coords.append_array(uvs[r])
	for r in rings.size() - 1:
		for i in n - 1:
			var a: int = r * n + i
			var c: int = (r + 1) * n + i
			indices.append_array(PackedInt32Array([a, a + 1, c, a + 1, c + 1, c]))
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, points, tints,
		coords, PackedInt32Array(), PackedFloat32Array(), texture.get_rid())


## Veio da madeira: linhas claras e escuras que ondulam devagar, com fibras finas. Repete
## sem emenda no comprimento (x); a altura (y) cobre a borda inteira. Gerado uma vez.
static func _wood_texture() -> Texture2D:
	if _wood == null:
		var w: int = 256
		var h: int = 64
		var image: Image = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = 11
		var fibers: PackedFloat32Array = PackedFloat32Array()
		for y in h:
			fibers.append(rng.randf())
		for y in h:
			for x in w:
				var a: float = TAU * x / w
				var warp: float = 5.0 * sin(a + y * 0.05) + 2.5 * sin(a * 3.0 + 1.3) \
					+ 1.2 * sin(a * 7.0 + y * 0.2)
				var band: float = 0.5 + 0.5 * sin((y + warp) * 0.55)
				var ring: float = pow(band, 6.0)
				var fiber: float = fibers[clampi(y + int(warp * 0.3), 0, h - 1)]
				var v: float = 0.9 - 0.32 * ring - 0.12 * fiber + 0.06 * rng.randf()
				image.set_pixel(x, y, Color(v, v * 0.97, v * 0.93, 1.0))
		_wood = ImageTexture.create_from_image(image)
	return _wood


## Trama do feltro: ruído fino que se repete sem emenda, gerado uma vez.
static func _weave_texture() -> Texture2D:
	if _weave == null:
		var size: int = 64
		var image: Image = Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = 7
		for y in size:
			for x in size:
				var v: float = rng.randf()
				var thread: float = 0.5 + 0.5 * sin((x + y) * 1.7) * 0.4
				var light: bool = v * thread > 0.32
				image.set_pixel(x, y, Color(1, 1, 1, v * 0.6) if light else Color(0, 0, 0, v * 0.8))
		_weave = ImageTexture.create_from_image(image)
	return _weave


## Contorno da mesa com o feltro em rect, aumentado de grow (negativo encolhe). Sempre
## com o mesmo número de pontos, na mesma ordem, para as faixas da borda.
static func contour(rect: Rect2, shape: int, grow: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	var c: Vector2 = rect.get_center()
	var total: int = (ARC_POINTS + SIDE_POINTS) * 2
	if shape == 1:
		for i in total:
			var a: float = TAU * i / total
			points.append(c + Vector2(cos(a) * (rect.size.x / 2.0 + grow),
				sin(a) * (rect.size.y / 2.0 + grow)))
		return points
	# Estádio: dois lados retos e duas pontas em meia-volta.
	var r: float = minf(rect.size.x, rect.size.y) / 2.0
	var half: float = maxf(rect.size.x / 2.0 - r, 0.0)
	var radius: float = maxf(r + grow, 1.0)
	for i in SIDE_POINTS:
		points.append(c + Vector2(-half + 2.0 * half * i / SIDE_POINTS, -radius))
	for i in ARC_POINTS:
		var a: float = -PI / 2.0 + PI * i / ARC_POINTS
		points.append(c + Vector2(half, 0) + Vector2(cos(a), sin(a)) * radius)
	for i in SIDE_POINTS:
		points.append(c + Vector2(half - 2.0 * half * i / SIDE_POINTS, radius))
	for i in ARC_POINTS:
		var a: float = PI / 2.0 + PI * i / ARC_POINTS
		points.append(c + Vector2(-half, 0) + Vector2(cos(a), sin(a)) * radius)
	return points
