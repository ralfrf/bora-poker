extends "res://tests/test_case.gd"
## Loja (SPEC 12): produtos, o que cada compra dá, prazos sem anúncios que se somam,
## avatares escolhidos e o estado de cada cartão.

const Catalog := preload("res://ui/app/store_catalog.gd")
const Paint := preload("res://ui/widgets/paint.gd")
const Profile := preload("res://ui/app/profile.gd")
const Tables := preload("res://ui/theme/tables.gd")
const ShopScreen := preload("res://ui/screens/shop_screen.gd")

const DAY: int = 86400
## 15/01/2027 12:00 (UTC).
const JAN_15: int = 1800014400


func test_store_products_are_unique_and_valid() -> void:
	var ids: Array[String] = Catalog.all_products()
	assert_eq(ids.size(), 11, "avatares, 3 níveis × 3 mesas e a renovação")
	var seen: Dictionary = {}
	var regex: RegEx = RegEx.create_from_string("^[a-z0-9][a-z0-9_]*$")
	for id: String in ids:
		assert_false(seen.has(id), "repetido: " + id)
		seen[id] = true
		assert_true(regex.search(id) != null, "código aceito pela Play: " + id)
		var g: Dictionary = Catalog.grant(id)
		assert_true(g["avatars"] > 0 or g["table"] != "" or g["months"] > 0, "dá algo: " + id)
	for table: String in Catalog.TABLES:
		assert_true(Tables.ALL.has(table), "mesa existe: " + table)


func test_store_grants() -> void:
	assert_eq(Catalog.grant("avatares_2"), {"avatars": 2, "table": "", "months": 0})
	assert_eq(Catalog.grant("mesa_rubi"), {"avatars": 0, "table": "rubi", "months": 0})
	assert_eq(Catalog.grant("mesa_safira_2meses"), {"avatars": 0, "table": "safira", "months": 2})
	assert_eq(Catalog.grant("completo_perola"), {"avatars": 2, "table": "perola", "months": 6})
	assert_eq(Catalog.grant(Catalog.RENEWAL), {"avatars": 0, "table": "", "months": 6})
	assert_eq(Catalog.grant("fichas_1000"), {"avatars": 0, "table": "", "months": 0}, "não existe")


func test_store_entitlements_sum_and_ignore_junk() -> void:
	var rights: Dictionary = Catalog.entitlements([
		{"id": "mesa_rubi", "time": JAN_15},
		{"id": "completo_safira", "time": JAN_15},
		{"id": "completo_safira", "time": JAN_15},
		{"id": "fichas_1000", "time": JAN_15},
		"lixo",
		{"id": "avatares_2", "time": JAN_15},
	])
	assert_eq(rights["tables"], ["rubi", "safira"])
	assert_eq(rights["avatars"], 4, "2 do completo e 2 dos avatares; repetida não conta")
	assert_eq(rights["owned"], ["mesa_rubi", "completo_safira", "avatares_2"])
	var empty: Dictionary = Catalog.entitlements([])
	assert_eq(empty["ad_free_until"], 0)
	assert_false(Catalog.shows_renewal(empty), "renovação só para quem já teve o prazo")
	assert_true(Catalog.shows_renewal(rights))


func test_store_add_months_uses_the_calendar() -> void:
	var jan_31: int = JAN_15 + 16 * DAY
	var feb_28: int = Catalog.add_months(jan_31, 1)
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(feb_28)
	assert_eq([d["year"], d["month"], d["day"], d["hour"]], [2027, 2, 28, 12], "31/01 + 1 mês")
	d = Time.get_datetime_dict_from_unix_time(Catalog.add_months(JAN_15, 12))
	assert_eq([d["year"], d["month"], d["day"]], [2028, 1, 15])
	d = Time.get_datetime_dict_from_unix_time(Catalog.add_months(JAN_15 - 30 * DAY, 2))
	assert_eq([d["year"], d["month"], d["day"]], [2027, 2, 16], "16/12/2026 + 2 meses")
	assert_eq(Catalog.days_in_month(2028, 2), 29)
	assert_eq(Catalog.days_in_month(2100, 2), 28)


