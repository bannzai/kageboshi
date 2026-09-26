extends Node2D
## 上下 2 画面の土台。上の画面に主人公、下の画面に影を置き、影は主人公と同じ動きをする。

## 上の画面 1 つ分の高さ。project.godot の viewport (1280x720) を上下に 2 等分した値。
## 下の画面の影は、主人公からこの分だけ下にずらして描く
const SCREEN_HEIGHT: float = 360.0
## 画面の幅。project.godot の viewport の幅と同じ値
const SCREEN_WIDTH: float = 1280.0
## 上の画面の地面の y 座標。scenes/main.tscn の TopFloor の上端と同じ値
const FLOOR_Y: float = 320.0
## 横移動の速さ (px/秒)。1 秒で画面幅の 1/4 進む仮の値で、操作感の調整はロードマップの子 issue で行う
const MOVE_SPEED: float = 320.0
## ジャンプの初速 (px/秒。負が上)。GRAVITY と合わせて最高点が約 114 px (主人公の高さの約 1.8 倍) になる仮の値
const JUMP_VELOCITY: float = -640.0
## 重力加速度 (px/秒²)。滞空が約 0.7 秒になる仮の値
const GRAVITY: float = 1800.0

## 主人公の縦の速度 (px/秒。負が上)
var velocity_y: float = 0.0

## 上の画面の主人公
@onready var hero: ColorRect = $Hero
## 下の画面の影。位置は _sync_shadow() で主人公から導く
@onready var shadow: ColorRect = $Shadow


func _ready() -> void:
	print("kageboshi boot")
	hero.position = Vector2(200.0, floor_top())
	_sync_shadow()


func _physics_process(delta: float) -> void:
	hero.position.x = next_x(
		hero.position.x, Input.get_axis("move_left", "move_right"), delta, SCREEN_WIDTH - hero.size.x
	)
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity_y = JUMP_VELOCITY
	var fall: Vector2 = next_fall(hero.position.y, velocity_y, delta, floor_top())
	hero.position.y = fall.x
	velocity_y = fall.y
	_sync_shadow()


## 主人公が地面に立っている時の上端の y 座標
func floor_top() -> float:
	return FLOOR_Y - hero.size.y


## 主人公が地面に立っているか
func is_on_floor() -> bool:
	return hero.position.y >= floor_top()


## 左右の入力 direction (-1〜1) で delta 秒進めた x。画面の左端 0 と右端 max_x の間に収める
static func next_x(x: float, direction: float, delta: float, max_x: float) -> float:
	return clampf(x + direction * MOVE_SPEED * delta, 0.0, max_x)


## 重力で delta 秒進めた (y, 縦の速度)。floor_y より下には行かず、着地したら速度を 0 にする
static func next_fall(y: float, velocity: float, delta: float, floor_y: float) -> Vector2:
	var next_velocity: float = velocity + GRAVITY * delta
	if y + next_velocity * delta >= floor_y:
		return Vector2(floor_y, 0.0)
	return Vector2(y + next_velocity * delta, next_velocity)


## 同期中の影の位置は主人公の位置から導く (.claude/rules/shadow-position-derived-from-hero.md)
func _sync_shadow() -> void:
	shadow.position = hero.position + Vector2(0.0, SCREEN_HEIGHT)
