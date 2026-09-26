extends SceneTree
## 移動・スクロール・影の位置・攻撃・敵・体力・同期ボーナス・光源による影の反転と倍率の計算、昼・夕方・夜の
## ステージの置き方とステージの進行、入力割り当て、シーンのロードの検証。
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
## ステージ 1 本の地形と敵の出現位置の定義
const STAGE_SCRIPT := preload("res://scripts/stage.gd")
## 遊ぶ順に並べたステージの一覧
const STAGES_SCRIPT := preload("res://scripts/stages.gd")
## 往復と体力の計算を持つ敵のスクリプト
const ENEMY_SCRIPT := preload("res://scripts/enemy.gd")
## 同期ボーナスの計算
const COMBAT_SCRIPT := preload("res://scripts/combat.gd")
## 体力と無敵時間を持つ autoload のスクリプト
const GAME_STATE_SCRIPT := preload("res://scripts/game_state.gd")
## 光源による影の反転と倍率の計算
const LIGHT_SCRIPT := preload("res://scripts/light.gd")
## 反転と倍率の検証に使う光源 (倍率 1 の高さ)。ステージの光源を変えても期待値が変わらないように、検証用に置く
const TEST_LIGHTS: Array[Dictionary] = [
	{"x": 1000.0, "height": LIGHT_SCRIPT.STANDARD_HEIGHT, "zone": 200.0},
	{"x": 2000.0, "height": LIGHT_SCRIPT.STANDARD_HEIGHT / 2.0, "zone": 100.0},
]

## スクロールの検証に使うステージの横幅
const TEST_STAGE_WIDTH: float = 3200.0

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
	_check_screen_transitions()
	_check_stage_progression()
	_check_sync_hit()
	_check_light_side()
	_check_light_reversal()
	_check_shadow_scale()
	_check_stage_lights()
	_check_stage_layouts()
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
	var width: float = TEST_STAGE_WIDTH
	var max_scroll: float = width - MAIN_SCRIPT.SCREEN_WIDTH
	_check(MAIN_SCRIPT.scroll_for(100.0, width) == 0.0, "スクロール: ステージの左端では左へスクロールしない")
	_check(MAIN_SCRIPT.scroll_for(half + 300.0, width) == 300.0, "スクロール: 主人公が画面の中央に来る")
	_check(
		MAIN_SCRIPT.scroll_for(width - 10.0, width) == max_scroll,
		"スクロール: ステージの右端より先は映さない"
	)


