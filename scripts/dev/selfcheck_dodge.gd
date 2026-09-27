extends RefCounted
## 光源で伸び縮みした影の当たり判定 (main.gd の shadow_hit_rects()) と、各ステージの光源の影響範囲に置いた、縮んだ
## 影がくぐる低く飛ぶ敵・伸びた影の股の下を通る地面を歩く敵の置き方の検証。scripts/dev/selfcheck.gd が run() を呼び、
## 返した失敗の内容を ERROR として出す。

## 影の体・当たり判定・攻撃の範囲と、光源の影響範囲で主人公が動く範囲
const Main := preload("res://scripts/main.gd")
## 主人公の体の大きさ
const Hero := preload("res://scripts/hero.gd")
## 敵の種類・体の大きさ・揺れ・体の置き方
const Enemy := preload("res://scripts/enemy.gd")
## 光源の高さと倍率
const Light := preload("res://scripts/light.gd")
## ステージ 1 本の定義
const Stage := preload("res://scripts/stage.gd")
## 遊ぶ順に並べたステージの一覧
const Stages := preload("res://scripts/stages.gd")
## 敵の出現先の画面 (Lane)
const Combat := preload("res://scripts/combat.gd")
## 当たり判定の検証に使う光源の x と影響範囲の幅。主人公はこの光源の右側の影響範囲の中ほどに立たせる
const TEST_LIGHT_X: float = 1000.0
## TEST_LIGHT_X の光源の左右それぞれの影響範囲の幅
const TEST_ZONE: float = 200.0
## 地面に立つ影が敵に触れないことを確かめる時に、主人公を置く x の間隔 (px)
const STAND_STEP: float = 4.0
## 地面を歩く敵が影の足元を横切る間に、敵を置く x の間隔 (px)
const CROSS_STEP: float = 2.0

## 失敗した検証の内容
var failures: Array[String] = []


## 全部の検証を行い、失敗した検証の内容を返す
func run() -> Array[String]:
	_check_low_bob()
	for light_scale: float in [Enemy.DUCK_SCALE, 1.0, 1.25, Light.MAX_SCALE]:
		_check_hit_rects(light_scale)
	for stage: Stage in Stages.all():
		_check_stage_dodges(stage)
	return failures


## cond が false なら label を失敗として記録する
func _expect(cond: bool, label: String) -> void:
	if not cond:
		failures.append(label)


## 低く飛ぶ敵は周期 BOB_PERIOD で揺れの中心から上下に LOW_BOB_AMPLITUDE だけ揺れ、往復の範囲は揺れの分だけ高い
func _check_low_bob() -> void:
	var low: Enemy.Kind = Enemy.Kind.LOW_FLYER
	_expect(
		is_equal_approx(Enemy.bob_offset(low, Enemy.BOB_PERIOD / 4.0), Enemy.LOW_BOB_AMPLITUDE),
		"低く飛ぶ敵: 1/4 周期で揺れの幅だけ下にいる"
	)
	var area: Rect2 = Enemy.patrol_area(low, 100.0, Stage.GROUND_Y, 0.0)
	_expect(
		is_equal_approx(area.size.y, Enemy.SIZE.y + Enemy.LOW_BOB_AMPLITUDE * 2.0),
		"低く飛ぶ敵: 往復の範囲は上下の揺れの分だけ高い"
	)


## 倍率が light_scale の光源 1 本の右側の影響範囲の中ほどに立つ主人公の影の当たり判定。倍率 1 以下なら影の体の
## 矩形のままで、倍率 DUCK_SCALE の縮んだ影は頭の上の低く飛ぶ敵に揺れのどこでも触れず、倍率 1 の影は触れる。
## 倍率が 1 より大きい伸びた影は、体の矩形から足元の STRADDLE_GAP の高さを除いた形で、足元を横切る地面を歩く敵に
## どの位置でも触れない (倍率 1 の影は触れる)。どの倍率でも、立ったままの影の攻撃は低く飛ぶ敵に届かない
func _check_hit_rects(light_scale: float) -> void:
	var label: String = "当たり判定 (倍率 %.2f)" % light_scale
	var lights: Array[Dictionary] = [
		{"x": TEST_LIGHT_X, "height": Light.STANDARD_HEIGHT / light_scale, "zone": TEST_ZONE}
	]
	var hero_at: Vector2 = Vector2(
		TEST_LIGHT_X + TEST_ZONE / 2.0 - Hero.SIZE.x / 2.0, Stage.GROUND_Y - Hero.SIZE.y
	)
	var body: Rect2 = Main.shadow_body_rect(hero_at, lights)
	var rects: Array[Rect2] = Main.shadow_hit_rects(hero_at, lights)
	var gap: float = Main.STRADDLE_GAP if light_scale > 1.0 else 0.0
	_expect(
		rects.size() == 1 and rects[0].is_equal_approx(body.grow_side(SIDE_BOTTOM, -gap)),
		"%s: 影の体の矩形から足元の %.0f px を除いた形" % [label, gap]
	)
	var offset: Vector2 = Vector2(-120.0, 0.0)
	var moved: Array[Rect2] = Main.shadow_hit_rects(hero_at, lights, offset)
	_expect(
		moved.size() == 1 and moved[0].is_equal_approx(Rect2(rects[0].position + offset, rects[0].size)),
		"%s: 影縫いでずれた影の当たり判定は、ずれの分だけ動く" % label
	)
	var low_top: float = Main.SCREEN_HEIGHT + Enemy.body_top(Enemy.Kind.LOW_FLYER, Stage.GROUND_Y)
	for bob: float in [-Enemy.LOW_BOB_AMPLITUDE, Enemy.LOW_BOB_AMPLITUDE]:
		var low: Rect2 = Rect2(body.position.x + 4.0, low_top + bob, Enemy.SIZE.x, Enemy.SIZE.y)
		var ducked: bool = light_scale <= Enemy.DUCK_SCALE
		if light_scale <= 1.0:
			_expect(
				Main.touches(rects, low) != ducked,
				"%s: 頭の上を低く飛ぶ敵 (揺れのずれ %.0f) に%s" % [label, bob, "触れない" if ducked else "触れる"]
			)
		for facing: float in [-1.0, 1.0]:
			var attack: Rect2 = Main.shadow_attack_area(hero_at, facing, lights)
			var ahead: Rect2 = Rect2(low.position + Vector2(facing * Hero.SIZE.x, 0.0), low.size)
			_expect(not attack.intersects(ahead), "%s: 立ったままの影の攻撃は低く飛ぶ敵に届かない" % label)
	var walker_y: float = Main.SCREEN_HEIGHT + Enemy.body_top(Enemy.Kind.WALKER, Stage.GROUND_Y)
	var touched: bool = false
	var x: float = body.position.x - Enemy.SIZE.x - CROSS_STEP
	while x <= body.end.x + CROSS_STEP:
		touched = touched or Main.touches(rects, Rect2(Vector2(x, walker_y), Enemy.SIZE))
		x += CROSS_STEP
	var straddled: bool = light_scale > 1.0
	_expect(
		touched != straddled,
		"%s: 足元を横切る地面を歩く敵に%s" % [label, "触れない (股の下を通る)" if straddled else "触れる"]
	)


