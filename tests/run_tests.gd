extends SceneTree
## Executor de testes de linha de comando, sem dependência externa.
##
##   godot --headless --path . -s res://tests/run_tests.gd [-- opções]
##
## Opções (depois de "--"):
##   --only=texto   roda só os testes cujo nome contém o texto (sem a simulação)
##   --hands=N      mãos da simulação do motor (no teste de força: mãos por lado)
##   --bot-hands=N  mãos da simulação com bots pelo servidor
##   --seed=N       semente das simulações
##   --no-sim       pula as simulações
##   --sim-only     roda só as simulações
##   --strength     roda só o teste de força dos bots (demora; não entra no padrão)
##
## Mostra só as falhas e o total. Código de saída: 0 se tudo passou, 1 se não.
## Também é falha: nenhum teste rodar, opção inválida e qualquer erro de script.

const TestCase := preload("res://tests/test_case.gd")

const UNIT_DIR: String = "res://tests/unit"
const SIM_PATH: String = "res://tests/sim/sim_random.gd"
const BOT_SIM_PATH: String = "res://tests/sim/sim_bots.gd"
const STRENGTH_PATH: String = "res://tests/sim/sim_strength.gd"
const DEFAULT_HANDS: int = 3000
const DEFAULT_BOT_HANDS: int = 2000
const DEFAULT_STRENGTH_HANDS: int = 3000
const DEFAULT_SEED: int = 20261114


