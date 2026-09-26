extends SceneTree
## 移動・スクロール・影の位置・攻撃・敵・体力・同期ボーナス・光源による影の反転と倍率の計算、入力割り当て、
## シーンのロードの検証。
## 実行方法は AGENTS.md を参照。release ビルドで assert が消えるため、明示的な判定と exit code で結果を返す。

## 起動検証 (main_scene の --quit) ではロードされない遷移先も含めた全シーン
const SCENES: Array[String] = [
	"res://scenes/main.tscn",
	"res://scenes/enemy.tscn",
]
## スクロール量と影の位置の計算を持つメインシーンのスクリプト
const MAIN_SCRIPT := preload("res://scripts/main.gd")
## 移動・落下の計算を持つ主人公のスクリプト
const HERO_SCRIPT := preload("res://scripts/hero.gd")
## 地形と敵の出現位置の定義
const STAGE_SCRIPT := preload("res://scripts/stage.gd")
## 往復と体力の計算を持つ敵のスクリプト
const ENEMY_SCRIPT := preload("res://scripts/enemy.gd")
## 同期ボーナスの計算
const COMBAT_SCRIPT := preload("res://scripts/combat.gd")
## 体力と無敵時間を持つ autoload のスクリプト
const GAME_STATE_SCRIPT := preload("res://scripts/game_state.gd")
## 光源による影の反転と倍率の計算
const LIGHT_SCRIPT := preload("res://scripts/light.gd")
## 反転と倍率の検証に使う光源 (倍率 1 の高さ)。Stage.LIGHTS を変えても期待値が変わらないように、検証用に置く
const TEST_LIGHTS: Array[Dictionary] = [
	{"x": 1000.0, "height": LIGHT_SCRIPT.STANDARD_HEIGHT, "zone": 200.0},
	{"x": 2000.0, "height": LIGHT_SCRIPT.STANDARD_HEIGHT / 2.0, "zone": 100.0},
]

## 検証が 1 件でも失敗したか。true なら exit code 1 で終わる
var failed: bool = false


func _initialize() -> void:
	_check_next_velocity()
	_check_scroll_for()
	_check_shadow_position()
	_check_attack_area()
	_check_spawns()
	_check_patrol()
	_check_enemy_hp()
	_check_game_state()
	_check_sync_hit()
	_check_light_side()
	_check_light_reversal()
	_check_shadow_scale()
	_check_stage_lights()
	_check_input_map()
	_check_scenes()
	if failed:
		quit(1)
	else:
		print("selfcheck OK")
		quit(0)


## cond が false なら label を ERROR として出し、失敗として記録する
func _check(cond: bool, label: String) -> void:
	if not cond:
		push_error("selfcheck FAIL: " + label)
		failed = true


func _check_next_velocity() -> void:
	var gravity_step: float = HERO_SCRIPT.GRAVITY * 0.25
	var right: Vector2 = HERO_SCRIPT.next_velocity(Vector2.ZERO, 1.0, false, true, 0.25)
	_check(right.x == HERO_SCRIPT.MOVE_SPEED, "移動: 右入力で右向きに移動の速さ")
	var left: Vector2 = HERO_SCRIPT.next_velocity(Vector2.ZERO, -1.0, false, true, 0.25)
	_check(left.x == -HERO_SCRIPT.MOVE_SPEED, "移動: 左入力で左向きに移動の速さ")
	var idle: Vector2 = HERO_SCRIPT.next_velocity(Vector2(100.0, 0.0), 0.0, false, true, 0.25)
	_check(idle.x == 0.0, "移動: 入力が無ければ横には止まる")
	var jump: Vector2 = HERO_SCRIPT.next_velocity(Vector2.ZERO, 0.0, true, true, 0.25)
	_check(jump.y == HERO_SCRIPT.JUMP_VELOCITY, "ジャンプ: 接地中のジャンプ入力で上向きの初速")
	var air_jump: Vector2 = HERO_SCRIPT.next_velocity(Vector2(0.0, -100.0), 0.0, true, false, 0.25)
	_check(air_jump.y == -100.0 + gravity_step, "ジャンプ: 空中ではジャンプできず重力で加速する")
	var falling: Vector2 = HERO_SCRIPT.next_velocity(Vector2.ZERO, 0.0, false, false, 0.25)
	_check(falling.y == gravity_step, "落下: 空中では重力で下向きに加速する")


