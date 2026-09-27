extends Node2D
## 上下 2 画面の横スクロール。上の画面に主人公と地形、下の画面に影と同じ形の地形を置き、
## 1 台のカメラで上下を同じ横スクロール量で映す。下の画面は仕切り線を軸に上下逆さまに描き、主人公と影が足元を
## 向かい合わせる (bottom_lane)。影は主人公と同じ動き・同じ攻撃をし、光源の左右の影響範囲では光源から遠ざかる
## 向きに、光源の高さで決まる倍率だけ伸び縮みする (scripts/light.gd)。縮んだ影は下の画面の低く飛ぶ敵の下をくぐり、
## 伸びた影は股の下を下の画面の地面を歩く敵に通らせる (shadow_hit_rects())。光源の灯りと光の色は、その光源で影が
## 縮むか伸びるかで変える (lamp_color())。
## 影縫いで影か主人公を縫い止めると上下の位置がずれ、引き寄せで同期に戻る (scripts/shadow_stitch.gd)。
## 敵 (地面を歩く敵と空を飛ぶ敵) は上下どちらの画面にも出て、上の画面の敵が主人公に触れると主人公の体力、
## 下の画面の敵が影に触れると影の体力 (GameState) が減る。
## ステージが進むのはプレイ中の画面の間だけで、タイトル・ポーズ・ゲームオーバー・ステージクリア・設定の画面は
## GameState の画面に合わせて重ねて表示する。ステージを最初からやり直す時と次のステージへ進む時は、このシーンを
## 読み込み直す。遊んでいるステージ (昼・夕方・夜) は GameState が持つ。
## ゴールに着いたらステージをクリア済みとして SaveData に保存する。
## ステージの BGM はプレイ中の間だけ鳴らし、攻撃・ダメージ・同期ボーナス・影縫いで効果音を鳴らす。BGM と効果音は
## 設定で音量を変えられるバス (SaveData の VOLUME_BUSES) で鳴らす。

## ステージ 1 本の地形・敵の出現位置・光源の定義
const Stage := preload("res://scripts/stage.gd")
## ステージごとの BGM
const StageBgm := preload("res://scripts/stage_bgm.gd")
## 光源による影の伸び縮みの計算
const Light := preload("res://scripts/light.gd")
## 主人公のスクリプト (体の大きさ・攻撃の範囲と 1 物理フレームの進め方)
const Hero := preload("res://scripts/hero.gd")
## 敵のスクリプト (種類と、種類ごとの体の置き方)
const Enemy := preload("res://scripts/enemy.gd")
## 攻撃の当たりと同期ボーナスの計算
const Combat := preload("res://scripts/combat.gd")
## 影縫いと引き寄せの計算
const ShadowStitch := preload("res://scripts/shadow_stitch.gd")
## autoload の GameState のスクリプト。autoload 名の識別子で参照すると、--script で起動する
## scripts/dev/ の検証が autoload の登録前に main.gd をコンパイルして失敗するため、ノードとして取る
const GameStateScript := preload("res://scripts/game_state.gd")
## autoload の SaveData のスクリプト (GameStateScript と同じ理由でノードとして取る)
const SaveDataScript := preload("res://scripts/save_data.gd")
## 敵のシーン
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")

