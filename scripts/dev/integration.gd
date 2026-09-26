extends SceneTree
## キー入力 (InputMap を通る InputEventKey) でメインシーンの主人公を動かし、地形との当たり判定・スクロール、
## 下の画面の影が同じ動き・同じ攻撃をすること、敵を倒す・ダメージを受ける・ゲームオーバー・同期ボーナスと、
## タイトル・ポーズ・ゲームオーバー・ステージクリアの画面の遷移、昼・夕方・夜の各ステージが読み込まれて最初の位置から
## ゴールに着けること、ステージクリアから次のステージへ進むこと、光源をまたいだ反転区間で影の左右の動きと
## 攻撃の向きが逆になり、光源の高さで伸び縮みすることを検証する。実行方法は AGENTS.md を参照。
## 失敗したら quit(1) で終わる。

## ステージ 1 本の定義 (地面の位置・地形・光源・ゴールの期待値に使う)
const Stage := preload("res://scripts/stage.gd")
## 遊ぶ順に並べたステージの一覧
const Stages := preload("res://scripts/stages.gd")
## 光源の高さから影の倍率を求める計算
const Light := preload("res://scripts/light.gd")
## 主人公のスクリプト (体の大きさ)
const Hero := preload("res://scripts/hero.gd")
## 敵のスクリプト (体力)
const Enemy := preload("res://scripts/enemy.gd")
## 攻撃の画面 (Lane) とダメージ
const Combat := preload("res://scripts/combat.gd")
## 画面 (Screen) の定義を持つ autoload の GameState のスクリプト
const GameStateScript := preload("res://scripts/game_state.gd")
## 位置の比較で許す誤差 (px)。CharacterBody2D は地形から safe_margin (0.08 px) だけ離れて止まる
const POSITION_TOLERANCE: float = 1.0
## 昼のステージの最初の段差 (Stages.DAY_OBSTACLES の 1 番目)
const STEP: Rect2 = Rect2(560.0, 272.0, 160.0, 48.0)
## 昼のステージの、壁の手前の段 (Stages.DAY_OBSTACLES の 3 番目)
const STAIR: Rect2 = Rect2(1340.0, 240.0, 60.0, 80.0)
## 昼のステージの、地面から 1 回では越えられない高さの壁 (Stages.DAY_OBSTACLES の 4 番目)
const WALL: Rect2 = Rect2(1400.0, 160.0, 60.0, 160.0)
## キーを押し続けて主人公を目標の位置まで動かす時の、待つ物理フレーム数の上限。移動の速さ (320 px/秒) で
## 反転区間 (200 px) を抜けるのにかかる約 40 フレームに余裕を持たせる
const MOVE_FRAME_LIMIT: int = 180

## 検証が 1 件でも失敗したか。true なら exit code 1 で終わる
var failed: bool = false
## シーンを置いた時の主人公の位置 (scenes/main.tscn の Hero)。ステージを作り直した後の位置の期待値に使う
var hero_start: Vector2 = Vector2.ZERO


## tree の準備が終わってから _run() を始める (シーンの追加は _initialize() の後でないとできない)
func _initialize() -> void:
	_run.call_deferred()


## 物理フレームを進めながら入力を流すため、同じ実行中に重ねて呼び出さない。
## 画面の遷移でステージを作り直すとメインシーンが読み込み直されるため、遷移の後は返ってきたシーンを使う
func _run() -> void:
	for rect: Rect2 in [STEP, STAIR, WALL]:
		_check(Stages.DAY_OBSTACLES.has(rect), "前提: 昼のステージの地形に %s がある" % rect)
	var game_state: Node = root.get_node_or_null("GameState")
	_check(game_state != null, "前提: autoload の GameState が root にある")
	if game_state != null:
		await _run_scenes(game_state)
	if failed:
		quit(1)
	else:
		print("integration OK")
		quit(0)


