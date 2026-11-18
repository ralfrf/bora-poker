extends Control
## A mesa deitada para até 9: desenha uma mensagem `state` do protocolo (SPEC 9.1).
## Mesa oval à esquerda, com você embaixo e os adversários ao redor; à direita, uma
## coluna estreita com o espaço reservado do anúncio no alto (longe dos botões) e os
## três botões embaixo, ao alcance do polegar. O painel de aposta abre ao lado deles.
## Não fala com o servidor: quem usa a mesa liga os sinais e chama render() a cada
## `state`. As animações (cartas chegando, fichas indo ao pote e ao vencedor) saem dos
## eventos da mensagem.

signal acted(action: String, amount: int)
## Toque em "Sair", no canto de cima.
signal leave_requested
## Pedido de recompra (true). Continuar assistindo não manda nada: a oferta não tem
## prazo e o botão "Voltar ao jogo" abre a pergunta de novo.
signal rebuy_answered(accept: bool)
## Toque em "Voltei" (estava ausente).
signal back_requested
## Toque no "?": abrir o ranking das mãos.
signal help_requested
## Toque no botão do histórico: abrir as últimas mãos.
signal history_requested
## Tocou no placar.
signal score_requested
## Toque no balão: abrir o painel de reações.
signal reactions_requested
## Quem assiste tocou em "Sentar".
signal sit_requested
## Quem voltou com fichas guardadas toca em "Voltar à mesa" (reabre a pergunta).
signal return_requested
## Quem levou o pote sem showdown toca em "Mostrar cartas".
signal show_requested

const CardView := preload("res://ui/widgets/card_view.gd")
const SeatView := preload("res://ui/widgets/seat_view.gd")
const AmountView := preload("res://ui/widgets/amount_view.gd")
const TableFelt := preload("res://ui/widgets/table_felt.gd")
const Tables := preload("res://ui/theme/tables.gd")
const ActionBar := preload("res://ui/widgets/action_bar.gd")
const T: String = "Tokens"

const AdSlot := preload("res://ui/widgets/ad_slot.gd")
const BoardMarks := preload("res://ui/widgets/board_marks.gd")
const ChipFlight := preload("res://ui/widgets/chip_flight.gd")
const PotMath := preload("res://ui/table/pot_math.gd")
const SafeArea := preload("res://ui/theme/safe_area.gd")
const Sfx := preload("res://ui/app/sfx.gd")
const ListIcon := preload("res://ui/widgets/list_icon_button.gd")
const ScoreIcon := preload("res://ui/widgets/score_icon_button.gd")
const GlyphButton := preload("res://ui/widgets/glyph_button.gd")
const ReactionView := preload("res://ui/widgets/reaction_view.gd")
const Prefs := preload("res://ui/app/prefs.gd")

const BOARD_CARD: Vector2 = Vector2(44, 62)
const MY_CARD: Vector2 = Vector2(56, 78)
const THEIR_BACK: Vector2 = Vector2(18, 26)
const THEIR_FACE: Vector2 = Vector2(30, 42)
const MARGIN: float = 12.0
const BANNER_LINES: int = 2   # linhas do aviso de fim de mão (potes paralelos)
const BANNER_STEP: float = 24.0
const POT_VIEWS: int = 3   # pilhas no centro: principal e até 2 paralelos (o resto junto)
const POT_GAP: float = 6.0   # entre as linhas pequenas do aviso
const COLUMN_W: float = 136.0
const SHEET_W: float = 248.0
## Distância mínima entre o anúncio e o botão mais alto (regra das lojas).
const AD_GAP: float = 48.0
## Vibra quando faltam estes milissegundos para acabar a sua vez.
const WARN_MS: int = 5000
const BAR_H: float = 52.0     # linha dos três botões; os atalhos abrem por cima
## Ângulo (graus, 0 à direita, 90 embaixo) de cada posição em volta da mesa.
## As do topo (4, 5 e 9) ficam numa linha reta, lado a lado.
const SLOT_ANGLES: Array[float] = [90.0, 142.0, 180.0, 212.0, 255.0, 285.0, 328.0, 0.0,
	38.0, 270.0]

## Posições dos adversários, no sentido horário a partir da sua esquerda: 1 embaixo à
## esquerda, 2 meio, 3 alto, 4 e 5 no topo, 6 a 8 descendo pela direita, e 9 no topo
## ao centro (só para mesas com número ímpar de adversários no topo).
## Para cada número de lugares, quais posições ficam ocupadas.
const SLOTS: int = 10
const SLOT_MAP: Dictionary = {
	2: [9], 3: [3, 6], 4: [2, 9, 7], 5: [2, 4, 5, 7], 6: [1, 3, 9, 6, 8],
	7: [1, 2, 4, 5, 7, 8], 8: [1, 2, 3, 9, 6, 7, 8], 9: [1, 2, 3, 4, 5, 6, 7, 8],
}
const ACTION_TAGS: Dictionary = {
	"fold": "Desistiu", "check": "Passou", "call": "Pagou", "bet": "Apostou",
	"raise": "Aumentou",
}

var _felt: TableFelt = null
var _info: Label = null
var _seats: Dictionary = {}     # posição -> SeatView
var _hole: Dictionary = {}      # posição -> [CardView, CardView]
var _bets: Dictionary = {}      # posição -> AmountView
var _board: Array[CardView] = []
var _pot: Control = null              # as pilhas do centro (some junto na animação)
var _pot_views: Array[AmountView] = [] # pote principal e paralelos
var _pot_amounts: Array[int] = []
var _total: AmountView = null          # "Pote: X", com as apostas da rodada
var _mine: Array[CardView] = []
var _bar: ActionBar = null
var _waiting: Label = null
var _ad: AdSlot = null
var _marks: BoardMarks = null
var _exit: Button = null
var _help: Button = null
var _history: Button = null
var _score: Button = null
var _my_turn: bool = false
var _warned: bool = false
var _banners: Array[AmountView] = []   # fim da mão: uma linha por ganhador (ou "dividem")
var _prompt: VBoxContainer = null
var _prompt_text: Label = null
var _prompt_main: ActionBar.ActionButton = null
var _prompt_alt: ActionBar.ActionButton = null
var _prompt_kind: String = ""
var _rebuy_left_ms: int = -1
## Escolheu continuar assistindo em vez de recomprar (até a oferta acabar).
var _watching: bool = false
## Liga o botão de reações (Wi-Fi e à distância; no offline não há com quem reagir).
## O retorno com as fichas iniciais tem anúncio antes (Wi-Fi e à distância; não no offline).
var rebuy_ads: bool = true
var reactions_enabled: bool = false
## A mesa espera o anfitrião voltar: os relógios ficam parados (SPEC 6.4).
var frozen: bool = false
## A mesa escolhida (ui/theme/tables.gd); vazio é a Salão. render() troca pela mesa da
## sala (options.felt), que o dono escolheu.
var table_skin: Dictionary = {}:
	set(value):
		table_skin = value
		if _felt != null:
			_felt.skin = value
			_marks.skin = value