func _check_scroll_for() -> void:
	var half: float = MAIN_SCRIPT.SCREEN_WIDTH / 2.0
	var max_scroll: float = STAGE_SCRIPT.WIDTH - MAIN_SCRIPT.SCREEN_WIDTH
	_check(MAIN_SCRIPT.scroll_for(100.0) == 0.0, "スクロール: ステージの左端では左へスクロールしない")
	_check(MAIN_SCRIPT.scroll_for(half + 300.0) == 300.0, "スクロール: 主人公が画面の中央に来る")
	_check(
		MAIN_SCRIPT.scroll_for(STAGE_SCRIPT.WIDTH - 10.0) == max_scroll,
		"スクロール: ステージの右端より先は映さない"
	)


func _check_shadow_position() -> void:
	var expected: Vector2 = Vector2(300.0, 200.0 + MAIN_SCRIPT.SCREEN_HEIGHT)
	_check(
		MAIN_SCRIPT.shadow_position(Vector2(300.0, 200.0)) == expected,
		"影: 同期中は主人公の上の画面 1 つ分下にいる"
	)


func _check_attack_area() -> void:
	var at: Vector2 = Vector2(100.0, 200.0)
	var right: Rect2 = HERO_SCRIPT.attack_area(at, 1.0, HERO_SCRIPT.ATTACK_REACH)
	_check(right.position.x == at.x + HERO_SCRIPT.SIZE.x, "攻撃: 右向きなら体の右端から前に出る")
	var left: Rect2 = HERO_SCRIPT.attack_area(at, -1.0, HERO_SCRIPT.ATTACK_REACH)
	_check(left.end.x == at.x, "攻撃: 左向きなら体の左端から前に出る")
	var enemy_on_ground: Rect2 = Rect2(
		at.x + HERO_SCRIPT.SIZE.x + 10.0,
		at.y + HERO_SCRIPT.SIZE.y - ENEMY_SCRIPT.SIZE.y,
		ENEMY_SCRIPT.SIZE.x,
		ENEMY_SCRIPT.SIZE.y
	)
	_check(right.intersects(enemy_on_ground), "攻撃: 同じ地面に立つ目の前の敵に届く")
	_check(not left.intersects(enemy_on_ground), "攻撃: 背中側の敵には届かない")


func _check_spawns() -> void:
	var spawns: Array[Dictionary] = STAGE_SCRIPT.SPAWNS
	for i: int in range(1, spawns.size()):
		_check(spawns[i - 1]["x"] <= spawns[i]["x"], "出現: SPAWNS が x の昇順 (%d 番目)" % i)
	var first_x: float = spawns[0]["x"]
	_check(
		STAGE_SCRIPT.due_spawn_count(first_x - STAGE_SCRIPT.SPAWN_AHEAD - 1.0) == 0,
		"出現: 画面の右端が出現位置の手前なら出現しない"
	)
	_check(
		STAGE_SCRIPT.due_spawn_count(first_x - STAGE_SCRIPT.SPAWN_AHEAD) == 1,
		"出現: 画面の右端が出現位置に近づいたら出現する"
	)
	_check(
		STAGE_SCRIPT.due_spawn_count(STAGE_SCRIPT.WIDTH) == spawns.size(),
		"出現: ステージの右端まで進めば全員出現する"
	)
	var has_top: bool = false
	var has_bottom: bool = false
	for spawn: Dictionary in spawns:
		has_top = has_top or spawn["lane"] == COMBAT_SCRIPT.Lane.TOP
		has_bottom = has_bottom or spawn["lane"] == COMBAT_SCRIPT.Lane.BOTTOM
	_check(has_top and has_bottom, "出現: 上の画面と下の画面の両方に敵が出る")


