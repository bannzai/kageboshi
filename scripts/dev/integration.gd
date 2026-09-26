extends SceneTree
## キー入力 (InputMap を通る InputEventKey) でメインシーンの主人公を動かし、地形との当たり判定・スクロール、
## 下の画面の影が同じ動き・同じ攻撃をすること、影縫い・ゲージ切れ・引き寄せで上下がずれて同期に戻ること、
## 敵を倒す・ダメージを受ける・ゲームオーバー・同期ボーナスを検証する。実行方法は AGENTS.md を参照。
## 失敗したら quit(1) で終わる。

## 地形の定義 (段差・壁・地面の位置の期待値に使う)
const Stage := preload("res://scripts/stage.gd")
## 主人公のスクリプト (体の大きさ)
const Hero := preload("res://scripts/hero.gd")
## 敵のスクリプト (体力)
const Enemy := preload("res://scripts/enemy.gd")
## 攻撃の画面 (Lane) とダメージ
const Combat := preload("res://scripts/combat.gd")
## 位置の比較で許す誤差 (px)。CharacterBody2D は地形から safe_margin (0.08 px) だけ離れて止まる
const POSITION_TOLERANCE: float = 1.0
## 最初の段差 (Stage.TERRAIN の 3 番目)
const STEP: Rect2 = Rect2(560.0, 272.0, 160.0, 48.0)
## 越えられない高さの壁 (Stage.TERRAIN の 5 番目)
const WALL: Rect2 = Rect2(1400.0, 160.0, 60.0, 160.0)

## 検証が 1 件でも失敗したか。true なら exit code 1 で終わる
var failed: bool = false


## tree の準備が終わってから _run() を始める (シーンの追加は _initialize() の後でないとできない)
func _initialize() -> void:
	_run.call_deferred()


## 物理フレームを進めながら入力を流すため、同じ実行中に重ねて呼び出さない。
func _run() -> void:
	_check(Stage.TERRAIN.has(STEP), "前提: 段差が Stage.TERRAIN にある")
	_check(Stage.TERRAIN.has(WALL), "前提: 壁が Stage.TERRAIN にある")
	var game_state: Node = root.get_node_or_null("GameState")
	_check(game_state != null, "前提: autoload の GameState が root にある")
	if game_state != null:
		var main: Node2D = await _start_main()
		await _check_move_and_jump(main)
		await _check_terrain_and_scroll(main)
		main.queue_free()
		main = await _start_main()
		await _check_stitch_and_pull(main, game_state)
		main.queue_free()
		main = await _start_main()
		await _check_attack_and_sync(main)
		await _check_damage_and_game_over(main, game_state)
		main.queue_free()
		await process_frame
	if failed:
		quit(1)
	else:
		print("integration OK")
		quit(0)


## メインシーンを新しく置き、主人公が地面に着くまで待つ (体力も GameState.reset() で最大値に戻る)
func _start_main() -> Node2D:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait_physics_frames(2)
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
	_check(main.get_node("Overlay/GameOver").visible, "ゲームオーバー: ゲームオーバーの表示が出る")
	var over_x: float = hero.position.x
	await _hold_keys([KEY_RIGHT], 20)
	_check(absf(hero.position.x - over_x) < POSITION_TOLERANCE, "ゲームオーバー: 操作を受け付けない")


