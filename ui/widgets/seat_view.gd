extends Control
## Um lugar da mesa: avatar redondo com aro metálico encostado numa placa de vidro
## escuro com apelido e fichas, relógio em anel em volta do avatar (verde, âmbar e
## vermelho no fim), marca do botão e marca do blind. O avatar fica do lado do centro da
## mesa (side = 1: à direita da placa; -1: à esquerda). Tamanho fixo de SIZE; as
## cartas e a aposta da rodada são peças separadas, posicionadas pela mesa.

const Paint := preload("res://ui/widgets/paint.gd")
const Money := preload("res://engine/money.gd")
const T: String = "Tokens"
const SIZE: Vector2 = Vector2(120, 44)
const AVATAR: float = 40.0
const PLATE_H: float = 36.0

## nick, stack, avatar, turn, fraction (0 a 1 do tempo que resta), folded, all_in,
## dealer, blind ("SB", "BB" ou vazio), rebuys (recompras feitas), tag (texto curto da última ação), winner,
## away, empty, countdown ("1:45": tempo até o lugar ser liberado, em cima do avatar), bot
## (selo com um robozinho).
var data: Dictionary = {}:
	set(value):
		data = value
		var dim: bool = data.get("folded", false) or data.get("away", false)
		# Com a contagem, menos apagado, para o tempo continuar legível.
		modulate.a = (0.75 if data.has("countdown") else 0.45) if dim else 1.0
		queue_redraw()
## Marcas do botão e do blind em cima do avatar (o seu lugar, que tem as cartas ao
## lado); nos outros ficam embaixo, do lado do centro da mesa.
var marks_up: bool = false
## Lado do avatar: 1 à direita da placa, -1 à esquerda.
var side: float = 1.0:
	set(value):
		side = value
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = SIZE


## Centro do avatar, em coordenadas do lugar.
func avatar_center() -> Vector2:
	var x: float = SIZE.x - AVATAR / 2.0 if side > 0.0 else AVATAR / 2.0
	return Vector2(x, SIZE.y / 2.0)


## Pulsação do destaque de quem está na vez (0 a 1), atualizada pela mesa.
var pulse: float = 0.0:
	set(value):
		pulse = value
		if data.get("turn", false):
			queue_redraw()


func set_fraction(fraction: float) -> void:
	data["fraction"] = fraction
	queue_redraw()


