extends RefCounted
## 空を飛ぶ敵の揺れ・見た目と、各ステージの空を飛ぶ敵の置き方の検証。scripts/dev/selfcheck.gd が run() を呼び、
## 返した失敗の内容を ERROR として出す。

## 同期中の影の当たり判定 (光源の影響範囲で伸び縮みする影の体)
const Main := preload("res://scripts/main.gd")
## 主人公の体の大きさ・ジャンプの最高点・攻撃の範囲
const Hero := preload("res://scripts/hero.gd")
## 敵の種類・揺れ・体の置き方
const Enemy := preload("res://scripts/enemy.gd")
## ステージ 1 本の定義
const Stage := preload("res://scripts/stage.gd")
## 遊ぶ順に並べたステージの一覧
const Stages := preload("res://scripts/stages.gd")
## 敵の出現先の画面 (Lane)
const Combat := preload("res://scripts/combat.gd")
## 種類と画面ごとの見た目のアニメーションを持つ敵のシーン
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")
## 地面に立つ主人公・影が飛ぶ敵に触れないことを確かめる時に、主人公を置く x の間隔 (px)
const STAND_STEP: float = 4.0

## 失敗した検証の内容
var failures: Array[String] = []


## 全部の検証を行い、失敗した検証の内容を返す
func run() -> Array[String]:
	_check_bob()
	_check_animations()
	for stage: Stage in Stages.all():
		_check_stage_flyers(stage)
	return failures


## cond が false なら label を失敗として記録する
func _expect(cond: bool, label: String) -> void:
	if not cond:
		failures.append(label)


## 飛ぶ敵は周期 BOB_PERIOD で揺れの中心から上下に BOB_AMPLITUDE だけ揺れ、地面を歩く敵は揺れない
func _check_bob() -> void:
	var period: float = Enemy.BOB_PERIOD
	var amplitude: float = Enemy.BOB_AMPLITUDE
	var flyer: Enemy.Kind = Enemy.Kind.FLYER
	_expect(Enemy.bob_offset(flyer, 0.0) == 0.0, "揺れ: 出現した瞬間は揺れの中心にいる")
	_expect(
		is_equal_approx(Enemy.bob_offset(flyer, period / 4.0), amplitude),
		"揺れ: 1/4 周期で揺れの幅だけ下にいる"
	)
	_expect(
		is_equal_approx(Enemy.bob_offset(flyer, period * 0.75), -amplitude),
		"揺れ: 3/4 周期で揺れの幅だけ上にいる"
	)
	_expect(
		is_equal_approx(Enemy.bob_offset(flyer, period + 0.1), Enemy.bob_offset(flyer, 0.1)),
		"揺れ: 1 周期ごとに同じ揺れを繰り返す"
	)
	for i: int in range(20):
		var time: float = period * i / 20.0
		_expect(absf(Enemy.bob_offset(flyer, time)) <= amplitude, "揺れ: 揺れの幅を越えない")
		_expect(Enemy.bob_offset(Enemy.Kind.WALKER, time) == 0.0, "揺れ: 地面を歩く敵は揺れない")


## 種類と画面ごとの見た目のアニメーションがどれも別の名前で、敵のシーンにある。
## シーンは tree には入れず (_ready を走らせず) アニメーションだけを確認して free する
func _check_animations() -> void:
	var enemy: Node = ENEMY_SCENE.instantiate()
	var frames: SpriteFrames = enemy.get_node("Body").sprite_frames
	var names: Array[StringName] = []
	for kind: Enemy.Kind in Enemy.ANIMATIONS:
		for animation: StringName in Enemy.ANIMATIONS[kind]:
			_expect(frames.has_animation(animation), "見た目: 敵のシーンに %s のアニメーションがある" % animation)
			_expect(not names.has(animation), "見た目: %s は種類・画面ごとに別のアニメーション" % animation)
			names.append(animation)
	_expect(names.size() == Enemy.Kind.size() * Combat.Lane.size(), "見た目: 種類と画面ごとに見た目がある")
	enemy.free()


