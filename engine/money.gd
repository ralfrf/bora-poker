extends RefCounted
## Valores do jogo: sempre inteiros em centavos (1 unidade = 0,01), nunca float.
## Na tela aparecem no formato brasileiro, ao lado de um ícone de ficha e sem
## símbolo de moeda.


## 125000 -> "1.250,00"
static func format(cents: int) -> String:
	var value: int = absi(cents)
	@warning_ignore("integer_division")
	var whole: String = str(value / 100)
	var grouped: String = ""
	while whole.length() > 3:
		grouped = "." + whole.right(3) + grouped
		whole = whole.left(whole.length() - 3)
	var prefix: String = "-" if cents < 0 else ""
	return "%s%s%s,%02d" % [prefix, whole, grouped, value % 100]


## "1.250,00" -> 125000. Aceita também "20" e "20,5". Só valores não negativos.
## O ponto só vale como separador de milhar ("1.5" é recusado, para não virar 15,00);
## depois da vírgula vêm um ou dois dígitos; zeros à esquerda não são aceitos.
## Devolve -1 se o texto não for um valor válido.
static func parse(text: String) -> int:
	var parts: PackedStringArray = text.strip_edges().split(",")
	if parts.size() > 2:
		return -1
	var cents: String = parts[1] if parts.size() == 2 else ""
	if cents.length() > 2 or not _only_digits(cents):
		return -1
	if parts.size() == 2 and cents == "":
		return -1
	var groups: PackedStringArray = parts[0].split(".")
	var whole: String = ""
	for i in groups.size():
		var group: String = groups[i]
		var size_ok: bool = group.length() >= 1
		if groups.size() > 1:
			size_ok = group.length() == 3 or (i == 0 and size_ok and group.length() < 3)
		if not size_ok or not _only_digits(group):
			return -1
		whole += group
	if whole.length() > 12 or (whole.length() > 1 and whole.begins_with("0")):
		return -1
	return whole.to_int() * 100 + cents.rpad(2, "0").to_int()


static func _only_digits(text: String) -> bool:
	for i in text.length():
		var code: int = text.unicode_at(i)
		if code < 48 or code > 57:
			return false
	return true