var _react: GlyphButton = null
var _react_ready_at: int = 0

var _state: Dictionary = {}
var _seat_count: int = 8
var _my_seat: int = -1
var _tags: Dictionary = {}       # lugar -> texto da última ação
var _countdowns: Dictionary = {} # lugar -> {ms, until, clock}: quem saiu ou caiu
var _turn_total_ms: int = 0
var _turn_left_ms: int = -1
var _turn_seat: int = -1
var _shown_board: int = 0         # cartas comunitárias já na tela (para animar as novas)
var _last_bets: Dictionary = {}   # posição -> ponto da aposta na tela (para irem ao pote)
var _last_amounts: Dictionary = {} # posição -> valor dessa aposta


func _ready() -> void:
	_felt = TableFelt.new()
	_felt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_felt.skin = table_skin
	add_child(_felt)
	_ad = AdSlot.new()
	add_child(_ad)
	_info = Label.new()
	_info.theme_type_variation = "SmallLabel"
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_info)
	_marks = BoardMarks.new()
	_marks.card = BOARD_CARD
	_marks.skin = table_skin
	add_child(_marks)
	for i in 5:
		var card: CardView = CardView.new()
		card.size = BOARD_CARD
		add_child(card)
		_board.append(card)
	_total = AmountView.new()
	_total.caption = "Pote"
	_total.visible = false
	add_child(_total)
	_pot = Control.new()
	_pot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pot)
	for i in POT_VIEWS:
		var pot_view: AmountView = AmountView.new()
		pot_view.visible = false
		_pot.add_child(pot_view)
		_pot_views.append(pot_view)
	for slot in SLOTS:
		if slot > 0:
			var pair: Array[CardView] = []
			for k in 2:
				var card: CardView = CardView.new()
				card.size = THEIR_BACK
				add_child(card)
				pair.append(card)
			_hole[slot] = pair
		var seat: SeatView = SeatView.new()
		seat.marks_up = slot == 0
		add_child(seat)
		_seats[slot] = seat
		var bet: AmountView = AmountView.new()
		bet.stack = true
		add_child(bet)
		_bets[slot] = bet
	for k in 2:
		var card: CardView = CardView.new()
		card.size = MY_CARD
		card.pivot_offset = Vector2(MY_CARD.x / 2.0, MY_CARD.y)
		card.rotation_degrees = -5.0 if k == 0 else 5.0
		card.glow = true
		add_child(card)
		_mine.append(card)
	_bar = ActionBar.new()
	_bar.acted.connect(func(action: String, amount: int) -> void: acted.emit(action, amount))
	_bar.sheet_toggled.connect(func(_open: bool) -> void:
		_place_bar()
		_refresh_react())
	add_child(_bar)
	add_child(_bar.sheet)
	_waiting = Label.new()
	_waiting.theme_type_variation = "DimLabel"
	_waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_waiting.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_waiting.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_waiting)
	for i in BANNER_LINES:
		var banner: AmountView = AmountView.new()
		banner.big = true
		banner.visible = false
		add_child(banner)
		_banners.append(banner)
	_exit = Button.new()
	_exit.text = "Sair"
	_exit.theme_type_variation = "QuietButton"
	_exit.focus_mode = Control.FOCUS_NONE
	_exit.pressed.connect(func() -> void: leave_requested.emit())
	add_child(_exit)
	_help = Button.new()
	_help.text = "?"
	_help.theme_type_variation = "QuietButton"
	_help.focus_mode = Control.FOCUS_NONE
	_help.pressed.connect(func() -> void: help_requested.emit())
	add_child(_help)
	_history = ListIcon.new()
	_history.pressed.connect(func() -> void: history_requested.emit())
	add_child(_history)
	_score = ScoreIcon.new()
	_score.pressed.connect(func() -> void: score_requested.emit())
	add_child(_score)
	_react = GlyphButton.new("react")
	_react.tooltip_text = "Reações"
	_react.pressed.connect(func() -> void: reactions_requested.emit())
	_react.visible = false
	add_child(_react)
	_prompt = VBoxContainer.new()
	_prompt.add_theme_constant_override("separation", 8)
	_prompt.alignment = BoxContainer.ALIGNMENT_END
	_prompt.visible = false
	add_child(_prompt)
	_prompt_text = Label.new()
	_prompt_text.theme_type_variation = "SmallLabel"
	_prompt_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt.add_child(_prompt_text)
	_prompt_main = ActionBar.ActionButton.new("PrimaryButton")
	_prompt_main.custom_minimum_size = Vector2(0, BAR_H)
	_prompt_main.pressed.connect(_on_prompt.bind(true))
	_prompt.add_child(_prompt_main)
	_prompt_alt = ActionBar.ActionButton.new()
	_prompt_alt.custom_minimum_size = Vector2(0, BAR_H)
	_prompt_alt.pressed.connect(_on_prompt.bind(false))
	_prompt.add_child(_prompt_alt)
	resized.connect(_layout)
	_layout()
	render(_state)


var _safe_seen: Rect2i = Rect2i()
var _safe_check: float = 0.0


