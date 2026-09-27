extends Node2D
## 上の画面・下の画面のどちらかに出る敵。地形に関係なく、決まった幅を左右に往復する。
## 上の画面の敵は主人公に、下の画面の敵は影に触れるとダメージを与える (判定は main.gd)。

## 出現する画面 (Combat.Lane)
const Combat := preload("res://scripts/combat.gd")

## 体の大きさ。scenes/enemy.tscn の Body の見た目 (64 px 四方の絵を 0.5 倍) と同じ大きさ
const SIZE: Vector2 = Vector2(32.0, 32.0)
## 往復の速さ (px/秒)。主人公の移動の速さの約 1/5 で、近づいてから攻撃するまでの余裕を持たせる
const SPEED: float = 60.0
## 体力。同期ボーナスのない攻撃 (Combat.BASE_DAMAGE) なら 3 回で倒れる
const MAX_HP: int = 3

## 出現している画面
var lane: Combat.Lane = Combat.Lane.TOP
## 残りの体力。0 以下で倒れる
var hp: int = MAX_HP
## 往復する範囲の左端の x
var patrol_min_x: float = 0.0
## 往復する範囲の右端の x
var patrol_max_x: float = 0.0
## 進む向き (-1 = 左、1 = 右)
var direction: float = -1.0

## 敵の見た目。出現している画面の名前のアニメーション (上の画面は紫、下の画面は影の世界に溶け込みすぎない赤の
## スライム) を、進む向きに合わせて左右反転して歩かせる。絵は左を向いている
@onready var body: AnimatedSprite2D = $Body


func _ready() -> void:
	body.play(&"top" if lane == Combat.Lane.TOP else &"bottom")
	body.flip_h = direction > 0.0


## tree に入れる前に呼ぶ。at は体の左上で、そこから左へ patrol の幅を往復する
func setup(at_lane: Combat.Lane, at: Vector2, patrol: float) -> void:
	lane = at_lane
	position = at
	patrol_min_x = at.x - patrol
	patrol_max_x = at.x


## delta 秒だけ往復を進める
func physics_step(delta: float) -> void:
	var next: Vector2 = patrol_step(position.x, direction, patrol_min_x, patrol_max_x, delta)
	position.x = next.x
	direction = next.y
	body.flip_h = direction > 0.0


## 体の矩形 (ステージ上の座標)
func body_rect() -> Rect2:
	return Rect2(position, SIZE)


## damage だけ体力を減らす。倒れたら true
func take_hit(damage: int) -> bool:
	hp -= damage
	return hp <= 0


## x から direction の向きに delta 秒進めた (x, 向き)。min_x と max_x の間で折り返す
static func patrol_step(
	x: float, current_direction: float, min_x: float, max_x: float, delta: float
) -> Vector2:
	var next_x: float = x + current_direction * SPEED * delta
	if next_x <= min_x:
		return Vector2(min_x, 1.0)
	if next_x >= max_x:
		return Vector2(max_x, -1.0)
	return Vector2(next_x, current_direction)
