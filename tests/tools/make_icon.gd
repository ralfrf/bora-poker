extends SceneTree
## Gera o ícone do app a partir da mesma ficha dourada do jogo (Paint.chip), em
## ui/icon/: icon.png (1024, fundo transparente, ícone do projeto), e as duas camadas
## do ícone adaptável do Android, icon_foreground.png e icon_background.png (432).
##
## Precisa de tela (sem --headless), como a ferramenta de fotos:
##   godot --path . -s res://tests/tools/make_icon.gd

const Paint := preload("res://ui/widgets/paint.gd")
const UiTheme := preload("res://ui/theme/ui_theme.gd")
const T: String = "Tokens"
const OUT: String = "res://ui/icon/"


## Desenha uma camada do ícone num controle do tamanho da imagem.
class Layer:
	extends Control

	## "chip" (só a ficha, com a fração do lado dada em fill) ou "background".
	var kind: String = "chip"
	var fill: float = 0.92

	func _draw() -> void:
		var center: Vector2 = size / 2.0
		if kind == "background":
			var top: Color = get_theme_color("bg_top", T)
			var bottom: Color = get_theme_color("bg", T)
			draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size,
				Vector2(0, size.y)]), PackedColorArray([top, top, bottom, bottom]))
			var glow: Vector2 = size * 1.1
			draw_texture_rect(Paint.soft_disc(), Rect2(center - glow / 2.0, glow), false,
				Color(get_theme_color("bokeh_0", T), 0.35))
			return
		# A ficha tem uma sombra curta embaixo; sobe um pouco para ficar centrada.
		var radius: float = size.x * fill / 2.0 / 1.05
		Paint.chip(self, center - Vector2(0, radius * 0.05), radius,
			get_theme_color("chip_0", T), get_theme_color("chip_mark", T),
			get_theme_constant("chip_style", T))


func _initialize() -> void:
	OS.low_processor_usage_mode = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	await _render("icon.png", 1024, "chip", 0.94, true)
	# Camada da frente do ícone adaptável: a ficha bem dentro da zona segura (66% do lado).
	await _render("icon_foreground.png", 432, "chip", 0.56, true)
	await _render("icon_background.png", 432, "background", 1.0, false)
	quit(0)


func _render(file: String, side: int, kind: String, fill: float, transparent: bool) -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(side, side)
	viewport.transparent_bg = transparent
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var layer: Layer = Layer.new()
	layer.theme = UiTheme.current()
	layer.kind = kind
	layer.fill = fill
	layer.size = Vector2(side, side)
	viewport.add_child(layer)
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT + file))
	print("ícone salvo: ", OUT + file)
	viewport.queue_free()
