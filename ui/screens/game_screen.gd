extends Control
## A partida: a mesa desenhando cada mensagem do servidor, que roda dentro do app
## (offline) ou no celular do anfitrião (Wi-Fi). Termina com o placar quando a sala
## encerra; no Wi-Fi, também quando o convidado sai, é expulso ou perde a conexão (aí
## sem placar: final vazio).

signal finished(final: Dictionary, members: Array, my_id: String)

const Ads := preload("res://ui/app/ads.gd")
const GameSession := preload("res://ui/app/game_session.gd")
const Money := preload("res://engine/money.gd")
const TableView := preload("res://ui/table/table_view.gd")
const Dialog := preload("res://ui/widgets/dialog.gd")
const RankingSheet := preload("res://ui/widgets/ranking_sheet.gd")
const HistorySheet := preload("res://ui/widgets/history_sheet.gd")
const ReactionSheet := preload("res://ui/widgets/reaction_sheet.gd")
const Protocol := preload("res://server/protocol.gd")

var _game: GameSession = null
var _table: TableView = null
var _dialog: Dialog = null
var _ranking: RankingSheet = null
var _history: HistorySheet = null
var _reactions: ReactionSheet = null
var _members: Array = []
var _done: bool = false
var _status: PanelContainer = null
var _status_label: Label = null
var _dialog_kind: String = ""      ## "leave" ou "return"
var _offer_seen: bool = false      ## a oferta de volta já foi mostrada com lugar livre


## game: a sessão já criada (begin chamado por quem abre a tela).
func _init(game: GameSession) -> void:
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
	_table.reactions_requested.connect(open_reactions)
	_table.sit_requested.connect(func() -> void: _game.sit_at(-1))
	_table.pause_requested.connect(func(on: bool) -> void:
		_game.owner(Protocol.CMD_PAUSE if on else Protocol.CMD_RESUME))
	_table.reactions_enabled = _game.has_reactions()
	add_child(_table)
	_ranking = RankingSheet.new()
	_ranking.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_ranking)
	_history = HistorySheet.new()
	_history.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_history)
	_reactions = ReactionSheet.new()
	_reactions.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reactions.chosen.connect(func(index: int) -> void:
		_game.react(index)
		_table.reaction_sent())
	add_child(_reactions)
	_dialog = Dialog.new()
	_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dialog.chosen.connect(_on_dialog)
	add_child(_dialog)
	_status = PanelContainer.new()
	_status.theme_type_variation = "DialogPanel"
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.visible = false
	_status_label = Label.new()
	_status_label.theme_type_variation = "StrongLabel"
	_status.add_child(_status_label)
	add_child(_status)
	# A sala de espera já recebeu o primeiro state: a mesa começa dele.
	if not _game.last_state.is_empty():
		_members = _game.last_state.get("room", {}).get("members", [])
		_table.render(_game.last_state)


func _process(_delta: float) -> void:
	if _done:
		return
	for message: Dictionary in _game.update():
		match message.get("t"):
			Protocol.STATE:
				_members = message.get("room", {}).get("members", [])
				_table.render(message)
				_check_offer(message.get("you", {}))
				# Com o histórico aberto, uma mão que termina já entra na lista.
				if _history.visible:
					for event: Dictionary in message.get("events", []):
						if event.get("type") == "end" or event.get("type") == "cancel":
							_game.history()
							break
			Protocol.HANDS:
				_history.set_hands(message.get("hands", []), _game.my_id)
			Protocol.REACTION:
				_table.show_reaction(int(message.get("seat", -1)), int(message.get("r", -1)))
			Protocol.CLOSED:
				_finish(message)
				return
			Protocol.LEFT:
				if not _game.pending_exit():
					_finish({})
					return
	if _game.failure() != "":
		_finish({})
		return
	_table.frozen = _game.waiting_host()
	_show_status(_game.status_text())


func _show_status(text: String) -> void:
	_status.visible = text != ""
	if text == "" or _status_label.text == text:
		return
	_status_label.text = text
	_status.reset_size()
	var panel: Vector2 = _status.get_combined_minimum_size()
	_status.size = panel
	_status.position = Vector2((size.x - panel.x) / 2.0, size.y * 0.12).round()


## Voltou com fichas guardadas (SPEC 6.2): pergunta com quais fichas voltar, quando há
## lugar livre.
func _check_offer(you: Dictionary) -> void:
	var offer: Dictionary = you.get("return_offer", {})
	if offer.is_empty() or not offer.get("seat", false):
		_offer_seen = false
		return
	if _offer_seen or _dialog.visible:
		return
	_offer_seen = true
	var before: int = int(offer.get("before", 0))
	var initial: int = int(offer.get("initial", 0))
	_dialog_kind = "return"
	if offer.get("can_initial", false):
		_dialog.dismissable = false
		_dialog.ask("Voltar para a mesa",
			"Suas fichas guardadas: %s. Ou volte com as fichas iniciais: %s%s." % [
				Money.format(before), Money.format(initial),
				" (conta como recompra)" if initial > before else ""],
			["Com as minhas", "Com as iniciais"])
	else:
		_dialog.dismissable = true
		_dialog.ask("Voltar para a mesa", "Suas fichas guardadas: %s." % Money.format(before),
			["Voltar", "Só assistir"])


func _on_dialog(index: int) -> void:
	_dialog.dismissable = true
	match _dialog_kind:
		"leave":
			if index == 0:
				var final: Dictionary = _game.leave()
				# O anfitrião que sai no meio da mão espera ela acabar para passar a sala.
				if not final.is_empty() or not _game.pending_exit():
					_finish(final)
		"return":
			var offer: Dictionary = _game.last_state.get("you", {}).get("return_offer", {})
			if offer.get("can_initial", false):
				_game.return_choice(index == 0)
			elif index == 0:
				_game.return_choice(true)
	_dialog_kind = ""


## Abre o histórico das mãos e pede a lista ao servidor.
func open_history() -> void:
	_ranking.close()
	_history.open()
	_game.history()


## Abre o painel de reações junto do botão (usado também nas fotos).
func open_reactions() -> void:
	_reactions.open(_table.reactions_corner())


## Abre o ranking das mãos por cima da mesa (usado também nas fotos).
func open_ranking() -> void:
	_ranking.open()


func _ask_leave() -> void:
	_ranking.close()
	_history.close()
	var question: Array[String] = _game.leave_question()
	_dialog_kind = "leave"
	_dialog.dismissable = true
	_dialog.ask(question[0], question[1], [question[2], "Continuar jogando"])


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
	if _reactions.visible:
		_reactions.close()
	elif _history.visible:
		_history.close()
	elif _ranking.visible:
		_ranking.close()
	elif _dialog.visible:
		if _dialog.dismissable:
			_dialog.visible = false
	else:
		_ask_leave()
	return true