func _draw() -> void:
	var center: Vector2 = avatar_center()
	var accent: Color = get_theme_color("accent", T)
	var text_color: Color = get_theme_color("text", T)
	var turn: bool = data.get("turn", false)
	var winner: bool = data.get("winner", false)
	var r: float = AVATAR / 2.0

	if data.get("empty", false):
		draw_circle(center, r, Color(0, 0, 0, 0.3), true, -1.0, true)
		draw_arc(center, r, 0, TAU, 48, Color(text_color, 0.2), 1.5, true)
		return

	var fraction: float = float(data.get("fraction", 1.0))
	var ring_color: Color = get_theme_color("ok", T)
	if fraction < 0.25:
		ring_color = get_theme_color("danger", T)
	elif fraction < 0.5:
		ring_color = accent
	var soft: Texture2D = Paint.soft_disc()
	if turn or winner:
		var halo: float = (r + 16.0 + pulse * 5.0) * 2.0 if turn else (r + 18.0) * 2.0
		var tint: Color = Color(ring_color if turn else accent, 0.35 + pulse * 0.2 if turn else 0.45)
		draw_texture_rect(soft, Rect2(center - Vector2.ONE * halo / 2.0, Vector2.ONE * halo),
			false, tint)

	# Placa de vidro escuro: vai da ponta oposta até o meio do avatar.
	var plate_x: float = 0.0 if side > 0.0 else r
	var plate: Rect2 = Rect2(plate_x, (SIZE.y - PLATE_H) / 2.0, SIZE.x - r, PLATE_H)
	var corner: float = PLATE_H / 2.0
	var shadow: StyleBoxFlat = StyleBoxFlat.new()
	shadow.bg_color = Color(0, 0, 0, 0)
	shadow.shadow_color = Color(get_theme_color("shadow", T), 0.5)
	shadow.shadow_size = 6
	shadow.shadow_offset = Vector2(0, 3)
	shadow.set_corner_radius_all(int(corner))
	draw_style_box(shadow, plate)
	Paint.gradient_rect(self, plate, corner, Color(get_theme_color("surface_top", T), 0.94),
		Color(get_theme_color("surface", T), 0.96))
	var rim: StyleBoxFlat = StyleBoxFlat.new()
	rim.draw_center = false
	rim.set_border_width_all(1)
	rim.border_color = Color(accent, 0.75) if turn else Color(get_theme_color("surface_line", T), 0.9)
	rim.set_corner_radius_all(int(corner))
	rim.anti_aliasing = true
	draw_style_box(rim, plate)
	var shine: StyleBoxFlat = StyleBoxFlat.new()
	shine.draw_center = false
	shine.border_width_top = 1
	shine.border_color = Color(1, 1, 1, 0.16)
	shine.set_corner_radius_all(int(corner - 1.0))
	shine.anti_aliasing = true
	draw_style_box(shine, plate.grow(-1.0))

	# Avatar com aro metálico: escuro embaixo, claro em cima.
	draw_circle(center + Vector2(0, 2), r + 3.0, Color(0, 0, 0, 0.45), true, -1.0, true)
	var metal: Color = accent if winner else get_theme_color("rail_hi", T)
	draw_circle(center, r + 2.5, metal.darkened(0.45), true, -1.0, true)
	draw_arc(center, r + 1.3, PI * 1.05, PI * 1.95, 24, metal.lightened(0.25), 2.2, true)
	Paint.avatar(self, Rect2(center - Vector2.ONE * r, Vector2.ONE * AVATAR),
		int(data.get("avatar", 0)), Paint.avatar_colors(self), 0, 0.0)
	if turn:
		Paint.timer_ring(self, center, r + 2.5, 3.5, fraction, ring_color, Color(0, 0, 0, 0.55))
	elif winner:
		draw_arc(center, r + 2.5, 0, TAU, 64, accent, 3.0, true)
	# Quem caiu ou saiu: o tempo até o lugar ser liberado, em cima do avatar escurecido.
	var countdown: String = String(data.get("countdown", ""))
	if countdown != "":
		draw_circle(center, r, Color(0, 0, 0, 0.62), true, -1.0, true)
		var clock_font: Font = get_theme_font("strong", T)
		var clock_size: int = get_theme_font_size("small", T)
		draw_string(clock_font, Vector2(center.x - r, center.y + clock_size * 0.36), countdown,
			HORIZONTAL_ALIGNMENT_CENTER, AVATAR, clock_size, text_color)

	# Bot: selo com um robozinho embaixo do avatar, no meio do aro.
	if data.get("bot", false):
		_bot_badge(center + Vector2(0, r + 1.0))

	# Marcador de recompras no avatar, do lado de fora (no seu lugar, embaixo).
	var rebuys: int = int(data.get("rebuys", 0))
	if rebuys > 0:
		var corner_y: float = r * 0.74 if marks_up else -r * 0.74
		_rebuy_badge(center + Vector2(-side * r * 0.74, corner_y), rebuys)

	# Texto na parte da placa que o avatar não cobre.
	var text_left: float = plate.position.x + (8.0 if side > 0.0 else r + 4.0)
	var text_right: float = plate.end.x - (r + 4.0 if side > 0.0 else 8.0)
	var text_w: float = text_right - text_left
	var small: int = get_theme_font_size("small", T)
	var tag: String = "All-in" if data.get("all_in", false) else String(data.get("tag", ""))
	var font: Font = get_theme_font("strong", T)
	var name_at: Vector2 = Vector2(text_left, plate.position.y + 15.0)
	var name_text: String = _ellipsis(font, String(data.get("nick", "")), small, text_w)
	draw_string(font, name_at + Vector2(0, 1), name_text, HORIZONTAL_ALIGNMENT_CENTER, text_w,
		small, Color(0, 0, 0, 0.5))
	draw_string(font, name_at, name_text, HORIZONTAL_ALIGNMENT_CENTER, text_w, small,
		Color(text_color, 0.88))
	_amount(int(data.get("stack", 0)), text_left, text_w, plate.position.y + 30.0)
	# A última ação (ou o nome da mão no showdown) numa etiqueta presa embaixo da placa,
	# para o apelido continuar à vista.
	if tag != "":
		_tag(tag, Vector2(text_left + text_w / 2.0, plate.end.y + 3.0), plate.size.x - r)

	# Marcas embaixo, do lado do centro da mesa (em cima ficam as cartas).
	var dealer: bool = data.get("dealer", false)
	var blind: String = String(data.get("blind", ""))
	if marks_up:
		var y: float = -r - 6.0
		if dealer:
			_dealer(center + Vector2(-12.0 if blind != "" else 0.0, y), small)
		if blind != "":
			_blind(center + Vector2(10.0 if dealer else 0.0, y), blind, small)
		return
	if dealer:
		_dealer(center + Vector2(side * (r + 9.0), 13.0), small)
	if blind != "":
		_blind(center + Vector2(side * (r + (30.0 if dealer else 13.0)), 13.0), blind, small)


