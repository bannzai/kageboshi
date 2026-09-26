extends Node2D
## 上下 2 画面の横スクロール。上の画面に主人公と地形、下の画面に影と同じ形の地形を置き、
## 1 台のカメラで上下を同じ横スクロール量で映す。影は主人公と同じ動き・同じ攻撃をし、光源をまたいだ先の反転区間でだけ
## 左右の動きが逆になり、光源の高さで伸び縮みする (scripts/light.gd)。
## 敵は上下どちらの画面にも出て、主人公・影のどちらが触れても共有の体力 (GameState) が減る。
## ステージが進むのはプレイ中の画面の間だけで、タイトル・ポーズ・ゲームオーバー・ステージクリア・設定の画面は
## GameState の画面に合わせて重ねて表示する。ステージを最初からやり直す時はこのシーンを読み込み直す。
## ゴールに着いたらステージをクリア済みとして SaveData に保存する。

## 地形・敵の出現位置・光源の定義
const Stage := preload("res://scripts/stage.gd")
## 光源による影の反転と倍率の計算
const Light := preload("res://scripts/light.gd")
## 主人公のスクリプト (体の大きさ・攻撃の範囲と 1 物理フレームの進め方)
const Hero := preload("res://scripts/hero.gd")
## 敵のスクリプト (体の大きさ)
const Enemy := preload("res://scripts/enemy.gd")
## 攻撃の当たりと同期ボーナスの計算
const Combat := preload("res://scripts/combat.gd")
## autoload の GameState のスクリプト。autoload 名の識別子で参照すると、--script で起動する
## scripts/dev/ の検証が autoload の登録前に main.gd をコンパイルして失敗するため、ノードとして取る
const GameStateScript := preload("res://scripts/game_state.gd")
## autoload の SaveData のスクリプト (GameStateScript と同じ理由でノードとして取る)
const SaveDataScript := preload("res://scripts/save_data.gd")
## 敵のシーン
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")

## 上の画面 1 つ分の高さ。project.godot の viewport (1280x720) を上下に 2 等分した値。
## 下の画面の影・地形・敵は、上の画面のものからこの分だけ下にずらして置く
const SCREEN_HEIGHT: float = 360.0
## 画面の幅。project.godot の viewport の幅と同じ値
const SCREEN_WIDTH: float = 1280.0
## 上の画面の地形の色 (地面・段差・足場・壁)
const TOP_TERRAIN_COLOR: Color = Color(0.45, 0.4, 0.33, 1.0)
## 下の画面の地形の色 (影が張り付く地面・壁)
const BOTTOM_TERRAIN_COLOR: Color = Color(0.13, 0.14, 0.18, 1.0)
## 敵に触れた時に減る体力
const CONTACT_DAMAGE: int = 1
## 無敵の間の主人公・影の不透明度 (点滅の代わりに半透明にして被弾が分かるようにする)
const INVINCIBLE_ALPHA: float = 0.5
## 同期ボーナスの演出の色 (仕切り線の光と文字)
const SYNC_COLOR: Color = Color(1.0, 0.82, 0.25, 1.0)
## 同期ボーナスの演出の長さ (秒)
const SYNC_EFFECT_TIME: float = 0.6
## 光源の柱の色
const LAMP_POST_COLOR: Color = Color(0.25, 0.22, 0.2, 1.0)
## 光源の灯りと、反転区間を照らす光・下の画面の帯の矢印の色
const LAMP_LIGHT_COLOR: Color = Color(1.0, 0.86, 0.45, 1.0)
## 上の画面で反転区間を照らす光の不透明度 (地形・敵が透けて見える薄さにする)
const LAMP_BEAM_ALPHA: float = 0.3
## 下の画面で、反転区間の影が逆へ動く範囲の帯の色 (下の画面の背景より明るくし、影が逆へ動く所だと分かるようにする)
const REVERSE_ZONE_COLOR: Color = Color(0.5, 0.45, 0.3, 0.35)
## 下の画面の帯に並べる左向きの矢印の間隔 (px)。矢印どうしの間を矢印 1 つ分以上空け、並んだ矢印だと読めるようにする
const REVERSE_ARROW_SPACING: float = 48.0
## ゴールの目印の色
const GOAL_COLOR: Color = Color(1.0, 0.82, 0.25, 0.45)
## 画面を切り替える入力のアクションと、GameState に送る操作。設定画面を閉じる操作 (BACK) は、設定画面のキー割り当ての
## 入力と区別するため scripts/settings_menu.gd が送る (設定画面は BACK 以外の操作を受け付けないので、
## キー割り当てで押したキーがここで画面を切り替えることはない)
const SCREEN_ACTIONS: Dictionary = {
	"confirm": GameStateScript.Command.CONFIRM,
	"pause": GameStateScript.Command.PAUSE,
	"quit_to_title": GameStateScript.Command.QUIT,
	"open_settings": GameStateScript.Command.SETTINGS,
}
## 画面ごとの操作の案内 ([アクション, 操作の説明] の並び)。キーの表示は今のキー割り当てから作る
const SCREEN_HINTS: Dictionary = {
	GameStateScript.Screen.TITLE: [["confirm", "Start"], ["open_settings", "Settings"]],
	GameStateScript.Screen.PAUSED: [["pause", "Resume"], ["quit_to_title", "Title"]],
	GameStateScript.Screen.GAME_OVER: [["confirm", "Retry"], ["quit_to_title", "Title"]],
	GameStateScript.Screen.CLEAR: [["confirm", "Title"]],
}