## stage の光源の影響範囲 (main.gd の light_zone_range()) に往復の範囲が重なる敵は下の画面の敵で、地面のどこに
## 立った影 (光源の真下と影響範囲の端を含む) にも触れず、光源の外の倍率 1 の影には触れる。低く飛ぶ敵は影響範囲に
## だけ置く。影が縮む光源があるステージには縮んだ影がくぐる低く飛ぶ敵を、影が伸びる光源があるステージには伸びた影の
## 股の下を通る地面を歩く敵を、少なくとも 1 か所ずつ置く
func _check_stage_dodges(stage: Stage) -> void:
	var ducks: int = 0
	var straddles: int = 0
	for spawn: Dictionary in stage.spawns:
		var kind: Enemy.Kind = Stage.spawn_kind(spawn)
		var area: Rect2 = Enemy.patrol_area(kind, spawn["x"], spawn["floor_y"], spawn["patrol"])
		var label: String = "影がよける敵 (%s の x = %d)" % [stage.title, int(spawn["x"])]
		var zoned: bool = false
		for light: Dictionary in stage.lights:
			zoned = zoned or Main.light_zone_range(light).intersects(area)
		if not zoned:
			_expect(kind != Enemy.Kind.LOW_FLYER, "%s: 低く飛ぶ敵は光源の影響範囲にだけ置く" % label)
			continue
		_expect(spawn["lane"] == Combat.Lane.BOTTOM, "%s: 光源の影響範囲の敵は下の画面の敵" % label)
		if spawn["lane"] != Combat.Lane.BOTTOM:
			continue
		var bottom_area: Rect2 = Rect2(area.position + Vector2(0.0, Main.SCREEN_HEIGHT), area.size)
		if not _passable(stage, bottom_area, label):
			continue
		var hero_at: Vector2 = Vector2(area.position.x, Stage.GROUND_Y - Hero.SIZE.y)
		var no_lights: Array[Dictionary] = []
		_expect(
			Main.touches(
				Main.shadow_hit_rects(hero_at, no_lights),
				Rect2(bottom_area.position, Enemy.SIZE)
			),
			"%s: 光源の外の倍率 1 の影には、最も上に揺れた時も触れる" % label
		)
		if kind == Enemy.Kind.LOW_FLYER:
			ducks += 1
		elif kind == Enemy.Kind.WALKER:
			straddles += 1
	var scales: Array[float] = []
	for light: Dictionary in stage.lights:
		scales.append(Light.shadow_scale(light["height"]))
	_expect(
		scales.all(func(s: float) -> bool: return s >= 1.0) or ducks > 0,
		"影がよける敵 (%s): 影が縮む光源の影響範囲に、縮んだ影がくぐる低く飛ぶ敵がいる" % stage.title
	)
	_expect(
		scales.all(func(s: float) -> bool: return s <= 1.0) or straddles > 0,
		"影がよける敵 (%s): 影が伸びる光源の影響範囲に、伸びた影の股の下を通る地面を歩く敵がいる" % stage.title
	)


## stage の地面のどこに立った影の当たり判定も、下の画面の敵が往復と揺れで通る範囲 bottom_area に触れないか。
## 主人公を STAND_STEP ごとと、各光源の真下・影響範囲の両端 (倍率 1 に戻る所) に置いて確かめる。触れたら label を
## 付けて失敗を記録し、false を返す
func _passable(stage: Stage, bottom_area: Rect2, label: String) -> bool:
	var centers: Array[float] = []
	var center: float = Hero.SIZE.x / 2.0
	while center <= stage.width - Hero.SIZE.x / 2.0:
		centers.append(center)
		center += STAND_STEP
	for light: Dictionary in stage.lights:
		centers.append_array([light["x"] - light["zone"], light["x"], light["x"] + light["zone"]])
	for hero_center: float in centers:
		var hero_at: Vector2 = Vector2(hero_center - Hero.SIZE.x / 2.0, Stage.GROUND_Y - Hero.SIZE.y)
		if Main.touches(Main.shadow_hit_rects(hero_at, stage.lights), bottom_area):
			_expect(false, "%s: 地面に立つ影 (体の中心の x = %.1f) に触れない" % [label, hero_center])
			return false
	return true
