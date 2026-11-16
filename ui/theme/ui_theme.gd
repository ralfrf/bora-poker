extends RefCounted
## O tema único do jogo. Monta um Theme do Godot a partir de uma direção visual
## (ui/theme/directions.gd). Cores, fontes, tamanhos, raios e estilos das peças ficam
## no tipo "Tokens"; as peças desenhadas (cartas, fichas, mesa) leem dali.
##
## Tamanhos de texto: só três (SMALL, BODY, LARGE).

const Directions := preload("res://ui/theme/directions.gd")
const GlossBox := preload("res://ui/theme/gloss_box.gd")

const TOKENS: String = "Tokens"
const SMALL: int = 12
const BODY: int = 15
const LARGE: int = 22

## Direção em uso no app.
const ACTIVE: int = 0

static var _current: Theme = null
static var _fonts: Dictionary = {}


static func current() -> Theme:
	if _current == null:
		_current = build(Directions.ALL[ACTIVE])
	return _current


static func build(direction: Dictionary) -> Theme:
	var theme: Theme = Theme.new()
	var fonts: Array = direction["fonts"]
	var text_font: Font = _variation(fonts[0], fonts[1])
	var text_strong: Font = _variation(fonts[0], maxi(int(fonts[1]) + 150, 650))
	var display: Font = _variation(fonts[2], fonts[3])
	var colors: Dictionary = {}
	for key: String in direction["colors"]:
		colors[key] = Color.html(direction["colors"][key])
		theme.set_color(key, TOKENS, colors[key])
	for key: String in direction["radius"]:
		theme.set_constant("radius_" + key, TOKENS, direction["radius"][key])
	for key: String in direction["style"]:
		theme.set_constant(key, TOKENS, direction["style"][key])
	theme.set_font("text", TOKENS, text_font)
	theme.set_font("strong", TOKENS, text_strong)
	theme.set_font("display", TOKENS, display)
	theme.set_font_size("small", TOKENS, SMALL)
	theme.set_font_size("body", TOKENS, BODY)
	theme.set_font_size("large", TOKENS, LARGE)

	theme.default_font = text_font
	theme.default_font_size = BODY
	theme.set_color("font_color", "Label", colors["text"])
	# Sombra curta em todo texto, para ler bem sobre o fundo com luzes.
	theme.set_color("font_shadow_color", "Label", Color(colors["shadow"], 0.5))
	theme.set_constant("shadow_offset_x", "Label", 0)
	theme.set_constant("shadow_offset_y", "Label", 1)

	_label(theme, "SmallLabel", text_font, SMALL, colors["text_dim"])
	_label(theme, "NameLabel", text_strong, SMALL, colors["text"])
	_label(theme, "AmountLabel", display, SMALL, colors["text"])
	_label(theme, "PotLabel", display, LARGE, colors["text"])
	_label(theme, "TitleLabel", display, LARGE, colors["text"])
	_label(theme, "DimLabel", text_font, BODY, colors["text_dim"])
	_label(theme, "NumberLabel", display, BODY, colors["text"])
	_label(theme, "StrongLabel", text_strong, BODY, colors["text"])

	var radius: int = direction["radius"]["button"]
	# Botões com volume: o comum em vidro azul-noite, o principal em ouro, Pagar em
	# azul e Desistir em vinho. QuietButton é vidro claro e translúcido.
	_button(theme, "Button", text_strong, colors["button_top"], colors["button"],
		colors["button_line"], colors["text"], radius, 0.22)
	var primary: GlossBox = _button(theme, "PrimaryButton", text_strong, colors["accent_top"],
		colors["accent"], colors["accent_line"], colors["on_accent"], radius, 0.75)
	primary.glow = Color(colors["accent"], 0.22)
	_button(theme, "CallButton", text_strong, colors["call_top"], colors["call"],
		colors["call_line"], colors["text"], radius, 0.35)
	_button(theme, "FoldButton", text_strong, colors["fold_top"], colors["fold"],
		colors["fold_line"], colors["text"], radius, 0.3)
	_button(theme, "QuietButton", text_font, Color(1, 1, 1, 0.13), Color(1, 1, 1, 0.05),
		Color(1, 1, 1, 0.12), colors["text"], radius, 0.2)
	_choice(theme, text_strong, colors, radius)
	_line_edit(theme, text_font, colors, radius)
	_panels(theme, colors, direction["radius"]["panel"])
	_slider(theme, colors)
	theme.set_icon("chip", TOKENS, _chip_icon(colors["chip_0"], colors["chip_mark"]))
	return theme