## Etiqueta da ação: cinza para Desistiu, azul para Passou e Pagou, vermelho para
## All-in e dourado para Apostou, Aumentou e o nome da mão.
func _tag(text: String, center: Vector2, max_w: float) -> void:
	var font: Font = get_theme_font("strong", T)
	var font_size: int = get_theme_font_size("small", T) - 2
	var fill: Color = get_theme_color("accent", T)
	var ink: Color = get_theme_color("on_accent", T)
	match text:
		"Desistiu":
			fill = get_theme_color("surface_line", T)
			ink = get_theme_color("text", T)
		"Passou", "Pagou":
			fill = get_theme_color("call_top", T)
			ink = get_theme_color("text", T)
		"All-in":
			fill = get_theme_color("danger", T)
			ink = get_theme_color("text", T)
	# Texto comprido ("Reconectando…", nome de mão): a letra diminui um pouco antes de cortar.
	var smallest: int = font_size - 3
	while font_size > smallest \
			and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_w - 12.0:
		font_size -= 1
	var label: String = _ellipsis(font, text, font_size, max_w - 12.0)
	var w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 12.0
	var pill: Rect2 = Rect2(center - Vector2(w, 14.0) / 2.0, Vector2(w, 14.0))
	var shadow: StyleBoxFlat = StyleBoxFlat.new()
	shadow.bg_color = Color(0, 0, 0, 0)
	shadow.shadow_color = Color(0, 0, 0, 0.4)
	shadow.shadow_size = 3
	shadow.shadow_offset = Vector2(0, 1)
	shadow.set_corner_radius_all(7)
	draw_style_box(shadow, pill)
	Paint.gradient_rect(self, pill, 7.0, fill.lightened(0.15), fill.darkened(0.15))
	draw_string(font, Vector2(pill.position.x, center.y + font_size * 0.36), label,
		HORIZONTAL_ALIGNMENT_CENTER, w, font_size, ink)


## Marcador de recompras: um disco dourado pequeno com o número de recompras.
func _rebuy_badge(spot: Vector2, count: int) -> void:
	var text: String = str(count) if count < 10 else "9+"
	var font: Font = get_theme_font("display", T)
	var font_size: int = 9
	var radius: float = 7.5 if count < 10 else 9.0
	draw_circle(spot + Vector2(0, 1.2), radius, Color(0, 0, 0, 0.45), true, -1.0, true)
	draw_circle(spot, radius, get_theme_color("accent_line", T), true, -1.0, true)
	draw_circle(spot, radius - 1.2, get_theme_color("accent", T), true, -1.0, true)
	draw_arc(spot, radius - 2.0, PI * 1.15, PI * 1.85, 10, Color(1, 1, 1, 0.45), 1.0, true)
	draw_string(font, Vector2(spot.x - radius, spot.y + font_size * 0.36), text,
		HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, font_size, get_theme_color("on_accent", T))