## Conta os erros que o Godot registra, para um erro de script não passar como sucesso.
class ErrorCounter:
	extends Logger

	var count: int = 0

	func _log_error(_function: String, _file: String, _line: int, _code: String,
			_rationale: String, _editor_notify: bool, error_type: int,
			_script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			count += 1

	func _log_message(_message: String, _error: bool) -> void:
		pass


var _failures: Array[String] = []
var _tests: int = 0
var _checks: int = 0
var _errors_reported: int = 0   # erros de script já atribuídos a um teste
var _exit_code: int = 1         # só vira 0 no fim de uma execução inteira e limpa


func _init() -> void:
	_run_all()
	quit(_exit_code)


func _run_all() -> void:
	var errors: ErrorCounter = ErrorCounter.new()
	OS.add_logger(errors)
	var started: int = Time.get_ticks_msec()

	var options: Dictionary = _parse_options(OS.get_cmdline_user_args())
	if _failures.is_empty():
		if options["strength"]:
			var hands: int = options["hands"] if options["hands_given"] else DEFAULT_STRENGTH_HANDS
			_run_simulation("teste de força", STRENGTH_PATH, hands, options["seed"], errors)
		else:
			if not options["sim_only"]:
				_run_unit_tests(options, errors)
			if not options["no_sim"] and options["only"] == "":
				_run_simulation("simulação", SIM_PATH, options["hands"], options["seed"], errors)
				_run_simulation("simulação com bots", BOT_SIM_PATH, options["bot_hands"],
					options["seed"], errors)
		if _tests == 0:
			_failures.append("nenhum teste rodou")
	if errors.count > _errors_reported:
		_failures.append("%d erro(s) de script fora dos testes" % (errors.count - _errors_reported))

	for line in _failures:
		print("FALHA  " + line)
	var seconds: float = (Time.get_ticks_msec() - started) / 1000.0
	print("Testes: %d | verificações: %d | falhas: %d | %.1f s" % [
		_tests, _checks, _failures.size(), seconds])
	OS.remove_logger(errors)
	if _failures.is_empty():
		_exit_code = 0


func _parse_options(args: PackedStringArray) -> Dictionary:
	var options: Dictionary = {
		"only": "", "hands": DEFAULT_HANDS, "hands_given": false, "bot_hands": DEFAULT_BOT_HANDS,
		"seed": DEFAULT_SEED, "no_sim": false, "sim_only": false, "strength": false,
	}
	for arg in args:
		if arg == "--no-sim":
			options["no_sim"] = true
		elif arg == "--sim-only":
			options["sim_only"] = true
		elif arg == "--strength":
			options["strength"] = true
		elif arg.begins_with("--bot-hands="):
			var bot_hands: String = arg.trim_prefix("--bot-hands=")
			if bot_hands.is_valid_int() and bot_hands.to_int() > 0:
				options["bot_hands"] = bot_hands.to_int()
			else:
				_failures.append("--bot-hands precisa de um número maior que zero")
		elif arg.begins_with("--only="):
			options["only"] = arg.trim_prefix("--only=")
		elif arg.begins_with("--hands="):
			var hands: String = arg.trim_prefix("--hands=")
			if hands.is_valid_int() and hands.to_int() > 0:
				options["hands"] = hands.to_int()
				options["hands_given"] = true
			else:
				_failures.append("--hands precisa de um número maior que zero")
		elif arg.begins_with("--seed="):
			var seed_text: String = arg.trim_prefix("--seed=")
			if seed_text.is_valid_int():
				options["seed"] = seed_text.to_int()
			else:
				_failures.append("--seed precisa de um número inteiro")
		else:
			_failures.append("opção desconhecida: " + arg)
	if options["no_sim"] and options["sim_only"]:
		_failures.append("--no-sim e --sim-only não combinam")
	if options["sim_only"] and options["only"] != "":
		_failures.append("--only e --sim-only não combinam")
	if options["strength"] and (options["only"] != "" or options["no_sim"] or options["sim_only"]):
		_failures.append("--strength roda sozinho")
	return options


func _run_unit_tests(options: Dictionary, errors: ErrorCounter) -> void:
	var only: String = options["only"]
	var files: PackedStringArray = DirAccess.get_files_at(UNIT_DIR)
	files.sort()
	for file_name in files:
		if not (file_name.begins_with("test_") and file_name.ends_with(".gd")):
			continue
		var script: GDScript = load(UNIT_DIR + "/" + file_name) as GDScript
		if script == null or not script.can_instantiate():
			_failures.append("%s: o arquivo não carregou" % file_name)
			continue
		var suite: TestCase = script.new() as TestCase
		if suite == null:
			_failures.append("%s: precisa estender tests/test_case.gd" % file_name)
			continue
		var seen: Dictionary = {}
		for method in suite.get_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with("test_") or seen.has(method_name):
				continue
			seen[method_name] = true
			var label: String = "%s.%s" % [file_name.get_basename(), method_name]
			if only != "" and not label.contains(only):
				continue
			_tests += 1
			suite.begin(label)
			if not (method["args"] as Array).is_empty():
				suite.fail("teste não pode ter parâmetros")
				continue
			var errors_before: int = errors.count
			var checks_before: int = suite.checks
			suite.call(method_name)
			if errors.count > errors_before:
				suite.fail("erro de script durante o teste")
				_errors_reported += errors.count - errors_before
			elif suite.checks == checks_before:
				suite.fail("teste sem nenhuma verificação")
		_checks += suite.checks
		_failures.append_array(suite.failures)


func _run_simulation(label: String, path: String, hands: int, seed_value: int,
		errors: ErrorCounter) -> void:
	var script: GDScript = load(path) as GDScript
	if script == null or not script.can_instantiate():
		_failures.append("%s: o arquivo não carregou" % label)
		return
	var sim: Object = script.new()
	var errors_before: int = errors.count
	var summary: Variant = sim.call("run", hands, seed_value)
	_tests += 1
	if errors.count > errors_before:
		_failures.append("%s: erro de script" % label)
		_errors_reported += errors.count - errors_before
	if typeof(summary) != TYPE_DICTIONARY:
		_failures.append("%s: não devolveu o resumo" % label)
		return
	for message: Variant in summary["errors"]:
		_failures.append("%s: %s" % [label, str(message)])
	if int(summary["hands"]) <= 0:
		_failures.append("%s: nenhuma mão jogada" % label)
	_checks += int(summary["checks"])
	print(str(summary["line"]))