## 上の画面 1 つ分の高さ。project.godot の viewport (1280x720) を上下に 2 等分した値で、仕切り線の y でもある。
## 下の画面の影・地形・敵の判定の座標は、上の画面のものからこの分だけ下にずらした値 (描画の座標は bottom_lane)
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
## 影の長さが変わらない光源 (倍率 1) の灯りと、影響範囲を照らす光の色
const LAMP_LIGHT_COLOR: Color = Color(1.0, 0.86, 0.45, 1.0)
## 影が最も縮む高い光源 (倍率 Light.MIN_SCALE) の灯りと光の色。真昼の日差しのような白
const LAMP_SHRINK_COLOR: Color = Color(0.9, 0.97, 1.0, 1.0)
## 影が最も伸びる低い光源 (倍率 Light.MAX_SCALE) の灯りと光の色。夕日や松明のような赤みの強い橙
const LAMP_STRETCH_COLOR: Color = Color(1.0, 0.45, 0.12, 1.0)
## 伸びた影 (倍率が 1 より大きい影) の足元の、当たり判定の無い隙間の高さ。地面を歩く敵 (Enemy.SIZE.y) が影に
## 触れずに股の下を通れるよう、敵の背丈に 4 px の余裕を足す (隙間の上端と敵の頭がちょうど接する高さだと、主人公の
## 位置の小数の誤差で重なり得るため)
const STRADDLE_GAP: float = Enemy.SIZE.y + 4.0
## 上の画面で影響範囲を照らす光の不透明度 (地形・敵が透けて見える薄さにする)
const LAMP_BEAM_ALPHA: float = 0.3
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
	GameStateScript.Screen.CLEAR: [["confirm", "Next Stage"]],
}
## 最後のステージのクリアの画面の操作の案内 (SCREEN_HINTS と同じ形)。次のステージが無いのでタイトルへ戻る
const LAST_CLEAR_HINTS: Array = [["confirm", "Title"]]

## カメラの横スクロール量 (画面の左端のステージ上の x)
var scroll_x: float = 0.0
## ステージの敵の出現位置 (Stage.spawns) のうち出現させた数 (先頭から)
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
## 縫い止めているもの
var pin: ShadowStitch.Pin = ShadowStitch.Pin.NONE
## 影を縫い止めた位置 (下の画面の座標)。pin が SHADOW の間だけ使う
var pinned_position: Vector2 = Vector2.ZERO
## 同期中の影の位置 (shadow_position) からの影のずれ。ZERO なら同期している
var shadow_offset: Vector2 = Vector2.ZERO
## 引き寄せの途中か。ずれが 0 に戻ったら終わる
var pulling: bool = false