## Ícone de ficha de 14 px, para pôr ao lado de valores em textos e botões.
static func _chip_icon(fill: Color, mark: Color) -> Texture2D:
	var size: int = 56
	var image: Image = Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var center: Vector2 = Vector2(size, size) / 2.0 - Vector2(0.5, 0.5)
	var r: float = size / 2.0 - 1.0
	for y in size:
		for x in size:
			var offset: Vector2 = Vector2(x, y) - center
			var d: float = offset.length()
			var color: Color = fill.darkened(0.25)
			if d < r * 0.9:
				color = fill
			var a: float = fposmod(offset.angle(), TAU / 6.0) - TAU / 12.0
			if d > r * 0.66 and d < r * 0.88 and absf(a) < 0.17:
				color = mark
			if absf(d - r * 0.5) < r * 0.07:
				color = fill.lerp(mark, 0.85)
			color.a = clampf(r - d, 0.0, 1.0)
			image.set_pixel(x, y, color)
	image.resize(14, 14, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(image)


## Botão de escolha (opções da sala, modos, avatares): vidro apagado quando solto e
## vidro dourado com contorno do destaque quando escolhido.
static func _choice(theme: Theme, font: Font, colors: Dictionary, radius: int) -> void:
	_button(theme, "ChoiceButton", font, Color(1, 1, 1, 0.09), Color(1, 1, 1, 0.03),
		Color(1, 1, 1, 0.10), colors["text_dim"], radius, 0.12)
	var chosen: GlossBox = _gloss(Color(colors["accent"], 0.34), Color(colors["accent"], 0.12),
		colors["accent"], radius, 0.35)
	chosen.rim_width = 2
	for state: String in ["normal", "hover", "disabled"]:
		var box: GlossBox = theme.get_stylebox(state, "ChoiceButton") as GlossBox
		box.content_margin_left = 4
		box.content_margin_right = 4
	_margins(chosen, 4, 6)
	theme.set_stylebox("pressed", "ChoiceButton", chosen)
	theme.set_stylebox("hover_pressed", "ChoiceButton", chosen)
	theme.set_font_size("font_size", "ChoiceButton", BODY)
	theme.set_color("font_hover_color", "ChoiceButton", colors["text"])
	theme.set_color("font_pressed_color", "ChoiceButton", colors["text"])
	theme.set_color("font_hover_pressed_color", "ChoiceButton", colors["text"])


static func _line_edit(theme: Theme, font: Font, colors: Dictionary, radius: int) -> void:
	# Campo afundado: mais escuro em cima, como um entalhe.
	var normal: GlossBox = _gloss(Color(colors["bg"], 0.9), Color(colors["surface"], 0.9),
		Color(1, 1, 1, 0.12), radius, 0.0)
	_margins(normal, 14, 8)
	var focus: StyleBoxFlat = _box(Color(0, 0, 0, 0), radius)
	focus.draw_center = false
	focus.set_border_width_all(2)
	focus.border_color = colors["accent"]
	theme.set_stylebox("normal", "LineEdit", normal)
	theme.set_stylebox("read_only", "LineEdit", normal)
	theme.set_stylebox("focus", "LineEdit", focus)
	theme.set_font("font", "LineEdit", font)
	theme.set_font_size("font_size", "LineEdit", LARGE)
	theme.set_color("font_color", "LineEdit", colors["text"])
	theme.set_color("font_placeholder_color", "LineEdit", Color(colors["text_dim"], 0.7))
	theme.set_color("caret_color", "LineEdit", colors["accent"])
	theme.set_color("selection_color", "LineEdit", Color(colors["accent"], 0.35))
	theme.set_constant("caret_width", "LineEdit", 2)


## Painel de cartão (modos do início, placar) e de diálogo: vidro escuro com brilho
## no alto; o diálogo é mais opaco e tem sombra.
static func _panels(theme: Theme, colors: Dictionary, radius: int) -> void:
	var card: GlossBox = _gloss(Color(colors["surface_top"], 0.72), Color(colors["surface"], 0.86),
		Color(colors["surface_line"], 0.8), radius, 0.14)
	card.set_content_margin_all(12)
	theme.set_type_variation("CardPanel", "PanelContainer")
	theme.set_stylebox("panel", "CardPanel", card)
	var dialog: GlossBox = _gloss(colors["surface_top"], colors["surface"],
		colors["surface_line"], radius, 0.18)
	dialog.shadow_color = Color(colors["shadow"], 0.6)
	dialog.shadow_size = 20
	dialog.shadow_offset = Vector2(0, 8)
	dialog.set_content_margin_all(18)
	theme.set_type_variation("DialogPanel", "PanelContainer")
	theme.set_stylebox("panel", "DialogPanel", dialog)
	# Painel solto (folha de aposta), igual ao diálogo, com menos margem.
	var sheet: GlossBox = dialog.duplicate() as GlossBox
	sheet.set_content_margin_all(8)
	theme.set_type_variation("SheetPanel", "PanelContainer")
	theme.set_stylebox("panel", "SheetPanel", sheet)


static func _label(theme: Theme, type_name: String, font: Font, size: int,
		color: Color) -> void:
	theme.set_type_variation(type_name, "Label")
	theme.set_font("font", type_name, font)
	theme.set_font_size("font_size", type_name, size)
	theme.set_color("font_color", type_name, color)


## Botão com volume: degradê de top a bottom, contorno line, sombra; apertado fica
## mais escuro e encosta na mesa; desativado fica apagado. Devolve o estilo normal.
static func _button(theme: Theme, type_name: String, font: Font, top: Color,
		bottom: Color, line: Color, ink: Color, radius: int, shine: float) -> GlossBox:
	if type_name != "Button":
		theme.set_type_variation(type_name, "Button")
	var normal: GlossBox = _gloss(top, bottom, line, radius, shine)
	_margins(normal, 12, 8)
	if bottom.a > 0.5:
		normal.shadow_color = Color(0, 0, 0, 0.45)
		normal.shadow_size = 5
		normal.shadow_offset = Vector2(0, 3)
	var hover: GlossBox = normal.tinted(top.lightened(0.05),
		bottom.lightened(0.05)) as GlossBox
	var pressed: GlossBox = normal.tinted(bottom.darkened(0.08), top.darkened(0.2), 1) as GlossBox
	pressed.shine = shine * 0.3
	pressed.glow = Color(0, 0, 0, 0)
	var disabled: GlossBox = normal.tinted(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.03),
		0) as GlossBox
	disabled.rim = Color(1, 1, 1, 0.1)
	disabled.glow = Color(0, 0, 0, 0)
	disabled.shine = 0.0
	theme.set_stylebox("normal", type_name, normal)
	theme.set_stylebox("hover", type_name, hover)
	theme.set_stylebox("pressed", type_name, pressed)
	theme.set_stylebox("hover_pressed", type_name, pressed)
	theme.set_stylebox("disabled", type_name, disabled)
	theme.set_stylebox("focus", type_name, StyleBoxEmpty.new())
	theme.set_font("font", type_name, font)
	theme.set_font_size("font_size", type_name, BODY)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color",
			"font_hover_pressed_color", "font_focus_color"]:
		theme.set_color(state, type_name, ink)
	theme.set_color("font_disabled_color", type_name, Color(1, 1, 1, 0.35))
	# Texto claro ganha sombra; texto escuro (botão dourado) não precisa.
	if ink.get_luminance() > 0.5:
		theme.set_color("font_shadow_color", type_name, Color(0, 0, 0, 0.45))
		theme.set_constant("shadow_offset_y", type_name, 1)
		theme.set_constant("shadow_offset_x", type_name, 0)
	return normal


