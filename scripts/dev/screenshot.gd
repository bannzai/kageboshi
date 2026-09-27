extends SceneTree
## 実際の描画で代表画面を撮影する (headless では描画されないため、Makefile の screenshot target が
## --headless なしで起動する)。撮影した PNG は tmp/screenshot-<名前>.png に保存し、失敗したら quit(1) で終わる。
## 画面や状態を増やす時は _capture_scenes() だけを差し替える。

## 撮影するメインシーン
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## 敵の出現先の画面 (Lane)
const Combat := preload("res://scripts/combat.gd")
## 地面の位置
const Stage := preload("res://scripts/stage.gd")
## 主人公のスクリプト (体の大きさ)
const Hero := preload("res://scripts/hero.gd")
## 画面 (Screen) の定義を持つ autoload の GameState のスクリプト
const GameStateScript := preload("res://scripts/game_state.gd")
## 壊れた保存データの退避先の名前を持つ autoload の SaveData のスクリプト
const SaveDataScript := preload("res://scripts/save_data.gd")
## 撮影中の保存データの置き場所。プレイヤーの保存データ (user://) を読み書きせず、毎回まっさらな状態から撮る
const SAVE_TEST_PATH: String = "res://tmp/screenshot-save.json"
## 前の攻撃のクールダウンが終わるのを待つ物理フレーム数の上限。攻撃の間隔 (0.3 秒 = 18 フレーム) に余裕を持たせ、
## プレイ中でない画面でクールダウンが進まない時に撮影が止まらないようにする
const COOLDOWN_FRAME_LIMIT: int = 60
## 最後のメインシーンを消してから終了するまで待つ時間 (秒)。理由と値の根拠は scripts/dev/integration.gd の
## AUDIO_RELEASE_TIME と同じ (消したシーンが鳴らしていた音の再生を AudioServer が解放するまで待つ)
const AUDIO_RELEASE_TIME: float = 0.25


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
		await create_timer(AUDIO_RELEASE_TIME).timeout
		quit(0)


## 撮影する画面の並び (起動直後のタイトル → プレイ開始 → 段差の手前でジャンプした瞬間 → 段差の上 →
## 右へスクロールして壁の手前 → ポーズ → 左へ歩く姿 → 右へ歩く姿 → 上下の画面の敵 → 上下で同時に攻撃を当てた同期ボーナス →
## 敵に触れ続けたゲームオーバー → リトライした昼のステージで光源の手前で見える反転区間の予兆 →
## 高い光源の反転区間で逆へ動いて縮んだ影の攻撃 → 影を縫い止めて主人公だけが進んだ影縫い → 引き寄せの途中 →
## 主人公を止めて影だけが進んだ逆の影縫い → ゴールに入ったステージクリア → 夕方のステージの開始 →
## 低い光源の反転区間で伸びた影の攻撃 → 夜のステージで点在する光源 → 最後のステージのクリア →
## クリアを保存したタイトル → 設定画面 → キーを待つ設定画面 → 壊れた保存データを既定値に戻したタイトル)。
## 失敗した撮影は _capture() が quit(1) 済みなので、false を受けたらそのまま抜ける。
func _capture_scenes() -> bool:
	var captures: Array[Callable] = [
		_capture_title,
		_capture_terrain_and_scroll,
		_capture_combat,
		_capture_day,
		_capture_evening,
		_capture_night,
		_capture_save_and_settings,
	]
	for capture: Callable in captures:
		if not await capture.call():
			return false
	return true


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
	if not await _capture_walks():
		return false
	main.queue_free()
	await process_frame
	return true


## 壁の手前の段から左へ歩いている途中と、そこから右へ歩いている途中 (段に着く前) を撮る
func _capture_walks() -> bool:
	if not await _capture_walk(KEY_LEFT, 16, "tmp/screenshot-walk-left.png"):
		return false
	return await _capture_walk(KEY_RIGHT, 10, "tmp/screenshot-walk-right.png")


## physical_keycode の向きへ physics_frames 物理フレーム歩かせ、歩いている途中の主人公と影 (歩きの姿と向き) を
## path へ撮影してからキーを離す
func _capture_walk(physical_keycode: Key, physics_frames: int, path: String) -> bool:
	Input.parse_input_event(_key_event(physical_keycode, true))
	await _wait_physics_frames(physics_frames)
	var captured: bool = await _capture(path)
	Input.parse_input_event(_key_event(physical_keycode, false))
	await physics_frame
	return captured


## プレイ中のまま新しいメインシーンを置き (GameState の画面は前のシーンから引き継ぐ)、敵・同期ボーナス・
## ゲームオーバーを撮ってから Enter キーでリトライする
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
	await _next_scene()
	return true


## リトライした昼のステージで光源の予兆・高い光源の反転区間で縮んだ影の攻撃・影縫いを撮り、引き寄せで同期に
## 戻してから、ゴールに入ったステージクリアを撮る
func _capture_day() -> bool:
	var main: Node2D = current_scene
	var high: Dictionary = main.stage.lights[0]
	await _place_hero(main, high["x"] - 130.0)
	if not await _capture("tmp/screenshot-light-omen.png"):
		return false
	await _hold_keys([KEY_RIGHT], 47)
	if not await _capture_attack(main, "tmp/screenshot-light-reverse.png"):
		return false
	if not await _capture_stitch(main):
		return false
	await _hold_keys([KEY_I], 1)
	await _wait_physics_frames(40)
	return await _capture_clear(main, "tmp/screenshot-clear.png")