func _process(delta: float) -> void:
	_safe_check -= delta
	if _safe_check <= 0.0 and OS.has_feature("mobile"):
		_safe_check = 0.5
		var safe: Rect2i = SafeArea.current()
		if safe != _safe_seen:
			_safe_seen = safe
			_layout()
	var turn_slot: int = _slot_of(_turn_seat)
	if turn_slot >= 0 and _state.get("table", {}).get("live", false):
		_seats[turn_slot].pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 4.5)
	if _react.disabled and Time.get_ticks_msec() >= _react_ready_at:
		_react.disabled = false
	# Mesa pausada ou esperando o anfitrião: os relógios não andam.
	var frozen_now: bool = _frozen()
	if not frozen_now and _turn_left_ms > 0 and _turn_total_ms > 0:
		_turn_left_ms = maxi(0, _turn_left_ms - int(delta * 1000.0))
		if turn_slot >= 0:
			_seats[turn_slot].set_fraction(float(_turn_left_ms) / _turn_total_ms)
		if _my_turn and not _warned and _turn_total_ms > WARN_MS and _turn_left_ms <= WARN_MS:
			_warned = true
			Sfx.vibrate(400)
	_tick_countdowns()
	if not frozen_now and _rebuy_left_ms > 0:
		var before: int = ceili(_rebuy_left_ms / 1000.0)
		_rebuy_left_ms = maxi(0, _rebuy_left_ms - int(delta * 1000.0))
		if ceili(_rebuy_left_ms / 1000.0) != before:
			_refresh_rebuy_text()


## Quem saiu ou caiu e ainda ocupa o lugar: a etiqueta diz "Saiu" ou "Reconectando…" e,
## quando o servidor manda remove_ms (torneio: 2 min; clássico: 60 s de quem caiu), o
## tempo até o lugar ser liberado aparece em cima do avatar. Devolve a etiqueta.
func _countdown_tag(seat_index: int, member: Dictionary) -> String:
	var base: String = "Saiu" if member.get("left", false) else "Reconectando…"
	if not member.has("remove_ms"):
		_countdowns.erase(seat_index)
		return base
	var ms: int = int(member["remove_ms"])
	var known: Dictionary = _countdowns.get(seat_index, {})
	# A mesma mensagem desenhada de novo (troca de tamanho da tela) não reinicia a conta.
	if int(known.get("ms", -2)) != ms:
		known = {"ms": ms, "until": Time.get_ticks_msec() + ms}
	known["clock"] = _countdown_clock(known)
	_countdowns[seat_index] = known
	return base


static func _countdown_clock(entry: Dictionary) -> String:
	var left: int = ceili(maxi(0, int(entry["until"]) - Time.get_ticks_msec()) / 1000.0)
	return "%d:%02d" % [left / 60, left % 60]


## A contagem anda a cada segundo, sem esperar a próxima mensagem do servidor.
func _tick_countdowns() -> void:
	for seat_index: int in _countdowns:
		var entry: Dictionary = _countdowns[seat_index]
		var clock: String = _countdown_clock(entry)
		if clock == entry["clock"]:
			continue
		entry["clock"] = clock
		var slot: int = _slot_of(seat_index)
		if slot < 0 or not _seats[slot].data.has("countdown"):
			continue
		var data: Dictionary = _seats[slot].data.duplicate()
		data["countdown"] = clock
		_seats[slot].data = data


