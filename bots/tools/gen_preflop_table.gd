extends SceneTree
## Gera a tabela de mãos iniciais de bots/preflop.gd: a chance de cada uma das 169 mãos
## contra uma mão ao acaso, em milésimos. Só precisa rodar de novo se o avaliador mudar.
##
##   godot --headless --path . -s res://bots/tools/gen_preflop_table.gd [-- --iterations=N]
##
## Posição na tabela, com os valores de 0 (o dois) a 12 (o ás), maior e menor:
##   par: maior * 13 + maior | do mesmo naipe: maior * 13 + menor | naipes diferentes: menor * 13 + maior

const Cards := preload("res://engine/cards.gd")
const Equity := preload("res://bots/equity.gd")

const DEFAULT_ITERATIONS: int = 20000


func _init() -> void:
	var iterations: int = DEFAULT_ITERATIONS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--iterations=") and arg.trim_prefix("--iterations=").is_valid_int():
			iterations = maxi(1, arg.trim_prefix("--iterations=").to_int())
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 169
	var table: Array[int] = []
	table.resize(169)
	for high in 13:
		for low in high + 1:
			if high == low:
				table[high * 13 + high] = _permille(high, low, false, iterations, rng)
			else:
				table[high * 13 + low] = _permille(high, low, true, iterations, rng)
				table[low * 13 + high] = _permille(high, low, false, iterations, rng)
	for row in 13:
		var parts: PackedStringArray = PackedStringArray()
		for column in 13:
			parts.append(str(table[row * 13 + column]))
		print("\t" + ", ".join(parts) + ",")
	quit(0)


func _permille(high: int, low: int, suited: bool, iterations: int,
		rng: RandomNumberGenerator) -> int:
	var hero: Array[int] = [Cards.make(high + 2, 0), Cards.make(low + 2, 0 if suited else 1)]
	return roundi(Equity.estimate(hero, [], 1, iterations, rng) * 1000.0)
