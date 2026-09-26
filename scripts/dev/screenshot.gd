extends SceneTree
## 実際の描画で代表画面を撮影する (headless では描画されないため、Makefile の screenshot target が
## --headless なしで起動する)。撮影した PNG は tmp/screenshot-<名前>.png に保存し、失敗したら quit(1) で終わる。
## 画面や状態を増やす時は _capture_scenes() だけを差し替える。

## 撮影するメインシーン
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## 敵の出現先の画面 (Lane)
const Combat := preload("res://scripts/combat.gd")
## 地面と光源の位置
const Stage := preload("res://scripts/stage.gd")
## 主人公のスクリプト (体の大きさ)
const Hero := preload("res://scripts/hero.gd")


## tree の準備が終わってから _run() を始める (シーンの追加は _initialize() の後でないとできない)
func _initialize() -> void:
	_run.call_deferred()


## 物理フレームを進めながら入力を流すため、同じ実行中に重ねて呼び出さない。
func _run() -> void:
	if await _capture_scenes():
		quit(0)


## 撮影する画面の並び (起動直後 → 段差の手前でジャンプした瞬間 → 段差の上 → 右へスクロールして壁の手前 →
## 上下の画面の敵 → 上下で同時に攻撃を当てた同期ボーナス → 敵に触れ続けたゲームオーバー →
## 光源の手前で見える反転区間の予兆 → 高い光源の反転区間で逆へ動いて縮んだ影の攻撃 → 低い光源の反転区間で伸びた影の攻撃)。
## 失敗した撮影は _capture() が quit(1) 済みなので、false を受けたらそのまま抜ける。
func _capture_scenes() -> bool:
	if not await _capture_terrain_and_scroll():
		return false
	if not await _capture_combat():
		return false
	return await _capture_lights()


func _capture_terrain_and_scroll() -> bool:
	var main: Node2D = MAIN_SCENE.instantiate()
	root.add_child(main)
	await create_timer(0.3).timeout
	if not await _capture("tmp/screenshot-main.png"):
		return false
	await _hold_keys([KEY_RIGHT], 70)
	Input.parse_input_event(_key_event(KEY_RIGHT, true))
	Input.parse_input_event(_key_event(KEY_SPACE, true))
	await _wait_physics_frames(12)
	if not await _capture("tmp/screenshot-jump.png"):
		return false
	await _wait_physics_frames(8)
	Input.parse_input_event(_key_event(KEY_SPACE, false))
	Input.parse_input_event(_key_event(KEY_RIGHT, false))
	await _wait_physics_frames(60)
	if not await _capture("tmp/screenshot-step.png"):
		return false
	await _hold_keys([KEY_RIGHT], 200)
	if not await _capture("tmp/screenshot-scroll.png"):
		return false
	main.queue_free()
	await process_frame
	return true


func _capture_combat() -> bool:
	var main: Node2D = MAIN_SCENE.instantiate()
	root.add_child(main)
	await create_timer(0.3).timeout
	var front_x: float = main.get_node("Hero").position.x + 90.0
	main.spawn_enemy(Combat.Lane.TOP, front_x, Stage.GROUND_Y, 0.0)
	main.spawn_enemy(Combat.Lane.BOTTOM, front_x, Stage.GROUND_Y, 0.0)
	if not await _capture("tmp/screenshot-enemies.png"):
		return false
	await _hold_keys([KEY_RIGHT], 7)
	await _hold_keys([KEY_J], 1)
	if not await _capture("tmp/screenshot-sync.png"):
		return false
	await create_timer(1.0).timeout
	var game_state: Node = root.get_node("GameState")
	main.spawn_enemy(Combat.Lane.BOTTOM, main.get_node("Hero").position.x, Stage.GROUND_Y, 0.0)
	for _i: int in range(600):
		if game_state.is_game_over():
			break
		await physics_frame
	await create_timer(0.2).timeout
	if not await _capture("tmp/screenshot-gameover.png"):
		return false
	main.queue_free()
	await process_frame
	return true


func _capture_lights() -> bool:
	var main: Node2D = MAIN_SCENE.instantiate()
	root.add_child(main)
	await create_timer(0.3).timeout
	var high: Dictionary = Stage.LIGHTS[0]
	await _place_hero(main, high["x"] - 130.0)
	if not await _capture("tmp/screenshot-light-omen.png"):
		return false
	await _hold_keys([KEY_RIGHT], 47)
	await _hold_keys([KEY_J], 1)
	if not await _capture("tmp/screenshot-light-reverse.png"):
		return false
	var low: Dictionary = Stage.LIGHTS[1]
	await _place_hero(main, low["x"] + low["zone"] / 2.0)
	await _hold_keys([KEY_J], 1)
	if not await _capture("tmp/screenshot-light-long.png"):
		return false
	main.queue_free()
	await process_frame
	return true


## 主人公の体の中心を center_x に置いて地面に立たせ、出現済みの敵を消す (敵に触れて半透明になった姿を撮らない)
func _place_hero(main: Node2D, center_x: float) -> void:
	var hero: Hero = main.get_node("Hero")
	hero.position = Vector2(center_x - Hero.SIZE.x / 2.0, Stage.GROUND_Y - Hero.SIZE.y)
	hero.velocity = Vector2.ZERO
	await _wait_physics_frames(3)
	for enemy: Node in main.get_node("Enemies").get_children():
		enemy.queue_free()
	await _wait_physics_frames(1)


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


## physics_frames 物理フレームだけ待つ
func _wait_physics_frames(physics_frames: int) -> void:
	for _i: int in range(physics_frames):
		await physics_frame


## physical_keycodes (Key の配列) のキーを同時に押し、physics_frames 物理フレームの間押し続けてから離す
func _hold_keys(physical_keycodes: Array, physics_frames: int) -> void:
	for keycode: Key in physical_keycodes:
		Input.parse_input_event(_key_event(keycode, true))
	await _wait_physics_frames(physics_frames)
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
