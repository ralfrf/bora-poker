extends RefCounted
## O que a Loja vende e o que cada compra dá (SPEC 12). Só contas: sem tela, sem rede e
## sem relógio (a data de cada compra vem da loja do celular).
##
## Tudo é compra única (volta sozinha pela conta Google ao reinstalar), menos a
## renovação, que é uma assinatura pré-paga (não renova sozinha). A Play não deixa
## comprar a mesma compra única duas vezes; por isso há um produto por mesa em cada
## nível (decisão do dono, 17/11/2026): a mesa é escolhida antes de pagar e volta igual
## ao reinstalar. Os 2 avatares são escolhidos depois da compra e, ao reinstalar,
## escolhidos de novo.
##
## Os preços nunca ficam aqui: vêm da loja do celular, já com o "R$" (exceção só da Loja).

const Paint := preload("res://ui/widgets/paint.gd")
const Tables := preload("res://ui/theme/tables.gd")

## Durante o Beta as mesas e os avatares exclusivos são grátis para todos (pedido do
## dono, 17/11/2026). Desligar quando as compras abrirem.
const BETA_FREE: bool = true

## Mesas que a Loja vende, na ordem da tela.
const TABLES: Array[String] = ["rubi", "safira", "perola"]

## Níveis, do menor ao maior (preços de referência na SPEC 12: 0,99 / 4,99 / 7,99 / 9,99).
const TIER_AVATARS: String = "avatares"
const TIER_TABLE: String = "mesa"
const TIER_TABLE_ADS: String = "mesa_sem_anuncios"
const TIER_FULL: String = "completo"
const TIERS: Array[String] = [TIER_AVATARS, TIER_TABLE, TIER_TABLE_ADS, TIER_FULL]

## A renovação do tempo sem anúncios (5,99, 6 meses), assinatura pré-paga.
const RENEWAL: String = "sem_anuncios_6meses"

## O que cada nível dá: avatares à escolha, se vem mesa e meses sem anúncios.
const GRANTS: Dictionary = {
	TIER_AVATARS: {"avatars": 2, "table": false, "months": 0},
	TIER_TABLE: {"avatars": 0, "table": true, "months": 0},
	TIER_TABLE_ADS: {"avatars": 0, "table": true, "months": 2},
	TIER_FULL: {"avatars": 2, "table": true, "months": 6},
}


## O código do produto na loja (o mesmo que for cadastrado no Play Console): letras
## minúsculas, números e "_".
static func product_id(tier: String, table: String = "") -> String:
	match tier:
		TIER_AVATARS:
			return "avatares_2"
		TIER_TABLE:
			return "mesa_%s" % table
		TIER_TABLE_ADS:
			return "mesa_%s_2meses" % table
		TIER_FULL:
			return "completo_%s" % table
	return ""


## Todos os produtos da Loja, para pedir os preços de uma vez.
static func all_products() -> Array[String]:
	var ids: Array[String] = [product_id(TIER_AVATARS)]
	for tier: String in [TIER_TABLE, TIER_TABLE_ADS, TIER_FULL]:
		for table: String in TABLES:
			ids.append(product_id(tier, table))
	ids.append(RENEWAL)
	return ids


## O que um produto dá: {"avatars", "table" (nome da mesa ou ""), "months"}. Produto
## desconhecido não dá nada.
static func grant(id: String) -> Dictionary:
	if id == RENEWAL:
		return {"avatars": 0, "table": "", "months": 6}
	if id == product_id(TIER_AVATARS):
		return _grant_of(TIER_AVATARS, "")
	for table: String in TABLES:
		for tier: String in [TIER_TABLE, TIER_TABLE_ADS, TIER_FULL]:
			if id == product_id(tier, table):
				return _grant_of(tier, table)
	return {"avatars": 0, "table": "", "months": 0}


static func _grant_of(tier: String, table: String) -> Dictionary:
	var g: Dictionary = GRANTS[tier]
	return {"avatars": g["avatars"], "table": table if g["table"] else "", "months": g["months"]}


