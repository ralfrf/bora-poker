extends "res://tests/test_case.gd"

const Money := preload("res://engine/money.gd")


func test_format() -> void:
	assert_eq(Money.format(0), "0,00")
	assert_eq(Money.format(5), "0,05")
	assert_eq(Money.format(10), "0,10")
	assert_eq(Money.format(2000), "20,00")
	assert_eq(Money.format(99999), "999,99")
	assert_eq(Money.format(100000), "1.000,00")
	assert_eq(Money.format(125000), "1.250,00")
	assert_eq(Money.format(123456789), "1.234.567,89")
	assert_eq(Money.format(-150), "-1,50")


func test_format_never_shows_currency_symbol() -> void:
	var text: String = Money.format(2000)
	assert_false(text.contains("R$"))
	assert_false(text.contains("$"))


func test_parse() -> void:
	assert_eq(Money.parse("20,00"), 2000)
	assert_eq(Money.parse("20"), 2000)
	assert_eq(Money.parse("20,5"), 2050)
	assert_eq(Money.parse("0,05"), 5)
	assert_eq(Money.parse("1.250,00"), 125000)
	assert_eq(Money.parse(" 7,10 "), 710)


func test_parse_rejects_invalid_text() -> void:
	for text: String in [
			"", "abc", "1,234", "1,2,3", "-5", "R$ 10", ",50", "1e3",
			"1.5", "1.50", "12.34,00", "1..000", ".500", "1.0000", "1234.567",
			"12,", "1.000,", "0.250", "00.123", "007", "00"]:
		assert_eq(Money.parse(text), -1, "texto '%s'" % text)
	assert_eq(Money.parse("1234567,89"), 123456789, "sem separador de milhar também vale")
	assert_eq(Money.parse("1.234.567,89"), 123456789)
	assert_eq(Money.parse("0"), 0)
	assert_eq(Money.parse("0,5"), 50)


func test_parse_and_format_round_trip() -> void:
	for cents: int in [0, 1, 99, 100, 2000, 123456, 99999999]:
		assert_eq(Money.parse(Money.format(cents)), cents)
