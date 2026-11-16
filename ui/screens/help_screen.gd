extends "res://ui/screens/screen.gd"
## Ajuda (SPEC 11.3): o ranking das mãos e as regras resumidas, em duas abas na coluna
## da direita. O texto das regras usa os termos da interface (SPEC 11.5).

signal back

const HandRanking := preload("res://ui/widgets/hand_ranking.gd")

## [título, texto] de cada bloco das regras.
const RULES: Array = [
	["A mão", "Cada um recebe 2 cartas fechadas. Na mesa abrem 5 cartas para todos: o flop (3), o turn (1) e o river (1). Vale a melhor combinação de 5 cartas entre as suas 2 e as 5 da mesa."],
	["As apostas", "Antes das cartas, dois jogadores põem os blinds (SB e BB). Na sua vez, você pode Desistir, Passar (se ninguém apostou), Pagar, Apostar ou Aumentar. All-in é apostar todas as suas fichas. O botão anda um lugar a cada mão."],
	["O showdown", "Se mais de um chegar ao fim, as cartas são mostradas e o pote vai para a melhor mão. Mãos iguais dividem o pote. Os naipes não desempatam."],
	["Clássico", "Os blinds não mudam. Quem perde todas as fichas pode recomprar, se a mesa permitir, ou continuar assistindo. No fim, o placar mostra o saldo de cada um."],
	["Torneio", "Todos começam com as mesmas fichas e os blinds sobem com o tempo. Não há recompra: quem zera sai. Vence quem ficar com todas as fichas."],
	["Fichas", "As fichas são só do jogo: não valem dinheiro, não se compram e não se vendem."],
]

var _title: Label = null
var _tabs: Array[Button] = []
var _ranking: HandRanking = null
var _rules: ScrollContainer = null
var _rule_columns: HBoxContainer = null
var _done: Button = null
var _tab: int = 0


## tab: 0 abre no ranking das mãos, 1 nas regras.
func _init(tab: int = 0) -> void:
	_tab = tab


func _build() -> void:
	_title = Label.new()
	_title.theme_type_variation = "TitleLabel"
	add_child(_title)
	_ranking = HandRanking.new()
	add_child(_ranking)
	_rules = ScrollContainer.new()
	_rules.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_rules)
	_rule_columns = HBoxContainer.new()
	_rule_columns.add_theme_constant_override("separation", 20)
	_rule_columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rules.add_child(_rule_columns)
	for c in 2:
		var column_box: VBoxContainer = VBoxContainer.new()
		column_box.add_theme_constant_override("separation", 10)
		column_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_rule_columns.add_child(column_box)
		for i in range(c * 3, c * 3 + 3):
			var block: VBoxContainer = VBoxContainer.new()
			block.add_theme_constant_override("separation", 2)
			var head: Label = Label.new()
			head.theme_type_variation = "StrongLabel"
			head.add_theme_color_override("font_color", get_theme_color("accent", T))
			head.text = RULES[i][0]
			block.add_child(head)
			var text: Label = Label.new()
			text.theme_type_variation = "SmallLabel"
			text.add_theme_font_size_override("font_size", 13)
			text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			text.text = RULES[i][1]
			block.add_child(text)
			column_box.add_child(block)
	var group: ButtonGroup = ButtonGroup.new()
	for i in 2:
		var tab: Button = Button.new()
		tab.text = "Ranking" if i == 0 else "Regras"
		tab.theme_type_variation = "ChoiceButton"
		tab.toggle_mode = true
		tab.button_group = group
		tab.focus_mode = Control.FOCUS_NONE
		tab.button_pressed = i == _tab
		tab.pressed.connect(_show_tab.bind(i))
		add_child(tab)
		_tabs.append(tab)
	_done = action_button("Voltar", true)
	_done.pressed.connect(func() -> void: back.emit())
	add_child(_done)
	_show_tab(_tab)


func _show_tab(index: int) -> void:
	_tab = index
	_title.text = "Ranking das mãos" if index == 0 else "Regras resumidas"
	_ranking.visible = index == 0
	_rules.visible = index == 1


func _layout() -> void:
	var b: Rect2 = body()
	var col: Rect2 = column()
	place(_title, Rect2(b.position.x, b.position.y, b.size.x, 34))
	var top: float = b.position.y + 42.0
	place(_ranking, Rect2(b.position.x, top, b.size.x, b.end.y - top))
	place(_rules, Rect2(b.position.x, top, b.size.x, b.end.y - top))
	_rule_columns.custom_minimum_size = Vector2(b.size.x, 0)
	for i in _tabs.size():
		place(_tabs[i], Rect2(col.position.x, col.position.y + i * 48.0, col.size.x, 40))
	place(_done, Rect2(col.position.x, col.end.y - BUTTON_H, col.size.x, BUTTON_H))


func go_back() -> bool:
	back.emit()
	return true
