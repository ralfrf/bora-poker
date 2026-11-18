extends RefCounted
## Filtro básico dos apelidos (SPEC 4.4): desconhecidos veem o apelido na mesa e na
## lista de salas. Barra palavrões e discurso de ódio (nazismo, racismo, homofobia,
## transfobia, antissemitismo, violência sexual, pedofilia). O servidor troca um apelido
## barrado por "Jogador" e a tela do perfil avisa antes de salvar.
##
## Antes de comparar, o texto é normalizado: maiúsculas viram minúsculas, acentos saem,
## números e símbolos que imitam letras viram letras ("put4" = "puta"), letras repetidas
## viram uma só ("poooorra" = "porra") e "PalavraGrudada" se separa em palavras. As
## listas passam pela mesma normalização, então podem ser escritas do jeito comum.
##
## Três listas, do mais estrito ao mais solto, para não barrar nomes de verdade
## (Cuca, Paulo, Viaduto, Computador, Pica-Pau, Boston, Nazira, Neguinho):
## WORDS só a palavra inteira; STEMS o começo de uma palavra; ANYWHERE em qualquer
## ponto, mesmo com espaços ou pontos no meio ("c a r a l h o").

const WORDS: Array[String] = [
	# Palavrões.
	"cu", "cus", "puta", "puto", "putas", "putos", "pqp", "fdp", "vsf", "vtnc", "tnc",
	"tmnc", "krl", "crl", "krlh", "crlh", "prr", "porra", "porras", "bosta", "bostas",
	"merda", "rola", "piru", "piroca", "corno", "corna", "cornos", "babaca", "cacete",
	"xota", "foda", "fodas", "porno", "shit", "cunt", "pussy", "cock",
	# Contra mulheres.
	"vadia", "vagabunda", "vagabundo", "rapariga",
	# Homofobia e transfobia.
	"viado", "viada", "viados", "bicha", "bichas", "bixa", "sapatao", "traveco",
	"boiola", "baitola", "fag", "tranny", "dyke",
	# Nazismo.
	"nazi", "nazis", "heil", "fuhrer", "reich",
	# Racismo, antissemitismo e xenofobia.
	"crioulo", "crioula", "kike", "chink", "gook", "spic", "beaner", "coon",
	# Capacitismo e pedofilia.
	"mongoloide", "pedo",
]

const STEMS: Array[String] = [
	"cuzao", "cuzinh", "cuzud", "putinh", "putao", "putona", "putari", "fodid", "fodao",
	"foder", "fodend", "merdinh", "merdos", "cornud", "cornao", "otari", "vagabund",
	"piroc", "punhet", "bitch", "whore", "asshol", "porn",
	"viadinh", "viadao", "viadag", "boiol", "baitol", "faggot", "tranni",
	"nazist", "fuhrer",
	"nigg", "retardad",
]

const ANYWHERE: Array[String] = [
	# Palavrões.
	"caralh", "karalh", "cralh", "kralh", "buceta", "boceta", "xoxota", "xereca",
	"siririca", "punheta", "boquete", "piroca", "arrombad", "filhadaputa", "filhodaputa",
	"fodase", "fodasse", "tomarnocu", "tomanocu", "merda", "fuck",
	# Nazismo e supremacia branca.
	"hitler", "neonazi", "feminazi", "siegheil", "suastica", "swastika", "hakenkreuz",
	"auschwitz", "goebbels", "himmler", "mengele", "whitepower", "whitepride",
	"kukluxklan", "terceiroreich", "fascis", "facist", "facism", "supremacist", "racist",
	# Racismo e antissemitismo.
	"nigger", "nigga", "negroimund", "pretoimund", "negrosujo", "pretosujo",
	"macacoimund", "chingchong", "wetback", "raghead", "judeusujo", "matajudeu",
	"matapreto", "mataviado", "matagay",
	# Preconceito declarado.
	"machist", "machism", "misogin", "homofob", "transfob", "xenofob",
	# Violência sexual, pedofilia e terrorismo.
	"estupr", "pedofil", "binladen",
]

## Números que são códigos nazistas (14 palavras + "Heil Hitler").
const CODES: Array[String] = ["1488", "8814"]

## Símbolos de ódio que o teclado consegue digitar (suástica e runas da SS).
const SYMBOLS: Array[String] = ["卐", "卍", "ϟϟ", "ᛋᛋ", "࿕", "࿖"]

const ACCENTS: Dictionary = {
	"á": "a", "à": "a", "â": "a", "ã": "a", "ä": "a", "é": "e", "è": "e", "ê": "e",
	"ë": "e", "í": "i", "ì": "i", "î": "i", "ï": "i", "ó": "o", "ò": "o", "ô": "o",
	"õ": "o", "ö": "o", "ú": "u", "ù": "u", "û": "u", "ü": "u", "ç": "c", "ñ": "n",
}

## Números e símbolos que imitam letras.
const LOOKALIKE: Dictionary = {
	"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s",
	"!": "i",
}

static var _lists: Dictionary = {}


## O apelido tem palavrão ou ódio e não pode aparecer como está.
static func blocked(nick: String) -> bool:
	for symbol: String in SYMBOLS:
		if nick.contains(symbol):
			return true
	var digits: String = ""
	for i in nick.length():
		if nick[i] >= "0" and nick[i] <= "9":
			digits += nick[i]
	for code: String in CODES:
		if digits.contains(code):
			return true
	var tokens: Array[String] = _tokens(nick)
	var joined: String = "".join(tokens)
	if joined == "":
		return false
	var lists: Dictionary = _normalized_lists()
	var words: Dictionary = lists["words"]
	if words.has(joined):
		return true
	for token: String in tokens:
		if words.has(token):
			return true
		for stem: String in lists["stems"]:
			if token.begins_with(stem):
				return true
	for piece: String in lists["anywhere"]:
		if joined.contains(piece):
			return true
	return false


## As palavras do texto, já normalizadas, na ordem em que aparecem.
static func _tokens(text: String) -> Array[String]:
	var spaced: String = ""
	var previous_lower: bool = false
	for i in text.length():
		var c: String = text[i]
		var lower: String = c.to_lower()
		var is_upper: bool = c != lower
		# "PalavraGrudada": uma maiúscula depois de minúscula começa outra palavra.
		if is_upper and previous_lower:
			spaced += " "
		previous_lower = not is_upper and c != c.to_upper()
		lower = ACCENTS.get(lower, lower)
		lower = LOOKALIKE.get(lower, lower)
		var code: int = lower.unicode_at(0)
		spaced += lower if code >= 97 and code <= 122 else " "
	var tokens: Array[String] = []
	for part: String in spaced.split(" ", false):
		tokens.append(_collapse(part))
	return tokens


## Letras repetidas em seguida viram uma só.
static func _collapse(word: String) -> String:
	var out: String = ""
	for i in word.length():
		if i == 0 or word[i] != word[i - 1]:
			out += word[i]
	return out


static func _normalized_lists() -> Dictionary:
	if _lists.is_empty():
		var words: Dictionary = {}
		for word: String in WORDS:
			words["".join(_tokens(word))] = true
		var stems: Array[String] = []
		for stem: String in STEMS:
			stems.append("".join(_tokens(stem)))
		var anywhere: Array[String] = []
		for piece: String in ANYWHERE:
			anywhere.append("".join(_tokens(piece)))
		_lists = {"words": words, "stems": stems, "anywhere": anywhere}
	return _lists
