extends "res://ui/screens/screen.gd"
## Placar final (clássico) ou pódio do torneio (SPEC 11.1, passo 7). No torneio, os três
## primeiros sobem ao pódio, com confete, e os demais aparecem na lista ao lado. Depois
## desta tela vem o início ou outra partida; o anúncio de tela cheia, quando existir,
## entra no meio (SPEC 12, ui/app/ads.gd), nunca durante a partida.

signal again
signal home

const Money := preload("res://engine/money.gd")
const Paint := preload("res://ui/widgets/paint.gd")
const AvatarButton := preload("res://ui/widgets/avatar_button.gd")
const Podium := preload("res://ui/widgets/podium.gd")
const Confetti := preload("res://ui/widgets/confetti.gd")
const Sfx := preload("res://ui/app/sfx.gd")


## A tabela do placar, desenhada linha a linha.
class Board:
	extends Control

	## Linhas: {nick, avatar, me, place, chips, net}. tournament: só o lugar, o
	## avatar e o apelido (a lista de quem ficou fora do pódio).
	var rows: Array = []
	var tournament: bool = false
	const HEAD: float = 22.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func row_height() -> float:
		return clampf((size.y - HEAD) / maxf(rows.size(), 1.0), 24.0, 40.0)

	func _draw() -> void:
		var T: String = "Tokens"
		var text_font: Font = get_theme_font("strong", T)
		var number_font: Font = get_theme_font("display", T)
		var small: int = get_theme_font_size("small", T)
		var body: int = get_theme_font_size("body", T)
		var dim: Color = get_theme_color("text_dim", T)
		var ink: Color = get_theme_color("text", T)
		var accent: Color = get_theme_color("accent", T)
		var chips_x: float = size.x * 0.62
		var net_x: float = size.x
		var head_font: Font = get_theme_font("text", T)
		if tournament:
			draw_string(head_font, Vector2(0, 14), "Classificação", HORIZONTAL_ALIGNMENT_LEFT, -1,
				small, dim)
		else:
			draw_string(head_font, Vector2(0, 14), "Jogador", HORIZONTAL_ALIGNMENT_LEFT, -1, small,
				dim)
			draw_string(head_font, Vector2(chips_x - 120.0, 14), "Fichas",
				HORIZONTAL_ALIGNMENT_RIGHT, 120, small, dim)
			draw_string(head_font, Vector2(net_x - 120.0, 14), "Saldo",
				HORIZONTAL_ALIGNMENT_RIGHT, 120, small, dim)
		var h: float = row_height()
		var colors: Array[Color] = AvatarButton.colors_of(self)
		for i in rows.size():
			var row: Dictionary = rows[i]
			var top: float = HEAD + i * h
			var mid: float = top + h / 2.0
			if row.get("me", false):
				var box: StyleBoxFlat = StyleBoxFlat.new()
				box.bg_color = Color(accent, 0.12)
				box.set_corner_radius_all(8)
				box.anti_aliasing = true
				draw_style_box(box, Rect2(-8.0, top + 1.0, size.x + 16.0, h - 2.0))
			else:
				draw_line(Vector2(0, top + h), Vector2(size.x, top + h),
					Color(get_theme_color("surface_line", T), 0.6), 1.0)
			var r: float = minf(h * 0.36, 13.0)
			var left: float = 0.0
			if tournament:
				var place: int = int(row.get("place", 0))
				draw_string(number_font, Vector2(0, mid + body * 0.36),
					"%dº" % place if place > 0 else "—", HORIZONTAL_ALIGNMENT_LEFT, 34, body, dim)
				left = 36.0
			Paint.avatar(self, Rect2(Vector2(left + r, mid) - Vector2.ONE * r,
				Vector2.ONE * r * 2.0), int(row.get("avatar", 0)), colors, 0, 0.0)
			var nick: String = String(row.get("nick", ""))
			if row.get("me", false):
				nick += " (você)"
			var nick_w: float = size.x - left - r * 2.0 - 10.0 if tournament else chips_x - 150.0
			draw_string(text_font, Vector2(left + r * 2.0 + 10.0, mid + body * 0.36), nick,
				HORIZONTAL_ALIGNMENT_LEFT, nick_w, body, ink)
			if not tournament:
				_amount(number_font, int(row.get("chips", 0)), chips_x, mid, body, ink, false)
				var net: int = int(row.get("net", 0))
				var color: Color = accent if net > 0 else (get_theme_color("danger", T) if net < 0 else dim)
				_amount(number_font, net, net_x, mid, body, color, true)

	## Valor alinhado à direita, com o ícone de ficha antes do número.
	func _amount(font: Font, cents: int, right: float, mid: float, font_size: int,
			color: Color, signed: bool) -> void:
		var T: String = "Tokens"
		var text: String = Money.format(cents)
		if signed and cents > 0:
			text = "+" + text
		var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, Vector2(right - w, mid + font_size * 0.36), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		Paint.chip(self, Vector2(right - w - 10.0, mid), 5.5, get_theme_color("chip_0", T),
			get_theme_color("chip_mark", T), get_theme_constant("chip_style", T))