## 表示している画面と、遊んでいるステージ、主人公と影それぞれの体力 (autoload の GameState)
@onready var game_state: GameStateScript = get_node("/root/GameState")
## 遊んでいるステージ。シーンを読み込み直すまで変わらない
@onready var stage: Stage = game_state.current_stage()
## クリアしたステージとキー割り当ての保存 (autoload の SaveData)
@onready var save_data: SaveDataScript = get_node("/root/SaveData")
## 上の画面の主人公
@onready var hero: Hero = $Hero
## 下の画面に描くもの (地形・敵・影) の親。子の位置は判定の座標 (上の画面の座標から SCREEN_HEIGHT
## だけ下) のまま置き、この親の変換 (_ready() で y を反転して 3 * SCREEN_HEIGHT だけ下へ動かす) で描画の座標へ写す。
## 判定の y が SCREEN_HEIGHT + h (上の画面の y = h) のものは描画の y = 2 * SCREEN_HEIGHT - h に描かれ、上の画面を
## 仕切り線 (y = SCREEN_HEIGHT) で上下反転した位置になる (主人公の足元の y = 320 と影の足元の描画の y = 400 が
## 仕切り線をはさんで向かい合う)。x は反転しない
@onready var bottom_lane: Node2D = $BottomLane
## 下の画面の影。位置は _sync_shadow() で主人公とずれから導く
@onready var shadow: Node2D = $BottomLane/Shadow
## 影の体の見た目。主人公の体の見た目と同じ絵を暗く塗ったもので、高さは光源の倍率で伸び縮みする
@onready var shadow_body: AnimatedSprite2D = $BottomLane/Shadow/Body
## 伸びた影の足元の隙間の左右に描く脚 (見た目だけで当たり判定は無い)。伸びている間だけ表示する
@onready var shadow_legs: Array[ColorRect] = [
	$BottomLane/Shadow/LegLeft as ColorRect, $BottomLane/Shadow/LegRight as ColorRect
]
## 影の攻撃の見た目。主人公の攻撃から導く
@onready var shadow_attack: ColorRect = $BottomLane/Shadow/Attack
## 影を縫い止めている間に影の足元に刺す針の見た目
@onready var shadow_needle: ColorRect = $BottomLane/Shadow/Needle
## 主人公を縫い止めている間に主人公の足元に刺す針の見た目
@onready var hero_needle: ColorRect = $Hero/Needle
## 上下の画面を同じスクロール量で映すカメラ
@onready var camera: Camera2D = $Camera
## 上の画面の地形 (当たり判定と見た目) を入れる親
@onready var top_terrain: Node2D = $TopTerrain
## 下の画面の地形 (見た目だけ) を入れる親。上の画面 1 つ分下にずらしてある
@onready var bottom_terrain: Node2D = $BottomLane/BottomTerrain
## 上の画面の光源と影響範囲を照らす光 (見た目だけ) を入れる親
@onready var lights: Node2D = $Lights
## 敵を入れる親。Combat.Lane で引く (上の画面の敵は Enemies、下の画面の敵は BottomLane/Enemies)
@onready var lane_enemies: Array[Node2D] = [$Enemies as Node2D, $BottomLane/Enemies as Node2D]
## 上下の画面の仕切り線に重ねる光。同期ボーナスの時だけ不透明にしてから消す
@onready var sync_flash: ColorRect = $Overlay/SyncFlash
## 主人公の体力の表示 (上の画面)
@onready var hp_label: Label = $Overlay/HpLabel
## 影の体力の表示 (下の画面)
@onready var shadow_hp_label: Label = $Overlay/ShadowHpLabel
## 遊んでいるステージの番号と名前の表示
@onready var stage_label: Label = $Overlay/StageLabel
## 上の画面の背景。ステージの空の色で塗る
@onready var sky: ColorRect = $Background/TopScreen
## 影縫いのゲージの枠
@onready var gauge_bar: ColorRect = $Overlay/GaugeBar
## 影縫いのゲージの残り
@onready var gauge_fill: ColorRect = $Overlay/GaugeBar/Fill
## 影縫いのゲージの名前の表示
@onready var gauge_label: Label = $Overlay/GaugeLabel
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
## ステージの BGM (BGM バス)
@onready var bgm_player: AudioStreamPlayer = $Audio/Bgm
## 攻撃の効果音 (SE バス)
@onready var attack_sound: AudioStreamPlayer = $Audio/Attack
## ダメージの効果音 (SE バス)
@onready var damage_sound: AudioStreamPlayer = $Audio/Damage
## 同期ボーナスの効果音 (SE バス)
@onready var sync_sound: AudioStreamPlayer = $Audio/Sync
## 影縫いの効果音 (SE バス)
@onready var stitch_sound: AudioStreamPlayer = $Audio/Stitch


func _ready() -> void:
	print("kageboshi boot")
	game_state.reset()
	bgm_player.stream = StageBgm.bgm_of(stage.id)
	sync_flash.color = SYNC_COLOR
	sky.color = stage.sky
	stage_label.text = "STAGE %d  %s" % [game_state.stage_index + 1, stage.title]
	if game_state.is_last_stage():
		$Screens/Clear/Label.text = "ALL CLEAR"
	goal.position = stage.goal().position
	goal.size = stage.goal().size
	goal.color = GOAL_COLOR
	bottom_lane.transform = Transform2D(
		0.0, Vector2(1.0, -1.0), 0.0, Vector2(0.0, SCREEN_HEIGHT * 3.0)
	)
	camera.make_current()
	_build_terrain()
	_build_lights()
	_sync_shadow()
	# 主人公の絵は物理フレームの外 (process) で枚目が進むため、進んだ時にも影へ写して描画のずれを無くす
	hero.body.frame_changed.connect(_sync_shadow)
	_follow_camera()
	_update_hud()


