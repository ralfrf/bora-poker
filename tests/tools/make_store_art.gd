extends SceneTree
## Gera as imagens da página da Play com as peças do próprio jogo: a imagem de destaque
## (feature.png, 1024x500, sem transparência) e o ícone da loja (icon_512.png, quadrado
## cheio: a Play arredonda os cantos sozinha).
##
## Precisa de tela (sem --headless), como a ferramenta de fotos. Salve fora do projeto:
##   godot --path . -s res://tests/tools/make_store_art.gd -- --out=C:/caminho/pasta

const Paint := preload("res://ui/widgets/paint.gd")
const UiTheme := preload("res://ui/theme/ui_theme.gd")
const Cards := preload("res://engine/cards.gd")
const Backdrop := preload("res://ui/widgets/backdrop.gd")
const TableFelt := preload("res://ui/widgets/table_felt.gd")
const CardView := preload("res://ui/widgets/card_view.gd")
const T: String = "Tokens"


## Lado esquerdo da imagem de destaque: a marca e os três pontos principais (sem
## cadastro, até 9 na mesa, offline e online), cada um com um selo dourado.
class Title:
	extends Control

	func _draw() -> void:
		var display: Font = get_theme_font("display", T)
		var strong: Font = get_theme_font("strong", T)
		var body: Font = get_theme_font("text", T)
		var text: Color = get_theme_color("text", T)
		var dim: Color = get_theme_color("text_dim", T)
		var shadow: Color = Color(0, 0, 0, 0.55)
		Paint.chip(self, Vector2(78, 72), 34, get_theme_color("chip_0", T),
			get_theme_color("chip_mark", T), get_theme_constant("chip_style", T))
		_text(display, Vector2(126, 94), "Bora Poker", 62, text, shadow)
		var rows: Array = [
			["check", "Sem cadastro", "Só um apelido para jogar"],
			["nine", "Até 9 na mesa", "Com amigos ou com bots"],
			["globe", "Offline e Online", "Sozinho, no mesmo Wi-Fi ou à distância"],
		]
		for i in rows.size():
			var y: float = 172.0 + i * 92.0
			_badge(rows[i][0], Vector2(78, y))
			_text(strong, Vector2(128, y + 4), rows[i][1], 40, text, shadow)
			_text(body, Vector2(130, y + 34), rows[i][2], 21, dim, shadow)
		_text(body, Vector2(48, 440), "Bots inteligentes com diferentes personalidades", 20, dim,
			shadow)
		_text(body, Vector2(48, 470), "Fichas virtuais · sem dinheiro real", 20, dim, shadow)

	## Selo dourado com o desenho do ponto: visto, o número 9 ou o globo.
	func _badge(kind: String, center: Vector2) -> void:
		var accent: Color = get_theme_color("accent", T)
		var ink: Color = get_theme_color("on_accent", T)
		var r: float = 30.0
		draw_circle(center + Vector2(0, 3), r, Color(0, 0, 0, 0.45))
		draw_circle(center, r, accent)
		draw_circle(center + Vector2(-6, -8), r * 0.5, Color(get_theme_color("accent_top", T), 0.45))
		match kind:
			"check":
				draw_polyline(PackedVector2Array([center + Vector2(-13, 1), center + Vector2(-4, 11),
					center + Vector2(14, -10)]), ink, 6.0, true)
			"nine":
				var font: Font = get_theme_font("display", T)
				draw_string(font, center + Vector2(-r, 14), "9", HORIZONTAL_ALIGNMENT_CENTER,
					r * 2.0, 40, ink)
			"globe":
				draw_arc(center, 16, 0, TAU, 40, ink, 3.5, true)
				draw_line(center + Vector2(-16, 0), center + Vector2(16, 0), ink, 3.0, true)
				var meridian: PackedVector2Array = PackedVector2Array()
				for k in 41:
					var t: float = TAU * k / 40.0
					meridian.append(center + Vector2(cos(t) * 7.0, sin(t) * 16.0))
				draw_polyline(meridian, ink, 3.0, true)

	func _text(font: Font, at: Vector2, value: String, font_size: int, color: Color,
			shadow: Color) -> void:
		draw_string(font, at + Vector2(0, 3), value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
			shadow)
		draw_string(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## Nove retratos em volta da mesa: mostra o "até 9" sem texto.
class Seats:
	extends Control

	var center: Vector2 = Vector2(792, 262)
	var radii: Vector2 = Vector2(182, 150)

	func _draw() -> void:
		var colors: Array[Color] = Paint.avatar_colors(self)
		var faces: Array[int] = [0, 11, 3, 13, 6, 15, 8, 17, 1]
		for i in 9:
			var angle: float = PI / 2.0 + TAU * i / 9.0
			var at: Vector2 = center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y)
			var r: float = 31.0
			draw_circle(at + Vector2(0, 4), r + 3.0, Color(0, 0, 0, 0.5))
			draw_circle(at, r + 3.0, get_theme_color("rail_line", T))
			Paint.avatar(self, Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0),
				Paint.FREE_AVATARS + faces[i], colors, 0, 0.0)


