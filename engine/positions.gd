extends RefCounted
## Posições na mesa (SPEC 3.2, itens 1 a 3). Cada lugar é um número; "à esquerda" é o
## próximo número maior entre os que participam da mão, dando a volta.


## Próximo lugar à esquerda de `after`. `after` não precisa estar na lista.
static func next_seat(seats: Array, after: int) -> int:
	var next: int = -1
	var lowest: int = -1
	for seat: int in seats:
		if lowest == -1 or seat < lowest:
			lowest = seat
		if seat > after and (next == -1 or seat < next):
			next = seat
	return next if next != -1 else lowest


## Todos os lugares em ordem, começando à esquerda de `after`. Se `after` participa,
## fica por último.
static func order_after(seats: Array, after: int) -> Array[int]:
	var sorted: Array[int] = []
	sorted.assign(seats)
	sorted.sort()
	var ordered: Array[int] = []
	for seat in sorted:
		if seat > after:
			ordered.append(seat)
	for seat in sorted:
		if seat <= after:
			ordered.append(seat)
	return ordered


## Botão da primeira mão: sorteado pela semente.
static func first_button(seats: Array, seed_value: int) -> int:
	var sorted: Array[int] = []
	sorted.assign(seats)
	sorted.sort()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	return sorted[rng.randi_range(0, sorted.size() - 1)]


## Botão das mãos seguintes: o próximo à esquerda que vai participar da mão.
static func next_button(seats: Array, previous_button: int) -> int:
	return next_seat(seats, previous_button)


## No mano a mano o botão põe o small blind; com mais gente, é quem está à esquerda dele.
static func small_blind_seat(seats: Array, button: int) -> int:
	if seats.size() == 2:
		return button
	return next_seat(seats, button)


static func big_blind_seat(seats: Array, button: int) -> int:
	return next_seat(seats, small_blind_seat(seats, button))