func _check_shadow_position() -> void:
	var expected: Vector2 = Vector2(300.0, 200.0 + MAIN_SCRIPT.SCREEN_HEIGHT)
	_check(
		MAIN_SCRIPT.shadow_position(Vector2(300.0, 200.0), TEST_LIGHTS) == expected,
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


## 各ステージの敵の出現位置の並びと、画面の右端の位置に応じた出現の数
func _check_spawns() -> void:
	for stage: STAGE_SCRIPT in STAGES_SCRIPT.all():
		var label: String = "出現 (%s)" % stage.title
		var spawns: Array[Dictionary] = stage.spawns
		for i: int in range(1, spawns.size()):
			_check(spawns[i - 1]["x"] <= spawns[i]["x"], "%s: spawns が x の昇順 (%d 番目)" % [label, i])
		var first_x: float = spawns[0]["x"]
		_check(
			stage.due_spawn_count(first_x - STAGE_SCRIPT.SPAWN_AHEAD - 1.0) == 0,
			"%s: 画面の右端が出現位置の手前なら出現しない" % label
		)
		_check(
			stage.due_spawn_count(first_x - STAGE_SCRIPT.SPAWN_AHEAD) == 1,
			"%s: 画面の右端が出現位置に近づいたら出現する" % label
		)
		_check(
			stage.due_spawn_count(stage.width) == spawns.size(),
			"%s: ステージの右端まで進めば全員出現する" % label
		)
		var has_top: bool = false
		var has_bottom: bool = false
		for spawn: Dictionary in spawns:
			has_top = has_top or spawn["lane"] == COMBAT_SCRIPT.Lane.TOP
			has_bottom = has_bottom or spawn["lane"] == COMBAT_SCRIPT.Lane.BOTTOM
		_check(has_top and has_bottom, "%s: 上の画面と下の画面の両方に敵が出る" % label)


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
	_check(
		state.send(GAME_STATE_SCRIPT.Command.CONFIRM), "体力: ゲームオーバーからのやり直しはステージを作り直す"
	)
	_check(
		state.hp == GAME_STATE_SCRIPT.MAX_HP and state.is_playing(),
		"体力: ゲームオーバーからやり直すと最大値に戻ってプレイ中になる"
	)
	state.take_damage(1)
	state.reset()
	_check(
		state.hp == GAME_STATE_SCRIPT.MAX_HP and not state.is_invincible(),
		"体力: reset で最大値に戻り無敵も解ける"
	)
	state.free()


## 画面の遷移表: 各画面で受け付ける操作と移る先、ステージを作り直す遷移
func _check_screen_transitions() -> void:
	var screen: Dictionary = GAME_STATE_SCRIPT.Screen
	var command: Dictionary = GAME_STATE_SCRIPT.Command
	var cases: Array[Array] = [
		[screen.TITLE, command.CONFIRM, screen.PLAYING, false],
		[screen.TITLE, command.PAUSE, screen.TITLE, false],
		[screen.TITLE, command.QUIT, screen.TITLE, false],
		[screen.PLAYING, command.PAUSE, screen.PAUSED, false],
		[screen.PLAYING, command.CONFIRM, screen.PLAYING, false],
		[screen.PLAYING, command.QUIT, screen.PLAYING, false],
		[screen.PAUSED, command.PAUSE, screen.PLAYING, false],
		[screen.PAUSED, command.QUIT, screen.TITLE, true],
		[screen.PAUSED, command.CONFIRM, screen.PAUSED, false],
		[screen.GAME_OVER, command.CONFIRM, screen.PLAYING, true],
		[screen.GAME_OVER, command.QUIT, screen.TITLE, true],
		[screen.GAME_OVER, command.PAUSE, screen.GAME_OVER, false],
		[screen.CLEAR, command.CONFIRM, screen.PLAYING, true],
		[screen.CLEAR, command.PAUSE, screen.CLEAR, false],
		[screen.CLEAR, command.QUIT, screen.CLEAR, false],
	]
	var state: Node = GAME_STATE_SCRIPT.new()
	for case: Array in cases:
		state.screen = case[0]
		var restart: bool = state.send(case[1])
		_check(
			state.screen == case[2] and restart == case[3],
			"画面: %s で %s を操作すると %s に移り、作り直しは %s"
			% [
				screen.keys()[case[0]],
				command.keys()[case[1]],
				screen.keys()[case[2]],
				case[3],
			]
		)
	state.screen = screen.TITLE
	state.clear_stage()
	_check(state.screen == screen.TITLE, "画面: プレイ中でなければゴールに着いてもクリアにならない")
	state.screen = screen.PLAYING
	state.clear_stage()
	_check(state.screen == screen.CLEAR, "画面: プレイ中にゴールに着くとステージクリアになる")
	state.free()


## ステージの進行: ステージクリアから次のステージへ進み、最後のステージのクリアとタイトルへ戻る遷移で最初の
## ステージに戻る。ゲームオーバーからのやり直しとポーズからの再開は同じステージのまま
func _check_stage_progression() -> void:
	var screen: Dictionary = GAME_STATE_SCRIPT.Screen
	var command: Dictionary = GAME_STATE_SCRIPT.Command
	var last: int = STAGES_SCRIPT.count() - 1
	# [移る前の画面, 移る前のステージの番号, 操作, 移った先の画面, 移った後のステージの番号, 作り直すか]
	var cases: Array[Array] = [
		[screen.TITLE, 0, command.CONFIRM, screen.PLAYING, 0, false],
		[screen.CLEAR, 0, command.CONFIRM, screen.PLAYING, 1, true],
		[screen.CLEAR, last - 1, command.CONFIRM, screen.PLAYING, last, true],
		[screen.CLEAR, last, command.CONFIRM, screen.TITLE, 0, true],
		[screen.GAME_OVER, 1, command.CONFIRM, screen.PLAYING, 1, true],
		[screen.GAME_OVER, 1, command.QUIT, screen.TITLE, 0, true],
		[screen.PAUSED, 1, command.PAUSE, screen.PLAYING, 1, false],
		[screen.PAUSED, last, command.QUIT, screen.TITLE, 0, true],
	]
	var state: Node = GAME_STATE_SCRIPT.new()
	for case: Array in cases:
		state.screen = case[0]
		state.stage_index = case[1]
		var restart: bool = state.send(case[2])
		_check(
			state.screen == case[3] and state.stage_index == case[4] and restart == case[5],
			"進行: ステージ %d の %s で %s を操作するとステージ %d の %s に移り、作り直しは %s"
			% [
				case[1],
				screen.keys()[case[0]],
				command.keys()[case[2]],
				case[4],
				screen.keys()[case[3]],
				case[5],
			]
		)
		_check(
			state.current_stage().title == STAGES_SCRIPT.all()[state.stage_index].title,
			"進行: 遊んでいるステージはステージの番号のもの"
		)
	state.stage_index = 0
	_check(not state.is_last_stage(), "進行: 最初のステージは最後のステージでない")
	state.stage_index = last
	_check(state.is_last_stage(), "進行: 最後のステージは最後のステージ")
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


## 各ステージの光源の置き方と、各光源の反転区間での影の体・攻撃の範囲 (倍率ごとの見た目の長さ・リーチ)。
## 昼は影が縮む高い光源だけ、夕方は影が伸びる低い光源だけ、夜は影が縮む光源と伸びる光源が点在する
func _check_stage_lights() -> void:
	var stages: Array[STAGE_SCRIPT] = STAGES_SCRIPT.all()
	_check(stages.size() == 3, "ステージ: 昼・夕方・夜の 3 本がある")
	if stages.size() != 3:
		return
	for stage: STAGE_SCRIPT in stages:
		var lights: Array[Dictionary] = stage.lights
		for i: int in range(lights.size()):
			var light: Dictionary = lights[i]
			var label: String = "光源 (%s の %d 番目)" % [stage.title, i]
			_check(
				light["height"] > 0.0 and light["height"] <= STAGE_SCRIPT.GROUND_Y,
				"%s: 上の画面の地面と上端の間の高さ" % label
			)
			if i > 0:
				var previous: Dictionary = lights[i - 1]
				_check(
					(
						previous["x"] + previous["zone"]
						<= MAIN_SCRIPT.shadow_reverse_range(light).position.x
					),
					"%s: x の昇順で、反転区間と予兆の帯が前の光源の反転区間と重ならない" % label
				)
			_check_shadow_in_zone(light, lights, label)
	var day: Vector2i = _scale_counts(stages[0])
	_check(
		day.x > 0 and day.x == stages[0].lights.size(), "光源: 昼 (%s) は影が縮む高い光源だけ" % stages[0].title
	)
	var evening: Vector2i = _scale_counts(stages[1])
	_check(
		evening.y > 0 and evening.y == stages[1].lights.size(),
		"光源: 夕方 (%s) は影が伸びる低い光源だけ" % stages[1].title
	)
	var night: Vector2i = _scale_counts(stages[2])
	_check(
		stages[2].lights.size() >= 3 and night.x > 0 and night.y > 0,
		"光源: 夜 (%s) は影が縮む光源と伸びる光源が 3 本以上点在する" % stages[2].title
	)


## stage の光源のうち、影が縮む光源 (倍率 1 未満) の数を x、影が伸びる光源 (倍率 1 より大きい) の数を y にした値
func _scale_counts(stage: STAGE_SCRIPT) -> Vector2i:
	var counts: Vector2i = Vector2i.ZERO
	for light: Dictionary in stage.lights:
		var scale: float = LIGHT_SCRIPT.shadow_scale(light["height"])
		if scale < 1.0:
			counts.x += 1
		elif scale > 1.0:
			counts.y += 1
	return counts


## 光源が lights のステージの light の手前・またいだ瞬間・反転区間の中で、影の体と攻撃の範囲を確かめる。
## label は失敗した時に出す光源の名前
func _check_shadow_in_zone(light: Dictionary, lights: Array[Dictionary], label: String) -> void:
	var hero_size: Vector2 = HERO_SCRIPT.SIZE
	var feet_y: float = STAGE_SCRIPT.GROUND_Y
	var offset: Vector2 = Vector2(0.0, MAIN_SCRIPT.SCREEN_HEIGHT)
	var before: Vector2 = Vector2(light["x"] - 100.0 - hero_size.x / 2.0, feet_y - hero_size.y)
	_check(
		MAIN_SCRIPT.shadow_body_rect(before, lights) == Rect2(before + offset, hero_size),
		"%s: 手前では影の体が主人公と同じ大きさで真下にある" % label
	)
	_check(
		MAIN_SCRIPT.shadow_attack_area(before, 1.0, lights)
		== HERO_SCRIPT.attack_area(before + offset, 1.0, HERO_SCRIPT.ATTACK_REACH),
		"%s: 手前では影の攻撃が主人公と同じ向き・同じリーチ" % label
	)
	var crossing: Vector2 = Vector2(light["x"] - hero_size.x / 2.0, feet_y - hero_size.y)
	_check(
		MAIN_SCRIPT.shadow_position(crossing, lights) == crossing + offset,
		"%s: またいだ瞬間は影が主人公の真下にいる" % label
	)
	var scale: float = LIGHT_SCRIPT.shadow_scale(light["height"])
	var inside: Vector2 = Vector2(
		light["x"] + light["zone"] / 2.0 - hero_size.x / 2.0, feet_y - hero_size.y
	)
	var at: Vector2 = MAIN_SCRIPT.shadow_position(inside, lights)
	var body: Rect2 = MAIN_SCRIPT.shadow_body_rect(inside, lights)
	_check(
		is_equal_approx(body.size.y, hero_size.y * scale),
		"%s: 反転区間では影の見た目の長さが倍率の分だけ伸び縮みする" % label
	)
	_check(
		is_equal_approx(body.end.y, feet_y + offset.y),
		"%s: 伸び縮みしても影の足元は下の画面の地面にある" % label
	)
	var attack: Rect2 = MAIN_SCRIPT.shadow_attack_area(inside, 1.0, lights)
	_check(
		is_equal_approx(attack.size.x, HERO_SCRIPT.ATTACK_REACH * scale),
		"%s: 反転区間では影の攻撃のリーチが倍率の分だけ伸び縮みする" % label
	)
	_check(
		is_equal_approx(attack.end.x, at.x),
		"%s: 右を向いた主人公の影の攻撃は、反転区間では影の左へ出る" % label
	)


## 各ステージの地形・敵・ゴールの置き方。地形はステージの中の地面より上に x の昇順で並び、反転区間で主人公と影が
## 動く範囲は地面だけの平らな所で、敵の往復の範囲とゴールは地形と重ならない
func _check_stage_layouts() -> void:
	for stage: STAGE_SCRIPT in STAGES_SCRIPT.all():
		var obstacles: Array[Rect2] = stage.obstacles
		var goal: Rect2 = stage.goal()
		for i: int in range(obstacles.size()):
			var rect: Rect2 = obstacles[i]
			var label: String = "地形 (%s の %d 番目)" % [stage.title, i]
			_check(
				(
					rect.position.x >= 0.0
					and rect.end.x <= stage.width
					and rect.position.y >= 0.0
					and rect.end.y <= STAGE_SCRIPT.GROUND_Y
				),
				"%s: ステージの中の地面より上にある" % label
			)
			if i > 0:
				_check(obstacles[i - 1].position.x <= rect.position.x, "%s: x の昇順" % label)
			_check(not rect.intersects(goal), "%s: ゴールと重ならない" % label)
		for light: Dictionary in stage.lights:
			var band: Rect2 = MAIN_SCRIPT.shadow_reverse_range(light)
			var left: float = band.position.x - HERO_SCRIPT.SIZE.x / 2.0
			var right: float = light["x"] + light["zone"] + HERO_SCRIPT.SIZE.x / 2.0
			var moving: Rect2 = Rect2(left, 0.0, right - left, STAGE_SCRIPT.GROUND_Y)
			for rect: Rect2 in obstacles:
				_check(
					not moving.intersects(rect),
					(
						"光源 (%s の x = %d): 反転区間で主人公と影が動く範囲が地面だけの平らな所"
						% [stage.title, int(light["x"])]
					)
				)
		for spawn: Dictionary in stage.spawns:
			var patrol: Rect2 = Rect2(
				spawn["x"] - spawn["patrol"],
				spawn["floor_y"] - ENEMY_SCRIPT.SIZE.y,
				spawn["patrol"] + ENEMY_SCRIPT.SIZE.x,
				ENEMY_SCRIPT.SIZE.y
			)
			for rect: Rect2 in obstacles:
				_check(
					not patrol.intersects(rect),
					"出現 (%s の x = %d): 敵の往復の範囲が地形と重ならない" % [stage.title, int(spawn["x"])]
				)


func _check_input_map() -> void:
	for action: String in [
		"move_left", "move_right", "jump", "attack", "confirm", "pause", "quit_to_title"
	]:
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
