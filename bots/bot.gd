extends RefCounted
## Um bot (SPEC 7). Recebe a mesma mensagem "state" que um humano receberia naquele
## lugar e devolve a jogada. Não tem acesso à mesa do servidor.

const Roster := preload("res://bots/roster.gd")
const Situation := preload("res://bots/situation.gd")
const Easy := preload("res://bots/easy.gd")
const Medium := preload("res://bots/medium.gd")
const Hard := preload("res://bots/hard.gd")

var level: int = Roster.EASY
var style: String = Roster.NEUTRAL

var _traits: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _hand: int = -1
var _memory: Dictionary = {}


## evaluations: teto de mãos avaliadas por decisão do Difícil (0 = o padrão do nível).
func _init(bot_level: int, bot_style: String, seed_value: int, evaluations: int = 0) -> void:
	level = bot_level
	style = bot_style
	_traits = Roster.traits(bot_style)
	_rng.seed = seed_value
	if evaluations > 0:
		_memory["evaluations"] = evaluations


## Toda mensagem "state" passa por aqui, para o bot acompanhar a mão.
func observe(state: Dictionary) -> void:
	var table: Dictionary = state.get("table", {})
	var number: int = int(table.get("hand", -1))
	if number != _hand:
		_hand = number
		_memory["aggressor"] = -1
		_memory["equity"] = {}
	if str(table.get("street", "")) != "preflop":
		return
	for event: Dictionary in state.get("events", []):
		if event.get("type") == "action" and (event["action"] == "bet" or event["action"] == "raise"):
			_memory["aggressor"] = int(event["seat"])


## A jogada do bot para a situação da mensagem: {action, amount}.
func decide(state: Dictionary) -> Dictionary:
	var s: Dictionary = Situation.read(state)
	if s.is_empty():
		return Situation.fold()
	var choice: Dictionary
	match level:
		Roster.HARD:
			choice = Hard.choose(s, _traits, _rng, _memory)
		Roster.MEDIUM:
			choice = Medium.choose(s, _traits, _rng, int(_memory.get("aggressor", -1)) == int(s["seat"]))
		_:
			choice = Easy.choose(s, _traits, _rng)
	return Situation.sanitize(s, choice)


## Quem zerou no clássico: os bots sempre recompram, para a mesa não esvaziar.
func wants_rebuy() -> bool:
	return true
