extends RefCounted
## Temas de mesa: cada um é um conjunto de valores (cores, fontes, raios e estilos das
## peças) que vira um Theme do Godot em ui_theme.gd. Nenhuma cena guarda cor solta;
## trocar o tema troca o visual inteiro. As duas mesas usam as mesmas fontes.
##
## fonts: [fonte dos textos, peso, fonte dos números e títulos, peso].
## Estilos (inteiros):
##   table_shape: 0 estádio (pontas redondas), 1 oval
##   card_style:  0 índice no canto e naipe grande embaixo, 1 valor grande e naipe ao lado
##   back_pattern: 0 losangos, 1 bolinhas, 2 divisas, 3 listras diagonais
##   chip_style:  0 marcas na borda, 1 anel interno, 2 marcas largas, 3 lisa com aro
##   felt_lane:   1 desenha a linha interna do feltro

const NAMES: Array[String] = ["Meia-noite", "Arena"]

const ALL: Array[Dictionary] = [
	{
		"name": "Meia-noite",
		"mood": "Clube privado depois da meia-noite: escuro, quente e silencioso, com o ouro só onde importa.",
		"fonts": ["inter", 500, "sora", 600],
		"colors": {
			"bg": "#0B0F14", "bg_top": "#131B23",
			"felt_center": "#165A57", "felt_edge": "#0A3332",
			"rail": "#111820", "rail_line": "#C9A35A", "felt_line": "#FFFFFF",
			"accent": "#E6B450", "on_accent": "#1A1305",
			"text": "#EEF2F3", "text_dim": "#8C9BA0",
			"surface": "#18212A", "surface_line": "#2A3742", "shadow": "#000000",
			"card_face": "#FFFFFF", "card_line": "#D9DEE2",
			"card_red": "#CF3A3A", "card_black": "#141A20",
			"card_back": "#165A57", "card_back_ink": "#E6B450",
			"chip_0": "#E6B450", "chip_1": "#D0483D", "chip_2": "#2F6FD6",
			"chip_3": "#EDEFF1", "chip_4": "#1B1F24", "chip_mark": "#FFFFFF",
			"danger": "#E5695C", "button": "#18212A", "button_line": "#33424F",
		},
		"radius": {"card": 6, "button": 12, "panel": 12},
		"style": {"table_shape": 0, "card_style": 0, "back_pattern": 0, "chip_style": 0,
			"upper_buttons": 0, "button_border": 1, "felt_lane": 1},
	},
	{
		"name": "Arena",
		"mood": "Mesa de torneio iluminada: aro azul, feltro turquesa e placas escuras.",
		"fonts": ["inter", 500, "sora", 600],
		"colors": {
			"bg": "#070C2B", "bg_top": "#111C55",
			"felt_center": "#22A7AE", "felt_edge": "#0D6E79",
			"rail": "#18276B", "rail_line": "#7C95FF", "felt_line": "#FFFFFF",
			"accent": "#FFC94A", "on_accent": "#1A1305",
			"text": "#FFFFFF", "text_dim": "#A9B6DD",
			"surface": "#10173A", "surface_line": "#2A3678", "shadow": "#020418",
			"card_face": "#FFFFFF", "card_line": "#D9DEE2",
			"card_red": "#D93A3A", "card_black": "#111633",
			"card_back": "#18276B", "card_back_ink": "#7C95FF",
			"chip_0": "#FFC94A", "chip_1": "#E5484D", "chip_2": "#2FB5F0",
			"chip_3": "#F2F4FA", "chip_4": "#10173A", "chip_mark": "#FFFFFF",
			"danger": "#FF6B6B", "button": "#16205A", "button_line": "#34449A",
		},
		"radius": {"card": 6, "button": 12, "panel": 12},
		"style": {"table_shape": 1, "card_style": 0, "back_pattern": 1, "chip_style": 1,
			"upper_buttons": 0, "button_border": 1, "felt_lane": 1},
	},
]