## カメラの横スクロール量 (画面の左端のステージ上の x)
var scroll_x: float = 0.0
## Stage.SPAWNS のうち出現させた数 (先頭から)
var spawned_count: int = 0
## ステージ開始からの経過時間 (秒)。同期ボーナスの判定の時刻に使う
var elapsed: float = 0.0
## 今の攻撃ですでに当たった敵。1 回の攻撃で同じ敵に 2 度当てない
var swing_hits: Array[Enemy] = []
## 同期ボーナスの時間幅 (Combat.SYNC_WINDOW) の中で攻撃が当たった敵 ({"enemy", "lane", "time"})。
## 上下の当たりが別のフレームで同期ボーナスが後から成立した時に、先に当たっていた敵へ不足分のダメージを与える
var recent_hits: Array[Dictionary] = []
## 仕切り線の光を消していく途中の Tween。続けて同期ボーナスが出たら止めて光らせ直す
var sync_flash_tween: Tween = null

## 表示している画面と、主人公と影で共有する体力 (autoload の GameState)
@onready var game_state: GameStateScript = get_node("/root/GameState")
## クリアしたステージとキー割り当ての保存 (autoload の SaveData)
@onready var save_data: SaveDataScript = get_node("/root/SaveData")
## 上の画面の主人公
@onready var hero: Hero = $Hero
## 下の画面の影。位置は _sync_shadow() で主人公から導く
@onready var shadow: Node2D = $Shadow
## 影の体の見た目。高さは光源の倍率で伸び縮みする
@onready var shadow_body: ColorRect = $Shadow/Body
## 影の攻撃の見た目。主人公の攻撃から導く
@onready var shadow_attack: ColorRect = $Shadow/Attack
## 上下の画面を同じスクロール量で映すカメラ
@onready var camera: Camera2D = $Camera
## 上の画面の地形 (当たり判定と見た目) を入れる親
@onready var top_terrain: Node2D = $TopTerrain
## 下の画面の地形 (見た目だけ) を入れる親。上の画面 1 つ分下にずらしてある
@onready var bottom_terrain: Node2D = $BottomTerrain
## 光源と反転区間の予兆 (見た目だけ) を入れる親
@onready var lights: Node2D = $Lights
## 上下の画面の敵を入れる親
@onready var enemies: Node2D = $Enemies
## 上下の画面の仕切り線に重ねる光。同期ボーナスの時だけ不透明にしてから消す
@onready var sync_flash: ColorRect = $Overlay/SyncFlash
## 体力の表示
@onready var hp_label: Label = $Overlay/HpLabel
## ゴールの目印 (上の画面)
@onready var goal: ColorRect = $Goal
## 画面ごとに重ねる表示。GameState の画面がこのキーの時だけ表示する
@onready var screen_panels: Dictionary = {
	GameStateScript.Screen.TITLE: $Screens/Title,
	GameStateScript.Screen.PAUSED: $Screens/Pause,
	GameStateScript.Screen.GAME_OVER: $Screens/GameOver,
	GameStateScript.Screen.CLEAR: $Screens/Clear,
	GameStateScript.Screen.SETTINGS: $Screens/Settings,
}
## タイトルに出す進行 (クリアしたステージの数)
@onready var progress_label: Label = $Screens/Title/Progress
## タイトルに出す、壊れた保存データを既定値に戻した知らせ
@onready var broken_save_label: Label = $Screens/Title/BrokenSave


