extends RefCounted
## Carta = inteiro de 0 a 51: valor de 2 a 14 (o ás vale 14) e naipe de 0 a 3.
## Texto curto, usado em testes e registros: valor + naipe, como "As", "Td", "7c".

const COUNT: int = 52
const ACE: int = 14
const RANK_CHARS: String = "23456789TJQKA"
const SUIT_CHARS: String = "cdhs"
const RANK_LABELS: Array[String] = [
	"2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]
const RANK_NAMES: Array[String] = [
	"dois", "três", "quatro", "cinco", "seis", "sete", "oito", "nove", "dez",
	"valete", "dama", "rei", "ás"]
const SUIT_NAMES: Array[String] = ["paus", "ouros", "copas", "espadas"]
const SUIT_SYMBOLS: Array[String] = ["♣", "♦", "♥", "♠"]


static func make(rank_value: int, suit_value: int) -> int:
	return (rank_value - 2) * 4 + suit_value


static func rank(card: int) -> int:
	return (card >> 2) + 2


static func suit(card: int) -> int:
	return card & 3


static func is_valid(card: int) -> bool:
	return card >= 0 and card < COUNT


## "As" -> carta; -1 se o texto não for uma carta.
static func from_text(text: String) -> int:
	if text.length() != 2:
		return -1
	var rank_index: int = RANK_CHARS.find(text[0].to_upper())
	var suit_index: int = SUIT_CHARS.find(text[1].to_lower())
	if rank_index < 0 or suit_index < 0:
		return -1
	return rank_index * 4 + suit_index


static func to_text(card: int) -> String:
	if not is_valid(card):
		return "??"
	return RANK_CHARS[card >> 2] + SUIT_CHARS[card & 3]


## "As Kd 7c" -> [carta, carta, carta]
static func list_from_text(text: String) -> Array[int]:
	var cards: Array[int] = []
	for token in text.split(" ", false):
		cards.append(from_text(token))
	return cards


static func list_to_text(cards: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for card in cards:
		parts.append(to_text(card))
	return " ".join(parts)


## Como a carta aparece na tela: "10♥", "A♠".
static func label(card: int) -> String:
	if not is_valid(card):
		return "?"
	return RANK_LABELS[card >> 2] + SUIT_SYMBOLS[card & 3]


static func rank_name(card: int) -> String:
	return RANK_NAMES[card >> 2] if is_valid(card) else "?"


static func suit_name(card: int) -> String:
	return SUIT_NAMES[card & 3] if is_valid(card) else "?"
