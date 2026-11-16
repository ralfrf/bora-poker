extends "res://tests/test_case.gd"

const Cashbox := preload("res://engine/cashbox.gd")
const Tournament := preload("res://engine/tournament.gd")


# --- Caixa de fichas ---

func test_entries_exits_and_net_balance() -> void:
	var box: Cashbox = Cashbox.new()
	assert_true(box.add_entry("ana", 2000))
	assert_true(box.add_entry("bia", 2000))
	assert_eq(box.total_entries(), 4000)
	assert_true(box.is_balanced(4000, 0))
	assert_true(box.is_balanced(3500, 500), "apostas e potes da mão contam")
	assert_false(box.is_balanced(3500, 0), "ficha sumida aparece")
	# Bia perdeu tudo para Ana e recomprou.
	assert_true(box.add_entry("bia", 2000))
	assert_eq(box.entries("bia"), 4000)
	assert_true(box.is_balanced(6000, 0))
	assert_eq(box.net("ana", 4000), 2000)
	assert_eq(box.net("bia", 2000), -2000)
	# Ana sai da mesa levando as fichas.
	assert_true(box.add_exit("ana", 4000))
	assert_eq(box.total_exits(), 4000)
	assert_true(box.is_balanced(2000, 0))
	assert_eq(box.net("ana", 0), 2000, "o saldo de quem saiu continua valendo")


func test_held_chips_of_a_dropped_player() -> void:
	var box: Cashbox = Cashbox.new()
	box.add_entry("ana", 2000)
	box.add_entry("bia", 2000)
	assert_true(box.hold("bia", 700))
	assert_eq(box.held("bia"), 700)
	assert_eq(box.total_held(), 700)
	assert_true(box.is_balanced(3300, 0))
	assert_eq(box.net("bia", 0), -1300, "fichas guardadas contam no saldo")
	assert_false(box.release("bia", 800), "não libera mais do que guardou")
	assert_true(box.release("bia", 700))
	assert_true(box.is_balanced(4000, 0))


func test_refuses_bad_amounts_and_unknown_ids() -> void:
	var box: Cashbox = Cashbox.new()
	assert_false(box.add_entry("ana", 0))
	assert_false(box.add_entry("ana", -5))
	assert_false(box.add_exit("ana", -1))
	assert_false(box.hold("ana", -1))
	assert_eq(box.entries("ninguém"), 0)
	assert_eq(box.net("ninguém", 0), 0)
	box.add_entry("ana", 100)
	box.forget("ana")
	assert_eq(box.total_entries(), 0)


func test_cashbox_save_and_restore() -> void:
	var box: Cashbox = Cashbox.new()
	box.add_entry("ana", 2000)
	box.add_entry("ana", 2000)
	box.add_exit("ana", 150)
	box.hold("bia", 30)
	var saved: String = JSON.stringify(box.to_dict())
	var copy: Cashbox = Cashbox.new()
	assert_true(copy.load_dict(JSON.parse_string(saved)), copy.load_error)
	assert_eq(JSON.stringify(copy.to_dict()), saved)
	assert_eq(copy.entries("ana"), 4000)
	assert_eq(copy.held("bia"), 30)


func test_cashbox_load_refuses_broken_state() -> void:
	var bad: Array = [
		{},
		{"accounts": "nada"},
		{"accounts": {"ana": 5}},
		{"accounts": {"ana": {"entries": 100, "exits": 0}}},
		{"accounts": {"ana": {"entries": "100", "exits": 0, "held": 0}}},
		{"accounts": {"ana": {"entries": 100.5, "exits": 0, "held": 0}}},
		{"accounts": {"ana": {"entries": 100, "exits": -1, "held": 0}}},
	]
	for state: Dictionary in bad:
		var box: Cashbox = Cashbox.new()
		box.add_entry("antes", 500)
		assert_false(box.load_dict(state), str(state))
		assert_true(box.load_error != "")
		assert_eq(box.entries("antes"), 500, "a caixa não muda quando a leitura falha")


# --- Torneio ---

func test_blind_levels() -> void:
	var expected: Array = [
		[10, 20], [15, 30], [25, 50], [50, 100], [75, 150], [100, 200], [150, 300],
		[200, 400], [300, 600], [500, 1000],
		[1000, 2000], [2000, 4000], [4000, 8000],   # depois do 10º, dobram
	]
	for level in expected.size():
		assert_eq(Tournament.small_blind(level), expected[level][0], "nível %d" % level)
		assert_eq(Tournament.big_blind(level), expected[level][1], "nível %d" % level)


func test_blinds_stop_growing_at_the_cap() -> void:
	var cap: int = Tournament.big_blind(Tournament.MAX_LEVEL)
	assert_true(cap > 0)
	assert_eq(Tournament.big_blind(Tournament.MAX_LEVEL + 100), cap)
	assert_eq(Tournament.big_blind(-3), 20)


func test_level_by_elapsed_time() -> void:
	assert_eq(Tournament.level_at(0, 5), 0)
	assert_eq(Tournament.level_at(299999, 5), 0)
	assert_eq(Tournament.level_at(300000, 5), 1)
	assert_eq(Tournament.level_at(180000, 3), 1)
	assert_eq(Tournament.level_at(1800000, 10), 3)
	assert_eq(Tournament.level_at(-50, 5), 0)
	assert_eq(Tournament.level_at(999999999999, 3), Tournament.MAX_LEVEL)


func test_time_to_next_level() -> void:
	assert_eq(Tournament.ms_to_next_level(0, 5), 300000)
	assert_eq(Tournament.ms_to_next_level(299000, 5), 1000)
	assert_eq(Tournament.ms_to_next_level(300000, 5), 300000)


func test_level_minutes_options() -> void:
	assert_eq(Tournament.LEVEL_MINUTES, [3, 5, 8, 10])
	assert_eq(Tournament.DEFAULT_LEVEL_MINUTES, 5)


func test_places_of_players_eliminated_in_the_same_hand() -> void:
	# Cinco tinham fichas; dois saíram: fica à frente quem tinha mais no início da mão.
	assert_eq(Tournament.assign_places(5, [
		{"seat": 1, "start_stack": 300}, {"seat": 2, "start_stack": 800}]),
		[{"seat": 2, "place": 4}, {"seat": 1, "place": 5}])
	# Com as mesmas fichas, dividem a colocação.
	assert_eq(Tournament.assign_places(5, [
		{"seat": 1, "start_stack": 500}, {"seat": 2, "start_stack": 500}]),
		[{"seat": 1, "place": 4}, {"seat": 2, "place": 4}])
	assert_eq(Tournament.assign_places(3, [{"seat": 0, "start_stack": 100}]),
		[{"seat": 0, "place": 3}])
	assert_eq(Tournament.assign_places(6, [
		{"seat": 0, "start_stack": 500}, {"seat": 1, "start_stack": 900},
		{"seat": 2, "start_stack": 500}]),
		[{"seat": 1, "place": 4}, {"seat": 0, "place": 5}, {"seat": 2, "place": 5}])
	assert_eq(Tournament.assign_places(4, []), [])
