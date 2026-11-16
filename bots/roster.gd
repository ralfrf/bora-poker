extends RefCounted
## Níveis, estilos e nomes dos bots (SPEC 7).

const EASY: int = 1
const MEDIUM: int = 2
const HARD: int = 3
const LEVELS: Array[int] = [1, 2, 3]
const LEVEL_NAMES: Dictionary = {1: "Fácil", 2: "Médio", 3: "Difícil"}

## Estilo sem ajuste nenhum. Não tem nome próprio: serve às simulações que medem a
## força de cada nível.
const NEUTRAL: String = "neutral"

## Cada estilo ajusta o nível em torno do padrão:
##   loose: quantidade de mãos jogadas | aggr: apostas e aumentos | bluff: blefes
const STYLES: Dictionary = {
	"neutral": {"label": "Equilibrado", "loose": 1.0, "aggr": 1.0, "bluff": 1.0},
	"aggressive": {"label": "Agressivo", "loose": 1.1, "aggr": 1.3, "bluff": 1.2},
	"cautious": {"label": "Cauteloso", "loose": 0.82, "aggr": 0.85, "bluff": 0.5},
	"bluffer": {"label": "Blefador", "loose": 1.12, "aggr": 1.1, "bluff": 1.9},
}

const NAMES: Array = [
	["Zeca", "bluffer"], ["Tonho", "aggressive"], ["Cida", "cautious"],
	["Bia", "aggressive"], ["Juca", "cautious"], ["Malu", "bluffer"],
	["Chico", "cautious"], ["Nina", "bluffer"], ["Tião", "aggressive"],
	["Duda", "cautious"], ["Beto", "bluffer"], ["Lia", "aggressive"],
	["Guto", "aggressive"], ["Tati", "cautious"], ["Neco", "bluffer"],
	["Carol", "aggressive"], ["Dudu", "cautious"], ["Vivi", "bluffer"],
	["Caio", "cautious"], ["Paulinha", "bluffer"], ["Léo", "aggressive"],
	["Jô", "cautious"], ["Rafa", "bluffer"], ["Lu", "aggressive"],
]


static func is_level(level: Variant) -> bool:
	return typeof(level) == TYPE_INT and LEVELS.has(level)


static func traits(style: String) -> Dictionary:
	return STYLES.get(style, STYLES[NEUTRAL])


## Sorteia um nome que ainda não está na sala. Devolve {name, style}.
static func pick(rng: RandomNumberGenerator, taken: Array) -> Dictionary:
	var free: Array = []
	for entry: Array in NAMES:
		if not taken.has(entry[0]):
			free.append(entry)
	if free.is_empty():
		free = NAMES
	var chosen: Array = free[rng.randi_range(0, free.size() - 1)]
	return {"name": chosen[0], "style": chosen[1]}
