extends RefCounted
## Escolhas da tela "Mesa offline" (SPEC 4.1) e a tradução delas para as opções que o
## servidor recebe em create_room. As escolhas são índices nas listas abaixo, para
## caberem no perfil e voltarem iguais na próxima vez.

const Money := preload("res://engine/money.gd")
const Roster := preload("res://bots/roster.gd")

const MIN_SEATS: int = 2
const MAX_SEATS: int = 9
const DEFAULT_SEATS: int = 4

const FORMATS: Array[String] = ["classic", "tournament"]
const FORMAT_LABELS: Array[String] = ["Clássico", "Torneio"]
const CLASSIC_STACKS: Array[int] = [1000, 2000, 5000, 10000]
const BLINDS: Array = [[5, 10], [10, 20], [25, 50], [50, 100]]
const TOURNAMENT_STACKS: Array[int] = [2000, 3000, 5000]
const LEVEL_MINUTES: Array[int] = [3, 5, 8, 10]
const TURN_SECONDS: Array[int] = [15, 30, 60, 0]
const TURN_LABELS: Array[String] = ["15 s", "30 s", "60 s", "Sem limite"]
const REBUYS: Array[int] = [0, 1, 2, 3, -1]
const REBUY_LABELS: Array[String] = ["Não", "1", "2", "3", "Sem limite"]
## 0 = misto: um de cada nível, em rodízio.
const BOT_LEVELS: Array[int] = [Roster.EASY, Roster.MEDIUM, Roster.HARD, 0]
const BOT_LABELS: Array[String] = ["Fácil", "Médio", "Difícil", "Misto"]

const KEEP_OPEN_LABELS: Array[String] = ["Não", "Sim"]

## keep_open: só nas salas com amigos (Wi-Fi e à distância), no clássico.
const DEFAULTS: Dictionary = {
	"format": 0, "seats": DEFAULT_SEATS, "stack": 1, "blinds": 1, "t_stack": 1,
	"minutes": 1, "turn": 1, "rebuys": 4, "bots": 1, "keep_open": 0,
}
const SIZES: Dictionary = {
	"format": 2, "stack": 4, "blinds": 4, "t_stack": 3, "minutes": 4, "turn": 4,
	"rebuys": 5, "bots": 4, "keep_open": 2,
}


## Escolhas guardadas, conferidas: o que estiver fora da lista volta ao padrão.
static func clean(raw: Dictionary) -> Dictionary:
	var choice: Dictionary = DEFAULTS.duplicate()
	for key: String in DEFAULTS:
		var value: Variant = raw.get(key)
		if typeof(value) != TYPE_INT:
			continue
		var ok: bool = value >= MIN_SEATS and value <= MAX_SEATS if key == "seats" \
			else value >= 0 and value < int(SIZES[key])
		if ok:
			choice[key] = value
	return choice


static func is_tournament(choice: Dictionary) -> bool:
	return int(choice["format"]) == 1


## Opções de create_room: você e os bots ocupam todos os lugares.
static func build(choice: Dictionary) -> Dictionary:
	var seats: int = int(choice["seats"])
	var options: Dictionary = {
		"format": FORMATS[int(choice["format"])],
		"seats": seats,
		"turn_seconds": TURN_SECONDS[int(choice["turn"])],
		"bots": bot_levels(choice),
	}
	if is_tournament(choice):
		options["starting_stack"] = TOURNAMENT_STACKS[int(choice["t_stack"])]
		options["level_minutes"] = LEVEL_MINUTES[int(choice["minutes"])]
	else:
		var blinds: Array = BLINDS[int(choice["blinds"])]
		options["starting_stack"] = CLASSIC_STACKS[int(choice["stack"])]
		options["small_blind"] = blinds[0]
		options["big_blind"] = blinds[1]
		options["rebuy_limit"] = REBUYS[int(choice["rebuys"])]
	return options


## Opções de create_room de uma sala com amigos: sem bots (o dono põe na sala de espera)
## e com "manter sala aberta".
static func build_room(choice: Dictionary) -> Dictionary:
	var options: Dictionary = build(choice)
	options["bots"] = []
	options["keep_open"] = not is_tournament(choice) and int(choice["keep_open"]) == 1
	return options


static func bot_levels(choice: Dictionary) -> Array:
	var level: int = BOT_LEVELS[int(choice["bots"])]
	var levels: Array = []
	for i in int(choice["seats"]) - 1:
		levels.append(level if level != 0 else Roster.LEVELS[i % Roster.LEVELS.size()])
	return levels


static func stack_labels(tournament: bool) -> Array[String]:
	var labels: Array[String] = []
	for cents: int in (TOURNAMENT_STACKS if tournament else CLASSIC_STACKS):
		@warning_ignore("integer_division")
		labels.append(str(cents / 100))
	return labels


static func blind_labels() -> Array[String]:
	var labels: Array[String] = []
	for pair: Array in BLINDS:
		labels.append("%s/%s" % [Money.format(pair[0]), Money.format(pair[1])])
	return labels


static func minute_labels() -> Array[String]:
	var labels: Array[String] = []
	for minutes: int in LEVEL_MINUTES:
		labels.append("%d min" % minutes)
	return labels