var final: Dictionary = {}
var members: Array = []
var my_id: String = ""

var _title: Label = null
var _subtitle: Label = null
var _board: Board = null
var _podium: Podium = null
var _confetti: Confetti = null
var _again: Button = null
var _home: Button = null


func _init(closed: Dictionary, room_members: Array, me: String) -> void:
	final = closed
	members = room_members
	my_id = me


func _build() -> void:
	var avatars: Dictionary = {}
	for member: Dictionary in members:
		avatars[member.get("id", "")] = int(member.get("avatar", 0))
	var podium: Array = final.get("podium", [])
	var tournament: bool = not podium.is_empty()
	for row: Dictionary in final.get("scoreboard", []):
		if int(row.get("place", 0)) > 0:
			tournament = true
	_board = Board.new()
	_board.tournament = tournament
	var my_row: Dictionary = {}
	var top: Array = []
	for row: Dictionary in final.get("scoreboard", []):
		var entry: Dictionary = {
			"nick": row.get("nick", ""), "avatar": avatars.get(row.get("id", ""), 0),
			"me": row.get("id", "") == my_id, "place": int(row.get("place", 0)),
			"chips": int(row.get("chips", 0)) + int(row.get("held", 0)),
			"net": int(row.get("net", 0)),
		}
		if entry["me"]:
			my_row = entry
		if tournament and entry["place"] >= 1 and entry["place"] <= 3:
			top.append(entry)
		else:
			_board.rows.append(entry)
	top.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["place"] < b["place"])
	if tournament:
		_board.rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return (a["place"] if a["place"] > 0 else 99) < (b["place"] if b["place"] > 0 else 99))
	add_child(_board)
	# Pódio só quando há campeão; sem ele (torneio interrompido), fica só a lista.
	if not top.is_empty() and int(top[0]["place"]) == 1:
		_podium = Podium.new()
		_podium.entries = top.slice(0, 3)
		add_child(_podium)
		_confetti = Confetti.new()
		_confetti.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_confetti)
	else:
		_board.rows.append_array(top)
		_board.rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return (a["place"] if a["place"] > 0 else 99) < (b["place"] if b["place"] > 0 else 99))
	_title = Label.new()
	_title.theme_type_variation = "TitleLabel"
	_title.text = "Resultado do torneio" if tournament else "Placar"
	add_child(_title)
	_subtitle = Label.new()
	_subtitle.theme_type_variation = "SmallLabel"
	_subtitle.text = _summary(my_row, tournament)
	add_child(_subtitle)
	_home = action_button("Início", false)
	_home.pressed.connect(func() -> void: home.emit())
	add_child(_home)
	_again = action_button("Jogar de novo", true)
	_again.pressed.connect(func() -> void: again.emit())
	add_child(_again)
	if _podium != null:
		_podium.ready.connect(func() -> void:
			_podium.play()
			_confetti.burst.call_deferred()
			if my_row.get("place", 0) == 1:
				Sfx.play(Sfx.WIN, 0.9), CONNECT_DEFERRED)


func _summary(row: Dictionary, tournament: bool) -> String:
	if row.is_empty():
		return "Fim da partida"
	if tournament:
		var place: int = int(row["place"])
		if place == 1:
			return "Você venceu o torneio!"
		return "Você terminou em %dº lugar" % place if place > 0 else "Fim da partida"
	var net: int = int(row["net"])
	if net > 0:
		return "Você saiu ganhando. Boa!"
	if net < 0:
		return "Não foi dessa vez."
	return "Você saiu no zero a zero."


func _layout() -> void:
	var b: Rect2 = body()
	var col: Rect2 = column()
	place(_title, Rect2(b.position.x, b.position.y, b.size.x, 32))
	place(_subtitle, Rect2(b.position.x, b.position.y + 32.0, b.size.x, 18))
	var top: float = b.position.y + 60.0
	var wanted: float = Board.HEAD + _board.rows.size() * 34.0
	if _podium != null:
		# Pódio à esquerda; quem ficou de fora, numa lista ao lado.
		var list_w: float = 0.0 if _board.rows.is_empty() else minf(b.size.x * 0.4, 240.0)
		var podium_w: float = b.size.x - list_w - (16.0 if list_w > 0.0 else 0.0)
		place(_podium, Rect2(b.position.x, top, podium_w, b.end.y - top))
		_podium.queue_redraw()
		_board.visible = list_w > 0.0
		place(_board, Rect2(b.end.x - list_w, top, list_w, minf(b.end.y - top, wanted)))
	else:
		place(_board, Rect2(b.position.x + 8.0, top, minf(b.size.x - 16.0, 520.0),
			minf(b.end.y - top, wanted)))
	_board.queue_redraw()
	place(_again, Rect2(col.position.x, col.end.y - BUTTON_H, col.size.x, BUTTON_H))
	place(_home, Rect2(col.position.x, col.end.y - BUTTON_H * 2.0 - 8.0, col.size.x, BUTTON_H))


func go_back() -> bool:
	home.emit()
	return true