func _physics_process(delta: float) -> void:
	if _handle_screen_input():
		return
	if game_state.is_playing():
		_step_stage(delta)
	_update_hud()
	_update_bgm()
	_update_animations()


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
		attack_sound.play()
	var direction: float = Input.get_axis("move_left", "move_right")
	_update_pin(delta)
	if pin == ShadowStitch.Pin.HERO:
		if direction != 0.0:
			hero.facing = signf(direction)
		hero.hold_step(delta)
	else:
		hero.physics_step(direction, Input.is_action_just_pressed("jump"), delta)
	_move_shadow_offset(direction, delta)
	_sync_shadow()
	_follow_camera()
	_spawn_due_enemies()
	for enemy: Enemy in _living_enemies():
		enemy.physics_step(delta)
	_resolve_attack_hits()
	_resolve_contact_damage()
	if hero.body_rect().intersects(stage.goal()) and game_state.clear_stage():
		save_data.mark_cleared(stage.id)


## lane の画面の、x から左へ patrol の幅を往復する kind の敵を置く。floor_y は足元の床の y 座標 (上の画面の座標)。
## kind の既定を地面を歩く敵にするのは、飛ぶ敵を足す前からある検証・撮影 (scripts/dev/) の呼び出しが地面を歩く敵を
## 置くものだから
func spawn_enemy(
	lane: Combat.Lane,
	x: float,
	floor_y: float,
	patrol: float,
	kind: Enemy.Kind = Enemy.Kind.WALKER
) -> Enemy:
	var enemy: Enemy = ENEMY_SCENE.instantiate()
	var at: Vector2 = Vector2(x, Enemy.body_top(kind, floor_y))
	if lane == Combat.Lane.BOTTOM:
		at.y += SCREEN_HEIGHT
	enemy.setup(lane, kind, at, patrol)
	lane_enemies[lane].add_child(enemy)
	return enemy


## ステージの地形 (Stage.terrain()) の矩形ごとに、上の画面には当たり判定と見た目を、下の画面には見た目だけを置く。
## 天井 (Stage.ceiling()) は当たり判定だけを置く
func _build_terrain() -> void:
	for rect: Rect2 in stage.terrain():
		var body: StaticBody2D = _collision_body(rect)
		body.add_child(_terrain_rect(Rect2(Vector2.ZERO, rect.size), TOP_TERRAIN_COLOR))
		top_terrain.add_child(body)
		bottom_terrain.add_child(_terrain_rect(rect, BOTTOM_TERRAIN_COLOR))
	add_child(_collision_body(stage.ceiling()))


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


## 親の座標で area を占める単色の見た目 (地形・光源)
func _terrain_rect(area: Rect2, color: Color) -> ColorRect:
	var rect: ColorRect = ColorRect.new()
	rect.position = area.position
	rect.size = area.size
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## ステージの光源 (Stage.lights) ごとに、上の画面に光源 (柱と灯り) と、光源の左右の影響範囲を照らす光を置く
## (影響範囲と、影が縮むか伸びるかの予兆。灯りと光の色は lamp_color())。主人公は画面の中央にいるため、影響範囲は
## 入る半画面前から見える
func _build_lights() -> void:
	for light: Dictionary in stage.lights:
		var x: float = light["x"]
		var lamp_y: float = Stage.GROUND_Y - light["height"]
		var color: Color = lamp_color(Light.shadow_scale(light["height"]))
		var beam: Polygon2D = Polygon2D.new()
		beam.polygon = PackedVector2Array(
			[
				Vector2(x, lamp_y),
				Vector2(x - light["zone"], Stage.GROUND_Y),
				Vector2(x + light["zone"], Stage.GROUND_Y)
			]
		)
		beam.color = Color(color, LAMP_BEAM_ALPHA)
		lights.add_child(beam)
		lights.add_child(_terrain_rect(Rect2(x - 3.0, lamp_y, 6.0, light["height"]), LAMP_POST_COLOR))
		lights.add_child(_terrain_rect(Rect2(x - 10.0, lamp_y - 12.0, 20.0, 14.0), color))