func _ready() -> void:
	print("kageboshi boot")
	game_state.reset()
	sync_flash.color = SYNC_COLOR
	goal.position = Stage.GOAL.position
	goal.size = Stage.GOAL.size
	goal.color = GOAL_COLOR
	camera.make_current()
	_build_terrain()
	_build_lights()
	_sync_shadow()
	_follow_camera()
	_update_hud()


func _physics_process(delta: float) -> void:
	if _handle_screen_input():
		return
	if game_state.is_playing():
		_step_stage(delta)
	_update_hud()


## 画面を切り替える入力を GameState に送る。ステージを最初から作り直す遷移なら、このシーンを読み込み直して
## true を返す (読み込み直すとこのノードは tree から外れるため、呼び出し側はこのフレームの処理をやめる)
func _handle_screen_input() -> bool:
	for action: String in SCREEN_ACTIONS:
		if Input.is_action_just_pressed(action) and game_state.send(SCREEN_ACTIONS[action]):
			get_tree().reload_current_scene()
			return true
	return false


## プレイ中の 1 物理フレーム。主人公・影・カメラ・敵を進め、攻撃・接触・ゴールを判定する
func _step_stage(delta: float) -> void:
	elapsed += delta
	game_state.tick(delta)
	if Input.is_action_just_pressed("attack") and hero.start_attack():
		swing_hits.clear()
	hero.physics_step(
		Input.get_axis("move_left", "move_right"), Input.is_action_just_pressed("jump"), delta
	)
	_sync_shadow()
	_follow_camera()
	_spawn_due_enemies()
	for enemy: Enemy in _living_enemies():
		enemy.physics_step(delta)
	_resolve_attack_hits()
	_resolve_contact_damage()
	if hero.body_rect().intersects(Stage.GOAL) and game_state.clear_stage():
		save_data.mark_cleared(Stage.ID)


## lane の画面の、x から左へ patrol の幅を往復する敵を置く。floor_y は足元の y 座標 (上の画面の座標)
func spawn_enemy(lane: Combat.Lane, x: float, floor_y: float, patrol: float) -> Enemy:
	var enemy: Enemy = ENEMY_SCENE.instantiate()
	var at: Vector2 = Vector2(x, floor_y - Enemy.SIZE.y)
	if lane == Combat.Lane.BOTTOM:
		at.y += SCREEN_HEIGHT
	enemy.setup(lane, at, patrol)
	enemies.add_child(enemy)
	return enemy


## Stage.TERRAIN の矩形ごとに、上の画面には当たり判定と見た目を、下の画面には見た目だけを置く。
## 天井 (Stage.CEILING) は当たり判定だけを置く
func _build_terrain() -> void:
	for rect: Rect2 in Stage.TERRAIN:
		var body: StaticBody2D = _collision_body(rect)
		body.add_child(_terrain_rect(Rect2(Vector2.ZERO, rect.size), TOP_TERRAIN_COLOR))
		top_terrain.add_child(body)
		bottom_terrain.add_child(_terrain_rect(rect, BOTTOM_TERRAIN_COLOR))
	add_child(_collision_body(Stage.CEILING))


