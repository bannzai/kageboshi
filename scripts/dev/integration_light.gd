extends "res://scripts/dev/headless_check.gd"
## scripts/dev/integration.gd が継承する、光源の影響範囲での影の入力統合テスト。影響範囲で影の足元は主人公と
## 同期したまま、影の体と攻撃が光源から遠ざかる向きに光源の高さの倍率で伸び縮みし、影響範囲を抜けると戻ること、
## 縮んだ影が低く飛ぶ敵をくぐり、伸びた影の股の下を地面を歩く敵が通って被弾しないこと、光源の外では同じ敵に
## 被弾することを確かめる。影と主人公・地形の画面上の対称の確かめ方 (_check_synced() など) も持つ。

## ステージ 1 本の定義 (地面の位置・出現位置の種類)
const Stage := preload("res://scripts/stage.gd")
## 光源の高さから影の倍率を求める計算
const Light := preload("res://scripts/light.gd")
## メインシーンのスクリプト (上の画面の高さ = 仕切り線の y・伸びた影の足元の隙間・光源の影響範囲で主人公が動く範囲)
const Main := preload("res://scripts/main.gd")
## 主人公のスクリプト (体の大きさ・攻撃の範囲)
const Hero := preload("res://scripts/hero.gd")
## 敵のスクリプト (体力・体の大きさ・往復の範囲)
const Enemy := preload("res://scripts/enemy.gd")


## light (遊んでいるステージの Stage.lights の要素) の影響範囲の手前から右キーで進むと、光源の左側・右側のどちらでも
## 影の足元は主人公の真下のまま同じ動きをし、影の体が光源の倍率の分だけ伸び縮みして描かれる。影の攻撃は主人公と
## 同じ向きに出て、光源から遠ざかる向き (左側では左、右側では右) の時だけリーチが倍率の分だけ伸び縮みし、右側では
## 前 (右) の下の画面の敵に倍率のリーチの分だけ届く。影響範囲を抜けると影が主人公と同じ長さに戻る
func _check_light_stretch(main: Node2D, light: Dictionary) -> void:
	var hero: Hero = main.get_node("Hero")
	var shadow: Node2D = main.get_node("BottomLane/Shadow")
	var label: String = "光源 (%s の x = %d)" % [main.stage.title, int(light["x"])]
	var scale: float = Light.shadow_scale(light["height"])
	hero.position = Vector2(
		light["x"] - light["zone"] - Hero.SIZE.x / 2.0, Stage.GROUND_Y - Hero.SIZE.y
	)
	hero.velocity = Vector2.ZERO
	await _wait_physics_frames(3)
	_clear_enemies(main)
	_check_synced(main, label + " の手前")

	await _hold_key_until(
		KEY_RIGHT, func() -> bool: return _center_x(hero) >= light["x"] - light["zone"] / 2.0
	)
	_check_stretched(main, scale, label + " の左側")
	await _check_shadow_attack(main, 1.0, 1.0, label + " の左側で光源に近づく向き (右)")
	await _hold_keys([KEY_LEFT], 1)
	await _check_shadow_attack(main, -1.0, scale, label + " の左側で光源から遠ざかる向き (左)")

	await _hold_key_until(
		KEY_RIGHT, func() -> bool: return _center_x(hero) >= light["x"] + light["zone"] / 2.0
	)
	_check_stretched(main, scale, label + " の右側")
	var gap: float = Hero.ATTACK_REACH * (1.0 + scale) / 2.0
	var front: Enemy = main.spawn_enemy(
		Combat.Lane.BOTTOM, shadow.position.x + Hero.SIZE.x + gap, Stage.GROUND_Y, 0.0
	)
	await _check_shadow_attack(main, 1.0, scale, label + " の右側で光源から遠ざかる向き (右)")
	var reached: bool = scale > 1.0
	_check(
		front.hp == Enemy.MAX_HP - (Combat.BASE_DAMAGE if reached else 0),
		(
			"%s: 右側の影の攻撃は、前の下の画面の敵 (影の前端から %.1f px) に%s"
			% [label, gap, "伸びたリーチで届く" if reached else "縮んだリーチでは届かない"]
		)
	)
	front.queue_free()

	await _hold_key_until(
		KEY_RIGHT, func() -> bool: return _center_x(hero) >= light["x"] + light["zone"] + 10.0
	)
	_check_synced(main, label + " の影響範囲を抜けた後 (影の見た目の長さが主人公と同じに戻る)")
	await _check_shadow_attack(main, 1.0, 1.0, label + " の影響範囲を抜けた後")