## Junta as compras que a loja informou ({"id", "time"}, time em segundos desde 1970) no
## que a pessoa tem: mesas, quantos avatares pode escolher e até quando fica sem
## anúncios (0: nunca teve). Os prazos de compras diferentes se somam: uma compra feita
## durante um prazo começa a contar quando ele acaba. Compra repetida ou desconhecida
## não conta duas vezes.
static func entitlements(purchases: Array) -> Dictionary:
	var owned: Array[String] = []
	var tables: Array[String] = []
	var avatars: int = 0
	var timed: Array = []
	for raw: Variant in purchases:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var id: String = str((raw as Dictionary).get("id", ""))
		var time: Variant = (raw as Dictionary).get("time", 0)
		var g: Dictionary = grant(id)
		if owned.has(id) or (g["avatars"] == 0 and g["table"] == "" and g["months"] == 0):
			continue
		owned.append(id)
		avatars += int(g["avatars"])
		if g["table"] != "" and not tables.has(g["table"]):
			tables.append(g["table"])
		if g["months"] > 0:
			timed.append([int(time) if typeof(time) == TYPE_INT else 0, int(g["months"])])
	timed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var until: int = 0
	for entry: Array in timed:
		until = add_months(maxi(until, entry[0]), entry[1])
	return {"owned": owned, "tables": tables, "avatars": avatars, "ad_free_until": until}


## Soma meses de calendário a uma data (dia 31 + 1 mês cai no último dia do mês seguinte).
static func add_months(unix: int, months: int) -> int:
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(unix)
	var total: int = int(d["month"]) - 1 + months
	d["year"] = int(d["year"]) + floori(total / 12.0)
	d["month"] = posmod(total, 12) + 1
	d["day"] = mini(int(d["day"]), days_in_month(d["year"], d["month"]))
	return Time.get_unix_time_from_datetime_dict(d)


static func days_in_month(year: int, month: int) -> int:
	if month == 2:
		return 29 if (year % 4 == 0 and year % 100 != 0) or year % 400 == 0 else 28
	return 30 if [4, 6, 9, 11].has(month) else 31


## Está sem anúncios agora? (now em segundos desde 1970.)
static func ad_free(rights: Dictionary, now: int) -> bool:
	return int(rights.get("ad_free_until", 0)) > now


## Os avatares exclusivos escolhidos que valem: só exclusivos, sem repetir e no máximo
## quantos as compras dão (os primeiros ficam).
static func valid_choices(chosen: Array, rights: Dictionary) -> Array[int]:
	var out: Array[int] = []
	var limit: int = int(rights.get("avatars", 0))
	for raw: Variant in chosen:
		if out.size() >= limit:
			break
		if typeof(raw) == TYPE_INT and Paint.is_photo(raw) \
				and raw < Paint.AVATAR_COUNT and not out.has(raw):
			out.append(raw)
	return out


## Quantos avatares a pessoa ainda pode escolher.
static func avatars_left(chosen: Array, rights: Dictionary) -> int:
	return int(rights.get("avatars", 0)) - valid_choices(chosen, rights).size()


## A mesa pode ser usada? A Salão sempre; as da Loja no Beta ou se foram compradas.
static func table_unlocked(table: String, rights: Dictionary) -> bool:
	return table == Tables.SALAO or BETA_FREE or (rights.get("tables", []) as Array).has(table)


## O avatar pode ser usado? Os grátis sempre; os exclusivos no Beta ou se foram escolhidos.
static func avatar_unlocked(index: int, chosen: Array, rights: Dictionary) -> bool:
	return not Paint.is_photo(index) or BETA_FREE or valid_choices(chosen, rights).has(index)


## Como fica um cartão da Loja para a mesa escolhida:
##   "bought": este produto já foi comprado (não se compra de novo);
##   "has_all": a pessoa já tem tudo o que ele dá (ex.: a mesa sem tempo, já comprada
##              noutro nível): não vende;
##   "has_table": já tem a mesa; viria só o resto (tempo sem anúncios e, no completo,
##              os avatares). A Loja avisa antes de comprar;
##   "buy": à venda.
static func card_state(tier: String, table: String, rights: Dictionary) -> String:
	var id: String = product_id(tier, table)
	var owned: Array = rights.get("owned", [])
	if owned.has(id):
		return "bought"
	var g: Dictionary = GRANTS[tier]
	var has_table: bool = g["table"] and (rights.get("tables", []) as Array).has(table)
	if has_table and g["months"] == 0 and g["avatars"] == 0:
		return "has_all"
	if has_table:
		return "has_table"
	return "buy"


## A primeira mesa da Loja que a pessoa ainda não tem (ou a primeira, se tem todas).
static func first_missing_table(rights: Dictionary) -> String:
	for table: String in TABLES:
		if not (rights.get("tables", []) as Array).has(table):
			return table
	return TABLES[0]


## A renovação aparece para quem já teve tempo sem anúncios (SPEC 12: "depois do prazo").
static func shows_renewal(rights: Dictionary) -> bool:
	return int(rights.get("ad_free_until", 0)) > 0