func _check_patrol() -> void:
	var walking: Vector2 = ENEMY_SCRIPT.patrol_step(150.0, -1.0, 100.0, 200.0, 0.5)
	_check(walking == Vector2(150.0 - ENEMY_SCRIPT.SPEED * 0.5, -1.0), "往復: 向きに速さ × 時間だけ進む")
	var left_end: Vector2 = ENEMY_SCRIPT.patrol_step(110.0, -1.0, 100.0, 200.0, 0.5)
	_check(left_end == Vector2(100.0, 1.0), "往復: 左端で止まって右へ折り返す")
	var right_end: Vector2 = ENEMY_SCRIPT.patrol_step(190.0, 1.0, 100.0, 200.0, 0.5)
	_check(right_end == Vector2(200.0, -1.0), "往復: 右端で止まって左へ折り返す")
	var still: Vector2 = ENEMY_SCRIPT.patrol_step(100.0, -1.0, 100.0, 100.0, 0.5)
	_check(still.x == 100.0, "往復: 幅 0 ならその場から動かない")


## tree には入れず (_ready を走らせず) 体力の計算だけを確認して free する
func _check_enemy_hp() -> void:
	var enemy: Node2D = ENEMY_SCRIPT.new()
	var hits_to_defeat: int = 0
	while hits_to_defeat < ENEMY_SCRIPT.MAX_HP and not enemy.take_hit(COMBAT_SCRIPT.BASE_DAMAGE):
		hits_to_defeat += 1
	_check(hits_to_defeat + 1 == ENEMY_SCRIPT.MAX_HP, "敵: 通常の攻撃を体力の回数だけ当てると倒れる")
	enemy.free()
	var synced: Node2D = ENEMY_SCRIPT.new()
	_check(synced.take_hit(COMBAT_SCRIPT.hit_damage(true)), "敵: 同期ボーナスの攻撃 1 回で倒れる")
	synced.free()


## autoload とは別のインスタンスで、体力・無敵時間・ゲームオーバーの遷移を確認して free する
func _check_game_state() -> void:
	var state: Node = GAME_STATE_SCRIPT.new()
	_check(state.hp == GAME_STATE_SCRIPT.MAX_HP, "体力: 最初は最大値")
	_check(state.take_damage(1), "体力: ダメージを受ける")
	_check(state.hp == GAME_STATE_SCRIPT.MAX_HP - 1, "体力: ダメージの分だけ減る")
	_check(not state.take_damage(1), "体力: 被弾直後の無敵の間はダメージを受けない")
	state.tick(GAME_STATE_SCRIPT.INVINCIBLE_TIME)
	_check(state.take_damage(1), "体力: 無敵時間が過ぎたらまたダメージを受ける")
	while not state.is_game_over():
		state.tick(GAME_STATE_SCRIPT.INVINCIBLE_TIME)
		if not state.take_damage(1):
			break
	_check(state.hp == 0 and state.is_game_over(), "体力: 0 になったらゲームオーバー")
	state.tick(GAME_STATE_SCRIPT.INVINCIBLE_TIME)
	_check(not state.take_damage(1) and state.hp == 0, "体力: ゲームオーバー後は 0 より減らない")
	state.reset()
	_check(
		state.hp == GAME_STATE_SCRIPT.MAX_HP and not state.is_game_over(), "体力: reset で最大値に戻る"
	)
	state.free()


