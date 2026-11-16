extends RefCounted
## Apoio para restaurar estados salvos em JSON. O JSON do Godot devolve todo número
## como float, e o jogo só trabalha com inteiros.


## Cópia do valor com os números inteiros de volta ao tipo inteiro, em qualquer nível.
## Um número com casas decimais fica como está, para a conferência de tipos recusá-lo.
static func ints(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			if is_finite(value) and value == floorf(value) and absf(value) < 9.0e15:
				return int(value)
			return value
		TYPE_ARRAY:
			var list: Array = []
			for item: Variant in value:
				list.append(ints(item))
			return list
		TYPE_DICTIONARY:
			var map: Dictionary = {}
			for key: Variant in value:
				map[key] = ints(value[key])
			return map
	return value


## Verdadeiro se `data` é um dicionário com cada chave de `schema` no tipo indicado
## ({chave: TYPE_*}).
static func matches(data: Variant, schema: Dictionary) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	for key: Variant in schema:
		if not data.has(key) or typeof(data[key]) != schema[key]:
			return false
	return true


## Verdadeiro se o dicionário tem todas as chaves pedidas.
static func has_keys(data: Dictionary, keys: Array) -> bool:
	for key: Variant in keys:
		if not data.has(key):
			return false
	return true
