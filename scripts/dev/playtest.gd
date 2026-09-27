extends "res://scripts/dev/game_driver.gd"
## タイトルから昼 → 夕方 → 夜の全ステージを ALL CLEAR まで通して遊ぶテストプレイ。Makefile の playtest target が
## 描画付きで起動して movie maker で録画し、agent が録画と静止画を目視して問題を探す (実行方法は AGENTS.md を参照)。
## ゴールまでは scripts/dev/integration.gd と同じ入力の経路 (_walk_to_goal()) で進み、各ステージの最初に影縫いと
## 引き寄せを使い、攻撃が届く敵がいれば止まって攻撃し、前に敵がいれば跳ばずに歩いて近づき、倒しながら進む。
## タイトル・ステージごとの開始・影縫い・光源の反転区間・敵との戦闘・同期ボーナス・ゲームオーバー・クリアの時点を
## tmp/playtest-<ステージの番号>-<ステージの名前>-<場面>.png に撮る。録画の末尾が ALL CLEAR の画面になるよう、最後の
## ステージのクリアの画面のまま終わる。ゲームオーバーはログに残してリトライし、1 ステージで MAX_RETRIES 回を超えるか、
## ゴールに着けなければ quit(1) で終わる。
## 保存データはプレイヤーのもの (user://) を書き換えないよう SAVE_TEST_PATH に書き、最後に消す。

## 遊ぶメインシーン
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## ステージ 1 本の定義 (名前・横幅・光源)
const Stage := preload("res://scripts/stage.gd")
## 遊ぶ順に並べたステージの一覧
const Stages := preload("res://scripts/stages.gd")
## 主人公のスクリプト (体の大きさ・移動の速さ・攻撃の範囲)
const Hero := preload("res://scripts/hero.gd")
## 敵のスクリプト (出現している画面と体の矩形)
const Enemy := preload("res://scripts/enemy.gd")
## 光源の反転区間の計算
const Light := preload("res://scripts/light.gd")
## 画面 (Screen) の定義を持つ autoload の GameState のスクリプト
const GameStateScript := preload("res://scripts/game_state.gd")
## テストプレイ中の保存データの置き場所
const SAVE_TEST_PATH: String = "res://tmp/playtest-save.json"
## 前の敵へ跳ばずに歩いて近づき始める、攻撃する側 (上の画面は主人公、下の画面は影) の体の前端から敵までの距離 (px)。
## 跳んで敵を跳び越したり敵の上に着地して触れたりしないよう、ジャンプ 1 回で進む距離 (約 220 px) に敵 1 体分の
## 幅を足した距離の手前から歩く
const ENGAGE_DISTANCE: float = 260.0
## 1 ステージでゲームオーバーからやり直せる回数
const MAX_RETRIES: int = 2
## 1 ステージでゴールに着くまで待つ物理フレーム数の、ステージの横幅を移動の速さで進むフレーム数に対する倍率。
## 敵を倒すために止まる時間と、跳んで段差を登る遠回りを含める
const STAGE_FRAME_FACTOR: float = 3.0
## 影縫いで影を縫い止めたまま主人公を右へ歩かせる物理フレーム数。ステージの最初の平らな所 (最初の地形は
## x = 480 から) を出ず、敵の出現位置にも近づかない長さ
const STITCH_FRAMES: int = 30
## 引き寄せで影が同期に戻るまで待つ物理フレーム数の上限 (引き寄せの速さで最大のずれから戻る約 35 フレームに余裕を持たせる)
const PULL_FRAME_LIMIT: int = 60
## タイトル・ステージの開始・ステージクリアの画面を、撮る前に映しておく時間 (秒)
const SCENE_SHOW_TIME: float = 0.5
## 録画の末尾に ALL CLEAR の画面を映し続ける時間 (秒)
const ALL_CLEAR_TIME: float = 1.5

## 撮影済みの場面の名前。同じ場面 (リトライしたステージの開始など) を 2 度撮らない
var captured: Dictionary = {}
## 攻撃キーを押したままか。押した次の物理フレームで離し、次の攻撃で押し直せるようにする
var attack_held: bool = false
## 前の物理フレームの体力。減ったら被弾した位置をログに残す
var last_hp: int = 0


## tree の準備が終わってから _run() を始める (シーンの追加は _initialize() の後でないとできない)
func _initialize() -> void:
	_run.call_deferred()


## 物理フレームを進めながら入力を流すため、同じ実行中に重ねて呼び出さない
func _run() -> void:
	var save_data: Node = root.get_node("SaveData")
	var save_path: String = ProjectSettings.globalize_path(SAVE_TEST_PATH)
	_remove_file(save_path)
	save_data.load_from(save_path)
	var cleared: bool = await _play_through(root.get_node("GameState"))
	_remove_file(save_path)
	if cleared:
		print("playtest OK")
		quit(0)
	else:
		quit(1)