## area を占める当たり判定
func _collision_body(area: Rect2) -> StaticBody2D:
	var body: StaticBody2D = StaticBody2D.new()
	body.position = area.position
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = area.size
	var collision: CollisionShape2D = CollisionShape2D.new()
	collision.shape = shape
	collision.position = area.size / 2.0
	body.add_child(collision)
	return body


## 親の座標で area を占める単色の見た目 (地形・光源・反転区間の帯)
func _terrain_rect(area: Rect2, color: Color) -> ColorRect:
	var rect: ColorRect = ColorRect.new()
	rect.position = area.position
	rect.size = area.size
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## Stage.LIGHTS の光源ごとに、上の画面には光源 (柱と灯り) と反転区間を照らす光を、下の画面には反転区間で影が
## 逆へ動く範囲 (光源から左へ、反転区間の幅に倍率を掛けた幅) の帯と左向きの矢印を置く (反転区間の予兆)。
## 帯の幅で影の伸び縮みも前もって分かる。主人公は画面の中央にいるため、反転区間は入る半画面前から見える
func _build_lights() -> void:
	for light: Dictionary in Stage.LIGHTS:
		var x: float = light["x"]
		var lamp_y: float = Stage.GROUND_Y - light["height"]
		var beam: Polygon2D = Polygon2D.new()
		beam.polygon = PackedVector2Array(
			[Vector2(x, lamp_y), Vector2(x, Stage.GROUND_Y), Vector2(x + light["zone"], Stage.GROUND_Y)]
		)
		beam.color = Color(LAMP_LIGHT_COLOR, LAMP_BEAM_ALPHA)
		lights.add_child(beam)
		lights.add_child(_terrain_rect(Rect2(x - 3.0, lamp_y, 6.0, light["height"]), LAMP_POST_COLOR))
		lights.add_child(_terrain_rect(Rect2(x - 10.0, lamp_y - 12.0, 20.0, 14.0), LAMP_LIGHT_COLOR))
		var band: Rect2 = shadow_reverse_range(light)
		lights.add_child(_terrain_rect(band, REVERSE_ZONE_COLOR))
		var arrow_y: float = band.get_center().y
		var arrow_x: float = band.position.x + REVERSE_ARROW_SPACING / 2.0
		while arrow_x < band.end.x:
			var arrow: Polygon2D = Polygon2D.new()
			arrow.polygon = PackedVector2Array(
				[
					Vector2(arrow_x - 10.0, arrow_y),
					Vector2(arrow_x + 10.0, arrow_y - 12.0),
					Vector2(arrow_x + 10.0, arrow_y + 12.0)
				]
			)
			arrow.color = LAMP_LIGHT_COLOR
			lights.add_child(arrow)
			arrow_x += REVERSE_ARROW_SPACING


## 影の位置・長さ・攻撃は主人公と、主人公がいる反転区間の光源から導く
## (.claude/rules/shadow-position-derived-from-hero.md)
func _sync_shadow() -> void:
	shadow.position = shadow_position(hero.position)
	var body: Rect2 = shadow_body_rect(hero.position)
	shadow_body.position = body.position - shadow.position
	shadow_body.size = body.size
	var attack: Rect2 = shadow_attack_area(hero.position, hero.facing)
	shadow_attack.visible = hero.attack_visual.visible
	shadow_attack.position = attack.position - shadow.position
	shadow_attack.size = attack.size


func _follow_camera() -> void:
	scroll_x = scroll_for(hero.position.x + Hero.SIZE.x / 2.0)
	camera.position = Vector2(scroll_x, 0.0)


## 画面の右端に近づいた Stage.SPAWNS の敵を出現させる
func _spawn_due_enemies() -> void:
	var due: int = Stage.due_spawn_count(scroll_x + SCREEN_WIDTH)
	while spawned_count < due:
		var spawn: Dictionary = Stage.SPAWNS[spawned_count]
		spawn_enemy(spawn["lane"], spawn["x"], spawn["floor_y"], spawn["patrol"])
		spawned_count += 1


