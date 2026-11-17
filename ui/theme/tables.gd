extends RefCounted
## As mesas: a Salão (grátis, a do tema) e as da Loja. Cada mesa muda só a mesa
## (feltro, borda, fios e estampa); fundo, cartas, botões e placas seguem o tema. O que
## uma mesa não diz vem do tema, por isso a Salão é um dicionário quase vazio.
##
## colors: as mesmas chaves do tema (felt_center, felt_edge, rail, rail_hi, rail_line,
##   felt_line) e mais pattern (cor da estampa, com transparência).
## style (inteiros):
##   rail_kind:    0 couro acolchoado, 1 madeira envernizada
##   felt_pattern: 0 liso, 1 estampa discreta de naipes
## lane_alpha: força da linha interna do feltro (0 a 1).

const SALAO: String = "salao"

const ALL: Dictionary = {
	"salao": {"name": "Salão"},
	"rubi": {
		"name": "Rubi",
		"colors": {
			"felt_center": "#A3243A", "felt_edge": "#3A0612",
			"rail": "#1A0F09", "rail_hi": "#9A6A42",
			"rail_line": "#E0B45A", "felt_line": "#E8BE66",
			"pattern": "#24020A4C",
		},
		"style": {"rail_kind": 1, "felt_pattern": 1},
		"lane_alpha": 0.4,
	},
}


## A mesa pelo nome interno; nome desconhecido vira a Salão.
static func skin(id: String) -> Dictionary:
	return ALL.get(id, ALL[SALAO])
