extends "res://scripts/dev/headless_check.gd"
## 移動・スクロール・影の位置・攻撃・敵・体力・同期ボーナス・光源による影の反転と倍率・影縫い・引き寄せの計算、
## 空を飛ぶ敵の揺れと置き方 (scripts/dev/selfcheck_flyer.gd)、昼・夕方・夜のステージの置き方とステージの進行、
## 入力割り当て、設定と進行の保存・読み込み (壊れた保存データの扱いを含む)、シーンのロード、ステージごとの BGM の繰り返しと BGM・効果音を鳴らすバス、全素材が
## assets/CREDITS.md に記録されていることの検証。
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
## 空を飛ぶ敵の揺れ・見た目と、各ステージの空を飛ぶ敵の置き方の検証
const FLYER_CHECKS := preload("res://scripts/dev/selfcheck_flyer.gd")
## 同期ボーナスの計算
const COMBAT_SCRIPT := preload("res://scripts/combat.gd")
## 体力と無敵時間・影縫いのゲージを持つ autoload のスクリプト
const GAME_STATE_SCRIPT := preload("res://scripts/game_state.gd")
## 影縫いと引き寄せの計算
const STITCH_SCRIPT := preload("res://scripts/shadow_stitch.gd")
## 光源による影の反転と倍率の計算
const LIGHT_SCRIPT := preload("res://scripts/light.gd")
## 反転と倍率の検証に使う光源 (倍率 1 の高さ)。ステージの光源を変えても期待値が変わらないように、検証用に置く
const TEST_LIGHTS: Array[Dictionary] = [
	{"x": 1000.0, "height": LIGHT_SCRIPT.STANDARD_HEIGHT, "zone": 200.0},
	{"x": 2000.0, "height": LIGHT_SCRIPT.STANDARD_HEIGHT / 2.0, "zone": 100.0},
]
## 設定と進行の保存・読み込みを持つ autoload のスクリプト
const SAVE_DATA_SCRIPT := preload("res://scripts/save_data.gd")
## project.godot で定義したゲームのアクション (キー割り当てを変えられるアクション)
const GAME_ACTIONS: Array[String] = [
	"move_left",
	"move_right",
	"jump",
	"attack",
	"confirm",
	"pause",
	"quit_to_title",
	"pin_shadow",
	"pin_hero",
	"pull_shadow",
	"open_settings",
]
## 保存・読み込みの検証で書き出す保存データ。プレイヤーの保存データ (user://) を書き換えないよう tmp/ に置く
const SAVE_TEST_PATH: String = "res://tmp/selfcheck-save.json"
## ステージごとの BGM
const STAGE_BGM_SCRIPT := preload("res://scripts/stage_bgm.gd")
## メインシーンの効果音のノード (Audio の下) の名前
const SOUND_EFFECTS: Array[String] = ["Attack", "Damage", "Sync", "Stitch"]
## 素材の置き場所
const ASSETS_DIR: String = "res://assets"
## 素材の記録。ASSETS_DIR の下の全素材を、ASSETS_DIR からの相対パスをバッククォートで囲んで書く
const CREDITS_PATH: String = "res://assets/CREDITS.md"

## スクロールと影縫いのずれの検証に使うステージの横幅
const TEST_STAGE_WIDTH: float = 3200.0


func _initialize() -> void:
	_check_next_velocity()
	_check_scroll_for()
	_check_shadow_position()
	_check_attack_area()
	_check_body_animation()
	_check_spawns()
	_check_patrol()
	_check_enemy_hp()
	_check_game_state()
	_check_screen_transitions()
	_check_stage_progression()
	_check_sync_hit()
	_check_gauge()
	_check_next_pin()
	_check_stitch_offset()
	_check_light_side()
	_check_light_reversal()
	_check_shadow_scale()
	_check_stage_lights()
	_check_stage_layouts()
	for label: String in FLYER_CHECKS.new().run():
		_check(false, label)
	_check_shadow_with_offset()
	_check_input_map()
	_check_save_parse()
	_check_rebound()
	_check_save_file()
	_check_scenes()
	_check_audio()
	_check_credits()
	if failed:
		quit(1)
	else:
		print("selfcheck OK")
		quit(0)