## 光源の影響範囲にいる main の影の足元が主人公の真下 (上の画面 1 つ分下) にあり、影の体が主人公と同じ向きで、
## 見た目の長さが scale 倍になって、主人公の足元と仕切り線をはさんで対称な足元から下へ伸びて描かれる。伸びた影
## (scale が 1 より大きい) は足元の隙間 (Main.STRADDLE_GAP) に左右の脚を描き、体の絵を隙間の分だけ下にずらす
func _check_stretched(main: Node2D, scale: float, label: String) -> void:
	var hero: Hero = main.get_node("Hero")
	var shadow: Node2D = main.get_node("BottomLane/Shadow")
	var shadow_body: AnimatedSprite2D = shadow.get_node("Body")
	var hero_body: AnimatedSprite2D = hero.get_node("Body")
	_check(
		shadow.position == hero.position + Vector2(0.0, Main.SCREEN_HEIGHT),
		"%s: 影の足元が主人公の真下にいる" % label
	)
	_check(shadow_body.flip_h == hero_body.flip_h, "%s: 影が主人公と同じ向きを向く" % label)
	var gap: float = Main.STRADDLE_GAP if scale > 1.0 else 0.0
	var torso_scale: float = scale - gap / Hero.SIZE.y
	_check(
		is_equal_approx(shadow_body.scale.y, hero_body.scale.y * torso_scale),
		"%s: 影の体の絵の長さが光源の倍率の分だけ伸び縮みし、足元の隙間の分だけ短い" % label
	)
	var drawn: Rect2 = _drawn_rect(shadow_body)
	var hero_drawn: Rect2 = _drawn_rect(hero_body)
	_check(
		(
			is_equal_approx(drawn.position.x, hero_drawn.position.x)
			and is_equal_approx(drawn.size.x, hero_drawn.size.x)
			and is_equal_approx(drawn.position.y, _mirrored(hero_drawn).position.y + gap)
			and is_equal_approx(drawn.size.y, hero_drawn.size.y * torso_scale)
		),
		"%s: 伸び縮みした影も主人公の真下の、仕切り線をはさんで対称な足元 (から隙間の先) から下へ伸びて描かれる" % label
	)
	var feet_y: float = Main.SCREEN_HEIGHT * 2.0 - (hero.position.y + Hero.SIZE.y)
	for leg_name: String in ["LegLeft", "LegRight"]:
		var leg: ColorRect = shadow.get_node(leg_name)
		_check(leg.visible == (gap > 0.0), "%s: 伸びた影にだけ %s の脚を描く" % [label, leg_name])
		if gap > 0.0:
			var leg_drawn: Rect2 = _drawn_rect(leg)
			_check(
				is_equal_approx(leg_drawn.position.y, feet_y) and is_equal_approx(leg_drawn.size.y, gap),
				"%s: %s の脚が影の足元から隙間の高さだけ描かれる" % [label, leg_name]
			)


## 攻撃のクールダウンが終わるまで待って攻撃キーを押し、main の主人公が facing を向いていて、影の攻撃が影の体から
## 同じ向きに、主人公のリーチの reach_scale 倍の幅で出ることを確かめる
func _check_shadow_attack(main: Node2D, facing: float, reach_scale: float, label: String) -> void:
	var hero: Hero = main.get_node("Hero")
	var shadow: Node2D = main.get_node("BottomLane/Shadow")
	var attack: ColorRect = shadow.get_node("Attack")
	for _i: int in range(MOVE_FRAME_LIMIT):
		if hero.attack_cooldown_left <= 0.0:
			break
		await physics_frame
	await _press_attack()
	_check(attack.visible, "%s: 影が攻撃する" % label)
	_check(hero.facing == facing, "%s: 主人公が%sを向いている" % [label, "左" if facing < 0.0 else "右"])
	var expected: Rect2 = Hero.attack_area(shadow.position, facing, Hero.ATTACK_REACH * reach_scale)
	_check(
		Rect2(shadow.position + attack.position, attack.size).is_equal_approx(expected),
		(
			"%s: 影の攻撃が主人公と同じ向きに、主人公の %.2f 倍のリーチで出る (幅 %.1f)"
			% [label, reach_scale, attack.size.x]
		)
	)


## stage の下の画面の敵の出現位置のうち、往復の範囲が light の影響範囲で主人公が動く範囲 (Main.light_zone_range())
## に重なるもの (影が触れずによける敵)
func _dodge_spawns(stage: Stage, light: Dictionary) -> Array[Dictionary]:
	var spawns: Array[Dictionary] = []
	for spawn: Dictionary in stage.spawns:
		var area: Rect2 = Enemy.patrol_area(
			Stage.spawn_kind(spawn), spawn["x"], spawn["floor_y"], spawn["patrol"]
		)
		if spawn["lane"] == Combat.Lane.BOTTOM and Main.light_zone_range(light).intersects(area):
			spawns.append(spawn)
	return spawns