## メインシーンを置いて各検証を順に行う。読み込み直したメインシーンが無ければ (失敗として記録済み) そこでやめる
func _run_scenes(game_state: Node) -> void:
	var main: Node2D = await _start_main(game_state)
	await _check_move_and_jump(main)
	await _check_terrain_and_scroll(main)
	await _check_pause(main, game_state)
	main = await _check_quit_to_title(main, game_state)
	if main == null:
		return
	await _check_attack_and_sync(main)
	await _check_damage_and_game_over(main, game_state)
	main = await _check_retry(main, game_state)
	if main == null:
		return
	for index: int in range(Stages.count()):
		main = await _check_stage(main, game_state, index)
		if main == null:
			return
	await _play_from_title(main, game_state, "全ステージのクリア後にタイトルから始める")
	_check(game_state.stage_index == 0, "全ステージのクリア後: 最初のステージから遊ぶ")
	main.queue_free()
	await process_frame


## メインシーンを置いてタイトルの画面から Enter キーでプレイを始める。画面の遷移で読み込み直せるよう
## current_scene にする
func _start_main(game_state: Node) -> Node2D:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	hero_start = main.get_node("Hero").position
	await _wait_physics_frames(2)
	await _play_from_title(main, game_state, "起動直後")
	return main


## タイトルの画面が出ていて移動キーでは主人公が動かず、Enter キーでプレイが始まって主人公が地面に着く
func _play_from_title(main: Node2D, game_state: Node, label: String) -> void:
	var hero: Hero = main.get_node("Hero")
	_check(game_state.screen == GameStateScript.Screen.TITLE, "%s: タイトルの画面になる" % label)
	_check(main.get_node("Screens/Title").visible, "%s: タイトルが表示される" % label)
	_check(not main.get_node("Overlay/HpLabel").visible, "%s: タイトルでは体力を表示しない" % label)
	await _hold_keys([KEY_RIGHT, KEY_SPACE], 10)
	_check(hero.position == hero_start, "%s: タイトルでは移動・ジャンプのキーで主人公が動かない" % label)
	await _hold_keys([KEY_ENTER], 1)
	_check(game_state.is_playing(), "%s: Enter キーでプレイが始まる" % label)
	_check(not main.get_node("Screens/Title").visible, "%s: プレイが始まるとタイトルが消える" % label)
	_check(main.get_node("Overlay/HpLabel").visible, "%s: プレイ中は体力を表示する" % label)
	await _wait_physics_frames(2)


## Esc キーでポーズすると主人公も敵も止まり、もう一度 Esc キーで続きから動く
func _check_pause(main: Node2D, game_state: Node) -> void:
	var hero: Hero = main.get_node("Hero")
	var enemy: Node2D = main.spawn_enemy(
		Combat.Lane.TOP, hero.position.x + 300.0, Stage.GROUND_Y, 200.0
	)
	await _wait_physics_frames(2)
	await _hold_keys([KEY_ESCAPE], 1)
	_check(game_state.screen == GameStateScript.Screen.PAUSED, "ポーズ: Esc キーでポーズの画面になる")
	_check(main.get_node("Screens/Pause").visible, "ポーズ: ポーズの表示が出る")
	var hero_at: Vector2 = hero.position
	var enemy_at: Vector2 = enemy.position
	await _hold_keys([KEY_LEFT, KEY_J], 20)
	_check(hero.position == hero_at, "ポーズ: 移動キーを押しても主人公が動かない")
	_check(not hero.is_attacking(), "ポーズ: 攻撃キーを押しても攻撃しない")
	_check(enemy.position == enemy_at, "ポーズ: 敵も止まる")
	await _hold_keys([KEY_ESCAPE], 1)
	_check(game_state.is_playing(), "ポーズ: もう一度 Esc キーでプレイ中に戻る")
	_check(not main.get_node("Screens/Pause").visible, "ポーズ: 再開するとポーズの表示が消える")
	await _hold_keys([KEY_LEFT], 10)
	_check(hero.position.x < hero_at.x, "ポーズ: 再開すると続きから動く")
	_check(enemy.position != enemy_at, "ポーズ: 再開すると敵も動く")