## Desenha uma mensagem `state`.
func render(state: Dictionary) -> void:
	_state = state
	if not is_node_ready() or state.is_empty():
		return
	var room: Dictionary = state.get("room", {})
	var table: Dictionary = state.get("table", {})
	var you: Dictionary = state.get("you", {})
	var events: Array = state.get("events", [])
	_seat_count = int(room.get("options", {}).get("seats", 9))
	var felt: String = str(room.get("options", {}).get("felt", ""))
	if felt != "" and table_skin != Tables.skin(felt):
		table_skin = Tables.skin(felt)
	_my_seat = int(you.get("seat", -1))
	_note_events(events, table)
	_layout()

	var members: Dictionary = {}
	var me: Dictionary = {}
	for member: Dictionary in room.get("members", []):
		if int(member.get("seat", -1)) >= 0:
			members[int(member["seat"])] = member
		if member.get("id", "") == you.get("id", "-"):
			me = member
	var seats: Dictionary = {}
	for entry: Dictionary in table.get("seats", []):
		seats[int(entry["seat"])] = entry
	var live: bool = table.get("live", false)
	var to_act: int = int(table.get("to_act", -1))
	var result: Dictionary = table.get("result", {}) if not live else {}
	var winners: Dictionary = {}
	for payout: Dictionary in result.get("payouts", []):
		winners[int(payout.get("seat", -1))] = true
	# Cartas da melhor mão de quem ganhou o pote principal, para destacar.
	var best: Dictionary = {}
	var shown: Dictionary = {}
	for entry: Dictionary in result.get("shown", []):
		shown[int(entry["seat"])] = entry
	for payout: Dictionary in result.get("payouts", []):
		if shown.has(int(payout["seat"])):
			for card: Variant in shown[int(payout["seat"])].get("best", []):
				best[int(card)] = true
			break

	if to_act != _turn_seat or int(table.get("turn_ms", -1)) > _turn_left_ms + 400:
		_turn_total_ms = maxi(int(table.get("turn_ms", -1)), 0)
		if _turn_total_ms > 0:
			_turn_total_ms = maxi(_turn_total_ms,
				int(room.get("options", {}).get("turn_seconds", 0)) * 1000)
	_turn_seat = to_act
	_turn_left_ms = int(table.get("turn_ms", -1))
	# Aviso da sua vez: som quando ela chega; a vibração vem perto do fim do tempo.
	var my_turn: bool = live and _my_seat >= 0 and to_act == _my_seat and you.has("legal")
	if my_turn and not _my_turn:
		_warned = false
		Sfx.play(Sfx.TURN, 0.15)
	_my_turn = my_turn

	var counting: Dictionary = {}
	for slot in SLOTS:
		var seat_view: SeatView = _seats[slot]
		var seat_index: int = _seat_at(slot)
		var bet_view: AmountView = _bets[slot]
		var used: bool = seat_index >= 0
		seat_view.visible = used
		bet_view.visible = false
		if slot > 0:
			for card: CardView in _hole[slot]:
				card.visible = false
		if not used:
			continue
		var member: Dictionary = members.get(seat_index, {})
		var entry: Dictionary = seats.get(seat_index, {})
		if member.is_empty() and entry.is_empty():
			seat_view.data = {"empty": true}
			continue
		var turn: bool = live and seat_index == to_act
		var fraction: float = 1.0
		if turn and _turn_total_ms > 0:
			fraction = float(_turn_left_ms) / _turn_total_ms
		var tag: String = _tags.get(seat_index, "")
		if shown.has(seat_index):
			# Sem nome (mostrou antes do flop): fica a última ação.
			var hand_name: String = String(shown[seat_index].get("name", ""))
			tag = hand_name if hand_name != "" else tag
		elif member.get("left", false) or not member.get("connected", true):
			tag = _countdown_tag(seat_index, member)
			counting[seat_index] = true
		elif member.get("away", false) and member.has("remove_ms"):
			# Ausente: o tempo para tocar em "Voltei" aparece no avatar.
			if tag == "":
				tag = "Ausente"
			_countdown_tag(seat_index, member)
			counting[seat_index] = true
		var info: Dictionary = {
			"nick": member.get("nick", ""), "avatar": member.get("avatar", 0),
			"bot": member.get("bot", false),
			"stack": entry.get("stack", 0), "turn": turn, "fraction": fraction,
			"folded": entry.get("folded", false),
			"all_in": entry.get("all_in", false) and not shown.has(seat_index),
			"dealer": seat_index == int(table.get("button", -1)),
			"blind": _blind_of(seat_index, table, live),
			"tag": tag, "winner": winners.has(seat_index),
			"away": member.get("away", false), "rebuys": int(member.get("rebuys", 0)),
		}
		if counting.has(seat_index) and _countdowns.has(seat_index):
			info["countdown"] = _countdowns[seat_index]["clock"]
		seat_view.data = info
		var bet: int = int(entry.get("bet", 0))
		if live and bet > 0:
			bet_view.amount = bet
			bet_view.visible = true
			bet_view.place_at(_bet_point(slot))
		if slot > 0 and entry.get("in_hand", false) and not entry.get("folded", false):
			var cards: Array = entry.get("cards", [])
			var pair: Array = _hole[slot]
			for k in 2:
				var card: CardView = pair[k]
				card.card = int(cards[k]) if cards.size() == 2 else -1
				card.highlight = cards.size() == 2 and best.has(int(cards[k]))
				card.visible = true
			_place_hole(slot, _slot_point(slot))
	for seat_index: int in _countdowns.keys():
		if not counting.has(seat_index):
			_countdowns.erase(seat_index)

	var board: Array = table.get("board", [])
	for i in 5:
		_board[i].visible = i < board.size()
		if i < board.size():
			_board[i].card = int(board[i])
			_board[i].highlight = best.has(int(board[i]))
		else:
			_board[i].land()
	# Só o que já foi recolhido: as apostas da rodada estão na frente de cada lugar.
	_show_pots(table)

	var my_cards: Array = you.get("cards", [])
	var my_entry: Dictionary = seats.get(_my_seat, {})
	for k in 2:
		_mine[k].visible = my_cards.size() == 2
		if my_cards.size() == 2:
			_mine[k].card = int(my_cards[k])
			_mine[k].dimmed = my_entry.get("folded", false)
			_mine[k].highlight = best.has(int(my_cards[k]))
		else:
			_mine[k].land()

	_show_banner(result, members)
	_show_column(table, you, me, members)
	# Reações só para quem está sentado.
	_refresh_react()

	# Os blinds aparecem na mesa, na marca de quem pôs (SB e BB) e nas fichas dele.
	_info.text = "Mão %d" % int(table.get("hand", 0))
	_animate(events, table, board.size(), live)


## "SB" ou "BB" para quem pôs o blind nesta mão; vazio fora da mão.
func _blind_of(seat_index: int, table: Dictionary, live: bool) -> String:
	if not live:
		return ""
	if seat_index == int(table.get("sb_seat", -1)):
		return "SB"
	if seat_index == int(table.get("bb_seat", -1)):
		return "BB"
	return ""


## Embaixo da coluna: os botões na sua vez; a oferta de recompra; "Voltei" quando
## ausente; ou de quem é a vez.
func _show_column(table: Dictionary, you: Dictionary, me: Dictionary,
		members: Dictionary) -> void:
	# Mesa pausada: ninguém joga até o dono retomar (o servidor recusaria).
	var paused: bool = _state.get("room", {}).get("paused", false)
	var legal: Dictionary = {} if paused else you.get("legal", {})
	var kind: String = ""
	if legal.is_empty():
		if you.has("rebuy_ms"):
			kind = "watching" if _watching else "rebuy"
		elif me.get("away", false) and _my_seat >= 0:
			kind = "away"
		elif _my_seat < 0 and you.get("can_sit", false):
			kind = "sit"
		elif _my_seat < 0 and you.get("return_offer", {}).get("seat", false):
			kind = "return"
		elif _can_show(table):
			kind = "show"
	_bar.visible = not legal.is_empty()
	_prompt.visible = kind != ""
	_waiting.visible = legal.is_empty() and kind == ""
	if not legal.is_empty():
		_bar.show_legal(legal, int(table.get("pot", 0)), int(table.get("current_bet", 0)),
			int(table.get("small_blind", 1)))
	else:
		_bar.close_sheet()
		_waiting.text = _waiting_text(table, you, members)
	if not you.has("rebuy_ms"):
		_watching = false
	_prompt_kind = kind
	_rebuy_left_ms = int(you.get("rebuy_ms", -1))
	match kind:
		"rebuy":
			var stack: int = int(_state.get("room", {}).get("options", {}).get("starting_stack", 0))
			_prompt_main.set_content("Ver anúncio e retornar" if rebuy_ads else "Retornar", -1)
			_prompt_alt.set_content("Continuar assistindo", -1)
			_prompt_alt.visible = true
			_refresh_rebuy_text()
		"watching":
			_prompt_text.text = "Você está assistindo a partida."
			_prompt_main.set_content("Voltar ao jogo", -1)
			_prompt_alt.visible = false
		"away":
			_prompt_text.text = "Você ficou ausente e está desistindo das mãos." + (
				" Volte em até 2 minutos ou você sai da sala." if me.has("remove_ms") else "")
			_prompt_main.set_content("Voltei", -1)
			_prompt_alt.visible = false
		"sit":
			# Quem assiste e pode sentar (SPEC 4.3): sala aberta ou quem já jogou aqui.
			_prompt_text.text = "Você está assistindo. Há um lugar livre." + (
				" Sentar conta como um retorno: antes, um anúncio." if you.get("sit_rebuy", false) else "")
			_prompt_main.set_content("Sentar", -1)
			_prompt_alt.visible = false
		"return":
			# Voltou com fichas guardadas (SPEC 6.2) e abriu lugar.
			_prompt_text.text = "Suas fichas estão guardadas. Há um lugar livre."
			_prompt_main.set_content("Voltar à mesa", -1)
			_prompt_alt.visible = false
		"show":
			# Como nos sites: quem levou sem showdown, ou perdeu e teve a mão escondida,
			# pode mostrar, se quiser.
			_prompt_text.text = "Sua mão ficou escondida." 				if table.get("result", {}).get("showdown", false) 				else "Todos desistiram. Você levou o pote."
			_prompt_main.set_content("Mostrar cartas", -1)
			_prompt_alt.visible = false
	_place_prompt()


