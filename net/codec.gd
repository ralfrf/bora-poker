extends RefCounted
## Mensagem do protocolo como texto JSON (SPEC 8). O JSON do Godot devolve todo número
## como float; ao ler, os números inteiros voltam ao tipo inteiro.

const Serial := preload("res://engine/serial.gd")


static func encode(message: Dictionary) -> String:
	return JSON.stringify(message)


## Devolve a mensagem, ou um dicionário vazio se o texto não for um objeto JSON.
static func decode(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {}
	return Serial.ints(json.data)
