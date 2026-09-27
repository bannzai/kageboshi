extends "res://scripts/dev/headless_check.gd"
## 入力統合テスト (scripts/dev/integration.gd) が継承する、検証の流れを持たない共通の処理。目標の位置までキーを
## 押し続ける操作と攻撃キーの操作、メインシーンの敵の数え方と消し方、保存データのファイルの削除。
## selfcheck と共通の処理 (失敗の記録・キー入力・物理フレームの待ち) は scripts/dev/headless_check.gd に置く。

## キーを押し続けて主人公を目標の位置まで動かす時の、待つ物理フレーム数の上限。移動の速さ (320 px/秒) で
## 反転区間 (200 px) を抜けるのにかかる約 40 フレームに余裕を持たせる
const MOVE_FRAME_LIMIT: int = 180


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


## 攻撃キーを 1 物理フレームだけ押して離す
func _press_attack() -> void:
	await _hold_keys([KEY_J], 1)


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