## ポーズから Q キーでタイトルに戻ると、ステージが最初から作り直される。そこから Enter キーでまた遊べる
func _check_quit_to_title(main: Node2D, game_state: Node) -> Node2D:
	await _hold_keys([KEY_ESCAPE], 1)
	await _hold_keys([KEY_Q], 1)
	var restarted: Node2D = await _reloaded_main(main, "タイトルへ戻る")
	if restarted == null:
		return null
	_check(restarted.scroll_x == 0.0, "タイトルへ戻る: スクロールが最初に戻る")
	_check(game_state.stage_index == 0, "タイトルへ戻る: 最初のステージに戻る")
	_check(_living_enemy_count(restarted) == 0, "タイトルへ戻る: 出現していた敵がいなくなる")
	await _play_from_title(restarted, game_state, "タイトルへ戻った後")
	return restarted


## ゲームオーバーから Enter キーでやり直すと、体力が戻ったステージの最初からプレイが始まる
func _check_retry(main: Node2D, game_state: Node) -> Node2D:
	await _hold_keys([KEY_ENTER], 1)
	var restarted: Node2D = await _reloaded_main(main, "リトライ")
	if restarted == null:
		return null
	_check(game_state.is_playing(), "リトライ: タイトルを経ずにプレイ中になる")
	_check(game_state.hp == game_state.MAX_HP, "リトライ: 体力が最大値に戻る")
	_check(not restarted.get_node("Screens/GameOver").visible, "リトライ: ゲームオーバーの表示が消える")
	_check(_living_enemy_count(restarted) == 0, "リトライ: 敵がいなくなる")
	var hero: Hero = restarted.get_node("Hero")
	await _hold_keys([KEY_RIGHT], 10)
	_check(hero.position.x > hero_start.x, "リトライ: 右キーで主人公が動く")
	return restarted


## プレイ中の index 番目のステージのメインシーン main で、そのステージが読み込まれていること・光源の予兆と反転区間の
## 影を確かめてから、最初の位置からゴールに着いてステージクリアになり、操作を受け付けないことを確かめる。
## Enter キーで次のステージ (最後のステージならタイトル) へ移り、読み込み直されたメインシーンを返す
func _check_stage(main: Node2D, game_state: Node, index: int) -> Node2D:
	var stage: Stage = Stages.all()[index]
	var label: String = "ステージ %d (%s)" % [index + 1, stage.title]
	var last: bool = index == Stages.count() - 1
	_check(
		game_state.is_playing() and game_state.stage_index == index,
		"%s: タイトルを経ずにプレイ中になる" % label
	)
	_check_stage_loaded(main, stage, label)
	_check_light_omen(main, stage)
	for light: Dictionary in stage.lights:
		await _check_light_reversal(main, light)
	await _run_to_goal(main, game_state, stage, label)
	_check(main.get_node("Screens/Clear").visible, "%s: ステージクリアの表示が出る" % label)
	var hint: String = "Enter: Title" if last else "Enter: Next Stage"
	_check(
		main.get_node("Screens/Clear/Hint").text == hint,
		"%s: ステージクリアの表示に次の操作 (%s) が出る" % [label, hint]
	)
	var hero: Hero = main.get_node("Hero")
	var cleared_at: Vector2 = hero.position
	await _hold_keys([KEY_LEFT], 10)
	_check(hero.position == cleared_at, "%s: ステージクリアの後は操作を受け付けない" % label)
	await _hold_keys([KEY_ENTER], 1)
	var restarted: Node2D = await _reloaded_main(main, label + " のクリア後")
	if restarted == null:
		return null
	if last:
		_check(
			game_state.screen == GameStateScript.Screen.TITLE,
			"%s: 最後のステージのクリアから Enter キーでタイトルに戻る" % label
		)
		_check(restarted.get_node("Screens/Title").visible, "%s: タイトルが表示される" % label)
	else:
		_check(
			game_state.stage_index == index + 1, "%s: Enter キーで次のステージへ進む" % label
		)
		_check(game_state.hp == game_state.MAX_HP, "%s: 次のステージは体力が最大値から始まる" % label)
	return restarted


## main に stage の地形・空の色・ゴール・ステージの名前が置かれている
func _check_stage_loaded(main: Node2D, stage: Stage, label: String) -> void:
	_check_terrain_mirrored(main, stage)
	_check(main.get_node("Background/TopScreen").color == stage.sky, "%s: 上の画面がステージの空の色" % label)
	_check(
		main.get_node("Goal").position == stage.goal().position,
		"%s: ゴールの目印がステージの右端の手前にある" % label
	)
	_check(
		main.get_node("Overlay/StageLabel").text.contains(stage.title),
		"%s: ステージの名前が表示される" % label
	)