## stage の上の画面と下の画面の両方に飛ぶ敵がいて、各飛ぶ敵は地形とその上に立つ主人公・影に触れず、跳んだ
## 最高点での攻撃が届いて地面に立ったままの攻撃は届かず、同じ画面の地上の敵と往復の範囲が重ならない。
## 地面のどこに立った主人公・影 (光源の影響範囲で伸びた影を含む) も飛ぶ敵に触れない
func _check_stage_flyers(stage: Stage) -> void:
	var lanes: Array[int] = []
	for spawn: Dictionary in stage.spawns:
		if Stage.spawn_kind(spawn) != Enemy.Kind.FLYER:
			continue
		lanes.append(spawn["lane"])
		var label: String = "飛ぶ敵 (%s の x = %d)" % [stage.title, int(spawn["x"])]
		var area: Rect2 = Enemy.patrol_area(
			Enemy.Kind.FLYER, spawn["x"], spawn["floor_y"], spawn["patrol"]
		)
		for rect: Rect2 in stage.obstacles:
			var standing: Rect2 = rect.grow_individual(
				Hero.SIZE.x, Hero.SIZE.y, Hero.SIZE.x, 0.0
			)
			_expect(not standing.intersects(area), "%s: 地形とその上に立つ主人公・影に触れない" % label)
		_check_reach(spawn["floor_y"], area, label)
		for other: Dictionary in stage.spawns:
			if Stage.spawn_kind(other) == Enemy.Kind.WALKER and other["lane"] == spawn["lane"]:
				var walker: Rect2 = Enemy.patrol_area(
					Enemy.Kind.WALKER, other["x"], other["floor_y"], other["patrol"]
				)
				_expect(
					walker.end.x <= area.position.x or area.end.x <= walker.position.x,
					"%s: 同じ画面の地上の敵 (x = %d) と往復の範囲が重ならない" % [label, int(other["x"])]
				)
		_check_standing(stage, spawn, area, label)
	_expect(lanes.has(Combat.Lane.TOP), "飛ぶ敵 (%s): 上の画面に飛ぶ敵がいる" % stage.title)
	_expect(lanes.has(Combat.Lane.BOTTOM), "飛ぶ敵 (%s): 下の画面に飛ぶ敵がいる" % stage.title)


## 足元の床の y が floor_y の飛ぶ敵が往復と揺れで通る範囲 area に、床から跳んだ最高点の攻撃が、最も上・最も下に
## 揺れた時のどちらでも届き、床に立ったままの攻撃は届かない。label は失敗した時に出す飛ぶ敵の名前
func _check_reach(floor_y: float, area: Rect2, label: String) -> void:
	var peak_at: Vector2 = Vector2(area.position.x, floor_y - Hero.SIZE.y - Hero.JUMP_HEIGHT)
	var peak: Rect2 = Hero.attack_area(peak_at, 1.0, Hero.ATTACK_REACH)
	var highest: Rect2 = Rect2(peak.position.x, area.position.y, Enemy.SIZE.x, Enemy.SIZE.y)
	var lowest: Rect2 = Rect2(peak.position.x, area.end.y - Enemy.SIZE.y, Enemy.SIZE.x, Enemy.SIZE.y)
	_expect(
		peak.intersects(highest) and peak.intersects(lowest),
		(
			"%s: 最も上・最も下に揺れても跳んだ最高点の攻撃 (y = %.1f〜%.1f) が届く (体の y = %.1f〜%.1f)"
			% [label, peak.position.y, peak.end.y, area.position.y, area.end.y]
		)
	)
	var ground: Rect2 = Hero.attack_area(
		Vector2(area.position.x, floor_y - Hero.SIZE.y), 1.0, Hero.ATTACK_REACH
	)
	_expect(
		not ground.intersects(Rect2(ground.position.x, area.position.y, area.size.x, area.size.y)),
		"%s: 床に立ったままの攻撃は届かない" % label
	)


## stage の地面のどこに立った主人公・影 (光源の影響範囲で伸び縮みした影を含む) の体も、spawn の飛ぶ敵が往復と揺れで
## 通る範囲 area (上の画面の座標) に触れない。label は失敗した時に出す飛ぶ敵の名前
func _check_standing(stage: Stage, spawn: Dictionary, area: Rect2, label: String) -> void:
	var lane_area: Rect2 = area
	if spawn["lane"] == Combat.Lane.BOTTOM:
		lane_area.position.y += Main.SCREEN_HEIGHT
	var x: float = 0.0
	while x <= stage.width - Hero.SIZE.x:
		var hero_at: Vector2 = Vector2(x, Stage.GROUND_Y - Hero.SIZE.y)
		var hero_rects: Array[Rect2] = [Rect2(hero_at, Hero.SIZE)]
		var bodies: Array[Array] = [hero_rects, Main.shadow_hit_rects(hero_at, stage.lights)]
		if Main.touches(bodies[spawn["lane"]], lane_area):
			_expect(false, "%s: 地面に立つ主人公・影 (x = %d) に触れない" % [label, int(x)])
			return
		x += STAND_STEP