## Selo do bot: disco azul com a cabeça de um robô (antena, orelhas e dois olhos).
func _bot_badge(spot: Vector2) -> void:
	var tint: Color = get_theme_color("bot_name", T)
	var ink: Color = Color(0.05, 0.12, 0.2)
	var radius: float = 6.5
	draw_circle(spot + Vector2(0, 1.2), radius, Color(0, 0, 0, 0.45), true, -1.0, true)
	draw_circle(spot, radius, tint.darkened(0.55), true, -1.0, true)
	draw_circle(spot, radius - 1.2, tint, true, -1.0, true)
	var u: float = radius - 1.2
	# Antena.
	draw_line(spot + Vector2(0, -0.28) * u, spot + Vector2(0, -0.6) * u, ink, 1.0, true)
	draw_circle(spot + Vector2(0, -0.66) * u, 0.13 * u, ink, true, -1.0, true)
	# Orelhas e cabeça.
	draw_rect(Rect2(spot + Vector2(-0.68, -0.08) * u, Vector2(0.14, 0.32) * u), ink)
	draw_rect(Rect2(spot + Vector2(0.54, -0.08) * u, Vector2(0.14, 0.32) * u), ink)
	var head: StyleBoxFlat = StyleBoxFlat.new()
	head.bg_color = ink
	head.set_corner_radius_all(int(maxf(0.18 * u, 1.0)))
	head.anti_aliasing = true
	draw_style_box(head, Rect2(spot + Vector2(-0.52, -0.3) * u, Vector2(1.04, 0.8) * u))
	# Olhos acesos.
	for x: float in [-0.22, 0.22]:
		draw_circle(spot + Vector2(x, 0.06) * u, 0.12 * u, tint, true, -1.0, true)


## Botão do dealer: uma ficha branca com "B".
func _dealer(spot: Vector2, small: int) -> void:
	draw_circle(spot + Vector2(0, 1.5), 8.5, Color(0, 0, 0, 0.45), true, -1.0, true)
	draw_circle(spot, 8.5, get_theme_color("card_line", T), true, -1.0, true)
	draw_circle(spot, 7.3, get_theme_color("card_face", T), true, -1.0, true)
	draw_arc(spot, 5.6, 0, TAU, 24, Color(get_theme_color("card_black", T), 0.25), 0.8, true)
	var display: Font = get_theme_font("display", T)
	draw_string(display, spot + Vector2(-8, small * 0.34), "B", HORIZONTAL_ALIGNMENT_CENTER,
		16, small - 2, get_theme_color("card_black", T))


## Marca de quem pôs o blind: "SB" (small blind) ou "BB" (big blind).
func _blind(spot: Vector2, text: String, small: int) -> void:
	var font: Font = get_theme_font("strong", T)
	var font_size: int = small - 3
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 9.0
	var pill: Rect2 = Rect2(spot - Vector2(w, 13.0) / 2.0, Vector2(w, 13.0))
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0.62)
	box.border_color = Color(get_theme_color("accent", T), 0.7) if text == "BB" \
		else Color(get_theme_color("text", T), 0.45)
	box.set_border_width_all(1)
	box.set_corner_radius_all(7)
	box.anti_aliasing = true
	draw_style_box(box, pill)
	draw_string(font, Vector2(pill.position.x, spot.y + font_size * 0.36), text,
		HORIZONTAL_ALIGNMENT_CENTER, w, font_size, get_theme_color("text", T))


func _amount(cents: int, left: float, width: float, baseline: float) -> void:
	var font: Font = get_theme_font("display", T)
	var font_size: int = get_theme_font_size("small", T)
	var text: String = Money.format(cents)
	var text_w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var icon: float = 10.0
	var x: float = left + (width - icon - 4.0 - text_w) / 2.0
	Paint.chip(self, Vector2(x + icon / 2.0, baseline - font_size * 0.36), icon / 2.0,
		get_theme_color("chip_0", T), get_theme_color("chip_mark", T),
		get_theme_constant("chip_style", T))
	draw_string(font, Vector2(x + icon + 4.0, baseline + 1.0), text, HORIZONTAL_ALIGNMENT_LEFT,
		-1, font_size, Color(0, 0, 0, 0.5))
	draw_string(font, Vector2(x + icon + 4.0, baseline), text, HORIZONTAL_ALIGNMENT_LEFT,
		-1, font_size, get_theme_color("accent_top", T))


func _ellipsis(font: Font, text: String, font_size: int, max_width: float) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
		return text
	var cut: String = text
	while cut.length() > 1 and font.get_string_size(cut + "…", HORIZONTAL_ALIGNMENT_LEFT,
			-1, font_size).x > max_width:
		cut = cut.left(cut.length() - 1)
	return cut + "…"
