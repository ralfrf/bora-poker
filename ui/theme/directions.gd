extends RefCounted
## O tema do jogo (uma mesa só, "Salão"): um conjunto de valores (cores, fontes, raios
## e estilos das peças) que vira um Theme do Godot em ui_theme.gd. Nenhuma cena guarda
## cor solta; mudar estes valores muda o visual inteiro.
##
## O visual é de objeto de verdade: fundo de salão com luzes desfocadas, mesa com
## borda acolchoada e fio dourado, feltro com luz no centro, botões e placas com
## degradê, brilho no alto e sombra.
##
## fonts: [fonte dos textos, peso, fonte dos números e títulos, peso].
## Cores em pares *_top / * (alto e base do degradê) e *_line (contorno).
## card_green e card_blue: paus e ouros no baralho de 4 cores. avatar_0 a avatar_9: o
## fundo de cada avatar.
## Estilos (inteiros):
##   table_shape: 0 estádio (pontas redondas), 1 oval
##   card_style:  0 índice no canto e naipe grande embaixo, 1 valor grande e naipe ao lado
##   back_pattern: 0 treliça de losangos, 1 bolinhas, 2 divisas, 3 listras diagonais
##   chip_style:  0 marcas na borda, 1 anel interno, 2 marcas largas, 3 lisa com aro
##   felt_lane:   1 desenha a linha interna do feltro

const NAMES: Array[String] = ["Salão"]

const ALL: Array[Dictionary] = [
	{
		"name": "Salão",
		"mood": "Salão de jogo à noite: luzes quentes desfocadas, couro escuro, fio de ouro e feltro verde iluminado.",
		"fonts": ["inter", 500, "sora", 600],
		"colors": {
			"bg": "#05070D", "bg_top": "#121A2C",
			"bokeh_0": "#FFB54D", "bokeh_1": "#FFE3A8", "bokeh_2": "#5C8CFF",
			"felt_center": "#2C8C5C", "felt_edge": "#0B3D27",
			"rail": "#121419", "rail_hi": "#767C8A",
			"rail_line": "#E2B65C", "felt_line": "#FFFFFF",
			"accent": "#F2C14E", "accent_top": "#FFE7A3", "accent_line": "#8F6116",
			"on_accent": "#2A1A02",
			"text": "#F4F6F8", "text_dim": "#9AA6B4",
			"surface": "#0F1520", "surface_top": "#243045", "surface_line": "#34425A",
			"shadow": "#000000",
			"card_face": "#FFFFFF", "card_face_low": "#ECE6D8", "card_line": "#C9C2B2",
			"card_red": "#C8202F", "card_black": "#151A24", "court": "#F6EBD0",
			"card_back": "#7E1828", "card_back_top": "#B02A3E", "card_back_ink": "#F2C14E",
			"chip_0": "#F2C14E", "chip_1": "#D8333F", "chip_2": "#2F6FE0",
			"chip_3": "#F1F2F4", "chip_4": "#1E2229", "chip_mark": "#FFFFFF",
			"danger": "#F0504A", "ok": "#3DDC84",
			"button": "#141E2E", "button_top": "#33435E", "button_line": "#0A0F18",
			"fold": "#5E101B", "fold_top": "#B43444", "fold_line": "#3A070F",
			"call": "#123579", "call_top": "#3A74D6", "call_line": "#0A1E4A",
			"card_green": "#1C7F3C", "card_blue": "#1E56C2",
			"avatar_0": "#E9B949", "avatar_1": "#D1343F", "avatar_2": "#EFE8D8",
			"avatar_3": "#2C9A5E", "avatar_4": "#7A4FCF", "avatar_5": "#1D97A6",
			"avatar_6": "#EE7A2B", "avatar_7": "#283F6E", "avatar_8": "#2F6FE0",
			"avatar_9": "#566379",
			"medal_silver": "#C9D2DC", "medal_bronze": "#C98450",
		},
		"radius": {"card": 6, "button": 12, "panel": 14},
		"style": {"table_shape": 0, "card_style": 0, "back_pattern": 0, "chip_style": 0,
			"felt_lane": 1},
	},
]
