extends "res://ui/screens/screen.gd"
## Loja (SPEC 11.3 e 12): existe na estrutura, mas fica escondida na fase com amigos:
## nenhum botão leva até ela enquanto VISIBLE for falso. A ideia do dono: "Gostou do
## app?" com três níveis de apoio, do menor ao maior: escolher 2 avatares exclusivos;
## uma mesa; tudo isso e o fim dos anúncios para sempre. Os preços virão da própria
## loja do celular, nunca escritos aqui. Nunca fichas.

signal back

## Ligar só depois de combinar com o dono (etapa 6 em diante).
const VISIBLE: bool = false

var _title: Label = null
var _text: Label = null
var _done: Button = null


func _build() -> void:
	_title = Label.new()
	_title.theme_type_variation = "TitleLabel"
	_title.text = "Loja"
	add_child(_title)
	_text = Label.new()
	_text.theme_type_variation = "DimLabel"
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.text = "Gostou do app? Em breve você poderá apoiar e ganhar avatares exclusivos, mesas novas e o fim dos anúncios. Fichas não se compram: são só do jogo."
	add_child(_text)
	_done = action_button("Voltar", true)
	_done.pressed.connect(func() -> void: back.emit())
	add_child(_done)


func _layout() -> void:
	var b: Rect2 = body()
	var col: Rect2 = column()
	place(_title, Rect2(b.position.x, b.position.y, b.size.x, 34))
	place(_text, Rect2(b.position.x, b.position.y + 46.0, minf(b.size.x, 460.0), 80))
	place(_done, Rect2(col.position.x, col.end.y - BUTTON_H, col.size.x, BUTTON_H))


func go_back() -> bool:
	back.emit()
	return true