## メインシーンを置いてタイトルから Enter キーで始め、全ステージを遊んで ALL CLEAR の画面で止める。
## ALL CLEAR まで遊べたら true
func _play_through(game_state: Node) -> bool:
	var main: Node2D = MAIN_SCENE.instantiate()
	root.add_child(main)
	current_scene = main
	await create_timer(SCENE_SHOW_TIME).timeout
	if not await _capture_once("0-title"):
		return false
	await _hold_keys([KEY_ENTER], 1)
	for index: int in range(Stages.count()):
		main = await _play_stage(main, game_state, index)
		if main == null:
			return false
	return await _end_on_all_clear(main, game_state)


## index 番目のステージのメインシーン main で、影縫いと引き寄せを使ってからゴールまで進む。ゲームオーバーなら
## Enter キーでやり直す。クリアしたら、最後のステージでなければ Enter キーで次のステージへ進んで読み込み直された
## メインシーンを、最後のステージならクリアの画面のままの main を返す。遊べなければ null
func _play_stage(main: Node2D, game_state: Node, index: int) -> Node2D:
	var stage: Stage = Stages.all()[index]
	var prefix: String = "%d-%s" % [index + 1, stage.title.to_lower()]
	var frame_limit: int = int(stage.width / Hero.MOVE_SPEED * 60.0 * STAGE_FRAME_FACTOR)
	for retries: int in range(MAX_RETRIES + 1):
		if not await _play_attempt(main, game_state, prefix, frame_limit):
			return null
		if game_state.screen == GameStateScript.Screen.CLEAR:
			var defeated: int = main.spawned_count - _living_enemies(main).size()
			print(
				(
					"playtest: %s をクリア (残りの体力 %d、倒した敵 %d / 出現 %d、リトライ %d 回)"
					% [stage.title, game_state.hp, defeated, main.spawned_count, retries]
				)
			)
			return await _leave_clear(main, prefix, index == Stages.count() - 1)
		var hero_x: float = main.get_node("Hero").position.x
		print("playtest: %s の x = %.1f でゲームオーバー (%d 回目)" % [stage.title, hero_x, retries + 1])
		await create_timer(SCENE_SHOW_TIME).timeout
		if not await _capture_once(prefix + "-gameover"):
			return null
		await _hold_keys([KEY_ENTER], 1)
		main = await _reloaded_main()
	push_error("playtest FAIL: %s で %d 回続けてゲームオーバーになる" % [stage.title, MAX_RETRIES + 1])
	return null


## ステージの最初から 1 回遊ぶ。開始を撮り、影縫いと引き寄せを使ってから、ステージクリアかゲームオーバーになるまで
## ゴールへ進む。frame_limit 物理フレーム以内にどちらにもならないか、撮影・引き寄せに失敗したら false
func _play_attempt(main: Node2D, game_state: Node, prefix: String, frame_limit: int) -> bool:
	await create_timer(SCENE_SHOW_TIME).timeout
	if not await _capture_once(prefix + "-start"):
		return false
	if not await _stitch_and_pull(main, prefix):
		return false
	last_hp = game_state.hp
	await _walk_to_goal(main, game_state, frame_limit, _fight.bind(prefix))
	_release_attack()
	if game_state.screen == GameStateScript.Screen.CLEAR or game_state.is_game_over():
		return true
	push_error(
		(
			"playtest FAIL: %s で %d 物理フレーム以内にゴールに着かない (x = %.1f)"
			% [main.stage.title, frame_limit, main.get_node("Hero").position.x]
		)
	)
	return false


## ステージクリアの画面を映す。最後のステージ (last) ならクリアの画面のままの main を返す。そうでなければクリアを撮り、
## Enter キーで次のステージへ進んで読み込み直されたメインシーンを返す。撮影に失敗したら null
func _leave_clear(main: Node2D, prefix: String, last: bool) -> Node2D:
	await create_timer(SCENE_SHOW_TIME).timeout
	if last:
		return main
	if not await _capture_once(prefix + "-clear"):
		return null
	await _hold_keys([KEY_ENTER], 1)
	return await _reloaded_main()


## 影を縫い止めたまま主人公を右へ歩かせて撮り、離してから引き寄せで同期に戻す。戻らなければ false
func _stitch_and_pull(main: Node2D, prefix: String) -> bool:
	_press_keys([KEY_K, KEY_RIGHT], true)
	await _wait_physics_frames(STITCH_FRAMES)
	var captured_stitch: bool = await _capture_once(prefix + "-stitch")
	_press_keys([KEY_K, KEY_RIGHT], false)
	await physics_frame
	if not captured_stitch:
		return false
	await _hold_keys([KEY_I], 1)
	var frames_left: int = PULL_FRAME_LIMIT
	while (main.shadow_offset != Vector2.ZERO or main.pulling) and frames_left > 0:
		await physics_frame
		frames_left -= 1
	if frames_left == 0:
		push_error("playtest FAIL: 引き寄せで %d 物理フレーム以内に同期に戻らない" % PULL_FRAME_LIMIT)
		return false
	return true