## K キーで影を縫い止めて主人公だけが動き、離してもずれたまま主人公と同じ動きをして、I キーの引き寄せで
## 同期に戻る。L キーで主人公を止めて影だけが動き、その最中の引き寄せでも同期に戻る。縫い止め続けると
## ゲージが切れて解除される
func _check_stitch_and_pull(main: Node2D, game_state: Node) -> void:
	var hero: Hero = main.get_node("Hero")
	var shadow: Node2D = main.get_node("Shadow")
	var shadow_needle: CanvasItem = main.get_node("Shadow/Needle")
	var hero_needle: CanvasItem = main.get_node("Hero/Needle")
	_check(game_state.gauge == game_state.MAX_GAUGE, "影縫い: 最初はゲージが満タン")

	var shadow_start: Vector2 = shadow.position
	var hero_start_x: float = hero.position.x
	_press_keys([KEY_K, KEY_RIGHT], true)
	await _wait_physics_frames(30)
	_check(hero.position.x > hero_start_x + 100.0, "影縫い: K キーを押している間も主人公は右へ進む")
	_check(
		shadow.position.distance_to(shadow_start) < POSITION_TOLERANCE,
		"影縫い: K キーを押している間は影が縫い止めた位置に残る"
	)
	_check(shadow_needle.visible, "影縫い: 縫い止めた影に針が刺さる")
	_check(game_state.gauge < game_state.MAX_GAUGE, "影縫い: 縫い止めている間はゲージが減る")

	_press_keys([KEY_K], false)
	await physics_frame
	var offset_x: float = shadow.position.x - hero.position.x
	var gauge_left: float = game_state.gauge
	var released_x: float = hero.position.x
	await _wait_physics_frames(10)
	_press_keys([KEY_RIGHT], false)
	await physics_frame
	_check(not shadow_needle.visible, "影縫い: K キーを離すと針が消える")
	_check(offset_x < -100.0, "影縫い: K キーを離しても影は縫い止めた分だけずれたまま")
	_check(hero.position.x > released_x, "影縫い: 離した後も主人公は右へ進む")
	_check(
		absf(shadow.position.x - hero.position.x - offset_x) < POSITION_TOLERANCE,
		"影縫い: 離した後は、ずれたまま影が主人公と同じ動きをする"
	)
	_check(
		absf(shadow.position.y - hero.position.y - main.SCREEN_HEIGHT) < POSITION_TOLERANCE,
		"影縫い: 離した後の影は主人公と同じ高さに戻る"
	)
	_check(game_state.gauge == gauge_left, "影縫い: ずれている間はゲージが回復しない")

	await _hold_keys([KEY_I], 1)
	await _wait_physics_frames(40)
	_check_synced(main, "引き寄せ後")
	var gauge_synced: float = game_state.gauge
	await _wait_physics_frames(10)
	_check(game_state.gauge > gauge_synced, "引き寄せ: 同期に戻るとゲージが回復する")

	await _hold_keys([KEY_SPACE], 3)
	_press_keys([KEY_L], true)
	await physics_frame
	var held_y: float = hero.position.y
	_check(not hero.is_on_floor(), "逆の影縫い: ジャンプ中に L キーを押す")
	await _wait_physics_frames(20)
	_check(
		absf(hero.position.y - held_y) < POSITION_TOLERANCE,
		"逆の影縫い: 空中で止めた主人公は落ちない (y = %.2f → %.2f)" % [held_y, hero.position.y]
	)
	_press_keys([KEY_L], false)
	await _wait_physics_frames(60)
	_check(hero.is_on_floor(), "逆の影縫い: L キーを離すと主人公が落ちて着地する")
	_check_synced(main, "空中で止めて離した後")

	var stopped_x: float = hero.position.x
	_press_keys([KEY_L, KEY_RIGHT, KEY_SPACE], true)
	await _wait_physics_frames(30)
	_check(absf(hero.position.x - stopped_x) < POSITION_TOLERANCE, "逆の影縫い: L キーで主人公が止まる")
	_check(hero.is_on_floor(), "逆の影縫い: 主人公を止めている間はジャンプもしない")
	_check(shadow.position.x > stopped_x + 100.0, "逆の影縫い: 影だけが右へ進む")
	_check(hero_needle.visible, "逆の影縫い: 止めた主人公に針が刺さる")
	_press_keys([KEY_RIGHT, KEY_SPACE], false)
	await _hold_keys([KEY_I], 1)
	await _wait_physics_frames(40)
	_check(not hero_needle.visible, "引き寄せ: 逆の影縫いの最中に引き寄せると縫い止めが解ける")
	_check_synced(main, "逆の影縫いの最中の引き寄せ後 (L キーは押したまま)")
	_press_keys([KEY_L], false)
	await physics_frame

	game_state.gauge = game_state.MAX_GAUGE
	var drain_frames: int = int(game_state.MAX_GAUGE / game_state.GAUGE_DRAIN * 60.0)
	_press_keys([KEY_K, KEY_RIGHT], true)
	await _wait_physics_frames(20)
	_press_keys([KEY_RIGHT], false)
	await _wait_physics_frames(drain_frames)
	_check(not game_state.has_gauge(), "ゲージ切れ: 縫い止め続けるとゲージが 0 になる")
	_check(not shadow_needle.visible, "ゲージ切れ: K キーを押したままでも縫い止めが解除される")
	var empty_offset_x: float = shadow.position.x - hero.position.x
	var before_left_x: float = hero.position.x
	await _hold_keys([KEY_LEFT], 10)
	_check(hero.position.x < before_left_x, "ゲージ切れ: 主人公は左へ進む")
	_check(
		absf(shadow.position.x - hero.position.x - empty_offset_x) < POSITION_TOLERANCE,
		"ゲージ切れ: 解除された影は、ずれたまま主人公と同じ動きをする"
	)
	_check(empty_offset_x < -50.0, "ゲージ切れ: 解除されてもずれは残る")
	_press_keys([KEY_K], false)
	await _hold_keys([KEY_LEFT], 120)
	_check(hero.position.x < POSITION_TOLERANCE, "ステージの端: 主人公がステージの左端まで戻る")
	_check(
		shadow.position.x > -POSITION_TOLERANCE,
		"ステージの端: 左にずれた影はステージの左端より外に出ない (x = %.2f)" % shadow.position.x
	)
	await _hold_keys([KEY_I], 1)
	await _wait_physics_frames(40)
	_check_synced(main, "ゲージ切れの後の引き寄せ後")