func _refresh_rebuy_text() -> void:
	if _prompt_kind != "rebuy":
		return
	# "Retornar", não "recomprar": as fichas são do jogo e não se compram (pedido do dono).
	var text: String = ("Suas fichas acabaram. Assista a um anúncio e volte à mesa com as fichas iniciais." 		if rebuy_ads else "Suas fichas acabaram. Toque em Retornar para voltar à mesa com as fichas iniciais.") 		+ " Cada retorno soma 1 no contador do seu avatar."
	if _rebuy_left_ms >= 0:
		text += " %d s para decidir." % ceili(_rebuy_left_ms / 1000.0)
	_prompt_text.text = text


func _on_prompt(main: bool) -> void:
	match _prompt_kind:
		"rebuy":
			if main:
				rebuy_answered.emit(true)
			else:
				_watching = true
				render(_state)
		"watching":
			_watching = false
			render(_state)
		"away":
			back_requested.emit()
		"sit":
			sit_requested.emit()
		"return":
			return_requested.emit()
		"show":
			show_requested.emit()


## Você pode mostrar as cartas por escolha: levou o pote porque todos desistiram, ou
## chegou ao showdown e a sua mão perdedora ficou escondida. Ainda não mostrou.
func _can_show(table: Dictionary) -> bool:
	if _my_seat < 0 or table.get("live", false):
		return false
	var result: Dictionary = table.get("result", {})
	if result.is_empty() or result.get("cancelled", false):
		return false
	var mine: Array = table.get("seats", []).filter(
		func(entry: Dictionary) -> bool: return int(entry.get("seat", -1)) == _my_seat)
	if mine.is_empty() or not mine[0].get("in_hand", false) or mine[0].get("folded", false):
		return false
	var payouts: Array = result.get("payouts", [])
	if not result.get("showdown", false) and (payouts.size() != 1
			or int(payouts[0].get("seat", -1)) != _my_seat):
		return false
	for entry: Dictionary in result.get("shown", []):
		if int(entry.get("seat", -1)) == _my_seat:
			return false
	return true


## Relógios parados: mesa pausada pelo dono, ou esperando o anfitrião voltar.
func _frozen() -> bool:
	return frozen or bool(_state.get("room", {}).get("paused", false))


## Mostra a reação de quem está nesse lugar, sobre o avatar (SPEC 11.2). Com "silenciar
## reações", só as suas aparecem.
func show_reaction(seat_index: int, index: int) -> void:
	if index < 0 or index >= ReactionView.Protocol.REACTIONS.size():
		return
	if Prefs.mute_reactions and seat_index != _my_seat:
		return
	var slot: int = _slot_of(seat_index)
	if slot < 0 or not _seats[slot].visible:
		return
	var bubble: ReactionView = ReactionView.new()
	add_child(bubble)
	bubble.index = index
	var seat: Control = _seats[slot]
	var top: Vector2 = seat.position + Vector2(seat.size.x / 2.0, -4.0)
	if slot == 0:
		top = seat.position + Vector2(seat.size.x / 2.0, -10.0)
	bubble.pop(top)


## O botão de reações: só para quem está sentado, e escondido com o painel de aposta
## aberto (ele fica por cima do canto do painel).
func _refresh_react() -> void:
	_react.visible = reactions_enabled and _my_seat >= 0 and not _bar.sheet.visible


## Você mandou uma reação: o botão descansa pelo intervalo mínimo do servidor.
func reaction_sent() -> void:
	_react_ready_at = Time.get_ticks_msec() + ReactionView.Protocol.REACTION_GAP_MS
	_react.disabled = true


## Onde o painel de reações abre: o canto de baixo à direita fica junto do botão.
func reactions_corner() -> Vector2:
	return _react.position + Vector2(_react.size.x, -8.0)


## Fim de mão: quem ganhou e quanto, embaixo das cartas comunitárias. Pote dividido
## numa linha só; potes paralelos ganhos por pessoas diferentes, uma linha para cada uma.
func _show_banner(result: Dictionary, members: Dictionary) -> void:
	var groups: Array = PotMath.groups(result.get("payouts", []), result.get("pots", []))
	if groups.size() > BANNER_LINES:
		# Mais ganhadores do que linhas: os menores valores ficam juntos na última.
		var rest: Dictionary = {"seats": [], "amount": 0}
		for group: Dictionary in groups.slice(BANNER_LINES - 1):
			rest["seats"].append_array(group["seats"])
			rest["amount"] = int(rest["amount"]) + int(group["amount"])
		groups = groups.slice(0, BANNER_LINES - 1) + [rest]
	for i in BANNER_LINES:
		var banner: AmountView = _banners[i]
		banner.visible = i < groups.size()
		if not banner.visible:
			continue
		var group: Dictionary = groups[i]
		# Várias linhas: menores, para caberem entre as cartas e a sua placa.
		banner.big = groups.size() == 1
		var names: Array[String] = []
		for seat_index: Variant in group["seats"]:
			var nick: String = "Você" if int(seat_index) == _my_seat 				else String(members.get(int(seat_index), {}).get("nick", ""))
			if nick != "" and not names.has(nick):
				names.append(nick)
		var who: String = "" if names.is_empty() else (names[0] if names.size() == 1 			else ", ".join(names.slice(0, names.size() - 1)) + " e " + names[-1])
		var verb: String = "ganha" if names.size() <= 1 else 			("dividem" if groups.size() == 1 else "ganham")
		banner.caption = ("%s %s" % [who, verb]).strip_edges()
		banner.amount = int(group["amount"])
		banner.place_at(_banner_point(i, groups.size()))


