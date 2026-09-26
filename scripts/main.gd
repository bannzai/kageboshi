extends Node2D
## 上下 2 画面の横スクロール。上の画面に主人公と地形、下の画面に影と同じ形の地形を置き、
## 1 台のカメラで上下を同じ横スクロール量で映す。影は主人公と同じ動きをする。

## 地形の定義
const Stage := preload("res://scripts/stage.gd")
## 主人公のスクリプト (体の大きさと 1 物理フレームの進め方)
const Hero := preload("res://scripts/hero.gd")

## 上の画面 1 つ分の高さ。project.godot の viewport (1280x720) を上下に 2 等分した値。
## 下の画面の影と地形は、上の画面のものからこの分だけ下にずらして置く
const SCREEN_HEIGHT: float = 360.0
## 画面の幅。project.godot の viewport の幅と同じ値
const SCREEN_WIDTH: float = 1280.0
## 上の画面の地形の色 (地面・段差・足場・壁)
const TOP_TERRAIN_COLOR: Color = Color(0.45, 0.4, 0.33, 1.0)
## 下の画面の地形の色 (影が張り付く地面・壁)
const BOTTOM_TERRAIN_COLOR: Color = Color(0.13, 0.14, 0.18, 1.0)

## カメラの横スクロール量 (画面の左端のステージ上の x)
var scroll_x: float = 0.0

## 上の画面の主人公
@onready var hero: Hero = $Hero
## 下の画面の影。位置は _sync_shadow() で主人公から導く
@onready var shadow: Node2D = $Shadow
## 上下の画面を同じスクロール量で映すカメラ
@onready var camera: Camera2D = $Camera
## 上の画面の地形 (当たり判定と見た目) を入れる親
@onready var top_terrain: Node2D = $TopTerrain
## 下の画面の地形 (見た目だけ) を入れる親。上の画面 1 つ分下にずらしてある
@onready var bottom_terrain: Node2D = $BottomTerrain


func _ready() -> void:
	print("kageboshi boot")
	_build_terrain()
	_sync_shadow()
	_follow_camera()


func _physics_process(delta: float) -> void:
	hero.physics_step(
		Input.get_axis("move_left", "move_right"), Input.is_action_just_pressed("jump"), delta
	)
	_sync_shadow()
	_follow_camera()


## Stage.TERRAIN の矩形ごとに、上の画面には当たり判定と見た目を、下の画面には見た目だけを置く
func _build_terrain() -> void:
	for rect: Rect2 in Stage.TERRAIN:
		var body: StaticBody2D = StaticBody2D.new()
		body.position = rect.position
		var shape: RectangleShape2D = RectangleShape2D.new()
		shape.size = rect.size
		var collision: CollisionShape2D = CollisionShape2D.new()
		collision.shape = shape
		collision.position = rect.size / 2.0
		body.add_child(collision)
		body.add_child(_terrain_rect(Rect2(Vector2.ZERO, rect.size), TOP_TERRAIN_COLOR))
		top_terrain.add_child(body)
		bottom_terrain.add_child(_terrain_rect(rect, BOTTOM_TERRAIN_COLOR))


## 親の座標で area を占める地形の見た目
func _terrain_rect(area: Rect2, color: Color) -> ColorRect:
	var rect: ColorRect = ColorRect.new()
	rect.position = area.position
	rect.size = area.size
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## 同期中の影の位置は主人公の位置から導く (.claude/rules/shadow-position-derived-from-hero.md)
func _sync_shadow() -> void:
	shadow.position = shadow_position(hero.position)


func _follow_camera() -> void:
	scroll_x = scroll_for(hero.position.x + hero.SIZE.x / 2.0)
	camera.position = Vector2(scroll_x, 0.0)


## 同期中の影の位置。主人公の位置から上の画面 1 つ分下
static func shadow_position(hero_position: Vector2) -> Vector2:
	return hero_position + Vector2(0.0, SCREEN_HEIGHT)


## 主人公の中心が hero_center_x の時の横スクロール量。主人公を画面の中央に置き、ステージの外は映さない
static func scroll_for(hero_center_x: float) -> float:
	return clampf(hero_center_x - SCREEN_WIDTH / 2.0, 0.0, Stage.WIDTH - SCREEN_WIDTH)
