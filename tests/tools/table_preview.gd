extends Control
## Prévia provisória das direções visuais no celular: a mesa de exemplo em tamanho
## real. Um toque fora dos botões alterna entre os temas de directions.gd (hoje só um).
## --table=rubi mostra uma mesa da Loja (ui/theme/tables.gd).
## --sidepots mostra uma mão com potes paralelos (com --ended, o fim dela, ganhos por
## pessoas diferentes).
## --foldout mostra todos desistindo depois de um aumento (quem aumentou leva tudo).

const Directions := preload("res://ui/theme/directions.gd")
const Tables := preload("res://ui/theme/tables.gd")
const UiTheme := preload("res://ui/theme/ui_theme.gd")
const DemoState := preload("res://tests/tools/demo_state.gd")
const TableView := preload("res://ui/table/table_view.gd")

var _index: int = 0
var _board: int = 4
var _sidepots: bool = false
var _ended: bool = false
var _foldout: bool = false
var _table: TableView = null
var _label: Label = null


func _ready() -> void:
	_table = TableView.new()
	_table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_table.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_table)
	_label = Label.new()
	_label.theme_type_variation = "SmallLabel"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_label.offset_top = -14
	_label.offset_bottom = 0
	add_child(_label)
	var sheet: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--direction="):
			_index = int(arg.get_slice("=", 1))
		elif arg == "--sheet":
			sheet = true
		elif arg.begins_with("--table="):
			_table.table_skin = Tables.skin(arg.get_slice("=", 1))
		elif arg == "--flop":
			_board = 3
		elif arg == "--sidepots":
			_sidepots = true
		elif arg == "--ended":
			_ended = true
		elif arg == "--foldout":
			_foldout = true
	_apply()
	if sheet:
		_table.open_bet_sheet()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_index = (_index + 1) % Directions.ALL.size()
		_apply()


func _apply() -> void:
	theme = UiTheme.build(Directions.ALL[_index])
	var state: Dictionary = DemoState.make()
	state["table"]["board"] = state["table"]["board"].slice(0, _board)
	if _sidepots:
		# Duda foi all-in no flop com 200; Tião acabou de ir all-in no turn.
		var table: Dictionary = state["table"]
		var totals: Dictionary = {0: 30000, 1: 4000, 2: 20000, 3: 30000, 4: 4000, 5: 72000,
			6: 36000, 7: 4000, 8: 4000}
		var pot: int = 0
		for entry: Dictionary in table["seats"]:
			entry["total"] = totals[int(entry["seat"])]
			pot += int(entry["total"])
		table["seats"][2]["stack"] = 0
		table["seats"][2]["all_in"] = true
		table["seats"][2]["bet"] = 0
		table["pot"] = pot
		if _ended:
			table["live"] = false
			table["result"] = {"showdown": false, "payouts": [
				{"seat": 2, "amount": 116000}, {"seat": 0, "amount": 88000}],
				"pots": [{"amount": 116000, "winners": [2]}, {"amount": 40000, "winners": [0]},
				{"amount": 48000, "winners": [0]}]}
			state["you"].erase("legal")
			state["events"] = []
	_table.render(state)
	_label.text = ""
	if _foldout:
		# Todos desistem depois do aumento do Tião: ele leva tudo o que estava na mesa
		# (o motor devolve os 36.000 que ninguém pagou e paga o resto).
		for i in 3:
			await get_tree().process_frame
		var table: Dictionary = state["table"]
		var pot: int = int(table["pot"])
		for entry: Dictionary in table["seats"]:
			if int(entry["seat"]) != 5:
				entry["folded"] = true
			entry["bet"] = 0
		var back: int = 36000
		table["seats"][5]["stack"] = int(table["seats"][5]["stack"]) + pot
		table["live"] = false
		table["pot"] = 0
		table["to_act"] = -1
		table["result"] = {"showdown": false, "payouts": [{"seat": 5, "amount": pot - back}],
			"pots": [{"amount": pot - back, "winners": [5]}], "returned": [{"seat": 5, "amount": back}]}
		state["you"].erase("legal")
		state["events"] = [{"type": "action", "seat": 0, "action": "fold", "amount": 0},
			{"type": "refund", "seat": 5, "amount": back},
			{"type": "end", "pots": table["result"]["pots"], "payouts": table["result"]["payouts"]}]
		_table.render(state)