## 主人公を最初の位置に戻し、右キーを押し続けて地面にいる間はジャンプキーを押し直し、ステージクリアになるまで進む。
## 地形だけで行き止まらずゴールに着けることを確かめるため、出現した敵は毎フレーム消す。
## ステージの横幅を移動の速さで進む時間の 2 倍のフレーム数を過ぎてもクリアにならなければ失敗として記録する
func _run_to_goal(main: Node2D, game_state: Node, stage: Stage, label: String) -> void:
	var hero: Hero = main.get_node("Hero")
	hero.position = hero_start
	hero.velocity = Vector2.ZERO
	await _wait_physics_frames(2)
	var frames_left: int = int(stage.width / Hero.MOVE_SPEED * 60.0 * 2.0)
	Input.parse_input_event(_key_event(KEY_RIGHT, true))
	while game_state.is_playing() and frames_left > 0:
		_clear_enemies(main)
		if hero.is_on_floor():
			await _hold_keys([KEY_SPACE], 1)
			frames_left -= 2
		else:
			await physics_frame
			frames_left -= 1
	Input.parse_input_event(_key_event(KEY_RIGHT, false))
	await physics_frame
	_check(
		game_state.screen == GameStateScript.Screen.CLEAR,
		"%s: 最初の位置から右へ跳び続けるとゴールに着いてステージクリアになる (x = %.2f)" % [label, hero.position.x]
	)
	_check(
		hero.body_rect().intersects(stage.goal()),
		"%s: ステージクリアになった時、主人公がゴールに入っている" % label
	)


## 画面の遷移でステージを作り直した後の、読み込み直されたメインシーン。主人公は最初の位置にいる。
## 遷移前のメインシーン old_main は呼び出しの時点で解放済みのことがあるため型を付けない
func _reloaded_main(old_main: Variant, label: String) -> Node2D:
	await process_frame
	await _wait_physics_frames(2)
	_check(not is_instance_valid(old_main), "%s: 遷移前のステージが消える" % label)
	var main: Node2D = current_scene
	_check(main != null, "%s: メインシーンが読み込み直される" % label)
	if main == null:
		return null
	_check(main.get_node("Hero").position == hero_start, "%s: 主人公が最初の位置に戻る" % label)
	return main


## 攻撃キーで目の前の敵に攻撃が当たり、通常の攻撃は体力の回数で、上下で同時に当てた攻撃は 1 回で倒す
func _check_attack_and_sync(main: Node2D) -> void:
	var hero: Hero = main.get_node("Hero")
	var front_x: float = hero.position.x + Hero.SIZE.x + 10.0
	var top_enemy: Node2D = main.spawn_enemy(Combat.Lane.TOP, front_x, Stage.GROUND_Y, 0.0)
	await _press_attack()
	_check(top_enemy.hp == Enemy.MAX_HP - Combat.BASE_DAMAGE, "攻撃: J キーで上の画面の目の前の敵に当たる")
	for _i: int in range(Enemy.MAX_HP - 1):
		await _wait_physics_frames(20)
		await _press_attack()
	_check(_living_enemy_count(main) == 0, "攻撃: 通常の攻撃を体力の回数だけ当てると敵が倒れる")
	_check(
		main.get_tree().get_nodes_in_group("sync_effect").is_empty(),
		"同期: 上の画面だけに当てた時は同期ボーナスが出ない"
	)

	await _wait_physics_frames(20)
	_check(not main.get_node("Shadow/Attack").visible, "攻撃: 攻撃が終われば影の攻撃も消える")
	main.spawn_enemy(Combat.Lane.TOP, front_x, Stage.GROUND_Y, 0.0)
	main.spawn_enemy(Combat.Lane.BOTTOM, front_x, Stage.GROUND_Y, 0.0)
	await _press_attack()
	_check(main.get_node("Shadow/Attack").visible, "攻撃: 同期中は影も同じ攻撃をする")
	_check(_living_enemy_count(main) == 0, "同期: 上下で同時に当てた攻撃 1 回で上下の敵が倒れる")
	_check(
		not main.get_tree().get_nodes_in_group("sync_effect").is_empty(),
		"同期: 同期ボーナスの演出が出る"
	)

	await _wait_physics_frames(60)
	_check(
		main.get_tree().get_nodes_in_group("sync_effect").is_empty(),
		"同期: 同期ボーナスの演出は時間が経つと消える"
	)
	main.spawn_enemy(Combat.Lane.TOP, front_x, Stage.GROUND_Y, 0.0)
	await _press_attack()
	await _wait_physics_frames(2)
	main.spawn_enemy(Combat.Lane.BOTTOM, front_x, Stage.GROUND_Y, 0.0)
	await _wait_physics_frames(2)
	_check(
		_living_enemy_count(main) == 0,
		"同期: 上下の当たりが時間幅の中で別のフレームでも、先に当たった敵を含めて 1 回で倒れる"
	)
	_check(
		not main.get_tree().get_nodes_in_group("sync_effect").is_empty(),
		"同期: 上下の当たりが別のフレームでも同期ボーナスの演出が出る"
	)


