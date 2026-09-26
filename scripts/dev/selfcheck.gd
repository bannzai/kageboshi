extends SceneTree
## 移動・落下の計算、入力割り当て、シーンのロードの検証。実行方法は AGENTS.md を参照。
## release ビルドで assert が消えるため、明示的な判定と exit code で結果を返す。

## 起動検証 (main_scene の --quit) ではロードされない遷移先も含めた全シーン
const SCENES: Array[String] = [
	"res://scenes/main.tscn",
]
## 移動・落下の計算を持つメインシーンのスクリプト
const MAIN_SCRIPT: GDScript = preload("res://scripts/main.gd")

## 検証が 1 件でも失敗したか。true なら exit code 1 で終わる
var failed: bool = false


func _initialize() -> void:
	_check_next_x()
	_check_next_fall()
	_check_input_map()
	_check_scenes()
	if failed:
		quit(1)
	else:
		print("selfcheck OK")
		quit(0)


## cond が false なら label を ERROR として出し、失敗として記録する
func _check(cond: bool, label: String) -> void:
	if not cond:
		push_error("selfcheck FAIL: " + label)
		failed = true


func _check_next_x() -> void:
	_check(MAIN_SCRIPT.next_x(100.0, 1.0, 0.5, 1000.0) == 260.0, "横移動: 右入力で速度 × 時間だけ進む")
	_check(MAIN_SCRIPT.next_x(100.0, -1.0, 0.5, 1000.0) == 0.0, "横移動: 左端より左へは行かない")
	_check(MAIN_SCRIPT.next_x(990.0, 1.0, 0.5, 1000.0) == 1000.0, "横移動: 右端より右へは行かない")
	_check(MAIN_SCRIPT.next_x(100.0, 0.0, 0.5, 1000.0) == 100.0, "横移動: 入力が無ければ止まる")


func _check_next_fall() -> void:
	var resting: Vector2 = MAIN_SCRIPT.next_fall(256.0, 0.0, 0.25, 256.0)
	_check(resting == Vector2(256.0, 0.0), "落下: 地面に立っていれば地面に留まり、速度は 0")
	var rising: Vector2 = MAIN_SCRIPT.next_fall(256.0, MAIN_SCRIPT.JUMP_VELOCITY, 0.125, 256.0)
	_check(rising.x < 256.0, "落下: ジャンプの初速で上へ進む")
	_check(rising.y > MAIN_SCRIPT.JUMP_VELOCITY, "落下: 重力で上向きの速度が減る")
	var landing: Vector2 = MAIN_SCRIPT.next_fall(250.0, 400.0, 0.25, 256.0)
	_check(landing == Vector2(256.0, 0.0), "落下: 地面を越える時は地面で止まり、速度は 0")


func _check_input_map() -> void:
	for action: String in ["move_left", "move_right", "jump"]:
		_check(InputMap.has_action(action), "InputMap: %s アクションがある" % action)
		var has_key: bool = false
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey:
				has_key = true
		_check(has_key, "InputMap: %s にキーが割り当てられている" % action)


## tree には入れず (_ready を走らせず) インスタンス化だけを確認して free する
func _check_scenes() -> void:
	for path: String in SCENES:
		var scene: PackedScene = load(path)
		_check(scene != null, "シーン: %s をロードできる" % path)
		if scene == null:
			continue
		var instance: Node = scene.instantiate()
		_check(instance != null, "シーン: %s をインスタンス化できる" % path)
		if instance != null:
			instance.free()