## 同時とみなす時間幅の内側・ちょうど・外側の境界
func _check_sync_hit() -> void:
	var window: float = COMBAT_SCRIPT.SYNC_WINDOW
	_check(COMBAT_SCRIPT.is_sync_hit(1.0, 1.0), "同期: 上下が同じ時刻に当たれば同時")
	_check(COMBAT_SCRIPT.is_sync_hit(0.0, window), "同期: 時間幅ちょうどの差 (下が遅い) は同時")
	_check(COMBAT_SCRIPT.is_sync_hit(window, 0.0), "同期: 時間幅ちょうどの差 (上が遅い) は同時")
	_check(COMBAT_SCRIPT.is_sync_hit(0.0, window * 0.5), "同期: 時間幅の内側の差は同時")
	_check(not COMBAT_SCRIPT.is_sync_hit(0.0, window + 0.001), "同期: 時間幅を越える差は同時でない")
	_check(not COMBAT_SCRIPT.is_sync_hit(window + 0.001, 0.0), "同期: 上が時間幅を越えて遅い時も同時でない")
	_check(not COMBAT_SCRIPT.is_sync_hit(1.0, -1.0), "同期: 下の画面で当たっていなければ同時でない")
	_check(not COMBAT_SCRIPT.is_sync_hit(-1.0, 1.0), "同期: 上の画面で当たっていなければ同時でない")
	_check(COMBAT_SCRIPT.hit_damage(false) == COMBAT_SCRIPT.BASE_DAMAGE, "同期: ボーナスなしは通常のダメージ")
	_check(
		COMBAT_SCRIPT.hit_damage(true) == COMBAT_SCRIPT.BASE_DAMAGE * COMBAT_SCRIPT.SYNC_MULTIPLIER,
		"同期: ボーナスありは倍率を掛けたダメージ"
	)
	_check(
		COMBAT_SCRIPT.hit_damage(false) + COMBAT_SCRIPT.sync_extra_damage()
		== COMBAT_SCRIPT.hit_damage(true),
		"同期: 先に通常のダメージで当たった敵も、足すダメージでボーナスありと同じダメージになる"
	)


## 光源の左 (手前)・真下・右 (またいだ先) の判定
func _check_light_side() -> void:
	_check(LIGHT_SCRIPT.side_of(1000.0, 999.0) == -1.0, "光源: 光源より左にいれば左側")
	_check(LIGHT_SCRIPT.side_of(1000.0, 1000.0) == 1.0, "光源: 光源の真下はまたいだ側 (右側)")
	_check(LIGHT_SCRIPT.side_of(1000.0, 1001.0) == 1.0, "光源: 光源より右にいれば右側")


## 倍率 1 の光源 (TEST_LIGHTS の 1 つ目) の手前・反転区間・出口の先で、主人公の体の中心の x を入力に
## 影の体の中心の x と向きを確かめる
func _check_light_reversal() -> void:
	_check(LIGHT_SCRIPT.shadow_center_x(900.0, TEST_LIGHTS) == 900.0, "反転: 光源の手前では影が主人公と同じ位置")
	_check(LIGHT_SCRIPT.shadow_direction(900.0, TEST_LIGHTS) == 1.0, "反転: 光源の手前では影が主人公と同じ向き")
	_check(
		LIGHT_SCRIPT.shadow_center_x(1000.0, TEST_LIGHTS) == 1000.0,
		"反転: 光源をまたいだ瞬間は影が主人公と同じ位置 (位置が飛ばない)"
	)
	_check(LIGHT_SCRIPT.shadow_center_x(1100.0, TEST_LIGHTS) == 900.0, "反転: 反転区間では光源の x を軸に逆側にいる")
	_check(
		LIGHT_SCRIPT.shadow_center_x(1150.0, TEST_LIGHTS) == 850.0,
		"反転: 反転区間で主人公が右へ 50 進むと影は左へ 50 進む"
	)
	_check(LIGHT_SCRIPT.shadow_direction(1100.0, TEST_LIGHTS) == -1.0, "反転: 反転区間では影が主人公と逆向き")
	_check(
		LIGHT_SCRIPT.active_light(1100.0, TEST_LIGHTS) == TEST_LIGHTS[0],
		"反転: 反転区間にいる光源が有効になる"
	)
	_check(
		LIGHT_SCRIPT.shadow_center_x(1199.0, TEST_LIGHTS) == 801.0, "反転: 反転区間の出口の手前まで逆側にいる"
	)
	_check(
		LIGHT_SCRIPT.shadow_center_x(1200.0, TEST_LIGHTS) == 1200.0,
		"反転: 反転区間を抜けたら影が主人公と同じ位置に戻る"
	)
	_check(LIGHT_SCRIPT.shadow_direction(1200.0, TEST_LIGHTS) == 1.0, "反転: 反転区間を抜けたら同じ向きに戻る")
	_check(
		LIGHT_SCRIPT.active_light(1500.0, TEST_LIGHTS).is_empty(), "反転: 反転区間の外では有効な光源がない"
	)
	_check(LIGHT_SCRIPT.shadow_scale_at(1500.0, TEST_LIGHTS) == 1.0, "倍率: 反転区間の外は 1")