## 影縫い・引き寄せの入力とゲージから、このフレームの縫い止めを決める。縫い止めている間はゲージを減らす。
## プレイ中の _step_stage() からだけ呼ぶ (プレイ中の間だけ入力を受け付ける)
func _update_pin(delta: float) -> void:
	var desynced: bool = pin != ShadowStitch.Pin.NONE or shadow_offset != Vector2.ZERO
	if desynced and Input.is_action_just_pressed("pull_shadow"):
		pulling = true
	var next: ShadowStitch.Pin = ShadowStitch.next_pin(
		pin,
		Input.is_action_just_pressed("pin_shadow"),
		Input.is_action_pressed("pin_shadow"),
		Input.is_action_just_pressed("pin_hero"),
		Input.is_action_pressed("pin_hero"),
		pulling,
		game_state.has_gauge()
	)
	if next != pin:
		if pin == ShadowStitch.Pin.SHADOW:
			shadow_offset = ShadowStitch.released_offset(shadow_offset)
		if next == ShadowStitch.Pin.SHADOW:
			pinned_position = shadow.position
		if next != ShadowStitch.Pin.NONE:
			stitch_sound.play()
		pin = next
	if pin != ShadowStitch.Pin.NONE:
		game_state.spend_gauge(delta)


## 主人公が動いた後の影のずれを、縫い止め・引き寄せに合わせて進める。同期している間はゲージを回復する
func _move_shadow_offset(direction: float, delta: float) -> void:
	var synced: Vector2 = shadow_position(hero.position)
	match pin:
		ShadowStitch.Pin.SHADOW:
			shadow_offset = ShadowStitch.pinned_offset(pinned_position, synced, stage.width)
		ShadowStitch.Pin.HERO:
			shadow_offset = ShadowStitch.running_offset(
				shadow_offset, direction, synced, delta, stage.width
			)
		_:
			shadow_offset = ShadowStitch.clamp_offset(shadow_offset, synced, stage.width)
			if pulling:
				shadow_offset = ShadowStitch.pulled_offset(shadow_offset, delta)
				pulling = shadow_offset != Vector2.ZERO
			if shadow_offset == Vector2.ZERO:
				game_state.recover_gauge(delta)


## 影の位置・長さ・姿・攻撃は、主人公と主人公がいる影響範囲の光源から導いた同期中の影に、影縫いのずれを
## 足して導く (.claude/rules/shadow-position-derived-from-hero.md)。影の体の見た目は主人公の体の見た目と同じ
## アニメーションの同じ枚目を同じ向きで、影の体の矩形から足元の隙間 (straddle_gap()) を除いた部分 (当たり判定の
## 矩形) の足元の中央に置き、高さをその部分の高さに合わせて伸び縮みさせる。隙間には左右の脚を描く
func _sync_shadow() -> void:
	shadow.position = shadow_position(hero.position) + shadow_offset
	var body: Rect2 = shadow_body_rect(hero.position, stage.lights, shadow_offset)
	var gap: float = straddle_gap(hero.position, stage.lights)
	var torso: Rect2 = body.grow_side(SIDE_BOTTOM, -gap)
	shadow_body.position = Vector2(torso.get_center().x, torso.end.y) - shadow.position
	shadow_body.scale = Vector2(hero.body.scale.x, hero.body.scale.y * torso.size.y / Hero.SIZE.y)
	for leg: ColorRect in shadow_legs:
		leg.visible = gap > 0.0
		leg.position.y = torso.end.y - shadow.position.y
		leg.size.y = gap
	shadow_body.flip_h = hero.facing < 0.0
	shadow_body.animation = hero.body.animation
	shadow_body.frame = hero.body.frame
	var attack: Rect2 = shadow_attack_area(hero.position, hero.facing, stage.lights, shadow_offset)
	shadow_attack.visible = hero.attack_visual.visible
	shadow_attack.position = attack.position - shadow.position
	shadow_attack.size = attack.size
	shadow_needle.visible = pin == ShadowStitch.Pin.SHADOW
	hero_needle.visible = pin == ShadowStitch.Pin.HERO


