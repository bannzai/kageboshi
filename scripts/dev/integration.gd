extends SceneTree
## キー入力 (InputMap を通る InputEventKey) でメインシーンの主人公を動かし、下の画面の影が同じ動きをする
## ことを検証する。実行方法は AGENTS.md を参照。失敗したら quit(1) で終わる。

## 検証が 1 件でも失敗したか。true なら exit code 1 で終わる
var failed: bool = false


## tree の準備が終わってから _run() を始める (シーンの追加は _initialize() の後でないとできない)
func _initialize() -> void:
	_run.call_deferred()


## 物理フレームを進めながら入力を流すため、同じ実行中に重ねて呼び出さない。
func _run() -> void:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	var hero: ColorRect = main.get_node("Hero")
	var shadow: ColorRect = main.get_node("Shadow")
	_check(main.is_on_floor(), "起動直後: 主人公が地面に立っている")
	_check_synced(hero, shadow, main.SCREEN_HEIGHT, "起動直後")

	var before_right: float = hero.position.x
	await _hold_key(KEY_RIGHT, 30)
	_check(hero.position.x > before_right, "右キー: 主人公が右へ進む")
	_check_synced(hero, shadow, main.SCREEN_HEIGHT, "右キー")

	var before_left: float = hero.position.x
	await _hold_key(KEY_A, 20)
	_check(hero.position.x < before_left, "A キー: 主人公が左へ進む")
	_check_synced(hero, shadow, main.SCREEN_HEIGHT, "A キー")

	await _hold_key(KEY_SPACE, 3)
	_check(not main.is_on_floor(), "スペースキー: 主人公がジャンプして地面から離れる")
	_check_synced(hero, shadow, main.SCREEN_HEIGHT, "ジャンプ中")

	for _i: int in range(180):
		await physics_frame
	_check(main.is_on_floor(), "ジャンプ後: 主人公が地面に戻る")
	_check_synced(hero, shadow, main.SCREEN_HEIGHT, "着地後")

	main.queue_free()
	await process_frame
	if failed:
		quit(1)
	else:
		print("integration OK")
		quit(0)


## cond が false なら label を ERROR として出し、失敗として記録する
func _check(cond: bool, label: String) -> void:
	if not cond:
		push_error("integration FAIL: " + label)
		failed = true


## 影は主人公と同じ x にいて、上の画面 1 つ分だけ下にいる
func _check_synced(hero: ColorRect, shadow: ColorRect, screen_height: float, label: String) -> void:
	_check(
		shadow.position == hero.position + Vector2(0.0, screen_height),
		"%s: 影が主人公と同じ位置 (下の画面) にいる" % label
	)


## physical_keycode のキーを physics_frames 物理フレームの間押し続けてから離す
func _hold_key(physical_keycode: Key, physics_frames: int) -> void:
	Input.parse_input_event(_key_event(physical_keycode, true))
	for _i: int in range(physics_frames):
		await physics_frame
	Input.parse_input_event(_key_event(physical_keycode, false))
	await physics_frame


## physical_keycode のキーを押した (pressed = true) / 離した (false) 入力イベント
func _key_event(physical_keycode: Key, pressed: bool) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = physical_keycode
	event.keycode = physical_keycode
	event.pressed = pressed
	return event