## Compras com prazo feitas durante um prazo começam quando ele acaba (SPEC 12).
func test_store_ad_free_periods_stack() -> void:
	var rights: Dictionary = Catalog.entitlements([
		{"id": Catalog.RENEWAL, "time": JAN_15 + 10 * DAY},
		{"id": "mesa_rubi_2meses", "time": JAN_15},
	])
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(rights["ad_free_until"])
	assert_eq([d["year"], d["month"], d["day"]], [2027, 9, 15], "15/01 + 2 meses + 6 meses")
	assert_true(Catalog.ad_free(rights, JAN_15 + DAY))
	assert_false(Catalog.ad_free(rights, rights["ad_free_until"]))
	# Compra depois do prazo vencido começa na data dela.
	var late: Dictionary = Catalog.entitlements([
		{"id": "mesa_rubi_2meses", "time": JAN_15},
		{"id": Catalog.RENEWAL, "time": JAN_15 + 365 * DAY},
	])
	d = Time.get_datetime_dict_from_unix_time(late["ad_free_until"])
	assert_eq([d["year"], d["month"], d["day"]], [2028, 7, 15])


func test_store_avatar_choices() -> void:
	var rights: Dictionary = Catalog.entitlements([{"id": "avatares_2", "time": JAN_15}])
	var first: int = Paint.FREE_AVATARS
	assert_eq(Catalog.avatars_left([], rights), 2)
	assert_eq(Catalog.valid_choices([3, first, first, "x", 999, first + 4, first + 5], rights),
		[first, first + 4], "só exclusivos, sem repetir, no máximo 2")
	assert_eq(Catalog.avatars_left([first], rights), 1)
	assert_eq(Catalog.avatars_left([first, first + 1], rights), 0)
	assert_eq(Catalog.valid_choices([first], Catalog.entitlements([])), [], "sem compra")


func test_store_unlocks() -> void:
	var none: Dictionary = Catalog.entitlements([])
	assert_true(Catalog.table_unlocked("salao", none), "a Salão é de todos")
	assert_true(Catalog.avatar_unlocked(0, [], none), "os grátis são de todos")
	assert_eq(Catalog.table_unlocked("rubi", none), Catalog.BETA_FREE, "no Beta, todas")
	assert_eq(Catalog.avatar_unlocked(Paint.FREE_AVATARS, [], none), Catalog.BETA_FREE)
	var rights: Dictionary = Catalog.entitlements([{"id": "completo_rubi", "time": JAN_15}])
	assert_true(Catalog.table_unlocked("rubi", rights))
	assert_true(Catalog.avatar_unlocked(Paint.FREE_AVATARS + 3, [Paint.FREE_AVATARS + 3], rights))


func test_store_card_states() -> void:
	var rights: Dictionary = Catalog.entitlements([
		{"id": "mesa_rubi", "time": JAN_15},
		{"id": "completo_safira", "time": JAN_15},
	])
	assert_eq(Catalog.card_state(Catalog.TIER_TABLE, "rubi", rights), "bought")
	assert_eq(Catalog.card_state(Catalog.TIER_TABLE_ADS, "rubi", rights), "has_table",
		"já tem a Rubi: vem só o tempo")
	assert_eq(Catalog.card_state(Catalog.TIER_TABLE, "safira", rights), "has_all",
		"a Safira já veio no completo")
	assert_eq(Catalog.card_state(Catalog.TIER_FULL, "safira", rights), "bought")
	assert_eq(Catalog.card_state(Catalog.TIER_FULL, "perola", rights), "buy")
	assert_eq(Catalog.card_state(Catalog.TIER_AVATARS, "", rights), "buy")
	assert_eq(Catalog.first_missing_table(rights), "perola")
	assert_eq(Catalog.first_missing_table(Catalog.entitlements([])), "rubi")