## 下の画面の敵が影に触れても、上の画面の敵が主人公に触れても体力が減り、0 でゲームオーバーになる
func _check_damage_and_game_over(main: Node2D, game_state: Node) -> void:
	var hero: Hero = main.get_node("Hero")
	await _wait_physics_frames(40)
	var start_hp: int = game_state.hp
	var bottom_enemy: Node2D = main.spawn_enemy(
		Combat.Lane.BOTTOM, hero.position.x + 10.0, Stage.GROUND_Y, 0.0
	)
	await _wait_physics_frames(2)
	_check(game_state.hp == start_hp - 1, "ダメージ: 下の画面の敵が影に触れると体力が減る")
	bottom_enemy.queue_free()
	await _wait_physics_frames(int(game_state.INVINCIBLE_TIME * 60.0) + 10)
	_check(game_state.hp == start_hp - 1, "ダメージ: 敵が離れれば体力は減らない")

	main.spawn_enemy(Combat.Lane.TOP, hero.position.x + 10.0, Stage.GROUND_Y, 0.0)
	await _wait_physics_frames(2)
	_check(game_state.hp == start_hp - 2, "ダメージ: 上の画面の敵が主人公に触れると体力が減る")

	var frames_left: int = int(game_state.INVINCIBLE_TIME * 60.0) * (start_hp + 1)
	while not game_state.is_game_over() and frames_left > 0:
		await physics_frame
		frames_left -= 1
	_check(game_state.is_game_over() and game_state.hp == 0, "ゲームオーバー: 敵に触れ続けて体力が 0 になる")
	_check(main.get_node("Screens/GameOver").visible, "ゲームオーバー: ゲームオーバーの表示が出る")
	var over_x: float = hero.position.x
	await _hold_keys([KEY_RIGHT], 20)
	_check(absf(hero.position.x - over_x) < POSITION_TOLERANCE, "ゲームオーバー: 操作を受け付けない")


## stage の各光源の反転区間の予兆として、下の画面の光源の x から左へ、反転区間の幅に倍率を掛けた幅の帯が置かれている
func _check_light_omen(main: Node2D, stage: Stage) -> void:
	for light: Dictionary in stage.lights:
		var width: float = light["zone"] * Light.shadow_scale(light["height"])
		var band: Rect2 = Rect2(light["x"] - width, main.SCREEN_HEIGHT, width, Stage.GROUND_Y)
		var found: bool = false
		for child: Node in main.get_node("Lights").get_children():
			found = found or (
				child is ColorRect and Rect2(child.position, child.size).is_equal_approx(band)
			)
		_check(found, "予兆: 光源 (x = %d) の反転区間で影が動く範囲に下の画面の帯がある" % int(light["x"]))