## 倒れて消える途中のものを除いた敵
func _living_enemies() -> Array[Enemy]:
	var living: Array[Enemy] = []
	for enemy: Enemy in enemies.get_children():
		if not enemy.is_queued_for_deletion():
			living.append(enemy)
	return living


## enemy が倒れて消えておらず、消える途中でもないか。消えた (free 済みの) 敵も受け取るため型を付けない
func _is_living(enemy: Variant) -> bool:
	return is_instance_valid(enemy) and not enemy.is_queued_for_deletion()


## 主人公の攻撃は上の画面の敵に、影の攻撃は下の画面の敵に当たる。上下で同時に当たったら
## 同期ボーナスでダメージを倍にする
func _resolve_attack_hits() -> void:
	if not hero.is_attacking():
		return
	var areas: Array[Rect2] = [
		Hero.attack_area(hero.position, hero.facing, Hero.ATTACK_REACH),
		shadow_attack_area(hero.position, hero.facing)
	]
	var hits: Array[Enemy] = []
	for enemy: Enemy in _living_enemies():
		if not swing_hits.has(enemy) and areas[enemy.lane].intersects(enemy.body_rect()):
			hits.append(enemy)
	if hits.is_empty():
		return
	swing_hits.append_array(hits)
	var kept: Array[Dictionary] = []
	for hit: Dictionary in recent_hits:
		if elapsed - hit["time"] <= Combat.SYNC_WINDOW:
			kept.append(hit)
	for enemy: Enemy in hits:
		kept.append({"enemy": enemy, "lane": enemy.lane, "time": elapsed})
	recent_hits = kept
	var latest: Array[float] = [-1.0, -1.0]
	for hit: Dictionary in recent_hits:
		latest[hit["lane"]] = maxf(latest[hit["lane"]], hit["time"])
	var sync: bool = Combat.is_sync_hit(latest[Combat.Lane.TOP], latest[Combat.Lane.BOTTOM])
	for enemy: Enemy in hits:
		if enemy.take_hit(Combat.hit_damage(sync)):
			enemy.queue_free()
	if not sync:
		return
	for hit: Dictionary in recent_hits:
		if hit["time"] < elapsed and _is_living(hit["enemy"]):
			var earlier: Enemy = hit["enemy"]
			if earlier.take_hit(Combat.sync_extra_damage()):
				earlier.queue_free()
	recent_hits.clear()
	_show_sync_effect()


## 上の画面の敵が主人公に、下の画面の敵が影に触れていたら体力を減らす
func _resolve_contact_damage() -> void:
	var bodies: Array[Rect2] = [hero.body_rect(), shadow_body_rect(hero.position)]
	for enemy: Enemy in _living_enemies():
		if bodies[enemy.lane].intersects(enemy.body_rect()):
			game_state.take_damage(CONTACT_DAMAGE)


## 同期ボーナスが出たことを、仕切り線の光と主人公・影の間の文字で知らせる
func _show_sync_effect() -> void:
	var label: Label = Label.new()
	label.text = "SYNC x%d" % Combat.SYNC_MULTIPLIER
	label.add_theme_color_override("font_color", SYNC_COLOR)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_font_size_override("font_size", 28)
	label.position = Vector2(hero.position.x - 40.0, SCREEN_HEIGHT - 60.0)
	label.add_to_group("sync_effect")
	add_child(label)
	var tween: Tween = create_tween()
	tween.set_parallel()
	tween.tween_property(label, "position:y", label.position.y - 40.0, SYNC_EFFECT_TIME)
	tween.tween_property(label, "modulate:a", 0.0, SYNC_EFFECT_TIME)
	tween.chain().tween_callback(label.queue_free)
	if sync_flash_tween != null:
		sync_flash_tween.kill()
	sync_flash.modulate.a = 1.0
	sync_flash_tween = create_tween()
	sync_flash_tween.tween_property(sync_flash, "modulate:a", 0.0, SYNC_EFFECT_TIME)


