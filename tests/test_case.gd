extends RefCounted
## Base dos testes. As verificações registram a falha e deixam o teste seguir, para o
## executor mostrar todas de uma vez.

var failures: Array[String] = []
var checks: int = 0
var _current: String = ""


func begin(test_name: String) -> void:
	_current = test_name


func fail(message: String) -> void:
	failures.append("%s: %s" % [_current, message])


func assert_true(condition: bool, message: String = "") -> void:
	checks += 1
	if not condition:
		fail(message if message != "" else "esperava verdadeiro")


func assert_false(condition: bool, message: String = "") -> void:
	checks += 1
	if condition:
		fail(message if message != "" else "esperava falso")


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	checks += 1
	if typeof(actual) != typeof(expected) or actual != expected:
		var prefix: String = message + ": " if message != "" else ""
		fail("%sesperava %s, veio %s" % [prefix, str(expected), str(actual)])
