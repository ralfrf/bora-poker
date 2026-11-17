extends Control
## Fileira de avatares que desliza com o dedo (perfil): arrastar rola, tocar escolhe.
## Desenha os avatares ela mesma, sem botões dentro, porque um botão fica com o toque e
## o arrastar não chega a quem rola. Os grátis vêm primeiro, um fio separa os
## exclusivos e uma seta na borda mostra que há mais para o lado.

signal picked(avatar: int)

const Paint := preload("res://ui/widgets/paint.gd")
const T: String = "Tokens"

## Distância que o dedo anda antes de virar arrasto (um toque nunca anda tanto).
const DRAG_START: float = 10.0
## Espaço do fio entre os grátis e os exclusivos.
const DIVIDER: float = 14.0

var diameter: float = 40.0
var selected: int = 0
var offset: float = 0.0

var _press_x: float = 0.0
var _press_offset: float = 0.0
var _pressing: bool = false
var _dragging: bool = false
var _reveal_pending: bool = true


func _init(avatar_diameter: float, current: int) -> void:
	diameter = avatar_diameter
	selected = current
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, cell())


func cell() -> float:
	return diameter + 16.0


## Começo (em x, sem o deslocamento) da casa do avatar index.
func cell_x(index: int) -> float:
	return index * cell() + (DIVIDER if index >= Paint.FREE_AVATARS else 0.0)


func content_width() -> float:
	return cell_x(Paint.AVATAR_COUNT - 1) + cell()


func max_offset() -> float:
	return maxf(content_width() - size.x, 0.0)


## Avatar sob o ponto x da fileira, ou -1 (no fio ou fora).
func index_at(x: float) -> int:
	var content_x: float = x + offset
	for index in Paint.AVATAR_COUNT:
		var start: float = cell_x(index)
		if content_x >= start and content_x < start + cell():
			return index
	return -1


## Rola o mínimo para o avatar index ficar inteiro à vista.
func reveal(index: int) -> void:
	var start: float = cell_x(index)
	if start < offset:
		offset = start
	elif start + cell() > offset + size.x:
		offset = start + cell() - size.x
	offset = clampf(offset, 0.0, max_offset())
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		offset = clampf(offset, 0.0, max_offset())
		if _reveal_pending and size.x > 0.0:
			_reveal_pending = false
			reveal(selected)
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_LEFT:
			if button.pressed:
				_scroll_to(offset - cell())
			_accept()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN or button.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
			if button.pressed:
				_scroll_to(offset + cell())
			_accept()
		elif button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_pressing = true
				_dragging = false
				_press_x = button.position.x
				_press_offset = offset
			elif _pressing:
				_pressing = false
				if not _dragging:
					var index: int = index_at(button.position.x)
					if index >= 0:
						selected = index
						queue_redraw()
						picked.emit(index)
				_dragging = false
			_accept()
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null and _pressing:
		var moved: float = motion.position.x - _press_x
		if not _dragging and absf(moved) >= DRAG_START:
			_dragging = true
		if _dragging:
			_scroll_to(_press_offset - moved)
		_accept()


func _scroll_to(value: float) -> void:
	offset = clampf(value, 0.0, max_offset())
	queue_redraw()


func _accept() -> void:
	if is_inside_tree():
		accept_event()


func _draw() -> void:
	var accent: Color = get_theme_color("accent", T)
	var line: Color = get_theme_color("surface_line", T)
	var bg: Color = get_theme_color("bg", T)
	var colors: Array[Color] = Paint.avatar_colors(self)
	var radius: float = diameter / 2.0
	var mid: float = size.y / 2.0
	for index in Paint.AVATAR_COUNT:
		var left: float = cell_x(index) - offset
		if left + cell() < 0.0 or left > size.x:
			continue
		var center: Vector2 = Vector2(left + cell() / 2.0, mid)
		if index == selected:
			draw_circle(center, radius + 7.0, Color(accent, 0.16), true, -1.0, true)
			draw_arc(center, radius + 4.0, 0, TAU, 64, accent, 3.0, true)
		else:
			draw_circle(center, radius + 1.5, line, true, -1.0, true)
		Paint.avatar(self, Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0),
			index, colors, 0, 0.0)
		if index != selected:
			draw_circle(center, radius, Color(bg, 0.35), true, -1.0, true)
	var divider_x: float = cell_x(Paint.FREE_AVATARS) - DIVIDER / 2.0 - offset
	draw_line(Vector2(divider_x, mid - radius), Vector2(divider_x, mid + radius), line, 1.0)
	if offset > 0.5:
		_edge(false, bg, accent)
	if offset < max_offset() - 0.5:
		_edge(true, bg, accent)


## Borda que esmaece com uma seta, do lado onde ainda há avatares escondidos.
func _edge(right: bool, bg: Color, ink: Color) -> void:
	var w: float = 30.0
	var x0: float = size.x - w if right else 0.0
	var outer: Color = Color(bg, 0.95)
	var inner: Color = Color(bg, 0.0)
	var a: Color = inner if right else outer
	var b: Color = outer if right else inner
	draw_polygon(PackedVector2Array([Vector2(x0, 0), Vector2(x0 + w, 0),
		Vector2(x0 + w, size.y), Vector2(x0, size.y)]), PackedColorArray([a, b, b, a]))
	var cx: float = size.x - 10.0 if right else 10.0
	var dir: float = 1.0 if right else -1.0
	var mid: float = size.y / 2.0
	draw_polyline(PackedVector2Array([Vector2(cx - dir * 4.0, mid - 8.0),
		Vector2(cx + dir * 3.0, mid), Vector2(cx - dir * 4.0, mid + 8.0)]), ink, 2.5, true)