func _follow_camera() -> void:
	scroll_x = scroll_for(hero.position.x + Hero.SIZE.x / 2.0, stage.width)
	camera.position = Vector2(scroll_x, 0.0)


## 画面の右端に近づいたステージの敵 (Stage.spawns) を出現させる
func _spawn_due_enemies() -> void:
	var due: int = stage.due_spawn_count(scroll_x + SCREEN_WIDTH)
	while spawned_count < due:
		var spawn: Dictionary = stage.spawns[spawned_count]
		spawn_enemy(
			spawn["lane"], spawn["x"], spawn["floor_y"], spawn["patrol"], Stage.spawn_kind(spawn)
		)
		spawned_count += 1


## 倒れて消える途中のものを除いた敵
func _living_enemies() -> Array[Enemy]:
	var living: Array[Enemy] = []
	for parent: Node2D in lane_enemies:
		for enemy: Enemy in parent.get_children():
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
		shadow_attack_area(hero.position, hero.facing, stage.lights, shadow_offset)
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


## 上の画面の敵が主人公に触れていたら主人公の体力を、下の画面の敵が影の当たり判定 (shadow_hit_rects()) に
## 触れていたら影の体力を減らす
func _resolve_contact_damage() -> void:
	var hero_rects: Array[Rect2] = [hero.body_rect()]
	var bodies: Array[Array] = [
		hero_rects, shadow_hit_rects(hero.position, stage.lights, shadow_offset)
	]
	for enemy: Enemy in _living_enemies():
		if (
			touches(bodies[enemy.lane], enemy.body_rect())
			and game_state.take_damage(enemy.lane, CONTACT_DAMAGE)
		):
			damage_sound.play()


## 同期ボーナスが出たことを、仕切り線の光と主人公・影の間の文字と効果音で知らせる
func _show_sync_effect() -> void:
	sync_sound.play()
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


## 主人公と影の体力・影縫いのゲージ・画面ごとの表示と、無敵の間の主人公・影それぞれの半透明を GameState に合わせる。
## タイトルの進行と操作の案内は SaveData の保存データとキー割り当てに合わせる
func _update_hud() -> void:
	hp_label.text = "HERO HP %d / %d" % [game_state.hp[Combat.Lane.TOP], game_state.MAX_HP]
	shadow_hp_label.text = (
		"SHADOW HP %d / %d" % [game_state.hp[Combat.Lane.BOTTOM], game_state.MAX_HP]
	)
	gauge_fill.size.x = gauge_bar.size.x * game_state.gauge / game_state.MAX_GAUGE
	var in_stage: bool = game_state.screen not in [
		GameStateScript.Screen.TITLE, GameStateScript.Screen.SETTINGS
	]
	hp_label.visible = in_stage
	shadow_hp_label.visible = in_stage
	stage_label.visible = in_stage
	gauge_label.visible = in_stage
	gauge_bar.visible = in_stage
	for screen: GameStateScript.Screen in screen_panels:
		var panel: Control = screen_panels[screen]
		panel.visible = game_state.screen == screen
	var hints: Array = SCREEN_HINTS.get(game_state.screen, [])
	if game_state.screen == GameStateScript.Screen.CLEAR and game_state.is_last_stage():
		hints = LAST_CLEAR_HINTS
	if not hints.is_empty():
		screen_panels[game_state.screen].get_node("Hint").text = hint_text(hints)
	progress_label.text = "Cleared stages: %d" % save_data.cleared_stages.size()
	progress_label.visible = not save_data.cleared_stages.is_empty()
	broken_save_label.visible = save_data.loaded_broken
	hero.modulate.a = INVINCIBLE_ALPHA if game_state.is_invincible(Combat.Lane.TOP) else 1.0
	shadow.modulate.a = INVINCIBLE_ALPHA if game_state.is_invincible(Combat.Lane.BOTTOM) else 1.0