## 保存の検証でクリアしたステージとして書くステージの ID (最初のステージの ID)
func _first_stage_id() -> String:
	return STAGES_SCRIPT.all()[0].id


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


## 主人公の体の見た目は攻撃・空中 (上昇と落下)・歩き・待機の姿になり、影は反転区間でだけ主人公と逆を向く
func _check_body_animation() -> void:
	var cases: Array[Array] = [
		[true, false, Vector2(0.0, -100.0), &"attack"],
		[false, false, Vector2(100.0, -100.0), &"jump"],
		[false, false, Vector2(100.0, 100.0), &"fall"],
		[false, true, Vector2(-100.0, 0.0), &"walk"],
		[false, true, Vector2.ZERO, &"idle"],
	]
	for c: Array in cases:
		_check(HERO_SCRIPT.body_animation(c[0], c[1], c[2]) == c[3], "見た目: %s の姿を選ぶ" % c[3])
	var in_zone: Vector2 = Vector2(TEST_LIGHTS[0]["x"], 0.0)
	_check(MAIN_SCRIPT.shadow_facing(in_zone, 1.0, TEST_LIGHTS) == -1.0, "見た目: 反転区間の影は逆を向く")
	_check(MAIN_SCRIPT.shadow_facing(Vector2.ZERO, -1.0, TEST_LIGHTS) == -1.0, "見た目: 区間外は同じ向き")


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