## light (遊んでいるステージの光源) の右側の影響範囲の中ほどに立ち止まった影を、kind の下の画面の敵 (影が縮む光源では
## 低く飛ぶ敵、伸びる光源では地面を歩く敵) が前から後ろへ横切っても、影も主人公も被弾しない。光源の外 (影響範囲の
## 左端。倍率 1) に立った影には同じ種類の敵が触れて、影の体力だけが減る
func _check_shadow_dodge(
	main: Node2D, game_state: Node, light: Dictionary, kind: Enemy.Kind
) -> void:
	var hero: Hero = main.get_node("Hero")
	var label: String = (
		"影がよける (%s の x = %d の光源、%s)"
		% [main.stage.title, int(light["x"]), Enemy.Kind.keys()[kind]]
	)
	await _stand_at(main, light["x"] + light["zone"] / 2.0)
	var hero_hp: int = game_state.hp[Combat.Lane.TOP]
	var shadow_hp: int = game_state.hp[Combat.Lane.BOTTOM]
	var shadow_x: float = hero.position.x
	var enemy: Enemy = main.spawn_enemy(
		Combat.Lane.BOTTOM,
		shadow_x + Hero.SIZE.x + 10.0,
		Stage.GROUND_Y,
		Hero.SIZE.x + Enemy.SIZE.x + 20.0,
		kind
	)
	for _i: int in range(MOVE_FRAME_LIMIT):
		if enemy.position.x + Enemy.SIZE.x < shadow_x:
			break
		await physics_frame
	_check(enemy.position.x + Enemy.SIZE.x < shadow_x, "%s: 敵が影の前から後ろへ横切る" % label)
	_check(
		_hp_is(game_state, hero_hp, shadow_hp),
		"%s: 影響範囲で伸び縮みした影は、横切る敵に触れず被弾しない" % label
	)
	enemy.queue_free()
	await _stand_at(main, light["x"] - light["zone"])
	main.spawn_enemy(Combat.Lane.BOTTOM, hero.position.x, Stage.GROUND_Y, 0.0, kind)
	await _wait_physics_frames(2)
	_check(
		_hp_is(game_state, hero_hp, shadow_hp - 1),
		"%s: 光源の外の倍率 1 の影には同じ敵が触れて、影の体力だけが減る" % label
	)
	_clear_enemies(main)
	await _wait_physics_frames(int(game_state.INVINCIBLE_TIME * 60.0) + 10)


## main の主人公の体の中心を center_x に置いて地面に立たせ、出現済みの敵を消す (置いた位置で画面に入った敵も消す)
func _stand_at(main: Node2D, center_x: float) -> void:
	var hero: Hero = main.get_node("Hero")
	hero.position = Vector2(center_x - Hero.SIZE.x / 2.0, Stage.GROUND_Y - Hero.SIZE.y)
	hero.velocity = Vector2.ZERO
	await _wait_physics_frames(3)
	_clear_enemies(main)
	await physics_frame


## 主人公の体の中心の x
func _center_x(hero: Hero) -> float:
	return hero.position.x + Hero.SIZE.x / 2.0


## 影は主人公から上の画面 1 つ分だけ下にいる (判定の座標)。画面上では影の体が主人公の真下に、主人公の体と仕切り線を
## はさんで上下対称に映る (足元を仕切り線の側に向け、そこから下へ伸びる)
func _check_synced(main: Node2D, label: String) -> void:
	var hero: Node2D = main.get_node("Hero")
	var shadow: Node2D = main.get_node("BottomLane/Shadow")
	var offset: Vector2 = Vector2(0.0, main.SCREEN_HEIGHT)
	_check(shadow.position == hero.position + offset, "%s: 影が主人公と同じ位置 (下の画面) にいる" % label)
	var hero_on_screen: Rect2 = _drawn_rect(hero.get_node("Body"))
	var shadow_on_screen: Rect2 = _drawn_rect(shadow.get_node("Body"))
	_check(
		shadow_on_screen.is_equal_approx(_mirrored(hero_on_screen)),
		"%s: 画面上で影の体が主人公の体と仕切り線をはさんで上下対称に映る" % label
	)
	_check(
		shadow_on_screen.position.y >= Main.SCREEN_HEIGHT,
		"%s: 画面上で影の体が仕切り線より下に、足元から下へ伸びて映る" % label
	)


## item (Control か AnimatedSprite2D の今の枚目) の画面上の矩形。上下反転した親の下でも大きさが正の矩形で返す
func _drawn_rect(item: CanvasItem) -> Rect2:
	var local: Rect2 = Rect2(Vector2.ZERO, (item as Control).size) if item is Control else Rect2()
	if item is AnimatedSprite2D:
		var sprite: AnimatedSprite2D = item
		var texture: Texture2D = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
		var size: Vector2 = texture.get_size()
		local = Rect2(sprite.offset - (size / 2.0 if sprite.centered else Vector2.ZERO), size)
	return item.get_global_transform_with_canvas() * local


## 画面上の矩形 rect を仕切り線 (y = Main.SCREEN_HEIGHT) を軸に上下反転した矩形
func _mirrored(rect: Rect2) -> Rect2:
	return Rect2(rect.position.x, Main.SCREEN_HEIGHT * 2.0 - rect.end.y, rect.size.x, rect.size.y)