## ゴールまで進む経路 (_walk_to_goal()) の、敵と戦いながら進む 1 物理フレーム分の動き方。戦闘は攻撃の見た目が
## 出ている、攻撃を始めた次のフレームで撮る
func _fight(main: Node2D, prefix: String) -> RouteStep:
	var hp: int = root.get_node("GameState").hp
	if hp < last_hp:
		var hero_x: float = main.get_node("Hero").position.x
		print("playtest: %s の x = %.1f で被弾 (残りの体力 %d)" % [main.stage.title, hero_x, hp])
	last_hp = hp
	if attack_held:
		_release_attack()
		await _capture_once(prefix + "-combat")
	await _capture_light(main, prefix)
	if not main.get_tree().get_nodes_in_group("sync_effect").is_empty():
		await _capture_once(prefix + "-sync")
	if not _enemy_in_reach(main):
		return RouteStep.WALK if _enemy_ahead(main) else RouteStep.HOP
	if main.get_node("Hero").attack_cooldown_left <= 0.0:
		_press_keys([KEY_J], true)
		attack_held = true
	return RouteStep.HOLD


## 押したままの攻撃キーを離す
func _release_attack() -> void:
	if attack_held:
		_press_keys([KEY_J], false)
		attack_held = false


## 主人公の体の中心が光源の反転区間の中ほどを過ぎていれば、その光源の反転区間を 1 度だけ撮る
func _capture_light(main: Node2D, prefix: String) -> void:
	var center_x: float = main.get_node("Hero").position.x + Hero.SIZE.x / 2.0
	var light: Dictionary = Light.active_light(center_x, main.stage.lights)
	if not light.is_empty() and center_x >= light["x"] + light["zone"] / 2.0:
		await _capture_once("%s-light-%d" % [prefix, int(light["x"])])


## 攻撃すれば当たる敵がいるか。上の画面の敵は主人公の攻撃の範囲、下の画面の敵は影の攻撃の範囲と重なるかで見る
## (main.gd の攻撃の当たりと同じ範囲)
func _enemy_in_reach(main: Node2D) -> bool:
	var hero: Hero = main.get_node("Hero")
	var areas: Array[Rect2] = [
		Hero.attack_area(hero.position, hero.facing, Hero.ATTACK_REACH),
		main.shadow_attack_area(hero.position, hero.facing, main.stage.lights, main.shadow_offset),
	]
	for enemy: Enemy in _living_enemies(main):
		if areas[enemy.lane].intersects(enemy.body_rect()):
			return true
	return false


## 攻撃する側 (上の画面の敵には主人公、下の画面の敵には影) の向いている先に、体の前端から ENGAGE_DISTANCE 以内の
## 敵がいるか
func _enemy_ahead(main: Node2D) -> bool:
	var hero: Hero = main.get_node("Hero")
	var lights: Array[Dictionary] = main.stage.lights
	var bodies: Array[Rect2] = [
		hero.body_rect(), main.shadow_body_rect(hero.position, lights, main.shadow_offset)
	]
	var facings: Array[float] = [
		hero.facing, main.shadow_facing(hero.position, hero.facing, lights)
	]
	for enemy: Enemy in _living_enemies(main):
		var body: Rect2 = bodies[enemy.lane]
		var target: Rect2 = enemy.body_rect()
		var gap: float = (
			target.position.x - body.end.x
			if facings[enemy.lane] > 0.0
			else body.position.x - target.end.x
		)
		if gap >= 0.0 and gap <= ENGAGE_DISTANCE:
			return true
	return false


## 倒れて消える途中のものを除いた敵
func _living_enemies(main: Node2D) -> Array[Node]:
	var living: Array[Node] = []
	for enemy: Node in _enemies(main):
		if not enemy.is_queued_for_deletion():
			living.append(enemy)
	return living


## 最後のステージのクリアの画面 (ALL CLEAR) を撮り、録画の末尾に映し続ける。終了で音の再生がリークしないよう、
## 画面を残したまま音を止めて AudioServer が解放するまで待つ。ALL CLEAR の画面でなければ false
func _end_on_all_clear(main: Node2D, game_state: Node) -> bool:
	var all_clear: bool = (
		game_state.screen == GameStateScript.Screen.CLEAR
		and game_state.is_last_stage()
		and main.get_node("Screens/Clear/Label").text == "ALL CLEAR"
	)
	if not all_clear:
		push_error("playtest FAIL: 最後のステージのクリアで ALL CLEAR の画面にならない")
		return false
	if not await _capture_once("all-clear"):
		return false
	for player: Node in main.get_node("Audio").get_children():
		(player as AudioStreamPlayer).stop()
	await create_timer(ALL_CLEAR_TIME).timeout
	return true


## 画面の遷移でステージを作り直した後の、読み込み直されたメインシーン
func _reloaded_main() -> Node2D:
	await process_frame
	await _wait_physics_frames(2)
	return current_scene


## まだ撮っていない場面 name を tmp/playtest-<name>.png に撮る。撮影済みなら撮らずに true
func _capture_once(name: String) -> bool:
	if captured.has(name):
		return true
	captured[name] = true
	return await _capture("tmp/playtest-%s.png" % name)


## path のファイルがあれば消す
func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
