extends SceneTree
## 移動・スクロール・影の位置の計算、入力割り当て、シーンのロードの検証。実行方法は AGENTS.md を参照。
## release ビルドで assert が消えるため、明示的な判定と exit code で結果を返す。

## 起動検証 (main_scene の --quit) ではロードされない遷移先も含めた全シーン
const SCENES: Array[String] = [
	"res://scenes/main.tscn",
]
## スクロール量と影の位置の計算を持つメインシーンのスクリプト
const MAIN_SCRIPT := preload("res://scripts/main.gd")
## 移動・落下の計算を持つ主人公のスクリプト
const HERO_SCRIPT := preload("res://scripts/hero.gd")
## 地形の定義
const STAGE_SCRIPT := preload("res://scripts/stage.gd")

## 検証が 1 件でも失敗したか。true なら exit code 1 で終わる
var failed: bool = false


func _initialize() -> void:
	_check_next_velocity()
	_check_scroll_for()
	_check_shadow_position()
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


func _check_next_velocity() -> void:
	var gravity_step: float = HERO_SCRIPT.GRAVITY * 0.25
	var right: Vector2 = HERO_SCRIPT.next_velocity(Vector2.ZERO, 1.0, false, true, 0.25)
	_check(right.x == HERO_SCRIPT.MOVE_SPEED, "移動: 右入力で右向きに移動の速さ")
	var left: Vector2 = HERO_SCRIPT.next_velocity(Vector2.ZERO, -1.0, false, true, 0.25)
	_check(left.x == -HERO_SCRIPT.MOVE_SPEED, "移動: 左入力で左向きに移動の速さ")
	var idle: Vector2 = HERO_SCRIPT.next_velocity(Vector2(100.0, 0.0), 0.0, false, true, 0.25)
	_check(idle.x == 0.0, "移動: 入力が無ければ横には止まる")
	var jump: Vector2 = HERO_SCRIPT.next_velocity(Vector2.ZERO, 0.0, true, true, 0.25)
	_check(jump.y == HERO_SCRIPT.JUMP_VELOCITY, "ジャンプ: 接地中のジャンプ入力で上向きの初速")
	var air_jump: Vector2 = HERO_SCRIPT.next_velocity(Vector2(0.0, -100.0), 0.0, true, false, 0.25)
	_check(air_jump.y == -100.0 + gravity_step, "ジャンプ: 空中ではジャンプできず重力で加速する")
	var falling: Vector2 = HERO_SCRIPT.next_velocity(Vector2.ZERO, 0.0, false, false, 0.25)
	_check(falling.y == gravity_step, "落下: 空中では重力で下向きに加速する")


func _check_scroll_for() -> void:
	var half: float = MAIN_SCRIPT.SCREEN_WIDTH / 2.0
	var max_scroll: float = STAGE_SCRIPT.WIDTH - MAIN_SCRIPT.SCREEN_WIDTH
	_check(MAIN_SCRIPT.scroll_for(100.0) == 0.0, "スクロール: ステージの左端では左へスクロールしない")
	_check(MAIN_SCRIPT.scroll_for(half + 300.0) == 300.0, "スクロール: 主人公が画面の中央に来る")
	_check(
		MAIN_SCRIPT.scroll_for(STAGE_SCRIPT.WIDTH - 10.0) == max_scroll,
		"スクロール: ステージの右端より先は映さない"
	)


func _check_shadow_position() -> void:
	var expected: Vector2 = Vector2(300.0, 200.0 + MAIN_SCRIPT.SCREEN_HEIGHT)
	_check(
		MAIN_SCRIPT.shadow_position(Vector2(300.0, 200.0)) == expected,
		"影: 同期中は主人公の上の画面 1 つ分下にいる"
	)


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
