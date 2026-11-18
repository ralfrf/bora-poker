extends "res://ui/screens/screen.gd"
## Loja (SPEC 11.3 e 12): "Gostou do app?" com quatro níveis, do menor ao maior: 2
## avatares exclusivos à escolha; uma mesa; mesa e 2 meses sem anúncios; mesa, 2
## avatares e 6 meses sem anúncios. Para quem já teve tempo sem anúncios, aparece também
## a renovação de 6 meses. A mesa das compras se escolhe na coluna da direita e vale para
## os três cartões com mesa (um produto por mesa na loja).
##
## Os preços vêm da loja do celular (ui/app/purchases.gd). Sem loja (hoje, sem plugin),
## os cartões mostram "Em breve" com o preço de referência acima e o aviso do Beta.
## Nunca fichas.

signal back

const Profile := preload("res://ui/app/profile.gd")
const Catalog := preload("res://ui/app/store_catalog.gd")
const Purchases := preload("res://ui/app/purchases.gd")
const Tables := preload("res://ui/theme/tables.gd")
const Paint := preload("res://ui/widgets/paint.gd")
const StoreCard := preload("res://ui/widgets/store_card.gd")
const AvatarPicker := preload("res://ui/widgets/avatar_picker.gd")
const Dialog := preload("res://ui/widgets/dialog.gd")

## O link "Loja" aparece no início (decisão do dono, 17/11/2026: visível no Beta, com as
## compras fechadas).
const VISIBLE: bool = true
const CARD_GAP: float = 8.0
const CHOICE_H: float = 36.0
## Avatares de exemplo nos cartões (um retrato de homem e um de mulher).
const SAMPLE_AVATARS: Array[int] = [Paint.FREE_AVATARS + 2, Paint.FREE_AVATARS + 12]

var profile: Profile = null

var _sample: Dictionary = {}
var _purchases: Array = []
var _prices: Dictionary = {}
var _rights: Dictionary = {}
var _table: String = Catalog.TABLES[0]
var _busy: bool = false
var _message: String = ""

var _title: Label = null
var _pitch: Label = null
var _notice: Label = null
var _cards: Dictionary = {}   ## nível (ou a renovação) -> StoreCard
var _table_label: Label = null
var _table_buttons: Array[Button] = []
var _restore: Button = null
var _restore_hint: Label = null
var _done: Button = null
var _dialog: Dialog = null
var _picker: AvatarPicker = null
var _pending: String = ""   ## produto esperando a confirmação do aviso


## sample (só para as fotos): {"purchases": [...], "prices": {produto: texto}} no lugar
## da loja do celular.
func _init(owner_profile: Profile, sample: Dictionary = {}) -> void:
	profile = owner_profile
	_sample = sample


func _build() -> void:
	_title = Label.new()
	_title.theme_type_variation = "TitleLabel"
	_title.text = "Loja"
	add_child(_title)
	_pitch = Label.new()
	_pitch.theme_type_variation = "SmallLabel"
	_pitch.text = "Gostou do app? Apoie e leve enfeites que ficam seus. Fichas não se vendem: são só do jogo."
	_pitch.clip_text = true
	add_child(_pitch)
	_notice = Label.new()
	_notice.theme_type_variation = "SmallLabel"
	_notice.clip_text = true
	add_child(_notice)
	for key: String in Catalog.TIERS + [Catalog.RENEWAL]:
		var card: StoreCard = StoreCard.new()
		card.pressed.connect(_on_card.bind(key))
		add_child(card)
		_cards[key] = card
	_table_label = Label.new()
	_table_label.theme_type_variation = "SmallLabel"
	_table_label.text = "Mesa das compras"
	add_child(_table_label)
	var group: ButtonGroup = ButtonGroup.new()
	for table: String in Catalog.TABLES:
		var button: Button = Button.new()
		button.text = str(Tables.skin(table)["name"])
		button.theme_type_variation = "ChoiceButton"
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void:
			_table = table
			_refresh())
		add_child(button)
		_table_buttons.append(button)
	# Recuperar compras (o "restaurar" das lojas, exigido pela Apple): a Loja já lê as
	# compras da conta ao abrir; o botão é a segunda tentativa de quem trocou de celular
	# ou instalou de novo.
	_restore_hint = Label.new()
	_restore_hint.theme_type_variation = "SmallLabel"
	_restore_hint.text = "Trocou de celular ou
