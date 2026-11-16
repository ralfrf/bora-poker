extends RefCounted
## Caixa de fichas da sala (SPEC 8.1). Para cada participante guarda as entradas
## (fichas iniciais e recompras), as saídas (fichas que deixaram a mesa com ele) e as
## fichas guardadas (de quem saiu ou caiu e ainda pode voltar). A qualquer momento vale:
##
##   fichas nos lugares + apostas e potes da mão + guardadas + saídas = entradas

const Serial := preload("res://engine/serial.gd")

const ACCOUNT_SCHEMA: Dictionary = {"entries": TYPE_INT, "exits": TYPE_INT, "held": TYPE_INT}

var load_error: String = ""      ## por que o último load_dict falhou
var _accounts: Dictionary = {}   # id -> {"entries", "exits", "held"}


## Fichas que entram na mesa para o participante: as iniciais ou uma recompra.
func add_entry(id: String, amount: int) -> bool:
	if amount <= 0:
		return false
	var account: Dictionary = _account(id)
	account["entries"] = int(account["entries"]) + amount
	return true


## Fichas que saem da mesa com o participante.
func add_exit(id: String, amount: int) -> bool:
	if amount < 0:
		return false
	var account: Dictionary = _account(id)
	account["exits"] = int(account["exits"]) + amount
	return true


## Fichas tiradas do lugar e guardadas para quem saiu ou caiu.
func hold(id: String, amount: int) -> bool:
	if amount < 0:
		return false
	var account: Dictionary = _account(id)
	account["held"] = int(account["held"]) + amount
	return true


## Fichas guardadas que deixam de estar guardadas: voltam ao lugar ou viram saída,
## conforme o que o chamador registrar em seguida.
func release(id: String, amount: int) -> bool:
	if amount < 0 or amount > held(id):
		return false
	var account: Dictionary = _account(id)
	account["held"] = int(account["held"]) - amount
	return true


## Apaga a conta de quem sentou e saiu antes de qualquer mão.
func forget(id: String) -> void:
	_accounts.erase(id)


func entries(id: String) -> int:
	return int(_accounts[id]["entries"]) if _accounts.has(id) else 0


func exits(id: String) -> int:
	return int(_accounts[id]["exits"]) if _accounts.has(id) else 0


func held(id: String) -> int:
	return int(_accounts[id]["held"]) if _accounts.has(id) else 0


func ids() -> Array:
	return _accounts.keys()


## Saldo líquido do placar: fichas atuais (no lugar, na mão ou guardadas) mais
## saídas, menos entradas.
func net(id: String, current_chips: int) -> int:
	return current_chips + held(id) + exits(id) - entries(id)


func total_entries() -> int:
	return _total("entries")


func total_exits() -> int:
	return _total("exits")


func total_held() -> int:
	return _total("held")


## A igualdade da seção 8.1.
func is_balanced(chips_on_seats: int, chips_in_hand: int) -> bool:
	return chips_on_seats + chips_in_hand + total_held() + total_exits() == total_entries()


func to_dict() -> Dictionary:
	return {"accounts": _accounts.duplicate(true)}


## Restaura a caixa gravada por to_dict. Devolve verdadeiro se deu certo; se não, o
## motivo fica em load_error e a caixa não muda.
func load_dict(saved: Dictionary) -> bool:
	load_error = "erro ao ler a caixa de fichas"
	var problem: String = _load(saved)
	load_error = problem
	return problem == ""


func _load(saved: Dictionary) -> String:
	var data: Dictionary = Serial.ints(saved)
	if not data.has("accounts") or typeof(data["accounts"]) != TYPE_DICTIONARY:
		return "caixa de fichas inválida"
	var loaded: Dictionary = {}
	var source: Dictionary = data["accounts"]
	for id: Variant in source:
		var account: Variant = source[id]
		if typeof(id) != TYPE_STRING or not Serial.matches(account, ACCOUNT_SCHEMA):
			return "conta da caixa de fichas inválida"
		if account["entries"] < 0 or account["exits"] < 0 or account["held"] < 0:
			return "conta da caixa de fichas com valor negativo"
		loaded[id] = {
			"entries": account["entries"], "exits": account["exits"], "held": account["held"],
		}
	_accounts = loaded
	return ""


func _account(id: String) -> Dictionary:
	if not _accounts.has(id):
		_accounts[id] = {"entries": 0, "exits": 0, "held": 0}
	return _accounts[id]


func _total(field: String) -> int:
	var sum: int = 0
	for id: Variant in _accounts:
		sum += int(_accounts[id][field])
	return sum
