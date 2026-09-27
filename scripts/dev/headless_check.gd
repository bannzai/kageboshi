extends "res://scripts/dev/game_driver.gd"
## headless で実行する検証 (scripts/dev/selfcheck.gd と scripts/dev/integration.gd) が継承する土台。
## 検証の失敗の記録と、GameState の体力の比べ方、失敗を記録しながら行う操作 (目標の位置までキーを押し続ける・
## 攻撃キーを押す・出現済みの敵を消す) を持つ (キー入力の送り方と敵の集め方は scripts/dev/game_driver.gd)。

## 体力を持つ体を表す画面 (上の画面は主人公、下の画面は影)
const Combat := preload("res://scripts/combat.gd")
## キーを押し続けて主人公を目標の位置まで動かす時の、待つ物理フレーム数の上限。移動の速さ (320 px/秒) で
## 反転区間 (200 px) を抜けるのにかかる約 40 フレームに余裕を持たせる
const MOVE_FRAME_LIMIT: int = 180

## 検証が 1 件でも失敗したか。true なら exit code 1 で終わる
var failed: bool = false


## cond が false なら label を ERROR として出し、失敗として記録する。
## ERROR の行頭には実行した検証のスクリプトの名前 (selfcheck / integration) を付ける
func _check(cond: bool, label: String) -> void:
	if not cond:
		push_error("%s FAIL: %s" % [get_script().resource_path.get_file().get_basename(), label])
		failed = true


## game_state (GameState のインスタンス) の主人公の体力が hero_hp、影の体力が shadow_hp か
func _hp_is(game_state: Node, hero_hp: int, shadow_hp: int) -> bool:
	return (
		game_state.hp[Combat.Lane.TOP] == hero_hp and game_state.hp[Combat.Lane.BOTTOM] == shadow_hp
	)


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


## 出現済みの敵をすべて消す (光源の検証で、位置を移した主人公・影に敵が触れないようにする)
func _clear_enemies(main: Node2D) -> void:
	for enemy: Node in _enemies(main):
		enemy.queue_free()
