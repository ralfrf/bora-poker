extends Control
## Confete caindo por alguns segundos (pódio do torneio). Papeizinhos nas cores das
## fichas, girando; depois some e para de desenhar, para poupar bateria.

const T: String = "Tokens"
const PIECES: int = 70
const DURATION: float = 4.0

var _pieces: Array = []   # [posição, velocidade, ângulo, giro, cor, tamanho]
var _time: float = 0.0
var _running: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func burst(seed_value: int = 7) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var colors: Array[Color] = []
	for key: String in ["chip_0", "chip_1", "chip_2", "chip_3", "ok", "accent_top"]:
		colors.append(get_theme_color(key, T))
	_pieces.clear()
	for i in PIECES:
		_pieces.append([
			Vector2(rng.randf_range(0.0, size.x), rng.randf_range(-size.y * 0.8, -10.0)),
			Vector2(rng.randf_range(-30.0, 30.0), rng.randf_range(70.0, 150.0)),
			rng.randf_range(0.0, TAU), rng.randf_range(-6.0, 6.0),
			colors[rng.randi() % colors.size()], Vector2(rng.randf_range(4.0, 7.0),
				rng.randf_range(7.0, 11.0))])
	_time = 0.0
	_running = true
	modulate.a = 1.0
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	for piece: Array in _pieces:
		piece[0] += piece[1] * delta + Vector2(sin(_time * 3.0 + piece[2]) * 18.0 * delta, 0)
		piece[2] += piece[3] * delta
	if _time > DURATION - 0.8:
		modulate.a = clampf((DURATION - _time) / 0.8, 0.0, 1.0)
	if _time >= DURATION:
		_running = false
		set_process(false)
	queue_redraw()


func _draw() -> void:
	if not _running:
		return
	for piece: Array in _pieces:
		var pos: Vector2 = piece[0]
		if pos.y < -12.0 or pos.y > size.y + 12.0:
			continue
		var s: Vector2 = piece[5]
		# O giro em 3D é imitado encolhendo a largura com o cosseno.
		var squash: float = absf(cos(piece[2] * 1.7))
		draw_set_transform(pos, piece[2], Vector2(maxf(squash, 0.15), 1.0))
		draw_rect(Rect2(-s / 2.0, s), piece[4])
	draw_set_transform(Vector2.ZERO)
