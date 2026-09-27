extends SceneTree
## キー入力 (InputMap を通る InputEventKey) でメインシーンを動かす開発用スクリプト (scripts/dev/ の screenshot.gd・
## playtest.gd と、headless_check.gd を継承する selfcheck.gd・integration.gd) が共通で使う、キーの押し方・物理フレームの
## 待ち方・ゴールまで進む入力の経路・メインシーンの敵の集め方・撮影・保存データのファイルの削除。
## 各スクリプトは _initialize() から自分の検証・撮影を始める。

## ゴールまで進む入力の経路 (_walk_to_goal()) で、1 物理フレームにどう動くか
enum RouteStep {
	HOP,  ## 右キーを押し続け、地面にいる間はジャンプキーを押し直す (段差・壁を越えてゴールまで進む)
	WALK,  ## 右キーを押し続け、地面で地形に行く手を阻まれた時だけ跳ぶ (前の敵へ地面の高さのまま近づく)
	HOLD,  ## 右キーを離して止まる (呼び出し側が攻撃などの入力をする)
}

## 最後のメインシーンを消してから (または音を止めてから) 終了するまで待つ時間 (秒)。消したシーンが鳴らしていた
## BGM・効果音の再生は AudioServer がミキシングを数回進めてから解放するため、headless (1 フレームがほぼ 0 秒で進む) で
## 待たずに終了すると再生がリークとして WARNING / ERROR に出る (CI で実測)。ミキシング数回分に余裕を持たせた値
const AUDIO_RELEASE_TIME: float = 0.25


## main の主人公を右へ進め、プレイ中でなくなる (ゴールに着いたステージクリア・ゲームオーバー) か frame_limit 物理
## フレームが過ぎるまで待つ。物理フレームごとに plan を main を引数に呼び、返った RouteStep で動き方を決める
## (plan は await してよい)。make integration の到達の検証と make playtest のテストプレイが同じ経路で進む
func _walk_to_goal(main: Node2D, game_state: Node, frame_limit: int, plan: Callable) -> void:
	var hero: CharacterBody2D = main.get_node("Hero")
	var frames_left: int = frame_limit
	var right_held: bool = false
	while game_state.is_playing() and frames_left > 0:
		var step: RouteStep = await plan.call(main)
		var move: bool = step != RouteStep.HOLD
		if move != right_held:
			right_held = move
			Input.parse_input_event(_key_event(KEY_RIGHT, move))
		var jump: bool = (
			hero.is_on_floor()
			and (step == RouteStep.HOP or (step == RouteStep.WALK and hero.is_on_wall()))
		)
		if jump:
			await _hold_keys([KEY_SPACE], 1)
			frames_left -= 2
		else:
			await physics_frame
			frames_left -= 1
	if right_held:
		Input.parse_input_event(_key_event(KEY_RIGHT, false))
	await physics_frame


## 上の画面と下の画面の敵 (倒れて消える途中のものを含む)
func _enemies(main: Node2D) -> Array[Node]:
	var enemies: Array[Node] = main.get_node("Enemies").get_children()
	enemies.append_array(main.get_node("BottomLane/Enemies").get_children())
	return enemies


## 倒れて消える途中のものを除いた敵
func _living_enemies(main: Node2D) -> Array[Node]:
	var living: Array[Node] = []
	for enemy: Node in _enemies(main):
		if not enemy.is_queued_for_deletion():
			living.append(enemy)
	return living


## 描画が反映されるまで 2 フレーム待ってから viewport を path に PNG で保存する。失敗したら quit(1) する
func _capture(path: String) -> bool:
	await process_frame
	await process_frame
	var status: Error = root.get_viewport().get_texture().get_image().save_png(path)
	if status != OK:
		push_error("スクリーンショット保存失敗: %s (%s)" % [path, error_string(status)])
		quit(1)
		return false
	print("screenshot: " + path)
	return true


## physical_keycodes (Key の配列) のキーを押す (pressed = true) / 離す (false)
func _press_keys(physical_keycodes: Array, pressed: bool) -> void:
	for keycode: Key in physical_keycodes:
		Input.parse_input_event(_key_event(keycode, pressed))


## physics_frames 物理フレームだけ待つ
func _wait_physics_frames(physics_frames: int) -> void:
	for _i: int in range(physics_frames):
		await physics_frame


## physical_keycodes (Key の配列) のキーを同時に押し、physics_frames 物理フレームの間押し続けてから離す。
## while_held を渡すと、離す直前 (押している間の状態) に呼ぶ
func _hold_keys(
	physical_keycodes: Array, physics_frames: int, while_held: Callable = Callable()
) -> void:
	_press_keys(physical_keycodes, true)
	await _wait_physics_frames(physics_frames)
	if while_held.is_valid():
		while_held.call()
	_press_keys(physical_keycodes, false)
	await physics_frame


## physical_keycode のキーを押した (pressed = true) / 離した (false) 入力イベント
func _key_event(physical_keycode: Key, pressed: bool) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = physical_keycode
	event.keycode = physical_keycode
	event.pressed = pressed
	return event


## path のファイルがあれば消す
func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
