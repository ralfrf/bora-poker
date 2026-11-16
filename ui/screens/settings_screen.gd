extends "res://ui/screens/screen.gd"
## Configurações (SPEC 11.3): sons, vibração e baralho de 4 cores. Cada troca vale na
## hora e fica gravada no perfil. Na coluna, as cartas mostram como fica o baralho.
## "Silenciar reações" chega com as reações, na etapa 4.

signal back

const Profile := preload("res://ui/app/profile.gd")
const ToggleRow := preload("res://ui/widgets/toggle_row.gd")
const CardView := preload("res://ui/widgets/card_view.gd")
const Cards := preload("res://engine/cards.gd")
const Sfx := preload("res://ui/app/sfx.gd")

const PREVIEW: String = "Ac Ad Ah As"

var profile: Profile = null

var _title: Label = null
var _sound: ToggleRow = null
var _vibration: ToggleRow = null
var _four: ToggleRow = null
var _preview_label: Label = null
var _cards: Array[CardView] = []
var _done: Button = null


func _init(owner_profile: Profile) -> void:
	profile = owner_profile


func _build() -> void:
	_title = Label.new()
	_title.theme_type_variation = "TitleLabel"
	_title.text = "Configurações"
	add_child(_title)
	_sound = ToggleRow.new("Sons", "Cartas, fichas, vitória e aviso da sua vez", profile.sound)
	_sound.toggled.connect(func(on: bool) -> void:
		profile.sound = on
		_save()
		Sfx.play(Sfx.CHIP))
	add_child(_sound)
	_vibration = ToggleRow.new("Vibração", "Quando faltam 5 segundos para acabar a sua vez",
		profile.vibration)
	_vibration.toggled.connect(func(on: bool) -> void:
		profile.vibration = on
		_save()
		Sfx.vibrate(200))
	add_child(_vibration)
	_four = ToggleRow.new("Baralho de 4 cores", "Paus em verde e ouros em azul",
		profile.four_color)
	_four.toggled.connect(func(on: bool) -> void:
		profile.four_color = on
		_save()
		for card: CardView in _cards:
			card.queue_redraw())
	add_child(_four)
	_preview_label = Label.new()
	_preview_label.theme_type_variation = "SmallLabel"
	_preview_label.text = "Assim ficam as cartas"
	_preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_preview_label)
	for card_value: int in Cards.list_from_text(PREVIEW):
		var card: CardView = CardView.new()
		card.card = card_value
		add_child(card)
		_cards.append(card)
	_done = action_button("Pronto", true)
	_done.pressed.connect(func() -> void: back.emit())
	add_child(_done)


func _save() -> void:
	profile.apply()
	profile.save()


func _layout() -> void:
	var b: Rect2 = body()
	var col: Rect2 = column()
	place(_title, Rect2(b.position.x, b.position.y, b.size.x, 34))
	var w: float = minf(b.size.x, 460.0)
	var y: float = b.position.y + 48.0
	for row: ToggleRow in [_sound, _vibration, _four]:
		place(row, Rect2(b.position.x, y, w, ToggleRow.ROW_H))
		row.queue_redraw()
		y += ToggleRow.ROW_H + 10.0
	var card_size: Vector2 = Vector2(30, 42)
	var total: float = card_size.x * 4.0 + 4.0 * 3.0
	place(_preview_label, Rect2(col.position.x, col.position.y + 4.0, col.size.x, 18))
	for i in _cards.size():
		_cards[i].size = card_size
		_cards[i].position = Vector2(col.get_center().x - total / 2.0 + i * (card_size.x + 4.0),
			col.position.y + 28.0).round()
	place(_done, Rect2(col.position.x, col.end.y - BUTTON_H, col.size.x, BUTTON_H))


func go_back() -> bool:
	back.emit()
	return true
