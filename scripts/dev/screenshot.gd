extends SceneTree
## 実際の描画で代表画面を撮影する (headless では描画されないため、Makefile の screenshot target が
## --headless なしで起動する)。撮影した PNG は tmp/screenshot-<名前>.png に保存し、失敗したら quit(1) で終わる。
## 画面や状態を増やす時は _capture_scenes() だけを差し替える。

## 撮影するメインシーン
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## 敵の出現先の画面 (Lane)
const Combat := preload("res://scripts/combat.gd")
## 地面とゴールの位置
const Stage := preload("res://scripts/stage.gd")
## 画面 (Screen) の定義を持つ autoload の GameState のスクリプト
const GameStateScript := preload("res://scripts/game_state.gd")
## 壊れた保存データの退避先の名前を持つ autoload の SaveData のスクリプト
const SaveDataScript := preload("res://scripts/save_data.gd")
## 撮影中の保存データの置き場所。プレイヤーの保存データ (user://) を読み書きせず、毎回まっさらな状態から撮る
const SAVE_TEST_PATH: String = "res://tmp/screenshot-save.json"


## tree の準備が終わってから _run() を始める (シーンの追加は _initialize() の後でないとできない)
func _initialize() -> void:
	_run.call_deferred()


## 物理フレームを進めながら入力を流すため、同じ実行中に重ねて呼び出さない。
func _run() -> void:
	var save_data: Node = root.get_node("SaveData")
	var save_path: String = ProjectSettings.globalize_path(SAVE_TEST_PATH)
	_remove_save_files(save_path)
	save_data.load_from(save_path)
	if await _capture_scenes():
		_remove_save_files(save_path)
		quit(0)


## 撮影する画面の並び (起動直後のタイトル → プレイ開始 → 段差の手前でジャンプした瞬間 → 段差の上 →
## 右へスクロールして壁の手前 → ポーズ → 上下の画面の敵 → 上下で同時に攻撃を当てた同期ボーナス →
## 敵に触れ続けたゲームオーバー → リトライしてゴールに入ったステージクリア → クリアを保存したタイトル →
## 設定画面 → キーを待つ設定画面 → 壊れた保存データを既定値に戻したタイトル)。
## 失敗した撮影は _capture() が quit(1) 済みなので、false を受けたらそのまま抜ける。
func _capture_scenes() -> bool:
	if not await _capture_title():
		return false
	if not await _capture_terrain_and_scroll():
		return false
	if not await _capture_combat():
		return false
	return await _capture_save_and_settings()


## メインシーンを置いてタイトルを撮り、Enter キーでプレイを始めた直後を撮る
func _capture_title() -> bool:
	_add_main()
	await create_timer(0.3).timeout
	if not await _capture("tmp/screenshot-title.png"):
		return false
	await _hold_keys([KEY_ENTER], 1)
	await create_timer(0.2).timeout
	return await _capture("tmp/screenshot-main.png")


## _capture_title() でプレイを始めたメインシーンで撮る
func _capture_terrain_and_scroll() -> bool:
	var main: Node = current_scene
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
	await _hold_keys([KEY_ESCAPE], 1)
	if not await _capture("tmp/screenshot-pause.png"):
		return false
	await _hold_keys([KEY_ESCAPE], 1)
	main.queue_free()
	await process_frame
	return true


## プレイ中のまま新しいメインシーンを置く (GameState の画面は前のシーンから引き継ぐ)
func _capture_combat() -> bool:
	_add_main()
	var main: Node = current_scene
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
	await _hold_keys([KEY_ENTER], 1)
	await process_frame
	await _wait_physics_frames(2)
	var retried: Node2D = current_scene
	retried.get_node("Hero").position.x = Stage.GOAL.position.x - 50.0
	Input.parse_input_event(_key_event(KEY_RIGHT, true))
	for _i: int in range(60):
		if game_state.screen == GameStateScript.Screen.CLEAR:
			break
		await physics_frame
	Input.parse_input_event(_key_event(KEY_RIGHT, false))
	await create_timer(0.2).timeout
	return await _capture("tmp/screenshot-clear.png")


## _capture_combat() でステージクリアにしたメインシーンから、Enter キーでタイトルに戻ってクリアの保存を撮り、
## S キーで開いた設定画面 (BGM の音量を下げた後・キーを待つ間) を撮る。最後に壊れた保存データを読み直して撮る
func _capture_save_and_settings() -> bool:
	await _hold_keys([KEY_ENTER], 1)
	await process_frame
	await _wait_physics_frames(2)
	await create_timer(0.2).timeout
	if not await _capture("tmp/screenshot-title-cleared.png"):
		return false
	await _hold_keys([KEY_S], 1)
	await _hold_keys([KEY_LEFT], 1)
	await _hold_keys([KEY_LEFT], 1)
	if not await _capture("tmp/screenshot-settings.png"):
		return false
	await _hold_keys([KEY_DOWN], 1)
	await _hold_keys([KEY_DOWN], 1)
	await _hold_keys([KEY_ENTER], 1)
	if not await _capture("tmp/screenshot-settings-waiting-key.png"):
		return false
	await _hold_keys([KEY_H], 1)
	await _hold_keys([KEY_ESCAPE], 1)
	var save_data: Node = root.get_node("SaveData")
	var file: FileAccess = FileAccess.open(save_data.path, FileAccess.WRITE)
	file.store_string("{ broken")
	file.close()
	save_data.load_from(save_data.path)
	await _wait_physics_frames(2)
	if not await _capture("tmp/screenshot-title-broken-save.png"):
		return false
	current_scene.queue_free()
	await process_frame
	return true


## 保存データ path と、壊れた時の退避先を消す (撮影をまっさらな状態から始め、終わったら残さない)
func _remove_save_files(path: String) -> void:
	for file: String in [path, path + SaveDataScript.BROKEN_SUFFIX]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)


## メインシーンを置き、画面の遷移で読み込み直せるよう current_scene にする
func _add_main() -> void:
	var main: Node2D = MAIN_SCENE.instantiate()
	root.add_child(main)
	current_scene = main


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
