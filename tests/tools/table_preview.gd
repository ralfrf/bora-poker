extends Control
## Prévia provisória das direções visuais no celular: a mesa de exemplo em tamanho
## real. Um toque fora dos botões alterna entre os temas de directions.gd (hoje só um).
## --table=rubi mostra uma mesa da Loja (ui/theme/tables.gd).
## --sidepots mostra o fim de uma mão com potes paralelos ganhos por pessoas diferentes.

const Directions := preload("res://ui/theme/directions.gd")
const Tables := preload("res://ui/theme/tables.gd")
const UiTheme := preload("res://ui/theme/ui_theme.gd")
const DemoState := preload("res://tests/tools/demo_state.gd")
const TableView := preload("res://ui/table/table_view.gd")

var _index: int = 0
var _board: int = 4
var _sidepots: bool = false
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
		var table: Dictionary = state["table"]
		table["live"] = false
		table["result"] = {"showdown": false, "payouts": [
			{"seat": 2, "amount": 54000}, {"seat": 0, "amount": 70000},
			{"seat": 6, "amount": 12000}],
			"pots": [{"amount": 70000, "winners": [0]}, {"amount": 54000, "winners": [2]},
			{"amount": 12000, "winners": [6]}]}
		state["you"].erase("legal")
		state["events"] = []
	_table.render(state)
	_label.text = ""
