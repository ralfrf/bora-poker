extends Control
## Espaço reservado para um anúncio (SPEC 12), no alto da coluna da direita da mesa:
## longe dos botões de jogada (pelo menos AD_GAP da mesa) e nunca coberto por eles,
## para não gerar toque sem querer (regra das lojas). O tamanho vem de quem o coloca.
## Na fase com amigos não há anúncio nem SDK: mostra só o nome do jogo.

const Paint := preload("res://ui/widgets/paint.gd")
const T: String = "Tokens"

## Liga quando houver um serviço de anúncios (hoje não há).
var ads_enabled: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if ads_enabled:
		return
	var font: Font = get_theme_font("display", T)
	var font_size: int = get_theme_font_size("body", T)
	var text: String = "Bora Poker"
	var y: float = size.y / 2.0
	Paint.chip(self, Vector2(size.x / 2.0, y - 12.0), 11.0, get_theme_color("chip_0", T),
		get_theme_color("chip_mark", T), get_theme_constant("chip_style", T))
	draw_string(font, Vector2(0, y + 12.0 + font_size * 0.36), text,
		HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, Color(get_theme_color("text", T), 0.55))
