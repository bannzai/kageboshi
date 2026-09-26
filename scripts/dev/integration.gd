extends SceneTree
## キー入力 (InputMap を通る InputEventKey) でメインシーンの主人公を動かし、地形との当たり判定・スクロールと、
## 下の画面の影が同じ動きをすることを検証する。実行方法は AGENTS.md を参照。失敗したら quit(1) で終わる。

## 地形の定義 (段差・壁の位置の期待値に使う)
const Stage := preload("res://scripts/stage.gd")
## 主人公のスクリプト (体の大きさ)
const Hero := preload("res://scripts/hero.gd")
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
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait_physics_frames(2)
	await _check_move_and_jump(main)
	await _check_terrain_and_scroll(main)
	main.queue_free()
	await process_frame
	if failed:
		quit(1)
	else:
		print("integration OK")
		quit(0)


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