## Abre a folha de aposta (usado nas fotos e pela própria barra).
func open_bet_sheet() -> void:
	_bar.open_sheet()


func _waiting_text(table: Dictionary, you: Dictionary, members: Dictionary) -> String:
	if _state.get("room", {}).get("paused", false):
		return "Mesa pausada pelo dono."
	if _my_seat < 0 and you.has("return_offer"):
		return "Fichas guardadas. Você volta quando abrir um lugar."
	if _my_seat < 0:
		return "Assistindo"
	var to_act: int = int(table.get("to_act", -1))
	if table.get("live", false) and to_act >= 0:
		var nick: String = members.get(to_act, {}).get("nick", "")
		return "Vez de %s" % nick if nick != "" else ""
	return ""


func _note_events(events: Array, table: Dictionary) -> void:
	for event: Dictionary in events:
		match String(event.get("type", "")):
			"deal", "street":
				_tags.clear()
			"action":
				var tag: String = ACTION_TAGS.get(event.get("action", ""), "")
				_tags[int(event.get("seat", -1))] = tag


# ------------------------------------------------------------------ posições


func _slot_of(seat_index: int) -> int:
	if seat_index < 0:
		return -1
	var me: int = maxi(_my_seat, 0)
	var relative: int = (seat_index - me + _seat_count) % _seat_count
	if relative == 0:
		return 0
	var slots: Array = SLOT_MAP.get(_seat_count, SLOT_MAP[9])
	return int(slots[relative - 1]) if relative - 1 < slots.size() else -1


func _seat_at(slot: int) -> int:
	for seat_index in _seat_count:
		if _slot_of(seat_index) == slot:
			return seat_index
	return -1


## Área útil da tela, sem o furo da câmera (só o lado da câmera perde a faixa).
func _content() -> Rect2:
	return SafeArea.content(self)


func _column() -> Rect2:
	var content: Rect2 = _content()
	return Rect2(content.end.x - MARGIN - COLUMN_W, content.position.y + MARGIN, COLUMN_W,
		content.size.y - MARGIN * 2.0)


func _table_area() -> Rect2:
	var content: Rect2 = _content()
	return Rect2(content.position.x, content.position.y,
		_column().position.x - MARGIN - content.position.x, content.size.y)


func _felt_rect() -> Rect2:
	var area: Rect2 = _table_area()
	var w: float = area.size.x - 140.0
	var h: float = minf(area.size.y - 130.0, w * 0.5)
	var center: Vector2 = Vector2(area.get_center().x, area.position.y + area.size.y * 0.47)
	return Rect2(center - Vector2(w, h) / 2.0, Vector2(w, h))


func _table_center() -> Vector2:
	return _felt_rect().get_center()


## Centro do lugar em cada posição: numa elipse um pouco maior que o feltro, para as
## placas ficarem apoiadas no aro. Você (posição 0) fica embaixo, à esquerda das suas
## cartas.
func _seat_point(slot: int) -> Vector2:
	var felt: Rect2 = _felt_rect()
	var center: Vector2 = felt.get_center()
	if slot == 0:
		return Vector2(center.x - 62.0, felt.end.y + 24.0)
	if slot == 4 or slot == 5 or slot == 9:
		var offsets: Dictionary = {4: -72.0, 5: 72.0, 9: 0.0}
		return Vector2(center.x + offsets[slot], felt.position.y - 10.0)
	var a: float = deg_to_rad(SLOT_ANGLES[slot])
	var area: Rect2 = _table_area()
	var rx: float = minf(felt.size.x / 2.0 + 14.0, center.x - area.position.x - SeatView.SIZE.x / 2.0 - 4.0)
	var ry: float = felt.size.y / 2.0 + 22.0
	return center + Vector2(cos(a) * rx, sin(a) * ry)


## Centro do avatar de cada posição, em coordenadas da mesa.
func _slot_point(slot: int) -> Vector2:
	var seat: SeatView = _seats[slot]
	return _seat_point(slot) - SeatView.SIZE / 2.0 + seat.avatar_center()


func _side_of(slot: int) -> float:
	if slot == 0:
		return 1.0
	var p: Vector2 = _seat_point(slot)
	return 1.0 if p.x < _table_center().x - 1.0 else -1.0


func _bet_point(slot: int) -> Vector2:
	var center: Vector2 = _table_center()
	var felt: Rect2 = _felt_rect()
	if slot == 0:
		return Vector2(center.x - 14.0, felt.end.y - 34.0)
	if slot == 4 or slot == 5 or slot == 9:
		var offsets: Dictionary = {4: -60.0, 5: 60.0, 9: 0.0}
		return Vector2(center.x + offsets[slot], felt.position.y + 30.0)
	if slot == 3 or slot == 6:
		return _slot_point(slot) + Vector2(_side_of(slot) * 8.0, 38.0)
	var a: float = deg_to_rad(SLOT_ANGLES[slot])
	var p: Vector2 = center + Vector2(cos(a) * felt.size.x * 0.33, sin(a) * felt.size.y * 0.40)
	if slot == 2 or slot == 7:
		p.y += felt.size.y * 0.17
	return p


func _board_center() -> Vector2:
	return _table_center() + Vector2(0, 2)


func _banner_point(line: int = 0, lines: int = 1) -> Vector2:
	if lines <= 1:
		return _board_center() + Vector2(0, BOARD_CARD.y / 2.0 + 24.0)
	return _board_center() + Vector2(0, BOARD_CARD.y / 2.0 + 16.0 + line * BANNER_STEP)