instalou de novo?"
	_restore_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_restore_hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_restore_hint.add_theme_constant_override("line_spacing", 0)
	add_child(_restore_hint)
	_restore = Button.new()
	_restore.text = "Recuperar compras"
	_restore.add_theme_constant_override("h_separation", 0)
	_restore.theme_type_variation = "QuietButton"
	_restore.focus_mode = Control.FOCUS_NONE
	_restore.add_theme_font_size_override("font_size", 11)
	_restore.clip_text = true
	_restore.pressed.connect(_on_restore)
	add_child(_restore)
	_done = action_button("Voltar", true)
	_done.pressed.connect(func() -> void: back.emit())
	add_child(_done)
	_dialog = Dialog.new()
	_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dialog.chosen.connect(_on_dialog)
	add_child(_dialog)
	_picker = AvatarPicker.new(true)
	_picker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_picker.picked.connect(_on_avatar_picked)
	add_child(_picker)

	if _sample.is_empty():
		Purchases.restore(_on_purchases)
		Purchases.prices(Catalog.all_products(), _on_prices)
	else:
		_purchases = _sample.get("purchases", [])
		_prices = _sample.get("prices", {})
	_rights = Catalog.entitlements(_purchases)
	_table = Catalog.first_missing_table(_rights)
	_refresh()


## Dá para comprar? (Há loja e ela informou preços.)
func _open() -> bool:
	return (Purchases.available() or _sample.has("prices")) and not _prices.is_empty()


func _refresh() -> void:
	_rights = Catalog.entitlements(_purchases)
	var now: int = int(Time.get_unix_time_from_system())
	var notice: String = ""
	var accent: bool = true
	if _message != "":
		notice = _message
	elif not _open():
		notice = "As compras abrem depois do Beta. Até lá, as mesas e os avatares exclusivos são grátis para todos."
	elif Catalog.ad_free(_rights, now):
		notice = "Sem anúncios até %s." % _date(_rights["ad_free_until"])
	elif Catalog.shows_renewal(_rights):
		notice = "O seu tempo sem anúncios acabou."
		accent = false
	_notice.text = notice
	_notice.add_theme_color_override("font_color",
		get_theme_color("accent", T) if accent else get_theme_color("text_dim", T))
	for i in _table_buttons.size():
		_table_buttons[i].set_pressed_no_signal(Catalog.TABLES[i] == _table)
	var table_name: String = str(Tables.skin(_table)["name"])
	_fill(Catalog.TIER_AVATARS, "2 avatares",
		["Exclusivos, à sua escolha", "Para sempre"], "", SAMPLE_AVATARS)
	_fill(Catalog.TIER_TABLE, "Mesa %s" % table_name,
		["Para sempre", "Todos da sala a veem"], _table, [])
	_fill(Catalog.TIER_TABLE_ADS, "Mesa + 2 meses",
		["Mesa %s para sempre" % table_name, "2 meses sem anúncios"], _table, [])
	_fill(Catalog.TIER_FULL, "Completo",
		["Mesa %s + 2 avatares" % table_name, "6 meses sem anúncios", "Não renova sozinho"],
		_table, SAMPLE_AVATARS)
	(_cards[Catalog.TIER_FULL] as StoreCard).badge = "Mais completo"
	var renewal: StoreCard = _cards[Catalog.RENEWAL]
	renewal.visible = Catalog.shows_renewal(_rights)
	renewal.title = "Mais 6 meses"
	renewal.lines = ["6 meses sem anúncios", "Não renova sozinho"]
	renewal.clock = true
	_set_pill(renewal, Catalog.RENEWAL, "buy")
	_restore.disabled = not (Purchases.available() or not _sample.is_empty())
	_layout()


func _fill(tier: String, title: String, lines: Array[String], table: String,
		avatars: Array[int]) -> void:
	var card: StoreCard = _cards[tier]
	var state: String = Catalog.card_state(tier, table, _rights)
	if state == "has_table":
		lines = lines.duplicate()
		lines[0] = "Você já tem a mesa %s" % str(Tables.skin(table)["name"])
	card.title = title
	card.lines = lines
	card.avatars = avatars
	card.table = table
	_set_pill(card, Catalog.product_id(tier, table), state)


func _set_pill(card: StoreCard, id: String, state: String) -> void:
	var claim: bool = state == "bought" and Catalog.grant(id)["avatars"] > 0 \
		and Catalog.avatars_left(profile.store_avatars, _rights) > 0
	if claim:
		card.pill = "Escolher"
	elif state == "bought":
		card.pill = "Comprado"
	elif state == "has_all":
		card.pill = "Você já tem"
	elif _open() and _prices.has(id):
		card.pill = str(_prices[id])
	else:
		card.pill = "Em breve"
	card.price = Catalog.reference_price(id) if card.pill == "Em breve" else ""
	card.highlight = claim or (state in ["buy", "has_table"] and _open() and _prices.has(id))
	card.disabled = not card.highlight or _busy
	card.refresh()


