extends RefCounted
## O tema único do jogo. Monta um Theme do Godot a partir de uma direção visual
## (ui/theme/directions.gd). Cores, fontes, tamanhos, raios e estilos das peças ficam
## no tipo "Tokens"; as peças desenhadas (cartas, fichas, mesa) leem dali.
##
## Tamanhos de texto: só três (SMALL, BODY, LARGE).

const Directions := preload("res://ui/theme/directions.gd")

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

	_label(theme, "SmallLabel", text_font, SMALL, colors["text_dim"])
	_label(theme, "NameLabel", text_strong, SMALL, colors["text"])
	_label(theme, "AmountLabel", display, SMALL, colors["text"])
	_label(theme, "PotLabel", display, LARGE, colors["text"])
	_label(theme, "TitleLabel", display, LARGE, colors["text"])
	_label(theme, "DimLabel", text_font, BODY, colors["text_dim"])

	var radius: int = direction["radius"]["button"]
	var border: int = direction["style"]["button_border"]
	_button(theme, "Button", text_strong, colors["button"], colors["button_line"],
		colors["text"], radius, border, colors)
	_button(theme, "PrimaryButton", text_strong, colors["accent"], colors["accent"],
		colors["on_accent"], radius, 0, colors)
	_button(theme, "QuietButton", text_font, Color(colors["surface_line"], 0.55),
		colors["button_line"], colors["text"], radius, 1 if border == 2 else 0, colors)
	_slider(theme, colors)
	return theme


static func _label(theme: Theme, type_name: String, font: Font, size: int,
		color: Color) -> void:
	theme.set_type_variation(type_name, "Label")
	theme.set_font("font", type_name, font)
	theme.set_font_size("font_size", type_name, size)
	theme.set_color("font_color", type_name, color)


static func _button(theme: Theme, type_name: String, font: Font, fill: Color,
		line: Color, ink: Color, radius: int, border: int, colors: Dictionary) -> void:
	if type_name != "Button":
		theme.set_type_variation(type_name, "Button")
	var normal: StyleBoxFlat = _box(fill, radius)
	normal.set_border_width_all(border)
	normal.border_color = line
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	if colors["bg"].get_luminance() > 0.5 and fill.a > 0.0:
		normal.shadow_color = Color(colors["shadow"], 0.10)
		normal.shadow_size = 6
		normal.shadow_offset = Vector2(0, 2)
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = fill.darkened(0.12) if fill.a > 0.0 else Color(line, 0.25)
	pressed.shadow_size = 0
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = fill.lightened(0.04) if fill.a > 0.0 else fill
	var disabled: StyleBoxFlat = normal.duplicate()
	disabled.bg_color = Color(fill, fill.a * 0.4)
	disabled.border_color = Color(line, 0.4)
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
	theme.set_color("font_disabled_color", type_name, Color(ink, 0.4))


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