## light (遊んでいるステージの Stage.lights の要素) の手前から右キーで進むと、光源をまたいだ反転区間で影だけが左へ、光源の倍率の分だけ
## 動き、左キーでは影が右へ動く。反転区間では影の攻撃が主人公と逆向きに倍率のリーチで出て、影の後ろ (左) にいる
## 下の画面の敵に当たる。反転区間を抜けると影が主人公の真下に戻る
func _check_light_reversal(main: Node2D, light: Dictionary) -> void:
	var hero: Hero = main.get_node("Hero")
	var shadow: Node2D = main.get_node("Shadow")
	var label: String = "光源 (%s の x = %d)" % [main.stage.title, int(light["x"])]
	var scale: float = Light.shadow_scale(light["height"])
	hero.position = Vector2(light["x"] - 80.0 - Hero.SIZE.x / 2.0, Stage.GROUND_Y - Hero.SIZE.y)
	hero.velocity = Vector2.ZERO
	await _wait_physics_frames(3)
	_clear_enemies(main)
	_check_synced(main, label + " の手前")

	await _hold_key_until(KEY_RIGHT, func() -> bool: return _center_x(hero) >= light["x"] + 20.0)
	var hero_x: float = hero.position.x
	var shadow_x: float = shadow.position.x
	await _hold_keys([KEY_RIGHT], 6)
	_check(hero.position.x > hero_x, "%s: 反転区間で右キーを押すと主人公は右へ進む" % label)
	_check(shadow.position.x < shadow_x, "%s: 反転区間で右キーを押すと影は左へ進む" % label)
	_check(
		is_equal_approx(shadow_x - shadow.position.x, (hero.position.x - hero_x) * scale),
		"%s: 影の移動量は主人公の移動量に光源の倍率を掛けた量" % label
	)
	_check(
		is_equal_approx(main.get_node("Shadow/Body").size.y, Hero.SIZE.y * scale),
		"%s: 影の見た目の長さが光源の倍率の分だけ伸び縮みする" % label
	)
	var band: Rect2 = main.shadow_reverse_range(light)
	var shadow_center: float = shadow.position.x + Hero.SIZE.x / 2.0
	_check(
		band.position.x <= shadow_center and shadow_center <= band.end.x,
		"%s: 反転区間の影は予兆の帯の範囲にいる" % label
	)

	var behind: Node2D = main.spawn_enemy(
		Combat.Lane.BOTTOM, shadow.position.x - Enemy.SIZE.x - 4.0, Stage.GROUND_Y, 0.0
	)
	await _press_attack()
	var attack: ColorRect = main.get_node("Shadow/Attack")
	_check(attack.visible, "%s: 反転区間でも影が攻撃する" % label)
	_check(
		attack.global_position.x + attack.size.x <= shadow.global_position.x + POSITION_TOLERANCE,
		"%s: 右を向いた主人公の影の攻撃は影の左 (主人公と逆向き) に出る" % label
	)
	_check(
		is_equal_approx(attack.size.x, Hero.ATTACK_REACH * scale),
		"%s: 影の攻撃のリーチが光源の倍率の分だけ伸び縮みする" % label
	)
	_check(behind.hp == Enemy.MAX_HP - Combat.BASE_DAMAGE, "%s: 影の後ろ (左) の下の画面の敵に当たる" % label)
	behind.queue_free()

	hero_x = hero.position.x
	shadow_x = shadow.position.x
	await _hold_keys([KEY_LEFT], 6)
	_check(hero.position.x < hero_x, "%s: 反転区間で左キーを押すと主人公は左へ進む" % label)
	_check(shadow.position.x > shadow_x, "%s: 反転区間で左キーを押すと影は右へ進む" % label)

	await _hold_key_until(
		KEY_RIGHT, func() -> bool: return _center_x(hero) >= light["x"] + light["zone"] + 10.0
	)
	_check_synced(main, label + " の反転区間を抜けた後")
	_check(
		main.get_node("Shadow/Body").size == Hero.SIZE,
		"%s: 反転区間を抜けると影の見た目の長さが主人公と同じに戻る" % label
	)


## 出現済みの敵をすべて消す (光源の検証で、位置を移した主人公・影に敵が触れないようにする)
func _clear_enemies(main: Node2D) -> void:
	for enemy: Node in main.get_node("Enemies").get_children():
		enemy.queue_free()