## As pilhas do centro, como nos sites: um pote só, grande; com potes paralelos, uma
## pilha menor para cada um, lado a lado ("Principal" e "Paralelo"; com três, sem nome).
## Embaixo das cartas comunitárias, "Pote" com o total da mão, inclusive as apostas.
func _show_pots(table: Dictionary) -> void:
	var amounts: Array[int] = PotMath.center_pots(table)
	if amounts.size() > POT_VIEWS:
		var extra: int = 0
		for amount in amounts.slice(POT_VIEWS - 1):
			extra += amount
		amounts = amounts.slice(0, POT_VIEWS - 1)
		amounts.append(extra)
	_pot_amounts = amounts
	for i in POT_VIEWS:
		var pot_view: AmountView = _pot_views[i]
		pot_view.visible = i < amounts.size()
		if not pot_view.visible:
			continue
		pot_view.big = amounts.size() == 1
		# Três pilhas não cabem com nome: o principal é o da esquerda.
		pot_view.caption = "" if amounts.size() != 2 else ("Principal" if i == 0 else "Paralelo")
		pot_view.amount = amounts[i]
	var total: int = PotMath.total(table)
	_total.visible = total > 0
	_total.amount = total
	_place_pots()


func _place_pots() -> void:
	var count: int = _pot_amounts.size()
	var width: float = 0.0
	for i in count:
		width += _pot_views[i].get_combined_minimum_size().x
	width += POT_GAP * maxi(count - 1, 0)
	var x: float = _pot_point().x - width / 2.0
	for i in count:
		var w: float = _pot_views[i].get_combined_minimum_size().x
		_pot_views[i].place_at(Vector2(x + w / 2.0, _pot_point().y))
		x += w + POT_GAP
	_total.place_at(_banner_point())


func _pot_point() -> Vector2:
	return _board_center() + Vector2(0, -BOARD_CARD.y / 2.0 - 24.0)


func _my_center() -> Vector2:
	var felt: Rect2 = _felt_rect()
	return Vector2(felt.get_center().x + 46.0, felt.end.y + 12.0)


## Cartas de um adversário: fechadas, aparecem pequenas atrás do avatar; abertas
## (showdown), ficam na frente, maiores, acima do lugar (ou abaixo, nos lugares do alto).
func _place_hole(slot: int, point: Vector2) -> void:
	var pair: Array = _hole[slot]
	var open: bool = pair[0].card >= 0
	var seat: SeatView = _seats[slot]
	for k in 2:
		var card: CardView = pair[k]
		var turn: float = -1.0 if k == 0 else 1.0
		if open:
			card.size = THEIR_FACE
			card.rotation = 0.0
			var below: bool = point.y < _table_center().y - 40.0
			var y: float = point.y + 26.0 if below else point.y - 26.0 - THEIR_FACE.y
			card.position = Vector2(point.x - THEIR_FACE.x + 2.0 + k * (THEIR_FACE.x - 4.0),
				y).round()
			move_child(card, seat.get_index() + 1)
		else:
			card.size = THEIR_BACK
			card.pivot_offset = Vector2(THEIR_BACK.x / 2.0, THEIR_BACK.y)
			# Em leque, saindo de trás do avatar para o lado do centro da mesa.
			var side: float = _side_of(slot)
			card.rotation_degrees = side * (6.0 + k * 16.0)
			card.position = (point + Vector2(-THEIR_BACK.x / 2.0 + side * (8.0 + k * 7.0),
				-THEIR_BACK.y - 4.0 + k * 2.0)).round()
			if card.get_index() > seat.get_index():
				move_child(card, seat.get_index())


func _layout() -> void:
	if _felt == null:
		return
	_felt.felt_rect = _felt_rect()
	var column: Rect2 = _column()
	var bar_h: float = _bar.get_combined_minimum_size().y
	_ad.position = column.position
	_ad.size = Vector2(column.size.x, maxf(column.size.y - bar_h - AD_GAP, 50.0))
	var area: Rect2 = _table_area()
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_info.position = area.position + Vector2(MARGIN, MARGIN - 2.0)
	_info.size = Vector2(240, 20)
	var board_center: Vector2 = _board_center()
	var gap: float = 4.0
	var total: float = BOARD_CARD.x * 5.0 + gap * 4.0
	_marks.gap = gap
	_marks.position = (board_center - Vector2(total, BOARD_CARD.y) / 2.0).round()
	_marks.size = Vector2(total, BOARD_CARD.y)
	for i in 5:
		_board[i].position = (board_center + Vector2(-total / 2.0 + i * (BOARD_CARD.x + gap),
			-BOARD_CARD.y / 2.0)).round()
	_place_pots()
	for slot in SLOTS:
		var seat: SeatView = _seats[slot]
		seat.side = _side_of(slot)
		seat.position = (_seat_point(slot) - SeatView.SIZE / 2.0).round()
		if _bets[slot].visible:
			_bets[slot].place_at(_bet_point(slot))
		if slot > 0:
			_place_hole(slot, _slot_point(slot))
	var my_center: Vector2 = _my_center()
	for k in 2:
		_mine[k].position = (my_center + Vector2(-MY_CARD.x + 6.0 + k * (MY_CARD.x - 12.0),
			-MY_CARD.y / 2.0)).round()
	_place_bar()
	_place_prompt()
	_waiting.position = Vector2(column.position.x, column.end.y - BAR_H * 2.0)
	_waiting.size = Vector2(column.size.x, BAR_H * 2.0)
	_exit.size = Vector2(64, 40)
	_exit.position = (Vector2(area.position.x + MARGIN, area.end.y - MARGIN - 40.0)).round()
	_help.size = Vector2(40, 40)
	_help.position = _exit.position + Vector2(_exit.size.x + 8.0, 0)
	_history.size = Vector2(40, 40)
	_history.position = _help.position + Vector2(48.0, 0)
	_score.size = Vector2(40, 40)
	# No canto de cima à direita da mesa (onde ficava a pausa), longe da sua placa.
	_score.position = Vector2(area.end.x - MARGIN - 40.0, area.position.y + MARGIN).round()
	_react.size = Vector2(40, 40)
	_react.position = Vector2(area.end.x - MARGIN - 40.0, area.end.y - MARGIN - 40.0).round()
	var lines: int = 0
	for banner: AmountView in _banners:
		lines += 1 if banner.visible else 0
	for i in _banners.size():
		if _banners[i].visible:
			_banners[i].place_at(_banner_point(i, lines))


func _place_prompt() -> void:
	if _prompt == null:
		return
	var column: Rect2 = _column()
	_prompt.size = Vector2(column.size.x, 0)
	var height: float = _prompt.get_combined_minimum_size().y
	_prompt.size = Vector2(column.size.x, height)
	_prompt.position = Vector2(column.position.x, column.end.y - height)