## 光源の高さから決まる倍率と、倍率ごとの影の移動量
func _check_shadow_scale() -> void:
	var standard: float = LIGHT_SCRIPT.STANDARD_HEIGHT
	_check(LIGHT_SCRIPT.shadow_scale(standard) == 1.0, "倍率: 基準の高さの光源では 1")
	_check(LIGHT_SCRIPT.shadow_scale(standard / 2.0) == 2.0, "倍率: 半分の高さの低い光源では影が 2 倍に伸びる")
	_check(LIGHT_SCRIPT.shadow_scale(standard * 2.0) == 0.5, "倍率: 2 倍の高さの高い光源では影が半分に縮む")
	_check(LIGHT_SCRIPT.shadow_scale(standard / 1.25) == 1.25, "倍率: 高さに反比例する")
	_check(LIGHT_SCRIPT.shadow_scale(1.0) == LIGHT_SCRIPT.MAX_SCALE, "倍率: 地面すれすれの光源でも上限で止まる")
	_check(
		LIGHT_SCRIPT.shadow_scale(100000.0) == LIGHT_SCRIPT.MIN_SCALE, "倍率: 真上の光源でも下限で止まる"
	)
	_check(LIGHT_SCRIPT.shadow_scale_at(2020.0, TEST_LIGHTS) == 2.0, "倍率: 反転区間では光源の高さの倍率")
	var moved: float = (
		LIGHT_SCRIPT.shadow_center_x(2050.0, TEST_LIGHTS)
		- LIGHT_SCRIPT.shadow_center_x(2020.0, TEST_LIGHTS)
	)
	_check(moved == -60.0, "移動量: 倍率 2 の反転区間で主人公が右へ 30 進むと影は左へ 60 進む")
	var standard_moved: float = (
		LIGHT_SCRIPT.shadow_center_x(1150.0, TEST_LIGHTS)
		- LIGHT_SCRIPT.shadow_center_x(1120.0, TEST_LIGHTS)
	)
	_check(standard_moved == -30.0, "移動量: 倍率 1 の反転区間で主人公が右へ 30 進むと影は左へ 30 進む")


## Stage.LIGHTS の置き方と、各光源の反転区間での影の体・攻撃の範囲 (倍率ごとの見た目の長さ・リーチ)
func _check_stage_lights() -> void:
	var lights: Array[Dictionary] = STAGE_SCRIPT.LIGHTS
	var has_short: bool = false
	var has_long: bool = false
	for i: int in range(lights.size()):
		var light: Dictionary = lights[i]
		var scale: float = LIGHT_SCRIPT.shadow_scale(light["height"])
		has_short = has_short or scale < 1.0
		has_long = has_long or scale > 1.0
		_check(
			light["height"] > 0.0 and light["height"] <= STAGE_SCRIPT.GROUND_Y,
			"光源 %d: 上の画面の地面と上端の間の高さ" % i
		)
		if i > 0:
			_check(
				lights[i - 1]["x"] + lights[i - 1]["zone"] <= light["x"],
				"光源 %d: x の昇順で、反転区間が前の光源の反転区間と重ならない" % i
			)
		_check_shadow_in_zone(light, i)
	_check(has_short and has_long, "光源: 影が縮む高い光源と、影が伸びる低い光源の両方がある")