## Os avatares escolhidos na Loja ficam no perfil; lixo no arquivo é descartado.
func test_store_choices_saved_in_profile() -> void:
	var path: String = "user://perfil_teste_loja.cfg"
	var profile: Profile = Profile.new()
	profile.load_file(path)
	profile.store_avatars = [Paint.FREE_AVATARS + 1, Paint.FREE_AVATARS + 7]
	assert_true(profile.save())
	var again: Profile = Profile.new()
	again.load_file(path)
	assert_eq(again.store_avatars, [Paint.FREE_AVATARS + 1, Paint.FREE_AVATARS + 7])
	var file: ConfigFile = ConfigFile.new()
	file.load(path)
	file.set_value("loja", "avatares", [2, "x", 999, Paint.FREE_AVATARS])
	file.save(path)
	again.load_file(path)
	assert_eq(again.store_avatars, [Paint.FREE_AVATARS], "só exclusivos que existem")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## A tela da Loja: sem loja do celular, tudo "Em breve" e travado; com preços, cada
## cartão mostra o seu estado; os avatares comprados se escolhem e ficam no perfil.
func test_store_screen_cards() -> void:
	var path: String = "user://perfil_teste_loja_tela.cfg"
	var profile: Profile = Profile.new()
	profile.load_file(path)
	var closed: ShopScreen = ShopScreen.new(profile, {"purchases": []})
	closed._build()
	for key: String in Catalog.TIERS:
		var card: Variant = closed._cards[key]
		assert_eq(card.pill, "Em breve", key)
		assert_true(card.disabled, "travado: " + key)
	assert_false(closed._cards[Catalog.RENEWAL].visible, "sem prazo, sem renovação")
	closed.free()

	var prices: Dictionary = {}
	for id: String in Catalog.all_products():
		prices[id] = "preço " + id
	var shop: ShopScreen = ShopScreen.new(profile, {"prices": prices, "purchases": [
		{"id": "mesa_rubi", "time": JAN_15}, {"id": "completo_safira", "time": JAN_15}]})
	shop._build()
	assert_eq(shop._table, "perola", "abre na mesa que falta")
	assert_eq(shop._cards[Catalog.TIER_TABLE].pill, "preço mesa_perola")
	assert_false(shop._cards[Catalog.TIER_TABLE].disabled)
	assert_true(shop._cards[Catalog.RENEWAL].visible, "já teve prazo: renovação à vista")
	shop._table = "rubi"
	shop._refresh()
	assert_eq(shop._cards[Catalog.TIER_TABLE].pill, "Comprado")
	assert_true(shop._cards[Catalog.TIER_TABLE].disabled)
	assert_eq(shop._cards[Catalog.TIER_TABLE_ADS].lines[0], "Você já tem a mesa Rubi")
	shop._on_card(Catalog.TIER_TABLE_ADS)
	assert_true(shop._dialog.visible, "avisa antes de vender só o tempo")
	assert_eq(shop._pending, "mesa_rubi_2meses")
	shop._table = "safira"
	shop._refresh()
	assert_eq(shop._cards[Catalog.TIER_TABLE].pill, "Você já tem", "veio no completo")
	assert_eq(shop._cards[Catalog.TIER_FULL].pill, "Escolher", "faltam os 2 avatares")
	assert_false(shop._cards[Catalog.TIER_FULL].disabled)
	shop._on_avatar_picked(Paint.FREE_AVATARS + 3)
	shop._on_avatar_picked(Paint.FREE_AVATARS + 3)
	shop._on_avatar_picked(Paint.FREE_AVATARS + 9)
	shop._on_avatar_picked(Paint.FREE_AVATARS + 11)
	assert_eq(profile.store_avatars, [Paint.FREE_AVATARS + 3, Paint.FREE_AVATARS + 9],
		"sem repetir e no máximo 2")
	assert_eq(shop._cards[Catalog.TIER_FULL].pill, "Comprado")
	shop.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