## BGM をプレイ中の間だけ鳴らす。ポーズ・ゲームオーバー・ステージクリアの間は止め、プレイ中に戻ったら続きから鳴らす。
## タイトル・設定の画面ではまだ鳴らさない (プレイを始めた時に最初から鳴らす)
func _update_bgm() -> void:
	bgm_player.stream_paused = not game_state.is_playing()
	if game_state.is_playing() and not bgm_player.has_stream_playback():
		bgm_player.play()


## 主人公と敵の見た目のアニメーションはプレイ中の間だけ進め、ポーズ・ゲームオーバー・ステージクリアでは止める。
## 影の見た目は主人公の再生から写すため (_sync_shadow())、主人公と一緒に止まる
func _update_animations() -> void:
	var mode: ProcessMode = PROCESS_MODE_INHERIT if game_state.is_playing() else PROCESS_MODE_DISABLED
	hero.body.process_mode = mode
	for parent: Node2D in lane_enemies:
		parent.process_mode = mode


## hints ([アクション, 操作の説明] の並び) の操作の案内。キーは各アクションの今の 1 つ目のキー (「Enter: Start」)
static func hint_text(hints: Array) -> String:
	var parts: PackedStringArray = []
	for hint: Array in hints:
		parts.append("%s: %s" % [SaveDataScript.first_key_name(hint[0]), hint[1]])
	return "    ".join(parts)


## 体の左上が hero_position の主人公の同期中の影の位置 (伸び縮みさせる前の、主人公と同じ大きさの体の左上)。
## 主人公の上の画面 1 つ分下で、光源の影響範囲でも変わらない。
## 影縫いでずれている間の影は、ここから shadow_offset だけ離れる
static func shadow_position(hero_position: Vector2) -> Vector2:
	return hero_position + Vector2(0.0, SCREEN_HEIGHT)


## 体の左上が hero_position の主人公の、光源が lights (Stage.lights の形) のステージで影縫いのずれが offset の
## 影の体の矩形。足元と横位置は shadow_position() から offset だけ離れた体と同じで、高さを主人公がいる光源の倍率で
## 伸び縮みさせる (敵との接触はこの矩形から足元の隙間を除いた shadow_hit_rects() で判定する)。offset の既定の ZERO は
## 影縫いでずれていない同期中の影を表し、同期中の影だけを確かめる検証 (scripts/dev/selfcheck.gd の光源の検証) から
## 省いて呼べるようにする
static func shadow_body_rect(
	hero_position: Vector2, lights: Array[Dictionary], offset: Vector2 = Vector2.ZERO
) -> Rect2:
	var at: Vector2 = shadow_position(hero_position) + offset
	var height: float = (
		Hero.SIZE.y * Light.shadow_scale_at(hero_position.x + Hero.SIZE.x / 2.0, lights)
	)
	return Rect2(at.x, at.y + Hero.SIZE.y - height, Hero.SIZE.x, height)


## 体の左上が hero_position の主人公の、光源が lights のステージの影の足元にできる、当たり判定の無い隙間の高さ。
## 主人公がいる光源で影が伸びている (倍率が 1 より大きい) 間だけ STRADDLE_GAP で、それ以外は 0
static func straddle_gap(hero_position: Vector2, lights: Array[Dictionary]) -> float:
	var stretch: float = Light.shadow_scale_at(hero_position.x + Hero.SIZE.x / 2.0, lights)
	return STRADDLE_GAP if stretch > 1.0 else 0.0