## light (Stage.LIGHTS の i 番目) の手前・またいだ瞬間・反転区間の中で、影の体と攻撃の範囲を確かめる
func _check_shadow_in_zone(light: Dictionary, i: int) -> void:
	var hero_size: Vector2 = HERO_SCRIPT.SIZE
	var feet_y: float = STAGE_SCRIPT.GROUND_Y
	var offset: Vector2 = Vector2(0.0, MAIN_SCRIPT.SCREEN_HEIGHT)
	var before: Vector2 = Vector2(light["x"] - 100.0 - hero_size.x / 2.0, feet_y - hero_size.y)
	_check(
		MAIN_SCRIPT.shadow_body_rect(before) == Rect2(before + offset, hero_size),
		"光源 %d: 手前では影の体が主人公と同じ大きさで真下にある" % i
	)
	_check(
		MAIN_SCRIPT.shadow_attack_area(before, 1.0)
		== HERO_SCRIPT.attack_area(before + offset, 1.0, HERO_SCRIPT.ATTACK_REACH),
		"光源 %d: 手前では影の攻撃が主人公と同じ向き・同じリーチ" % i
	)
	var crossing: Vector2 = Vector2(light["x"] - hero_size.x / 2.0, feet_y - hero_size.y)
	_check(
		MAIN_SCRIPT.shadow_position(crossing) == crossing + offset,
		"光源 %d: またいだ瞬間は影が主人公の真下にいる" % i
	)
	var scale: float = LIGHT_SCRIPT.shadow_scale(light["height"])
	var inside: Vector2 = Vector2(
		light["x"] + light["zone"] / 2.0 - hero_size.x / 2.0, feet_y - hero_size.y
	)
	var at: Vector2 = MAIN_SCRIPT.shadow_position(inside)
	var body: Rect2 = MAIN_SCRIPT.shadow_body_rect(inside)
	_check(
		is_equal_approx(body.size.y, hero_size.y * scale),
		"光源 %d: 反転区間では影の見た目の長さが倍率の分だけ伸び縮みする" % i
	)
	_check(
		is_equal_approx(body.end.y, feet_y + offset.y),
		"光源 %d: 伸び縮みしても影の足元は下の画面の地面にある" % i
	)
	var attack: Rect2 = MAIN_SCRIPT.shadow_attack_area(inside, 1.0)
	_check(
		is_equal_approx(attack.size.x, HERO_SCRIPT.ATTACK_REACH * scale),
		"光源 %d: 反転区間では影の攻撃のリーチが倍率の分だけ伸び縮みする" % i
	)
	_check(
		is_equal_approx(attack.end.x, at.x),
		"光源 %d: 右を向いた主人公の影の攻撃は、反転区間では影の左へ出る" % i
	)


func _check_input_map() -> void:
	for action: String in ["move_left", "move_right", "jump", "attack"]:
		_check(InputMap.has_action(action), "InputMap: %s アクションがある" % action)
		var has_key: bool = false
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey:
				has_key = true
		_check(has_key, "InputMap: %s にキーが割り当てられている" % action)


## tree には入れず (_ready を走らせず) インスタンス化だけを確認して free する
func _check_scenes() -> void:
	for path: String in SCENES:
		var scene: PackedScene = load(path)
		_check(scene != null, "シーン: %s をロードできる" % path)
		if scene == null:
			continue
		var instance: Node = scene.instantiate()
		_check(instance != null, "シーン: %s をインスタンス化できる" % path)
		if instance != null:
			instance.free()