## physical_keycodes (Key の配列) のキーを押す (pressed = true) / 離す (false)
func _press_keys(physical_keycodes: Array, pressed: bool) -> void:
	for keycode: Key in physical_keycodes:
		Input.parse_input_event(_key_event(keycode, pressed))


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


## 段差の側面で止まる → ジャンプで段差に乗る → 右へ進んで壁で止まる。その間スクロールしても上下の対応が崩れない
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
		absf(stopped_x + Hero.SIZE.x - WALL.position.x) < POSITION_TOLERANCE,
		"壁: 右へ進み続けても壁の左端で止まる (x = %.2f)" % stopped_x
	)
	await _hold_keys([KEY_RIGHT], 10)
	_check(absf(hero.position.x - stopped_x) < POSITION_TOLERANCE, "壁: 押し続けても壁を抜けない")
	_check(
		absf(hero.position.y + Hero.SIZE.y - Stage.GROUND_Y) < POSITION_TOLERANCE,
		"壁: 段差から降りて地面に立っている"
	)

	_check(main.scroll_x > 0.0, "スクロール: 主人公が右へ進むと画面が右へスクロールする")
	_check(
		absf(main.scroll_x - main.scroll_for(hero.position.x + Hero.SIZE.x / 2.0)) < POSITION_TOLERANCE,
		"スクロール: 主人公が画面の中央に来るスクロール量"
	)
	_check(
		absf(main.get_viewport().get_canvas_transform().origin.x + main.scroll_x) < POSITION_TOLERANCE,
		"スクロール: 上下の画面をスクロール量だけずらして映す"
	)
	_check_synced(main, "スクロール後")
	_check_terrain_mirrored(main)
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


## 下の画面の地形は、上の画面の地形と同じ形で上の画面 1 つ分だけ下にある
func _check_terrain_mirrored(main: Node2D) -> void:
	var top: Array[Node] = main.get_node("TopTerrain").get_children()
	var bottom: Array[Node] = main.get_node("BottomTerrain").get_children()
	_check(top.size() == Stage.TERRAIN.size(), "地形: 上の画面に Stage.TERRAIN の数だけ地形がある")
	_check(bottom.size() == top.size(), "地形: 下の画面に上の画面と同じ数の地形がある")
	for i: int in range(mini(top.size(), bottom.size())):
		var body: StaticBody2D = top[i]
		var top_rect: ColorRect = body.get_child(1)
		var bottom_rect: ColorRect = bottom[i]
		_check(
			bottom_rect.global_position == body.global_position + Vector2(0.0, main.SCREEN_HEIGHT),
			"地形 %d: 下の画面の地形が上の画面の地形の真下にある" % i
		)
		_check(bottom_rect.size == top_rect.size, "地形 %d: 上下の地形が同じ大きさ" % i)


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