## shadow_body_rect() と同じ引数の影の、下の画面の敵との当たり判定の矩形の集まり。影の体の矩形から、足元の
## 体の幅いっぱいの隙間 (straddle_gap()) を除いた形。地面を歩く敵は横から来るため、隙間の左右の脚に当たり判定が
## 残ると通り抜ける途中で必ず脚に触れる。そこで脚は見た目だけにし (_sync_shadow())、今は矩形 1 つになる。
## 縮んだ影は体の矩形のまま低くなり、頭の上を低く飛ぶ敵 (Enemy.Kind.LOW_FLYER) に触れない
static func shadow_hit_rects(
	hero_position: Vector2, lights: Array[Dictionary], offset: Vector2 = Vector2.ZERO
) -> Array[Rect2]:
	var body: Rect2 = shadow_body_rect(hero_position, lights, offset)
	var rects: Array[Rect2] = [
		body.grow_side(SIDE_BOTTOM, -straddle_gap(hero_position, lights))
	]
	return rects


## rects (当たり判定の矩形の集まり) のどれかが area に重なるか (辺が接するだけなら重ならない)
static func touches(rects: Array[Rect2], area: Rect2) -> bool:
	for rect: Rect2 in rects:
		if rect.intersects(area):
			return true
	return false


## 倍率が light_scale の光源 (Light.shadow_scale()) の灯りと光の色。倍率 1 は LAMP_LIGHT_COLOR で、影が縮むほど
## LAMP_SHRINK_COLOR の白に、伸びるほど LAMP_STRETCH_COLOR の橙に近づく
static func lamp_color(light_scale: float) -> Color:
	if light_scale < 1.0:
		var shrink: float = inverse_lerp(1.0, Light.MIN_SCALE, light_scale)
		return LAMP_LIGHT_COLOR.lerp(LAMP_SHRINK_COLOR, shrink)
	return LAMP_LIGHT_COLOR.lerp(LAMP_STRETCH_COLOR, inverse_lerp(1.0, Light.MAX_SCALE, light_scale))


## 体の左上が hero_position で hero_facing を向いている主人公の、光源が lights のステージで影縫いのずれが
## offset の影の攻撃の範囲。影の体 (shadow_position() から offset だけ離れた位置) から主人公と同じ向きに出て、
## 光源から遠ざかる向きを向いている時だけリーチが光源の倍率で伸び縮みする。高さは主人公と同じ (足元から同じ高さに
## 出て、地面に立つ敵に届く)。offset の既定の ZERO の意図は shadow_body_rect() と同じ
static func shadow_attack_area(
	hero_position: Vector2,
	hero_facing: float,
	lights: Array[Dictionary],
	offset: Vector2 = Vector2.ZERO
) -> Rect2:
	var center_x: float = hero_position.x + Hero.SIZE.x / 2.0
	return Hero.attack_area(
		shadow_position(hero_position) + offset,
		hero_facing,
		Hero.ATTACK_REACH * Light.reach_scale_at(center_x, hero_facing, lights)
	)


## light (Stage.lights の要素) の影響範囲に主人公の体の中心がある間に、主人公の体が動く上の画面の範囲 (地面より上)。
## 光源の x から左右へ zone の幅に、主人公の体の幅の半分ずつを足した幅
static func light_zone_range(light: Dictionary) -> Rect2:
	var half_width: float = light["zone"] + Hero.SIZE.x / 2.0
	return Rect2(light["x"] - half_width, 0.0, half_width * 2.0, Stage.GROUND_Y)


## 主人公の中心が hero_center_x の時の、横幅 stage_width のステージの横スクロール量。主人公を画面の中央に置き、
## ステージの外は映さない
static func scroll_for(hero_center_x: float, stage_width: float) -> float:
	return clampf(hero_center_x - SCREEN_WIDTH / 2.0, 0.0, stage_width - SCREEN_WIDTH)
