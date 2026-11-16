extends Control
## Pódio do torneio (SPEC 3.5 e 11.1): três degraus (2º à esquerda, 1º no meio, 3º à
## direita), cada um com o avatar, a medalha e o apelido. Os degraus sobem e os
## avatares aparecem do 3º para o 1º; o campeão ganha uma coroa.

const Paint := preload("res://ui/widgets/paint.gd")
const T: String = "Tokens"

## Ordem dos degraus da esquerda para a direita (índice em entries).
const ORDER: Array[int] = [1, 0, 2]
const HEIGHTS: Array[float] = [0.4, 0.29, 0.21]   # 1º, 2º, 3º (fração da altura)

## Até três linhas, do 1º ao 3º: {nick, avatar, place, me}.
var entries: Array = []
## 0 a 1: altura dos degraus (animada).
var rise: float = 1.0:
	set(value):
		rise = value
		queue_redraw()
## 0 a 3: quantos avatares já apareceram (3º, depois 2º, depois 1º).
var reveal: float = 3.0:
	set(value):
		reveal = value
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Anima a entrada: degraus sobem, depois os avatares aparecem.
func play() -> void:
	rise = 0.0
	reveal = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(self, "rise", 1.0, 0.55).set_trans(Tween.TRANS_CUBIC) \
		.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "reveal", 3.0, 1.0)


func _draw() -> void:
	var count: int = mini(entries.size(), 3)
	if count == 0:
		return
	var gap: float = 8.0
	var step_w: float = minf((size.x - gap * 2.0) / 3.0, 150.0)
	var total_w: float = step_w * 3.0 + gap * 2.0
	var left: float = (size.x - total_w) / 2.0
	var medals: Array[Color] = [get_theme_color("accent", T), get_theme_color("medal_silver", T),
		get_theme_color("medal_bronze", T)]
	var colors: Array[Color] = Paint.avatar_colors(self)
	var strong: Font = get_theme_font("strong", T)
	var display: Font = get_theme_font("display", T)
	var small: int = get_theme_font_size("small", T)
	var body: int = get_theme_font_size("body", T)
	for column in 3:
		var rank: int = ORDER[column]    # 0 = 1º lugar
		if rank >= count:
			continue
		var entry: Dictionary = entries[rank]
		var medal: Color = medals[rank]
		var x: float = left + column * (step_w + gap)
		var full_h: float = size.y * HEIGHTS[rank]
		var h: float = maxf(full_h * rise, 2.0)
		var step: Rect2 = Rect2(x, size.y - h, step_w, h)
		# Degrau de vidro escuro com tampo claro e fio na cor da medalha.
		Paint.gradient_rect(self, step, 6.0, get_theme_color("surface_top", T),
			get_theme_color("surface", T))
		draw_rect(Rect2(step.position, Vector2(step_w, minf(5.0, h))), Color(medal, 0.85))
		draw_rect(Rect2(step.position + Vector2(0, 5.0), Vector2(step_w, minf(4.0, h))),
			Color(1, 1, 1, 0.06))
		var number: String = "%dº" % int(entry.get("place", rank + 1))
		var number_size: int = 30 if rank == 0 else 24
		if h > number_size + 10.0:
			draw_string(display, Vector2(x, step.position.y + 12.0 + number_size), number,
				HORIZONTAL_ALIGNMENT_CENTER, step_w, number_size, Color(medal, 0.9))
		# Avatar, medalha e apelido em cima do degrau.
		var shown: float = clampf(reveal - (2 - rank), 0.0, 1.0)
		if shown <= 0.0:
			continue
		var pop: float = ease(shown, 0.4)
		var r: float = (32.0 if rank == 0 else 25.0) * lerpf(0.6, 1.0, pop)
		var nick_y: float = size.y - full_h - 8.0
		var center: Vector2 = Vector2(x + step_w / 2.0, nick_y - small - 10.0 - r)
		var alpha: float = minf(shown * 2.0, 1.0)
		draw_circle(center + Vector2(0, 3), r + 4.0, Color(0, 0, 0, 0.4 * alpha), true, -1.0, true)
		draw_circle(center, r + 3.5, Color(medal.darkened(0.3), alpha), true, -1.0, true)
		draw_arc(center, r + 2.0, PI * 1.05, PI * 1.95, 24, Color(medal.lightened(0.3), alpha),
			2.0, true)
		Paint.avatar(self, Rect2(center - Vector2.ONE * r, Vector2.ONE * r * 2.0),
			int(entry.get("avatar", 0)), colors, 0, 0.0)
		if rank == 0:
			_crown(center + Vector2(0, -r - 12.0), r * 0.62, medal)
		# Medalha pendurada no canto do avatar.
		var m: Vector2 = center + Vector2(r * 0.72, r * 0.72)
		draw_line(m + Vector2(-5, -11), m + Vector2(-2, -3), Color(get_theme_color("chip_1", T), alpha),
			3.0, true)
		draw_line(m + Vector2(5, -11), m + Vector2(2, -3), Color(get_theme_color("chip_2", T), alpha),
			3.0, true)
		draw_circle(m, 7.5, Color(medal.darkened(0.35), alpha), true, -1.0, true)
		draw_circle(m + Vector2(-0.5, -0.5), 6.0, Color(medal, alpha), true, -1.0, true)
		draw_string(display, m + Vector2(-6, 3.5), str(rank + 1), HORIZONTAL_ALIGNMENT_CENTER,
			12, 10, Color(get_theme_color("on_accent", T), alpha))
		var nick: String = String(entry.get("nick", ""))
		var color: Color = get_theme_color("accent", T) if entry.get("me", false) \
			else get_theme_color("text", T)
		draw_string(strong, Vector2(x - 6.0, nick_y), nick, HORIZONTAL_ALIGNMENT_CENTER,
			step_w + 12.0, body if rank == 0 else small + 1, Color(color, alpha))


## Coroa do campeão, com brilho.
func _crown(center: Vector2, half: float, gold: Color) -> void:
	var s: float = half
	var points: PackedVector2Array = PackedVector2Array([
		center + Vector2(-1.0, 0.55) * s, center + Vector2(-1.05, -0.45) * s,
		center + Vector2(-0.48, 0.05) * s, center + Vector2(0.0, -0.75) * s,
		center + Vector2(0.48, 0.05) * s, center + Vector2(1.05, -0.45) * s,
		center + Vector2(1.0, 0.55) * s])
	var shadow: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in points:
		shadow.append(p + Vector2(0, 2))
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.35))
	draw_colored_polygon(points, gold)
	draw_rect(Rect2(center + Vector2(-1.0, 0.3) * s, Vector2(2.0, 0.25) * s),
		gold.darkened(0.25))
	for tip: Vector2 in [Vector2(-1.05, -0.5), Vector2(0.0, -0.82), Vector2(1.05, -0.5)]:
		draw_circle(center + tip * s, s * 0.14, gold.lightened(0.35), true, -1.0, true)