func _layout() -> void:
	if _title == null or not is_inside_tree():
		return
	var b: Rect2 = body()
	var col: Rect2 = column()
	place(_title, Rect2(b.position.x, b.position.y, b.size.x, 34))
	place(_pitch, Rect2(b.position.x, b.position.y + 36.0, b.size.x, 18))
	place(_notice, Rect2(b.position.x, b.position.y + 55.0, b.size.x, 18))
	var shown: Array[StoreCard] = []
	for key: String in Catalog.TIERS + [Catalog.RENEWAL]:
		if (_cards[key] as StoreCard).visible:
			shown.append(_cards[key])
	var top: float = b.position.y + 82.0
	var w: float = (b.size.x - CARD_GAP * (shown.size() - 1)) / shown.size()
	for i in shown.size():
		place(shown[i], Rect2(b.position.x + i * (w + CARD_GAP), top, w, b.end.y - top))
	place(_table_label, Rect2(col.position.x, col.position.y + 4.0, col.size.x, 18))
	for i in _table_buttons.size():
		place(_table_buttons[i], Rect2(col.position.x, col.position.y + 26.0 + i * (CHOICE_H + 6.0),
			col.size.x, CHOICE_H))
	place(_done, Rect2(col.position.x, col.end.y - BUTTON_H, col.size.x, BUTTON_H))
	place(_restore, Rect2(col.position.x, col.end.y - BUTTON_H - 48.0, col.size.x, 40))
	place(_restore_hint, Rect2(col.position.x, col.end.y - BUTTON_H - 90.0, col.size.x, 38))


func _on_purchases(list: Array) -> void:
	_purchases = list
	_refresh()


func _on_prices(prices: Dictionary) -> void:
	_prices = prices
	_refresh()


func _on_card(key: String) -> void:
	if _busy:
		return
	var table: String = "" if key in [Catalog.TIER_AVATARS, Catalog.RENEWAL] else _table
	var id: String = key if key == Catalog.RENEWAL else Catalog.product_id(key, table)
	var state: String = "buy" if key == Catalog.RENEWAL else Catalog.card_state(key, table, _rights)
	if state == "bought":
		_open_claim()
	elif state == "has_table":
		_pending = id
		var table_name: String = str(Tables.skin(table)["name"])
		var rest: String = "os 2 avatares e os 6 meses sem anúncios" if key == Catalog.TIER_FULL \
			else "os 2 meses sem anúncios"
		_dialog.ask("Você já tem a mesa %s" % table_name,
			"Com esta compra vêm só %s. Para outra mesa, escolha-a em \"Mesa das compras\"." % rest,
			["Comprar", "Voltar"])
	else:
		_buy(id)


func _on_dialog(index: int) -> void:
	var id: String = _pending
	_pending = ""
	if index == 0 and id != "":
		_buy(id)


func _buy(id: String) -> void:
	_busy = true
	_message = ""
	_refresh()
	Purchases.buy(id, func(ok: bool, list: Array) -> void:
		_busy = false
		if ok:
			_purchases = list
		_refresh()
		if ok and Catalog.avatars_left(profile.store_avatars, _rights) > 0:
			_open_claim())


func _on_restore() -> void:
	_message = ""
	Purchases.restore(func(list: Array) -> void:
		_purchases = list
		_message = "Compras recuperadas desta conta Google." if not list.is_empty() \
			else "Nenhuma compra encontrada nesta conta Google."
		_refresh())


func _open_claim() -> void:
	var left: int = Catalog.avatars_left(profile.store_avatars, _rights)
	if left > 0:
		_picker.open_claim(Catalog.valid_choices(profile.store_avatars, _rights), left)


func _on_avatar_picked(index: int) -> void:
	var chosen: Array[int] = Catalog.valid_choices(profile.store_avatars, _rights)
	if chosen.has(index) or chosen.size() >= int(_rights.get("avatars", 0)):
		return
	chosen.append(index)
	profile.store_avatars = chosen
	profile.save()
	_refresh()
	_open_claim.call_deferred()


static func _date(unix: int) -> String:
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(unix)
	return "%02d/%02d/%d" % [d["day"], d["month"], d["year"]]


func go_back() -> bool:
	if _picker.visible:
		_picker.close()
	elif _dialog.visible:
		_dialog.visible = false
		_pending = ""
	else:
		back.emit()
	return true
