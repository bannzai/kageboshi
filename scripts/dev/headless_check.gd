extends SceneTree
## headless で実行する検証 (scripts/dev/selfcheck.gd と scripts/dev/integration.gd) が継承する土台。
## 検証の失敗の記録と、キー入力 (InputMap を通る InputEventKey) の送り方、GameState の体力の比べ方を持つ。

## 体力を持つ体を表す画面 (上の画面は主人公、下の画面は影)
const Combat := preload("res://scripts/combat.gd")

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


## physics_frames 物理フレームだけ待つ
func _wait_physics_frames(physics_frames: int) -> void:
	for _i: int in range(physics_frames):
		await physics_frame


## physical_keycodes (Key の配列) のキーを押す (pressed = true) / 離す (false)
func _press_keys(physical_keycodes: Array, pressed: bool) -> void:
	for keycode: Key in physical_keycodes:
		Input.parse_input_event(_key_event(keycode, pressed))


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


## physical_keycode のキーを押した (pressed = true) / 離した (false) 入力イベント
func _key_event(physical_keycode: Key, pressed: bool) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = physical_keycode
	event.keycode = physical_keycode
	event.pressed = pressed
	return event
