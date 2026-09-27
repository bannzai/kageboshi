extends SceneTree
## 入力統合テスト (scripts/dev/integration.gd) が継承する、検証の流れを持たない共通の処理。失敗の記録、キー入力と
## 物理フレームの待ち、メインシーンの敵の数え方と消し方、保存データのファイルの削除。

## キーを押し続けて主人公を目標の位置まで動かす時の、待つ物理フレーム数の上限。移動の速さ (320 px/秒) で
## 反転区間 (200 px) を抜けるのにかかる約 40 フレームに余裕を持たせる
const MOVE_FRAME_LIMIT: int = 180

## 検証が 1 件でも失敗したか。true なら exit code 1 で終わる
var failed: bool = false


## cond が false なら label を ERROR として出し、失敗として記録する
func _check(cond: bool, label: String) -> void:
	if not cond:
		push_error("integration FAIL: " + label)
		failed = true


## physics_frames 物理フレームだけ待つ
func _wait_physics_frames(physics_frames: int) -> void:
	for _i: int in range(physics_frames):
		await physics_frame


## physical_keycodes (Key の配列) のキーを同時に押し、physics_frames 物理フレームの間押し続けてから離す。
## while_held を渡すと、離す直前 (押している間の状態) に呼ぶ
func _hold_keys(
	physical_keycodes: Array, physics_frames: int, while_held: Callable = Callable()
) -> void:
	for keycode: Key in physical_keycodes:
		Input.parse_input_event(_key_event(keycode, true))
	await _wait_physics_frames(physics_frames)
	if while_held.is_valid():
		while_held.call()
	for keycode: Key in physical_keycodes:
		Input.parse_input_event(_key_event(keycode, false))
	await physics_frame


## physical_keycode のキーを reached が true を返すまで押し続けてから離す。MOVE_FRAME_LIMIT フレーム経っても
## true にならなければ失敗として記録する
func _hold_key_until(physical_keycode: Key, reached: Callable) -> void:
	Input.parse_input_event(_key_event(physical_keycode, true))
	var frames_left: int = MOVE_FRAME_LIMIT
	while not reached.call() and frames_left > 0:
		await physics_frame
		frames_left -= 1
	Input.parse_input_event(_key_event(physical_keycode, false))
	await physics_frame
	_check(frames_left > 0, "移動: %d フレーム以内に目標の位置へ着く" % MOVE_FRAME_LIMIT)


## physical_keycodes (Key の配列) のキーを押す (pressed = true) / 離す (false)
func _press_keys(physical_keycodes: Array, pressed: bool) -> void:
	for keycode: Key in physical_keycodes:
		Input.parse_input_event(_key_event(keycode, pressed))


## 攻撃キーを 1 物理フレームだけ押して離す
func _press_attack() -> void:
	await _hold_keys([KEY_J], 1)


## physical_keycode のキーを押した (pressed = true) / 離した (false) 入力イベント
func _key_event(physical_keycode: Key, pressed: bool) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = physical_keycode
	event.keycode = physical_keycode
	event.pressed = pressed
	return event


## 上の画面と下の画面の敵
func _enemies(main: Node2D) -> Array[Node]:
	var enemies: Array[Node] = main.get_node("Enemies").get_children()
	enemies.append_array(main.get_node("BottomLane/Enemies").get_children())
	return enemies


## 倒れて消える途中のものを除いた敵の数
func _living_enemy_count(main: Node2D) -> int:
	var count: int = 0
	for enemy: Node in _enemies(main):
		if not enemy.is_queued_for_deletion():
			count += 1
	return count


## 出現済みの敵をすべて消す (光源の検証で、位置を移した主人公・影に敵が触れないようにする)
func _clear_enemies(main: Node2D) -> void:
	for enemy: Node in _enemies(main):
		enemy.queue_free()


## path のファイルがあれば消す
func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