## A barra cresce para cima quando os atalhos de aposta abrem.
func _place_bar() -> void:
	var column: Rect2 = _column()
	var height: float = _bar.get_combined_minimum_size().y
	_bar.size = Vector2(column.size.x, height)
	_bar.position = Vector2(column.position.x, column.end.y - height)
	var sheet_h: float = _bar.sheet.get_combined_minimum_size().y
	_bar.sheet.size = Vector2(SHEET_W, sheet_h)
	_bar.sheet.position = Vector2(column.position.x - MARGIN - SHEET_W, column.end.y - sheet_h)


# ------------------------------------------------------------------ animações


## Animações da mensagem que acabou de chegar: cartas distribuídas, cartas
## comunitárias novas, apostas indo para a frente do lugar e depois para o pote, e o
## pote indo para quem ganhou.
func _animate(events: Array, table: Dictionary, board_count: int, live: bool) -> void:
	var dealt: bool = false
	var streets: int = 0
	var ended: bool = false
	var paid: Array[int] = []
	for event: Dictionary in events:
		match String(event.get("type", "")):
			"deal":
				dealt = true
			"street":
				streets += 1
			"end":
				ended = true
			"action", "blind":
				# Passar: duas batidas na mesa. Desistir: as cartas entregues.
				match String(event.get("action", "")):
					"check":
						Sfx.play(Sfx.KNOCK)
					"fold":
						Sfx.play(Sfx.FOLD)
				var slot: int = _slot_of(int(event.get("seat", -1)))
				if int(event.get("amount", 0)) > 0 and slot >= 0 and not paid.has(slot):
					paid.append(slot)
	if live:
		_pot_fade(1.0, 0.0, 0.0)
	if dealt:
		_shown_board = 0
		_last_bets.clear()
		_last_amounts.clear()
		_deal_cards()

	var to_pot: Dictionary = {}
	if streets > 0 or ended:
		to_pot = _last_bets.duplicate()
		for slot: int in paid:
			to_pot[slot] = _bet_point(slot)
		# A parte da aposta que ninguém pagou volta para o lugar; o resto vai ao pote.
		var back: Dictionary = PotMath.refunds(events)
		for seat_index: int in back:
			var slot: int = _slot_of(seat_index)
			if slot < 0:
				continue
			var start: Vector2 = to_pot.get(slot, _bet_point(slot))
			_fly_chips(start, _slot_point(slot), 0.0, 0.3)
			if int(back[seat_index]) >= int(_last_amounts.get(slot, 0)) 					and not paid.has(slot):
				to_pot.erase(slot)
		for slot: int in to_pot:
			_fly_chips(_slot_point(slot) if not _last_bets.has(slot) else to_pot[slot],
				_pot_point(), 0.0)
		if not to_pot.is_empty():
			Sfx.play(Sfx.CHIP, 0.25, -4.0)
	else:
		for slot: int in paid:
			var bet_view: AmountView = _bets[slot]
			if bet_view.visible:
				_fly_chips(_slot_point(slot), _bet_point(slot), 0.0, 0.25)
				bet_view.modulate.a = 0.0
				create_tween().tween_property(bet_view, "modulate:a", 1.0, 0.12).set_delay(0.22)
		if not paid.is_empty():
			Sfx.play(Sfx.CHIP, 0.18)

	if board_count > _shown_board:
		var base: float = 0.3 if not to_pot.is_empty() else 0.0
		var first: int = _shown_board
		var first_group: int = 0 if first < 3 else first - 2
		for i in range(first, board_count):
			var group: int = 0 if i < 3 else i - 2
			var card: CardView = _board[i]
			var delay: float = base + (group - first_group) * 0.45
			var origin: Vector2 = card.position + card.size / 2.0 + Vector2(0, -22)
			if i < 3:
				# Flop: as três saem da primeira posição e se espalham.
				delay += (i - first) * 0.07
				origin = _board[0].position + BOARD_CARD / 2.0 + Vector2(0, -16)
			card.fly_from(origin, delay)
			Sfx.play(Sfx.CARD, delay + 0.05)
	_shown_board = board_count

	if ended:
		var delay: float = 0.5 if not to_pot.is_empty() else 0.15
		if table.get("result", {}).get("showdown", false):
			delay += 0.6
		var won: bool = false
		for payout: Dictionary in table.get("result", {}).get("payouts", []):
			var slot: int = _slot_of(int(payout.get("seat", -1)))
			if slot >= 0:
				_fly_chips(_pot_point(), _slot_point(slot), delay, 0.5)
				won = won or (_my_seat >= 0 and int(payout.get("seat", -1)) == _my_seat)
		if not table.get("result", {}).get("payouts", []).is_empty():
			Sfx.play(Sfx.CHIP, delay + 0.4)
		if won:
			Sfx.play(Sfx.WIN, delay + 0.1)
		_pot_fade(0.0, delay, 0.25)

	_last_bets.clear()
	_last_amounts.clear()
	if live:
		for slot in SLOTS:
			if _bets[slot].visible:
				_last_bets[slot] = _bet_point(slot)
				_last_amounts[slot] = _bets[slot].amount


## Distribuição: duas voltas pela mesa, uma carta por vez, saindo do centro.
func _deal_cards() -> void:
	var origin: Vector2 = _board_center()
	var order: int = 0
	for k in 2:
		for slot in SLOTS:
			var card: CardView = _mine[k] if slot == 0 else (_hole[slot][k] if slot > 0 else null)
			if card != null and card.visible:
				card.fly_from(origin, order * 0.06, 0.26)
				Sfx.play(Sfx.CARD, order * 0.06 + 0.05, -6.0)
				order += 1


func _fly_chips(from: Vector2, to: Vector2, delay: float, duration: float = 0.38) -> void:
	var flight: ChipFlight = ChipFlight.new()
	add_child(flight)
	flight.launch(from, to, delay, duration)


var _pot_tween: Tween = null


func _pot_fade(alpha: float, delay: float, duration: float) -> void:
	if _pot_tween != null:
		_pot_tween.kill()
		_pot_tween = null
	if duration <= 0.0:
		_pot.modulate.a = alpha
		return
	_pot_tween = create_tween()
	_pot_tween.tween_property(_pot, "modulate:a", alpha, duration).set_delay(delay)