## Pilhas de fichas sobre o feltro.
class Stacks:
	extends Control

	func _draw() -> void:
		var mark: Color = get_theme_color("chip_mark", T)
		var c: Array[Color] = []
		for i in 5:
			c.append(get_theme_color("chip_%d" % i, T))
		Paint.chip_stack(self, Vector2(888, 300), 20, [c[1], c[1], c[2], c[1], c[0]], mark)
		Paint.chip_stack(self, Vector2(918, 318), 20, [c[2], c[2], c[0], c[2]], mark)
		Paint.chip_stack(self, Vector2(696, 318), 20, [c[4], c[0], c[0], c[3], c[0], c[0]],
			mark)


## O ícone da loja: fundo de salão e a ficha dourada no centro.
class Icon:
	extends Control

	func _draw() -> void:
		var top: Color = get_theme_color("bg_top", T)
		var bottom: Color = get_theme_color("bg", T)
		draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size,
			Vector2(0, size.y)]), PackedColorArray([top, top, bottom, bottom]))
		var center: Vector2 = size / 2.0
		var glow: Vector2 = size * 1.1
		draw_texture_rect(Paint.soft_disc(), Rect2(center - glow / 2.0, glow), false,
			Color(get_theme_color("bokeh_0", T), 0.35))
		var radius: float = size.x * 0.74 / 2.0 / 1.05
		Paint.chip(self, center - Vector2(0, radius * 0.05), radius,
			get_theme_color("chip_0", T), get_theme_color("chip_mark", T),
			get_theme_constant("chip_style", T))


func _initialize() -> void:
	OS.low_processor_usage_mode = false
	var out: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	if out == "":
		printerr("uso: -- --out=C:/caminho/pasta")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	await _render(out.path_join("feature.png"), Vector2i(1024, 500), _feature())
	var icon: Icon = Icon.new()
	await _render(out.path_join("icon_512.png"), Vector2i(512, 512), icon)
	quit(0)


func _feature() -> Control:
	var canvas: Control = Control.new()
	canvas.size = Vector2(1024, 500)
	var backdrop: Control = Backdrop.new()
	backdrop.size = canvas.size
	canvas.add_child(backdrop)
	var felt: Control = TableFelt.new()
	felt.show_room = false
	felt.size = canvas.size
	felt.felt_rect = Rect2(612, 120, 376, 284)
	canvas.add_child(felt)
	var stacks: Control = Stacks.new()
	stacks.size = canvas.size
	canvas.add_child(stacks)
	_card(canvas, "Ah", Vector2(730, 190), -9.0)
	_card(canvas, "As", Vector2(800, 184), 7.0)
	var seats: Control = Seats.new()
	seats.size = canvas.size
	canvas.add_child(seats)
	var title: Control = Title.new()
	title.size = canvas.size
	canvas.add_child(title)
	return canvas


func _card(parent: Control, text: String, at: Vector2, degrees: float) -> void:
	var card: Control = CardView.new()
	card.card = Cards.from_text(text)
	card.glow = true
	card.size = Vector2(76, 106)
	card.position = at
	card.pivot_offset = card.size / 2.0
	card.rotation_degrees = degrees
	parent.add_child(card)


func _render(path: String, side: Vector2i, content: Control) -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = side
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	content.theme = UiTheme.current()
	content.size = Vector2(side)
	viewport.add_child(content)
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	# A Play pede PNG de 24 bits na imagem de destaque e aceita 32 no ícone; sem
	# transparência nos dois.
	image.convert(Image.FORMAT_RGB8)
	image.save_png(path)
	print("salvo: ", path)
	viewport.queue_free()