## autoload とは別のインスタンスで、主人公と影それぞれの体力・無敵時間と、どちらかの体力が 0 になった時の
## ゲームオーバーの遷移を確認して free する
func _check_game_state() -> void:
	var top: COMBAT_SCRIPT.Lane = COMBAT_SCRIPT.Lane.TOP
	var bottom: COMBAT_SCRIPT.Lane = COMBAT_SCRIPT.Lane.BOTTOM
	var full: int = GAME_STATE_SCRIPT.MAX_HP
	var state: Node = GAME_STATE_SCRIPT.new()
	_check(_hp_is(state, full, full), "体力: 主人公も影も最初は最大値")
	_check(state.take_damage(top, 1), "体力: 上の画面で被弾すると主人公がダメージを受ける")
	_check(_hp_is(state, full - 1, full), "体力: 上の画面の被弾は主人公の体力だけを減らす")
	_check(not state.take_damage(top, 1), "体力: 被弾直後の主人公は無敵の間ダメージを受けない")
	_check(state.take_damage(bottom, 1), "体力: 無敵時間は体ごとで、主人公が無敵の間も影は被弾する")
	_check(_hp_is(state, full - 1, full - 1), "体力: 下の画面の被弾は影の体力だけを減らす")
	state.tick(GAME_STATE_SCRIPT.INVINCIBLE_TIME)
	_check(state.take_damage(top, 1), "体力: 無敵時間が過ぎたらまたダメージを受ける")
	while state.take_damage(bottom, 1):
		state.tick(GAME_STATE_SCRIPT.INVINCIBLE_TIME)
	_check(
		state.is_game_over() and _hp_is(state, full - 2, 0),
		"体力: 主人公の体力が残っていても影の体力が 0 になったらゲームオーバー"
	)
	state.tick(GAME_STATE_SCRIPT.INVINCIBLE_TIME)
	_check(
		not state.take_damage(top, 1) and _hp_is(state, full - 2, 0), "体力: ゲームオーバー後は減らない"
	)
	_check(
		state.send(GAME_STATE_SCRIPT.Command.CONFIRM), "体力: ゲームオーバーからのやり直しはステージを作り直す"
	)
	_check(
		_hp_is(state, full, full) and state.is_playing(),
		"体力: ゲームオーバーからやり直すと主人公も影も最大値に戻ってプレイ中になる"
	)
	while state.take_damage(top, 1):
		state.tick(GAME_STATE_SCRIPT.INVINCIBLE_TIME)
	_check(
		state.is_game_over() and _hp_is(state, 0, full),
		"体力: 影の体力が残っていても主人公の体力が 0 になったらゲームオーバー"
	)
	state.send(GAME_STATE_SCRIPT.Command.CONFIRM)
	state.take_damage(top, 1)
	state.take_damage(bottom, 1)
	state.reset()
	_check(
		_hp_is(state, full, full) and not state.is_invincible(top) and not state.is_invincible(bottom),
		"体力: reset で主人公も影も最大値に戻り無敵も解ける"
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
		[screen.TITLE, command.SETTINGS, screen.SETTINGS, false],
		[screen.TITLE, command.BACK, screen.TITLE, false],
		[screen.PLAYING, command.SETTINGS, screen.PLAYING, false],
		[screen.PAUSED, command.SETTINGS, screen.PAUSED, false],
		[screen.PAUSED, command.BACK, screen.PAUSED, false],
		[screen.SETTINGS, command.BACK, screen.TITLE, false],
		[screen.SETTINGS, command.CONFIRM, screen.SETTINGS, false],
		[screen.SETTINGS, command.PAUSE, screen.SETTINGS, false],
		[screen.SETTINGS, command.QUIT, screen.SETTINGS, false],
		[screen.SETTINGS, command.SETTINGS, screen.SETTINGS, false],
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
	_check(not state.clear_stage(), "画面: プレイ中でなければゴールに着いてもクリアにならない (false を返す)")
	_check(state.screen == screen.TITLE, "画面: プレイ中でなければゴールに着いてもクリアにならない")
	state.screen = screen.PLAYING
	_check(state.clear_stage(), "画面: プレイ中にゴールに着くとステージクリアになる (true を返す)")
	_check(state.screen == screen.CLEAR, "画面: プレイ中にゴールに着くとステージクリアになる")
	_check(not state.clear_stage(), "画面: ステージクリアの後にゴールに触れ続けても、もう一度はクリアしない")
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


## autoload とは別のインスタンスで、ゲージの消費・ゲージ切れ・回復を確認して free する
func _check_gauge() -> void:
	var state: Node = GAME_STATE_SCRIPT.new()
	var full_time: float = GAME_STATE_SCRIPT.MAX_GAUGE / GAME_STATE_SCRIPT.GAUGE_DRAIN
	_check(state.gauge == GAME_STATE_SCRIPT.MAX_GAUGE and state.has_gauge(), "ゲージ: 最初は満タン")
	state.spend_gauge(full_time / 2.0)
	_check(
		is_equal_approx(state.gauge, GAME_STATE_SCRIPT.MAX_GAUGE / 2.0),
		"ゲージ: 縫い止められる時間の半分でゲージが半分に減る"
	)
	state.spend_gauge(full_time)
	_check(state.gauge == 0.0 and not state.has_gauge(), "ゲージ: 使い切ると 0 で止まり縫い止められない")
	state.recover_gauge(1.0)
	_check(
		is_equal_approx(state.gauge, GAME_STATE_SCRIPT.GAUGE_RECOVER) and state.has_gauge(),
		"ゲージ: 同期している間に回復する"
	)
	state.recover_gauge(GAME_STATE_SCRIPT.MAX_GAUGE / GAME_STATE_SCRIPT.GAUGE_RECOVER)
	_check(state.gauge == GAME_STATE_SCRIPT.MAX_GAUGE, "ゲージ: 回復は最大値で止まる")
	state.spend_gauge(full_time)
	state.reset()
	_check(state.gauge == GAME_STATE_SCRIPT.MAX_GAUGE, "ゲージ: reset で満タンに戻る")
	state.free()


## 縫い止めの開始・継続・解除と、引き寄せ・ゲージ切れの間は縫い止めないこと。
## 各行は [前の縫い止め, 影縫いを押した瞬間, 押している, 逆の操作を押した瞬間, 押している,
## 引き寄せの途中, ゲージが残っている, 期待する縫い止め, 検証の内容]
func _check_next_pin() -> void:
	var none: int = STITCH_SCRIPT.Pin.NONE
	var shadow: int = STITCH_SCRIPT.Pin.SHADOW
	var hero: int = STITCH_SCRIPT.Pin.HERO
	var cases: Array[Array] = [
		[none, false, false, false, false, false, true, none, "押さなければ同期のまま"],
		[none, true, true, false, false, false, true, shadow, "影縫いを押すと影を縫い止める"],
		[shadow, false, true, false, false, false, true, shadow, "押している間は続く"],
		[shadow, false, false, false, false, false, true, none, "離すと解除する"],
		[none, false, false, true, true, false, true, hero, "逆の操作で主人公を止める"],
		[hero, false, false, false, true, false, true, hero, "逆の操作も押している間は続く"],
		[none, false, true, false, false, false, true, none, "押しっぱなしでは始まらない"],
		[shadow, false, true, false, false, false, false, none, "ゲージ切れで解除する"],
		[none, true, true, false, false, false, false, none, "ゲージが無ければ始まらない"],
		[shadow, false, true, false, false, true, true, none, "引き寄せると解除する"],
	]
	for row: Array in cases:
		var next: int = STITCH_SCRIPT.next_pin(
			row[0], row[1], row[2], row[3], row[4], row[5], row[6]
		)
		_check(next == row[7], "縫い止め: " + row[8])


## 縫い止め・影だけの移動・解除・引き寄せで、影のずれが期待どおりに変わること
func _check_stitch_offset() -> void:
	var synced: Vector2 = Vector2(1000.0, 256.0 + MAIN_SCRIPT.SCREEN_HEIGHT)
	var pinned: Vector2 = Vector2(900.0, 200.0 + MAIN_SCRIPT.SCREEN_HEIGHT)
	_check(
		STITCH_SCRIPT.pinned_offset(pinned, synced, TEST_STAGE_WIDTH) == pinned - synced,
		"ずれ: 縫い止めた影は縫い止めた位置に残る"
	)
	var far: Vector2 = synced + Vector2(-STITCH_SCRIPT.MAX_OFFSET - 100.0, 0.0)
	_check(
		STITCH_SCRIPT.pinned_offset(far, synced, TEST_STAGE_WIDTH).x == -STITCH_SCRIPT.MAX_OFFSET,
		"ずれ: 影は主人公から離れられる距離より遠くへは残らない"
	)
	var at_left: Vector2 = Vector2(100.0, synced.y)
	_check(
		STITCH_SCRIPT.clamp_offset(Vector2(-300.0, 0.0), at_left, TEST_STAGE_WIDTH).x == -at_left.x,
		"ずれ: 影はステージの左端より外に出ない"
	)
	var at_right: Vector2 = Vector2(TEST_STAGE_WIDTH - HERO_SCRIPT.SIZE.x - 100.0, synced.y)
	_check(
		STITCH_SCRIPT.clamp_offset(Vector2(300.0, 0.0), at_right, TEST_STAGE_WIDTH).x == 100.0,
		"ずれ: 影はステージの右端より外に出ない"
	)
	var run: Vector2 = STITCH_SCRIPT.running_offset(Vector2.ZERO, 1.0, synced, 0.25, TEST_STAGE_WIDTH)
	_check(
		run == Vector2(HERO_SCRIPT.MOVE_SPEED * 0.25, 0.0),
		"ずれ: 主人公を止めている間は影だけが左右入力で主人公の速さで動く"
	)
	_check(
		STITCH_SCRIPT.released_offset(Vector2(-120.0, -80.0)) == Vector2(-120.0, 0.0),
		"ずれ: 縫い止めを解くと横のずれだけが残る"
	)
	var pull_step: float = STITCH_SCRIPT.PULL_SPEED * 0.1
	_check(
		STITCH_SCRIPT.pulled_offset(Vector2(-300.0, 0.0), 0.1).is_equal_approx(
			Vector2(-300.0 + pull_step, 0.0)
		),
		"引き寄せ: 引き寄せの速さで主人公へ近づく"
	)
	_check(
		STITCH_SCRIPT.pulled_offset(Vector2(-10.0, 0.0), 0.1) == Vector2.ZERO,
		"引き寄せ: ずれが 1 フレームで縮む距離より小さければちょうど同期に戻る"
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
					"%s: x の昇順で、反転区間と影が逆へ動く範囲が前の光源の反転区間と重ならない" % label
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
			var reverse_range: Rect2 = MAIN_SCRIPT.shadow_reverse_range(light)
			var left: float = reverse_range.position.x - HERO_SCRIPT.SIZE.x / 2.0
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
			var patrol: Rect2 = ENEMY_SCRIPT.patrol_area(
				STAGE_SCRIPT.spawn_kind(spawn), spawn["x"], spawn["floor_y"], spawn["patrol"]
			)
			for rect: Rect2 in obstacles:
				_check(
					not patrol.intersects(rect),
					"出現 (%s の x = %d): 敵の往復の範囲が地形と重ならない" % [stage.title, int(spawn["x"])]
				)


## 影縫いのずれがある時の影の体・攻撃の範囲は、同期中の影の体・攻撃の範囲をずれの分だけ動かしたもので、
## 大きさ・向きは主人公がいる光源の反転区間で決まる (最初のステージの最初の光源の反転区間の中で確かめる)
func _check_shadow_with_offset() -> void:
	var lights: Array[Dictionary] = STAGES_SCRIPT.all()[0].lights
	var light: Dictionary = lights[0]
	var inside: Vector2 = Vector2(
		light["x"] + light["zone"] / 2.0 - HERO_SCRIPT.SIZE.x / 2.0,
		STAGE_SCRIPT.GROUND_Y - HERO_SCRIPT.SIZE.y
	)
	var offset: Vector2 = Vector2(-120.0, 0.0)
	var body: Rect2 = MAIN_SCRIPT.shadow_body_rect(inside, lights)
	_check(
		MAIN_SCRIPT.shadow_body_rect(inside, lights, offset).is_equal_approx(
			Rect2(body.position + offset, body.size)
		),
		"影縫いと光源: ずれた影の体は、反転区間の同期中の影の体をずれの分だけ動かした位置と大きさ"
	)
	var attack: Rect2 = MAIN_SCRIPT.shadow_attack_area(inside, 1.0, lights)
	_check(
		MAIN_SCRIPT.shadow_attack_area(inside, 1.0, lights, offset).is_equal_approx(
			Rect2(attack.position + offset, attack.size)
		),
		"影縫いと光源: ずれた影の攻撃は、反転区間の同期中の影の攻撃をずれの分だけ動かした向き・リーチ"
	)
	_check(
		MAIN_SCRIPT.shadow_body_rect(inside, lights, Vector2.ZERO) == body,
		"影縫いと光源: ずれが 0 なら影の体は同期中と同じ"
	)


func _check_input_map() -> void:
	for action: String in GAME_ACTIONS:
		_check(InputMap.has_action(action), "InputMap: %s アクションがある" % action)
		var has_key: bool = false
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey:
				has_key = true
		_check(has_key, "InputMap: %s にキーが割り当てられている" % action)
	var rebindable: Array[String] = SAVE_DATA_SCRIPT.rebindable_actions()
	for action: String in GAME_ACTIONS:
		_check(rebindable.has(action), "キー設定: %s のキー割り当てを変えられる" % action)
	for action: String in rebindable:
		_check(
			not action.begins_with("ui_") and not action.contains("/"),
			"キー設定: Godot 組み込みの %s は変えられるアクションに入らない" % action
		)


## 保存データの文字列の解釈。壊れたデータ (JSON でない・形が違う・版が違う) と、一部の値だけがおかしいデータ
func _check_save_parse() -> void:
	var defaults: Dictionary = SAVE_DATA_SCRIPT.default_data()
	var broken_texts: Array[String] = [
		"", "{", "not json", "[1, 2]", "42", '{"version": 2}', '{"version": "1"}', "{}"
	]
	for broken_text: String in broken_texts:
		var broken: Dictionary = SAVE_DATA_SCRIPT.parse(broken_text)
		_check(broken["broken"], "保存データ: %s は壊れたデータとして扱う" % broken_text)
		_check(
			broken["volumes"] == defaults["volumes"] and broken["cleared_stages"].is_empty()
			and broken["keys"].is_empty(),
			"保存データ: 壊れたデータ %s は既定値にする" % broken_text
		)
	var empty: Dictionary = SAVE_DATA_SCRIPT.parse('{"version": 1}')
	_check(not empty["broken"], "保存データ: 版だけのデータは壊れていない")
	_check(empty["volumes"] == defaults["volumes"], "保存データ: 書かれていない音量は既定値")

	var stages: Array[String] = [_first_stage_id()]
	var keys: Dictionary = {"jump": [KEY_H]}
	var text: String = SAVE_DATA_SCRIPT.serialize({"BGM": 0.3, "SE": 0.0}, stages, keys)
	var loaded: Dictionary = SAVE_DATA_SCRIPT.parse(text)
	_check(not loaded["broken"], "保存データ: 書き出したデータを読める")
	_check(is_equal_approx(loaded["volumes"]["BGM"], 0.3), "保存データ: BGM の音量を読み戻せる")
	_check(loaded["volumes"]["SE"] == 0.0, "保存データ: 効果音の音量 0 を読み戻せる")
	_check(loaded["cleared_stages"] == stages, "保存データ: クリアしたステージを読み戻せる")
	_check(loaded["keys"] == keys, "保存データ: キー割り当てを読み戻せる")
	_check(
		SAVE_DATA_SCRIPT.serialize(loaded["volumes"], loaded["cleared_stages"], loaded["keys"]) == text,
		"保存データ: 読み戻した値から同じ文字列を書き出す"
	)

	var partial: Dictionary = SAVE_DATA_SCRIPT.parse(
		JSON.stringify(
			{
				"version": 1,
				"volumes": {"BGM": 5.0, "SE": "loud"},
				"cleared_stages": [1, _first_stage_id(), _first_stage_id(), null],
				"keys":
				{
					"jump": [-3],
					"attack": [KEY_H, KEY_H],
					"move_left": "A",
					"move_right": [KEY_D, 1.5],
					"pause": [],
				},
			}
		)
	)
	_check(not partial["broken"], "保存データ: 一部の値だけがおかしいデータは壊れたデータとしない")
	_check(partial["volumes"]["BGM"] == 1.0, "保存データ: 範囲を超えた音量は 1.0 に収める")
	_check(partial["volumes"]["SE"] == SAVE_DATA_SCRIPT.DEFAULT_VOLUME, "保存データ: 数でない音量は既定値")
	_check(
		partial["cleared_stages"] == [_first_stage_id()],
		"保存データ: 文字列でない・重複したクリア済みステージは捨てる"
	)
	_check(partial["keys"].keys() == ["attack"], "保存データ: キーコードでない値を含むキー割り当ては捨てる")
	_check(partial["keys"]["attack"] == [KEY_H], "保存データ: 重複したキーは 1 つにする")
	_check(SAVE_DATA_SCRIPT.snap_volume(0.34) == 0.3, "保存データ: 音量は 0.1 刻みに丸める")
	_check(SAVE_DATA_SCRIPT.snap_volume(-1.0) == 0.0, "保存データ: 0 未満の音量は 0 にする")


## キー割り当ての変更で、押したキーを使っていた別のアクションとの重なりを解く
func _check_rebound() -> void:
	var bindings: Dictionary = {
		"move_left": [KEY_LEFT, KEY_A],
		"move_right": [KEY_RIGHT, KEY_D],
		"jump": [KEY_SPACE],
	}
	var moved: Dictionary = SAVE_DATA_SCRIPT.rebound(bindings, "jump", KEY_D)
	_check(moved["jump"] == [KEY_D], "キー設定: 変えたアクションは押したキーだけになる")
	_check(moved["move_right"] == [KEY_RIGHT], "キー設定: 押したキーを使っていた別のアクションからは外す")
	_check(moved["move_left"] == bindings["move_left"], "キー設定: 関係ないアクションはそのまま")
	var swapped: Dictionary = SAVE_DATA_SCRIPT.rebound(bindings, "move_left", KEY_SPACE)
	_check(
		swapped["jump"] == [KEY_LEFT, KEY_A],
		"キー設定: 押したキーしか無かったアクションには、変えたアクションの元のキーを譲る"
	)
	var same: Dictionary = SAVE_DATA_SCRIPT.rebound(bindings, "jump", KEY_SPACE)
	_check(same == bindings, "キー設定: 今と同じキーにしても何も変わらない")
	var pressed: InputEventKey = InputEventKey.new()
	pressed.physical_keycode = KEY_H
	pressed.pressed = true
	_check(SAVE_DATA_SCRIPT.pressed_key_code(pressed) == KEY_H, "キー設定: 押したキーの物理キーコードを取る")
	pressed.echo = true
	_check(SAVE_DATA_SCRIPT.pressed_key_code(pressed) == 0, "キー設定: 押しっぱなしの繰り返しは取らない")
	var released: InputEventKey = InputEventKey.new()
	released.physical_keycode = KEY_H
	_check(SAVE_DATA_SCRIPT.pressed_key_code(released) == 0, "キー設定: 離した入力は取らない")
	_check(
		SAVE_DATA_SCRIPT.pressed_key_code(InputEventMouseButton.new()) == 0,
		"キー設定: キー以外の入力は取らない"
	)


## ファイルへの保存と読み込み、壊れたファイルの退避。tree に入れない SaveData のインスタンスで行い、
## 最後に InputMap を project.godot の既定に戻して free する
func _check_save_file() -> void:
	var path: String = ProjectSettings.globalize_path(SAVE_TEST_PATH)
	var broken_path: String = path + SAVE_DATA_SCRIPT.BROKEN_SUFFIX
	_remove_file(path)
	_remove_file(broken_path)
	SAVE_DATA_SCRIPT.add_volume_buses()
	var saver: Node = SAVE_DATA_SCRIPT.new()
	saver.load_from(path)
	_check(not saver.loaded_broken, "保存: 保存データが無ければ壊れていない扱いで始める")
	_check(saver.cleared_stages.is_empty(), "保存: 保存データが無ければクリアしたステージは無い")
	_check(saver.key_overrides().is_empty(), "保存: 保存データが無ければキー割り当ては既定")

	saver.set_volume("BGM", 0.3)
	_check(FileAccess.file_exists(path), "保存: 音量を変えると保存データを書き出す")
	var bgm: int = AudioServer.get_bus_index("BGM")
	_check(bgm != -1 and AudioServer.get_bus_index("SE") != -1, "音量: BGM と効果音のバスがある")
	_check(
		is_equal_approx(AudioServer.get_bus_volume_db(bgm), linear_to_db(0.3)),
		"音量: BGM の音量をバスに反映する"
	)
	saver.set_volume("SE", 0.0)
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("SE")), "音量: 音量 0 はミュートにする")
	saver.mark_cleared(_first_stage_id())
	saver.mark_cleared(_first_stage_id())
	_check(saver.cleared_stages == [_first_stage_id()], "保存: 同じステージを 2 度クリアしても 1 つ")
	saver.rebind("jump", KEY_H)
	_check(SAVE_DATA_SCRIPT.action_keys("jump") == [KEY_H], "キー設定: 変えたキーを InputMap に反映する")
	_check(saver.key_overrides().keys() == ["jump"], "キー設定: 既定と違うアクションだけを保存する")
	var written: String = FileAccess.get_file_as_string(path)
	_check(saver.save() == OK, "保存: もう一度保存できる")
	_check(FileAccess.get_file_as_string(path) == written, "保存: 同じ内容なら同じファイルになる")
	saver.free()

	InputMap.load_from_project_settings()
	var loader: Node = SAVE_DATA_SCRIPT.new()
	loader.load_from(path)
	_check(not loader.loaded_broken, "読み込み: 書き出した保存データは壊れていない")
	_check(is_equal_approx(loader.volumes["BGM"], 0.3), "読み込み: BGM の音量を読み戻す")
	_check(loader.volumes["SE"] == 0.0, "読み込み: 効果音の音量を読み戻す")
	_check(loader.cleared_stages == [_first_stage_id()], "読み込み: クリアしたステージを読み戻す")
	_check(SAVE_DATA_SCRIPT.action_keys("jump") == [KEY_H], "読み込み: キー割り当てを InputMap に反映する")
	_check(
		is_equal_approx(AudioServer.get_bus_volume_db(bgm), linear_to_db(0.3)),
		"読み込み: 音量をバスに反映する"
	)

	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"version": 1, "volumes": {"BGM": 0.')
	file.close()
	loader.load_from(path)
	_check(loader.loaded_broken, "壊れた保存データ: 読めないファイルを壊れたと判定する")
	_check(loader.cleared_stages.is_empty(), "壊れた保存データ: クリアしたステージは無い状態で始める")
	_check(loader.volumes["BGM"] == SAVE_DATA_SCRIPT.DEFAULT_VOLUME, "壊れた保存データ: 音量は既定値で始める")
	_check(loader.key_overrides().is_empty(), "壊れた保存データ: キー割り当ては既定で始める")
	_check(
		not FileAccess.file_exists(path) and FileAccess.file_exists(broken_path),
		"壊れた保存データ: 元のファイルを退避して残す"
	)
	loader.load_from(path)
	_check(not loader.loaded_broken, "壊れた保存データ: 退避した後の読み込みでは壊れていない扱い")
	loader.loaded_broken = true
	_check(loader.save() == OK and not loader.loaded_broken, "壊れた保存データ: 保存し直すと知らせを消す")
	loader.free()
	InputMap.load_from_project_settings()
	_remove_file(path)
	_remove_file(broken_path)


## path のファイルがあれば消す
func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## 昼・夕方・夜の各ステージに別々の BGM があって繰り返し鳴り、メインシーンの BGM と効果音は設定で音量を変えられる
## バスで鳴らす。メインシーンは tree には入れず (_ready を走らせず) ノードの設定だけを確認して free する
func _check_audio() -> void:
	for bgm: Resource in [
		STAGE_BGM_SCRIPT.BGM_DAY, STAGE_BGM_SCRIPT.BGM_EVENING, STAGE_BGM_SCRIPT.BGM_NIGHT
	]:
		_check(bgm is AudioStreamOggVorbis, "BGM: %s を Ogg Vorbis として読み込める" % bgm.resource_path)
	var stage_bgms: Array[AudioStream] = []
	for stage: STAGE_SCRIPT in STAGES_SCRIPT.all():
		_check(STAGE_BGM_SCRIPT.STAGE_BGM.has(stage.id), "BGM: ステージ %s の BGM がある" % stage.title)
		if not STAGE_BGM_SCRIPT.STAGE_BGM.has(stage.id):
			continue
		var bgm: AudioStreamOggVorbis = STAGE_BGM_SCRIPT.bgm_of(stage.id)
		_check(bgm.loop, "BGM: ステージ %s の BGM は繰り返す" % stage.title)
		_check(not stage_bgms.has(bgm), "BGM: ステージ %s の BGM は他のステージと別の曲" % stage.title)
		stage_bgms.append(bgm)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	var bgm_player: AudioStreamPlayer = main.get_node("Audio/Bgm")
	_check(bgm_player.bus == &"BGM", "音量: BGM は設定で音量を変えられる BGM バスで鳴らす")
	for effect: String in SOUND_EFFECTS:
		var player: AudioStreamPlayer = main.get_node("Audio/" + effect)
		_check(player.stream != null, "効果音: %s の音がある" % effect)
		_check(player.bus == &"SE", "音量: 効果音 %s は設定で音量を変えられる SE バスで鳴らす" % effect)
	main.free()


## ASSETS_DIR の下の全素材が CREDITS_PATH に記録されている。記録の照合が記録の無い素材を見逃さないことも確かめる
func _check_credits() -> void:
	_check(
		unrecorded_assets(["audio/missing.wav"], "`audio/other.wav`") == ["audio/missing.wav"],
		"素材の記録: 記録の無い素材を見つける"
	)
	var credits: String = FileAccess.get_file_as_string(CREDITS_PATH)
	_check(not credits.is_empty(), "素材の記録: %s がある" % CREDITS_PATH)
	var files: Array[String] = asset_files(ASSETS_DIR)
	_check(not files.is_empty(), "素材の記録: %s に素材がある" % ASSETS_DIR)
	for file: String in unrecorded_assets(files, credits):
		_check(false, "素材の記録: %s が %s に記録されていない" % [file, CREDITS_PATH])


## dir の下 (サブディレクトリを含む) の素材の、ASSETS_DIR からの相対パス。素材の記録 (CREDITS.md) と、
## Godot がインポートで作るファイル (.import / .uid) は素材でないため除く
static func asset_files(dir: String) -> Array[String]:
	var files: Array[String] = []
	for file: String in DirAccess.get_files_at(dir):
		if file == CREDITS_PATH.get_file() or file.get_extension() in ["import", "uid"]:
			continue
		files.append(dir.path_join(file).trim_prefix(ASSETS_DIR + "/"))
	for sub: String in DirAccess.get_directories_at(dir):
		files.append_array(asset_files(dir.path_join(sub)))
	return files


## files (ASSETS_DIR からの相対パス) のうち、credits (CREDITS.md の本文) にバッククォートで囲んで書かれていないもの
static func unrecorded_assets(files: Array[String], credits: String) -> Array[String]:
	var missing: Array[String] = []
	for file: String in files:
		if not credits.contains("`%s`" % file):
			missing.append(file)
	return missing


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
