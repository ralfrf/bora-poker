extends Control
## A partida offline: a mesa desenhando cada mensagem do servidor que roda dentro do
## app (ui/app/offline_game.gd). Termina com o placar quando a sala encerra ou quando
## você sai.

signal finished(final: Dictionary, members: Array, my_id: String)

const Ads := preload("res://ui/app/ads.gd")
const OfflineGame := preload("res://ui/app/offline_game.gd")
const TableView := preload("res://ui/table/table_view.gd")
const Dialog := preload("res://ui/widgets/dialog.gd")
const RankingSheet := preload("res://ui/widgets/ranking_sheet.gd")
const HistorySheet := preload("res://ui/widgets/history_sheet.gd")
const Protocol := preload("res://server/protocol.gd")

var _game: OfflineGame = null
var _table: TableView = null
var _dialog: Dialog = null
var _ranking: RankingSheet = null
var _history: HistorySheet = null
var _members: Array = []
var _done: bool = false


## game: a sessão já criada (begin chamado por quem abre a tela).
func _init(game: OfflineGame) -> void:
	_game = game


func _ready() -> void:
	_table = TableView.new()
	_table.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_table.acted.connect(func(action: String, amount: int) -> void: _game.act(action, amount))
	_table.rebuy_answered.connect(_on_rebuy)
	_table.back_requested.connect(func() -> void: _game.back())
	_table.leave_requested.connect(_ask_leave)
	_table.help_requested.connect(func() -> void: _ranking.open())
	_table.history_requested.connect(open_history)
	add_child(_table)
	_ranking = RankingSheet.new()
	_ranking.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_ranking)
	_history = HistorySheet.new()
	_history.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_history)
	_dialog = Dialog.new()
	_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dialog.chosen.connect(func(index: int) -> void:
		if index == 0:
			_finish(_game.leave()))
	add_child(_dialog)


func _process(_delta: float) -> void:
	if _done:
		return
	for message: Dictionary in _game.update():
		match message.get("t"):
			Protocol.STATE:
				_members = message.get("room", {}).get("members", [])
				_table.render(message)
				# Com o histórico aberto, uma mão que termina já entra na lista.
				if _history.visible:
					for event: Dictionary in message.get("events", []):
						if event.get("type") == "end" or event.get("type") == "cancel":
							_game.history()
							break
			Protocol.HANDS:
				_history.set_hands(message.get("hands", []), _game.my_id)
			Protocol.CLOSED:
				_finish(message)
				return


## Abre o histórico das mãos e pede a lista ao servidor.
func open_history() -> void:
	_ranking.close()
	_history.open()
	_game.history()


## Abre o ranking das mãos por cima da mesa (usado também nas fotos).
func open_ranking() -> void:
	_ranking.open()


func _ask_leave() -> void:
	_ranking.close()
	_history.close()
	_dialog.ask("Sair da mesa?", "A partida termina e você vê o placar.",
		["Sair", "Continuar jogando"])


## Recompra: primeiro o anúncio, depois o pedido ao servidor. Quem prefere assistir não
## responde nada: a oferta fica aberta, sem prazo, e a mesa mostra "Voltar ao jogo".
func _on_rebuy(accept: bool) -> void:
	if accept:
		Ads.rewarded(func(watched: bool) -> void:
			if watched and not _done:
				_game.rebuy(true))


func _finish(final: Dictionary) -> void:
	if _done:
		return
	_done = true
	finished.emit(final, _members, _game.my_id)


## Botão "voltar" do Android: pergunta antes de sair.
func go_back() -> bool:
	if _history.visible:
		_history.close()
	elif _ranking.visible:
		_ranking.close()
	elif _dialog.visible:
		_dialog.visible = false
	else:
		_ask_leave()
	return true
