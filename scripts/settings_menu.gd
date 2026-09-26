extends ColorRect
## 設定画面 (GameState の画面が SETTINGS の間だけ表示する)。BGM・効果音の音量と、ゲームの各アクションのキー割り当てを
## 変え、変えるたびに SaveData が保存する。この画面の操作は Godot 組み込みの ui_* アクション (矢印キー・Enter・Esc) で
## 受け、キー割り当てをどう変えてもこの画面を操作できるようにする。

## 行の種類。音量 (左右キーで変える)、キー割り当て (Enter の後に押したキーにする)、キー割り当てを既定に戻す
enum RowKind { VOLUME, KEY, RESET_KEYS }

## autoload の SaveData / GameState のスクリプト (autoload 名の識別子で参照しない理由は main.gd の GameStateScript)
const SaveDataScript := preload("res://scripts/save_data.gd")
const GameStateScript := preload("res://scripts/game_state.gd")
## 選んでいる行の文字色
const SELECTED_COLOR: Color = Color(1.0, 0.82, 0.25, 1.0)
## 選んでいない行の文字色
const NORMAL_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
## 行の文字の大きさ
const FONT_SIZE: int = 22
## 行の名前の列の幅 (px)
const NAME_WIDTH: float = 360.0
## キーを待っている行に出す文字
const WAITING_TEXT: String = "Press a key..."

## 上から並べた行 ({"kind": RowKind, "id": バス名かアクション名, "name": 名前の Label, "value": 値の Label})
var rows: Array[Dictionary] = []
## 選んでいる行 (rows の添字)。開くたびに先頭 (BGM の音量) に戻す
var selected: int = 0
## 次に押したキーを割り当てるアクション。空ならキーを待っていない
var waiting_action: String = ""

## 音量と保存 (autoload の SaveData)
@onready var save_data: SaveDataScript = get_node("/root/SaveData")
## 表示している画面 (autoload の GameState)
@onready var game_state: GameStateScript = get_node("/root/GameState")
## 行を並べる入れ物
@onready var row_box: VBoxContainer = $Rows


func _ready() -> void:
	for bus: String in SaveDataScript.VOLUME_BUSES:
		_add_row(RowKind.VOLUME, bus, "%s Volume" % bus)
	for action: String in SaveDataScript.rebindable_actions():
		_add_row(RowKind.KEY, action, action.capitalize())
	_add_row(RowKind.RESET_KEYS, "", "Reset Keys")
	visibility_changed.connect(_on_visibility_changed)
	refresh()


## 設定画面の操作。キーを待っている間は、押したキーをそのまま割り当てる (Esc や Enter も割り当てられる)
func _input(event: InputEvent) -> void:
	if game_state.screen != GameStateScript.Screen.SETTINGS:
		return
	if waiting_action != "":
		var keycode: int = SaveDataScript.pressed_key_code(event)
		if keycode == 0:
			return
		save_data.rebind(waiting_action, keycode)
		waiting_action = ""
	elif event.is_action_pressed("ui_cancel"):
		game_state.send(GameStateScript.Command.BACK)
	elif event.is_action_pressed("ui_up", true):
		selected = wrapi(selected - 1, 0, rows.size())
	elif event.is_action_pressed("ui_down", true):
		selected = wrapi(selected + 1, 0, rows.size())
	elif event.is_action_pressed("ui_left", true):
		_step_volume(-1)
	elif event.is_action_pressed("ui_right", true):
		_step_volume(1)
	elif event.is_action_pressed("ui_accept"):
		_accept()
	else:
		return
	get_viewport().set_input_as_handled()
	refresh()


## 各行の値と、選んでいる行の色を今の設定に合わせる
func refresh() -> void:
	for i: int in range(rows.size()):
		var row: Dictionary = rows[i]
		var color: Color = SELECTED_COLOR if i == selected else NORMAL_COLOR
		row["name"].add_theme_color_override("font_color", color)
		row["value"].add_theme_color_override("font_color", color)
		row["value"].text = _value_text(row)


## 開くたびに先頭の行から始め、キーを待っていない状態にする (保存データの読み直しで設定が変わっていてもよいよう表示も直す)
func _on_visibility_changed() -> void:
	selected = 0
	waiting_action = ""
	refresh()


## 選んでいる行が音量なら、direction (-1 / 1) の向きに 1 刻み (1 / SaveData.VOLUME_STEPS) だけ変える
func _step_volume(direction: int) -> void:
	var row: Dictionary = rows[selected]
	if row["kind"] != RowKind.VOLUME:
		return
	var bus: String = row["id"]
	var step: float = float(direction) / SaveDataScript.VOLUME_STEPS
	save_data.set_volume(bus, save_data.volumes[bus] + step)


## 選んでいる行がキー割り当てならキーを待ち始め、既定に戻す行なら戻す
func _accept() -> void:
	var row: Dictionary = rows[selected]
	match row["kind"]:
		RowKind.KEY:
			waiting_action = row["id"]
		RowKind.RESET_KEYS:
			save_data.reset_keys()


func _value_text(row: Dictionary) -> String:
	match row["kind"]:
		RowKind.VOLUME:
			return "<  %d%%  >" % roundi(save_data.volumes[row["id"]] * 100.0)
		RowKind.KEY:
			if row["id"] == waiting_action:
				return WAITING_TEXT
			return SaveDataScript.key_names(row["id"])
	return ""


func _add_row(kind: RowKind, id: String, title: String) -> void:
	var line: HBoxContainer = HBoxContainer.new()
	var name_label: Label = _row_label(title)
	name_label.custom_minimum_size.x = NAME_WIDTH
	var value_label: Label = _row_label("")
	line.add_child(name_label)
	line.add_child(value_label)
	row_box.add_child(line)
	rows.append({"kind": kind, "id": id, "name": name_label, "value": value_label})


func _row_label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	return label