## ステージクリアから Enter キーで進んだ夕方のステージの開始と、低い光源の反転区間で伸びた影の攻撃を撮り、
## ゴールまで進める
func _capture_evening() -> bool:
	var main: Node2D = await _next_scene()
	await create_timer(0.2).timeout
	if not await _capture("tmp/screenshot-stage-evening.png"):
		return false
	var low: Dictionary = main.stage.lights[0]
	await _place_hero(main, low["x"] + low["zone"] / 2.0)
	if not await _capture_attack(main, "tmp/screenshot-light-long.png"):
		return false
	return await _reach_goal(main)


## ステージクリアから Enter キーで進んだ夜のステージで、点在する光源が 2 本見える位置を撮り、最後のステージの
## クリアを撮る
func _capture_night() -> bool:
	var main: Node2D = await _next_scene()
	var second: Dictionary = main.stage.lights[1]
	await _place_hero(main, second["x"] - 130.0)
	if not await _capture("tmp/screenshot-stage-night.png"):
		return false
	return await _capture_clear(main, "tmp/screenshot-clear-last.png")


## main の主人公をゴールの手前に置いて右キーでゴールに入れ、ステージクリアを path へ撮影する
func _capture_clear(main: Node2D, path: String) -> bool:
	if not await _reach_goal(main):
		return false
	await create_timer(0.2).timeout
	return await _capture(path)


## main の主人公をゴールの手前に置き、ステージクリアになるまで右キーを押す。ならなければ quit(1) する。
## 置いた直後に出現する敵に触れて半透明になった姿を撮らないよう、ゴールの近くの敵から離れた位置に置く
func _reach_goal(main: Node2D) -> bool:
	var game_state: Node = root.get_node("GameState")
	await _place_hero(main, main.stage.goal().position.x - 150.0)
	Input.parse_input_event(_key_event(KEY_RIGHT, true))
	for _i: int in range(60):
		if game_state.screen == GameStateScript.Screen.CLEAR:
			break
		await physics_frame
	Input.parse_input_event(_key_event(KEY_RIGHT, false))
	await physics_frame
	if game_state.screen != GameStateScript.Screen.CLEAR:
		push_error("ゴールに入ってもステージクリアにならない: %s" % main.stage.title)
		quit(1)
		return false
	return true


## Enter キーで画面を移し、読み込み直されたメインシーンを返す
func _next_scene() -> Node2D:
	await _hold_keys([KEY_ENTER], 1)
	await process_frame
	await _wait_physics_frames(2)
	return current_scene


## _capture_night() で最後のステージをクリアしたメインシーンから、Enter キーでタイトルに戻ってクリアの保存を撮り、
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


## 主人公を光源の反転区間の外 (ステージの左の平らな所) に置き、影縫い・引き寄せの途中・逆の影縫いを撮る
func _capture_stitch(main: Node2D) -> bool:
	await _place_hero(main, 220.0)
	await _wait_physics_frames(20)
	Input.parse_input_event(_key_event(KEY_K, true))
	Input.parse_input_event(_key_event(KEY_RIGHT, true))
	await _wait_physics_frames(40)
	if not await _capture("tmp/screenshot-stitch.png"):
		return false
	Input.parse_input_event(_key_event(KEY_RIGHT, false))
	Input.parse_input_event(_key_event(KEY_K, false))
	await _hold_keys([KEY_I], 1)
	await _wait_physics_frames(5)
	if not await _capture("tmp/screenshot-pull.png"):
		return false
	await _wait_physics_frames(40)
	Input.parse_input_event(_key_event(KEY_L, true))
	Input.parse_input_event(_key_event(KEY_RIGHT, true))
	await _wait_physics_frames(40)
	if not await _capture("tmp/screenshot-stitch-hero.png"):
		return false
	Input.parse_input_event(_key_event(KEY_RIGHT, false))
	Input.parse_input_event(_key_event(KEY_L, false))
	await _wait_physics_frames(1)
	return true


## 前の攻撃から次の攻撃を始められるまで待って攻撃キーを押し、影の攻撃が表示されている間に path へ撮影する。
## 攻撃が始まらなければ quit(1) する
func _capture_attack(main: Node2D, path: String) -> bool:
	var hero: Hero = main.get_node("Hero")
	var frames_left: int = COOLDOWN_FRAME_LIMIT
	while hero.attack_cooldown_left > 0.0 and frames_left > 0:
		await physics_frame
		frames_left -= 1
	if frames_left == 0:
		push_error("攻撃のクールダウンが %d フレーム以内に終わらない: %s" % [COOLDOWN_FRAME_LIMIT, path])
		quit(1)
		return false
	await _hold_keys([KEY_J], 1)
	if not main.get_node("Shadow/Attack").visible:
		push_error("影の攻撃が表示されていない: %s" % path)
		quit(1)
		return false
	return await _capture(path)


## 主人公の体の中心を center_x に置いて地面に立たせ、出現済みの敵を消す (敵に触れて半透明になった姿を撮らない)
func _place_hero(main: Node2D, center_x: float) -> void:
	var hero: Hero = main.get_node("Hero")
	hero.position = Vector2(center_x - Hero.SIZE.x / 2.0, Stage.GROUND_Y - Hero.SIZE.y)
	hero.velocity = Vector2.ZERO
	await _wait_physics_frames(3)
	for enemy: Node in main.get_node("Enemies").get_children():
		enemy.queue_free()
	await _wait_physics_frames(1)


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