## 体力・画面ごとの表示と、無敵の間の主人公・影の半透明を GameState に合わせる。タイトルの進行と操作の案内は
## SaveData の保存データとキー割り当てに合わせる
func _update_hud() -> void:
	hp_label.text = "HP %d / %d" % [game_state.hp, game_state.MAX_HP]
	hp_label.visible = game_state.screen not in [
		GameStateScript.Screen.TITLE, GameStateScript.Screen.SETTINGS
	]
	for screen: GameStateScript.Screen in screen_panels:
		var panel: Control = screen_panels[screen]
		panel.visible = game_state.screen == screen
	var hints: Array = SCREEN_HINTS.get(game_state.screen, [])
	if not hints.is_empty():
		screen_panels[game_state.screen].get_node("Hint").text = hint_text(hints)
	progress_label.text = "Cleared stages: %d" % save_data.cleared_stages.size()
	progress_label.visible = not save_data.cleared_stages.is_empty()
	broken_save_label.visible = save_data.loaded_broken
	var alpha: float = INVINCIBLE_ALPHA if game_state.is_invincible() else 1.0
	hero.modulate.a = alpha
	shadow.modulate.a = alpha


## hints ([アクション, 操作の説明] の並び) の操作の案内。キーは各アクションの今の 1 つ目のキー (「Enter: Start」)
static func hint_text(hints: Array) -> String:
	var parts: PackedStringArray = []
	for hint: Array in hints:
		parts.append("%s: %s" % [SaveDataScript.first_key_name(hint[0]), hint[1]])
	return "    ".join(parts)


## 体の左上が hero_position の主人公の影の位置 (伸び縮みさせる前の、主人公と同じ大きさの体の左上)。
## 上の画面 1 つ分下で、横は主人公の体の中心を Light.shadow_center_x() で写した位置 (反転区間の外は主人公と同じ)
static func shadow_position(hero_position: Vector2) -> Vector2:
	var half_width: float = Hero.SIZE.x / 2.0
	return Vector2(
		Light.shadow_center_x(hero_position.x + half_width, Stage.LIGHTS) - half_width,
		hero_position.y + SCREEN_HEIGHT
	)


## 体の左上が hero_position の主人公の影の体の矩形。足元と横位置は shadow_position() の体と同じで、
## 高さを光源の倍率で伸び縮みさせる (敵との接触もこの矩形で判定する)
static func shadow_body_rect(hero_position: Vector2) -> Rect2:
	var at: Vector2 = shadow_position(hero_position)
	var height: float = (
		Hero.SIZE.y * Light.shadow_scale_at(hero_position.x + Hero.SIZE.x / 2.0, Stage.LIGHTS)
	)
	return Rect2(at.x, at.y + Hero.SIZE.y - height, Hero.SIZE.x, height)


## 体の左上が hero_position で hero_facing を向いている主人公の影の攻撃の範囲。反転区間では主人公と逆を向き、
## リーチは光源の倍率で伸び縮みする。高さは主人公と同じ (足元から同じ高さに出て、地面に立つ敵に届く)
static func shadow_attack_area(hero_position: Vector2, hero_facing: float) -> Rect2:
	var center_x: float = hero_position.x + Hero.SIZE.x / 2.0
	return Hero.attack_area(
		shadow_position(hero_position),
		hero_facing * Light.shadow_direction(center_x, Stage.LIGHTS),
		Hero.ATTACK_REACH * Light.shadow_scale_at(center_x, Stage.LIGHTS)
	)


## light (Stage.LIGHTS の要素) の反転区間で、影の体の中心が逆へ動く範囲の下の画面の矩形 (地面より上)。
## 光源の x から左へ、反転区間の幅に光源の倍率を掛けた幅
static func shadow_reverse_range(light: Dictionary) -> Rect2:
	var width: float = light["zone"] * Light.shadow_scale(light["height"])
	return Rect2(light["x"] - width, SCREEN_HEIGHT, width, Stage.GROUND_Y)


## 主人公の中心が hero_center_x の時の横スクロール量。主人公を画面の中央に置き、ステージの外は映さない
static func scroll_for(hero_center_x: float) -> float:
	return clampf(hero_center_x - SCREEN_WIDTH / 2.0, 0.0, Stage.WIDTH - SCREEN_WIDTH)