static func _gloss(top: Color, bottom: Color, rim: Color, radius: int, shine: float) -> GlossBox:
	var box: GlossBox = GlossBox.new()
	box.top = top
	box.bottom = bottom
	box.rim = rim
	box.radius = radius
	box.shine = shine
	return box


static func _margins(box: GlossBox, horizontal: float, vertical: float) -> void:
	box.content_margin_left = horizontal
	box.content_margin_right = horizontal
	box.content_margin_top = vertical
	box.content_margin_bottom = vertical


static func _slider(theme: Theme, colors: Dictionary) -> void:
	var track: StyleBoxFlat = _box(colors["surface_line"], 3)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var filled: StyleBoxFlat = _box(colors["accent"], 3)
	filled.content_margin_top = 3
	filled.content_margin_bottom = 3
	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", filled)
	theme.set_stylebox("grabber_area_highlight", "HSlider", filled)
	var knob: Texture2D = _knob(colors["accent"], colors["on_accent"])
	theme.set_icon("grabber", "HSlider", knob)
	theme.set_icon("grabber_highlight", "HSlider", knob)
	theme.set_constant("center_grabber", "HSlider", 1)


static func _box(fill: Color, radius: int) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(radius)
	box.anti_aliasing = true
	box.corner_detail = 12
	return box


## Pegador do controle deslizante: círculo de 28 px desenhado com bordas suaves.
static func _knob(fill: Color, ring: Color) -> Texture2D:
	var size: int = 56
	var image: Image = Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var center: Vector2 = Vector2(size, size) / 2.0 - Vector2(0.5, 0.5)
	for y in size:
		for x in size:
			var d: float = Vector2(x, y).distance_to(center)
			var outer: float = clampf(size / 2.0 - 1.0 - d, 0.0, 1.0)
			var inner: float = clampf(size / 2.0 - 9.0 - d, 0.0, 1.0)
			var color: Color = ring.lerp(fill, inner)
			color.a = outer
			image.set_pixel(x, y, color)
	image.resize(28, 28, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(image)


static func _variation(font_name: String, weight: int) -> Font:
	var variation: FontVariation = FontVariation.new()
	variation.base_font = _font_file(font_name)
	var weight_tag: int = TextServerManager.get_primary_interface().name_to_tag("wght")
	variation.variation_opentype = {weight_tag: weight}
	return variation


## Fonte embutida em ui/fonts. Sem a pasta .godot (testes no Docker) lê o arquivo cru.
static func _font_file(font_name: String) -> FontFile:
	if _fonts.has(font_name):
		return _fonts[font_name]
	var path: String = "res://ui/fonts/%s.ttf" % font_name
	var file: FontFile = null
	if ResourceLoader.exists(path):
		file = load(path)
	if file == null:
		file = FontFile.new()
		file.load_dynamic_font(path)
	_fonts[font_name] = file
	return file
