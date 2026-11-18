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

## Nome, estilo e "m" (homem) ou "f" (mulher), que escolhe o grupo de retratos.
const NAMES: Array = [
	["Zeca", "bluffer", "m"], ["Tonho", "aggressive", "m"], ["Cida", "cautious", "f"],
	["Bia", "aggressive", "f"], ["Juca", "cautious", "m"], ["Malu", "bluffer", "f"],
	["Chico", "cautious", "m"], ["Nina", "bluffer", "f"], ["Tião", "aggressive", "m"],
	["Duda", "cautious", "f"], ["Beto", "bluffer", "m"], ["Lia", "aggressive", "f"],
	["Guto", "aggressive", "m"], ["Tati", "cautious", "f"], ["Neco", "bluffer", "m"],
	["Carol", "aggressive", "f"], ["Dudu", "cautious", "m"], ["Vivi", "bluffer", "f"],
	["Caio", "cautious", "m"], ["Paulinha", "bluffer", "f"], ["Léo", "aggressive", "m"],
	["Jô", "cautious", "f"], ["Rafa", "bluffer", "m"], ["Lu", "aggressive", "f"],
]

## Os retratos dos bots, na ordem da grade de ui/avatars/fotos.png (os avatares 0 a 9
## são os grátis em vetor): 10 a 18 são homens (01 a 09 na arte) e 19 a 28 mulheres
## (11 a 20 na arte).
const MEN_AVATARS: Array[int] = [10, 11, 12, 13, 14, 15, 16, 17, 18]
const WOMEN_AVATARS: Array[int] = [19, 20, 21, 22, 23, 24, 25, 26, 27, 28]


static func is_level(level: Variant) -> bool:
	return typeof(level) == TYPE_INT and LEVELS.has(level)


static func traits(style: String) -> Dictionary:
	return STYLES.get(style, STYLES[NEUTRAL])


## Sorteia um nome que ainda não está na sala. Devolve {name, style, gender}.
static func pick(rng: RandomNumberGenerator, taken: Array) -> Dictionary:
	var free: Array = []
	for entry: Array in NAMES:
		if not taken.has(entry[0]):
			free.append(entry)
	if free.is_empty():
		free = NAMES
	var chosen: Array = free[rng.randi_range(0, free.size() - 1)]
	return {"name": chosen[0], "style": chosen[1], "gender": chosen[2]}


## Sorteia um retrato do grupo do nome ("m" ou "f") que ninguém na sala está usando;
## com todos em uso, repete um do grupo. Sempre um só sorteio no gerador.
static func avatar_for(rng: RandomNumberGenerator, gender: String, taken: Array) -> int:
	var group: Array[int] = WOMEN_AVATARS if gender == "f" else MEN_AVATARS
	var free: Array[int] = []
	for avatar: int in group:
		if not taken.has(avatar):
			free.append(avatar)
	if free.is_empty():
		free = group
	return free[rng.randi_range(0, free.size() - 1)]