## 主人公の体の中心の x
func _center_x(hero: Hero) -> float:
	return hero.position.x + Hero.SIZE.x / 2.0


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


## 倒れて消える途中のものを除いた敵の数
func _living_enemy_count(main: Node2D) -> int:
	var count: int = 0
	for enemy: Node in main.get_node("Enemies").get_children():
		if not enemy.is_queued_for_deletion():
			count += 1
	return count


## 平らな地面での左右移動とジャンプ
func _check_move_and_jump(main: Node2D) -> void:
	var hero: Hero = main.get_node("Hero")
	_check(hero.is_on_floor(), "起動直後: 主人公が地面に立っている")
	_check_synced(main, "起動直後")

	var before_right: float = hero.position.x
	await _hold_keys([KEY_RIGHT], 20)
	_check(hero.position.x > before_right, "右キー: 主人公が右へ進む")
	_check_synced(main, "右キー")

	var before_left: float = hero.position.x
	await _hold_keys([KEY_A], 10)
	_check(hero.position.x < before_left, "A キー: 主人公が左へ進む")
	_check_synced(main, "A キー")

	await _hold_keys([KEY_SPACE], 3)
	_check(not hero.is_on_floor(), "スペースキー: 主人公がジャンプして地面から離れる")
	_check_synced(main, "ジャンプ中")

	await _wait_physics_frames(60)
	_check(hero.is_on_floor(), "ジャンプ後: 主人公が地面に戻る")
	_check_synced(main, "着地後")


## 段差の側面で止まる → ジャンプで段差に乗る → 右へ進んで壁の手前の段で止まる。その間スクロールしても上下の対応が
## 崩れない
func _check_terrain_and_scroll(main: Node2D) -> void:
	var hero: Hero = main.get_node("Hero")
	await _hold_keys([KEY_RIGHT], 90)
	_check(
		absf(hero.position.x + Hero.SIZE.x - STEP.position.x) < POSITION_TOLERANCE,
		"段差の側面: 右へ進み続けても段差の左端で止まる (x = %.2f)" % hero.position.x
	)
	_check(hero.is_on_floor(), "段差の側面: 地面に立ったまま")

	await _hold_keys([KEY_RIGHT, KEY_SPACE], 20)
	await _wait_physics_frames(60)
	_check(hero.is_on_floor(), "段差: ジャンプして着地する")
	_check(
		absf(hero.position.y + Hero.SIZE.y - STEP.position.y) < POSITION_TOLERANCE,
		"段差: 段差の上に乗る (足元 y = %.2f)" % (hero.position.y + Hero.SIZE.y)
	)
	_check_synced(main, "段差の上")

	await _hold_keys([KEY_RIGHT], 200)
	var stopped_x: float = hero.position.x
	_check(
		absf(stopped_x + Hero.SIZE.x - STAIR.position.x) < POSITION_TOLERANCE,
		"壁の手前の段: 右へ進み続けても段の左端で止まる (x = %.2f)" % stopped_x
	)
	await _hold_keys([KEY_RIGHT], 10)
	_check(
		absf(hero.position.x - stopped_x) < POSITION_TOLERANCE, "壁の手前の段: 押し続けても段を抜けない"
	)
	_check(
		absf(hero.position.y + Hero.SIZE.y - Stage.GROUND_Y) < POSITION_TOLERANCE,
		"壁の手前の段: 段差から降りて地面に立っている"
	)

	_check(main.scroll_x > 0.0, "スクロール: 主人公が右へ進むと画面が右へスクロールする")
	_check(
		(
			absf(main.scroll_x - main.scroll_for(hero.position.x + Hero.SIZE.x / 2.0, main.stage.width))
			< POSITION_TOLERANCE
		),
		"スクロール: 主人公が画面の中央に来るスクロール量"
	)
	_check(
		absf(main.get_viewport().get_canvas_transform().origin.x + main.scroll_x) < POSITION_TOLERANCE,
		"スクロール: 上下の画面をスクロール量だけずらして映す"
	)
	_check_synced(main, "スクロール後")
	await _check_ceiling(main)


