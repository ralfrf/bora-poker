extends RefCounted
## Baralho de 52 cartas. O embaralhamento depende só da semente: no jogo o servidor
## passa uma semente aleatória forte a cada mão; nos testes, uma semente fixa.

const SIZE: int = 52


## As 52 cartas embaralhadas (Fisher-Yates). A primeira da lista é a primeira a sair.
static func shuffled(seed_value: int) -> Array[int]:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var cards: Array[int] = ordered()
	for i in range(SIZE - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: int = cards[i]
		cards[i] = cards[j]
		cards[j] = swap
	return cards


static func ordered() -> Array[int]:
	var cards: Array[int] = []
	cards.resize(SIZE)
	for i in SIZE:
		cards[i] = i
	return cards


## Baralho montado: as cartas dadas saem primeiro, na ordem; as outras completam o
## baralho em ordem crescente. Serve para os testes armarem uma mão.
static func stacked(top: Array) -> Array[int]:
	var cards: Array[int] = []
	var used: Dictionary = {}
	for card in top:
		cards.append(card)
		used[card] = true
	for card in SIZE:
		if not used.has(card):
			cards.append(card)
	return cards


## Verdadeiro se a lista só tem cartas válidas e nenhuma repetida.
static func is_valid(cards: Array) -> bool:
	var seen: Dictionary = {}
	for card in cards:
		if typeof(card) != TYPE_INT or card < 0 or card >= SIZE or seen.has(card):
			return false
		seen[card] = true
	return true
