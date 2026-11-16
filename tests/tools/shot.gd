extends SceneTree
## Foto de uma cena: abre a cena, espera ela se arrumar e salva um PNG.
##
## Precisa de tela (sem --headless), porque o modo sem tela não desenha nada:
##   godot --path . -s res://tests/tools/shot.gd -- --scene=res://ui/x.tscn
##       --size=360x800 --scale=2 --out=C:/caminho/foto.png [--frames=20]
##
## --size é a tela simulada, em pixels; o tamanho lógico (o que a interface enxerga)
## sai da mesma regra de escala do projeto (canvas_items + expand sobre a base do projeto), como
## no celular. --logical=LxA usa um tamanho lógico direto (quadros de comparação).
## --scale multiplica os pixels da foto, para dar para ver os detalhes. A cena é
## desenhada num SubViewport: a foto não depende da janela nem da tela do computador.
## Outras opções depois de -- ficam disponíveis para a cena em OS.get_cmdline_user_args().

const UiTheme := preload("res://ui/theme/ui_theme.gd")


func _initialize() -> void:
	# No modo de baixo consumo do app a tela parada não redesenha, e a foto esperaria
	# para sempre por um quadro desenhado.
	OS.low_processor_usage_mode = false
	var options: Dictionary = {}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var parts: PackedStringArray = arg.substr(2).split("=", true, 1)
			options[parts[0]] = parts[1]
	var scene_path: String = options.get("scene", "")
	var out: String = options.get("out", "")
	if scene_path == "" or out == "":
		printerr("uso: --scene=res://... --out=arquivo.png [--size=360x800] [--scale=2]")
		quit(1)
		return
	var screen: Vector2 = _pair(options.get("size", "360x800"))
	var base: Vector2 = Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height")))
	var fit: float = minf(screen.x / base.x, screen.y / base.y)
	var logical: Vector2i = Vector2i((screen / fit).round())
	var pixel_scale: float = float(options.get("scale", "1")) * fit
	if options.has("logical"):
		logical = Vector2i(_pair(options["logical"]))
		pixel_scale = float(options.get("scale", "1"))
	_take(scene_path, out, logical, pixel_scale, int(options.get("frames", "20")))


func _pair(text: String) -> Vector2:
	var parts: PackedStringArray = text.split("x")
	return Vector2(float(parts[0]), float(parts[1]))


func _take(scene_path: String, out: String, logical: Vector2i, pixel_scale: float,
		frames: int) -> void:
	var packed: PackedScene = load(scene_path)
	if packed == null:
		printerr("cena não encontrada: ", scene_path)
		quit(1)
		return
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(Vector2(logical) * pixel_scale)
	viewport.size_2d_override = logical
	viewport.size_2d_override_stretch = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	root.add_child(viewport)
	# Moldura com o tema do jogo, para a cena herdar cores e fontes como no app.
	var frame: Control = Control.new()
	frame.theme = UiTheme.current()
	frame.size = Vector2(logical)
	viewport.add_child(frame)
	var scene: Node = packed.instantiate()
	frame.add_child(scene)
	if scene is Control:
		(scene as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	var error: int = image.save_png(out)
	if error != OK:
		printerr("não consegui salvar ", out, " (erro ", error, ")")
		quit(1)
		return
	print("foto salva: ", out, " (", image.get_width(), "x", image.get_height(), ")")
	quit(0)