## 高い地形 (壁の上) から跳んでも主人公は上の画面の上端を越えず、影は下の画面からはみ出さない
func _check_ceiling(main: Node2D) -> void:
	var hero: Hero = main.get_node("Hero")
	var shadow: Node2D = main.get_node("Shadow")
	hero.position = Vector2(WALL.position.x + 10.0, WALL.position.y - Hero.SIZE.y)
	hero.velocity = Vector2.ZERO
	await _wait_physics_frames(3)
	_check(hero.is_on_floor(), "天井: 壁の上に立つ")
	var highest_hero: float = hero.position.y
	var highest_shadow: float = shadow.position.y
	Input.parse_input_event(_key_event(KEY_SPACE, true))
	for _i: int in range(40):
		await physics_frame
		highest_hero = minf(highest_hero, hero.position.y)
		highest_shadow = minf(highest_shadow, shadow.position.y)
	Input.parse_input_event(_key_event(KEY_SPACE, false))
	await physics_frame
	_check(highest_hero < WALL.position.y - Hero.SIZE.y, "天井: 壁の上からジャンプする")
	_check(
		highest_hero > -POSITION_TOLERANCE,
		"天井: 主人公が上の画面の上端を越えない (最も高い y = %.2f)" % highest_hero
	)
	_check(
		highest_shadow > main.SCREEN_HEIGHT - POSITION_TOLERANCE,
		"天井: 影が下の画面の上端を越えて上の画面に入らない"
	)


## 影は主人公から上の画面 1 つ分だけ下にいて、画面上の位置も同じ横位置・上の画面 1 つ分下にある。
## 影の足元は下の画面の地形の上にある
func _check_synced(main: Node2D, label: String) -> void:
	var hero: Node2D = main.get_node("Hero")
	var shadow: Node2D = main.get_node("Shadow")
	var offset: Vector2 = Vector2(0.0, main.SCREEN_HEIGHT)
	_check(shadow.position == hero.position + offset, "%s: 影が主人公と同じ位置 (下の画面) にいる" % label)
	var hero_on_screen: Vector2 = hero.get_global_transform_with_canvas().origin
	var shadow_on_screen: Vector2 = shadow.get_global_transform_with_canvas().origin
	_check(
		shadow_on_screen.is_equal_approx(hero_on_screen + offset),
		"%s: 画面上でも影が主人公の真下 (上の画面 1 つ分下) に映る" % label
	)


## 上の画面の地形は stage の地形 (Stage.terrain()) と同じ位置・大きさで、下の画面の地形は上の画面の地形と同じ形で
## 上の画面 1 つ分だけ下にある
func _check_terrain_mirrored(main: Node2D, stage: Stage) -> void:
	var terrain: Array[Rect2] = stage.terrain()
	var top: Array[Node] = main.get_node("TopTerrain").get_children()
	var bottom: Array[Node] = main.get_node("BottomTerrain").get_children()
	_check(
		top.size() == terrain.size(), "地形 (%s): 上の画面にステージの地形の数だけ地形がある" % stage.title
	)
	_check(bottom.size() == top.size(), "地形 (%s): 下の画面に上の画面と同じ数の地形がある" % stage.title)
	for i: int in range(mini(terrain.size(), mini(top.size(), bottom.size()))):
		var body: StaticBody2D = top[i]
		var top_rect: ColorRect = body.get_child(1)
		var bottom_rect: ColorRect = bottom[i]
		_check(
			Rect2(body.global_position, top_rect.size) == terrain[i],
			"地形 (%s の %d 番目): 上の画面の地形がステージの地形の位置・大きさにある" % [stage.title, i]
		)
		_check(
			bottom_rect.global_position == body.global_position + Vector2(0.0, main.SCREEN_HEIGHT),
			"地形 (%s の %d 番目): 下の画面の地形が上の画面の地形の真下にある" % [stage.title, i]
		)
		_check(
			bottom_rect.size == top_rect.size, "地形 (%s の %d 番目): 上下の地形が同じ大きさ" % [stage.title, i]
		)


## cond が false なら label を ERROR として出し、失敗として記録する
func _check(cond: bool, label: String) -> void:
	if not cond:
		push_error("integration FAIL: " + label)
		failed = true


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
