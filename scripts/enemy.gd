extends Node2D
## 上の画面・下の画面のどちらかに出る敵。地形に関係なく、決まった幅を左右に往復する。地面を歩く敵と、床から
## FLY_HEIGHT の高さを上下に揺れながら飛ぶ敵と、下の画面で縮んだ影の頭の上をかすめて低く飛ぶ敵がいる。
## 上の画面の敵は主人公に、下の画面の敵は影に触れるとダメージを与える (判定は main.gd)。

## 敵の種類。WALKER は地面を歩き、FLYER は空を飛び、LOW_FLYER は低く飛ぶ
enum Kind { WALKER, FLYER, LOW_FLYER }

## 出現する画面 (Combat.Lane)
const Combat := preload("res://scripts/combat.gd")
## 主人公のスクリプト (体の大きさ・ジャンプの最高点・攻撃の範囲)。飛ぶ敵の高さを導く
const Hero := preload("res://scripts/hero.gd")
## 体の大きさ。scenes/enemy.tscn の Body の見た目 (64 px 四方の絵を 0.5 倍) と同じ大きさ
const SIZE: Vector2 = Vector2(32.0, 32.0)
## 往復の速さ (px/秒)。主人公の移動の速さの約 1/5 で、近づいてから攻撃するまでの余裕を持たせる
const SPEED: float = 60.0
## 体力。同期ボーナスのない攻撃 (Combat.BASE_DAMAGE) なら 3 回で倒れる
const MAX_HP: int = 3
## 飛ぶ敵の体の中心の、足元の床からの高さ (揺れの中心)。床から跳んだ最高点にいる主人公の攻撃の範囲の中心と同じ
## 高さにし、最高点の近くで攻撃すれば当たり、床に立つ主人公の頭には触れず、地上の攻撃は届かない
const FLY_HEIGHT: float = (
	Hero.SIZE.y + Hero.JUMP_HEIGHT - Hero.ATTACK_TOP - Hero.ATTACK_HEIGHT / 2.0
)
## 飛ぶ敵が上下に揺れる幅 (揺れの中心から片側、px)。最も上・最も下に揺れても体の半分が最高点の攻撃の範囲に残る
const BOB_AMPLITUDE: float = 8.0
## 飛ぶ敵が上下に 1 往復する時間 (秒)
const BOB_PERIOD: float = 1.2
## 低く飛ぶ敵の下をくぐれる、高い光源で縮んだ影の倍率の上限 (scripts/light.gd の shadow_scale())。昼の街灯と
## 夜の高い街灯の倍率を含む
const DUCK_SCALE: float = 0.7
## 低く飛ぶ敵の体の下端の、足元の床からの高さ (揺れの中心)。倍率 1 の影 (主人公と同じ背丈) の頭の高さと、
## DUCK_SCALE の倍率で縮んだ影の頭の高さの中央にし、倍率 1 の影には当たり、縮んだ影には当たらない
const LOW_FLY_CLEARANCE: float = Hero.SIZE.y * (1.0 + DUCK_SCALE) / 2.0
## 低く飛ぶ敵が上下に揺れる幅 (揺れの中心から片側、px)。揺れても体の下端が LOW_FLY_CLEARANCE の上下の
## 影の頭の高さ (それぞれ約 10 px 離れている) の間に収まる
const LOW_BOB_AMPLITUDE: float = 4.0
## 種類と出現している画面 (Combat.Lane の順) ごとの見た目のアニメーション (scenes/enemy.tscn の SpriteFrames の名前)。
## 地面を歩く敵は上の画面が紫・下の画面が影の世界に溶け込みすぎない赤のスライム、空を飛ぶ敵は上の画面が黄色の蜂・
## 下の画面が灰色の蠅。低く飛ぶ敵は空を飛ぶ敵と同じ絵を速く羽ばたかせる
const ANIMATIONS: Dictionary = {
	Kind.WALKER: [&"top", &"bottom"],
	Kind.FLYER: [&"flyer_top", &"flyer_bottom"],
	Kind.LOW_FLYER: [&"low_flyer_top", &"low_flyer_bottom"],
}

## 出現している画面
var lane: Combat.Lane = Combat.Lane.TOP
## 敵の種類
var kind: Kind = Kind.WALKER
## 残りの体力。0 以下で倒れる
var hp: int = MAX_HP
## 往復する範囲の左端の x
var patrol_min_x: float = 0.0
## 往復する範囲の右端の x
var patrol_max_x: float = 0.0
## 進む向き (-1 = 左、1 = 右)
var direction: float = -1.0
## 揺れの中心の体の上端の y。飛ぶ敵はここから bob_offset() だけ上下する
var base_y: float = 0.0
## 出現してから進めた時間 (秒)。飛ぶ敵の揺れの位相に使う
var elapsed: float = 0.0

## 敵の見た目。種類と出現している画面の名前のアニメーション (ANIMATIONS) を、進む向きに合わせて左右反転して動かす。
## 絵は左を向いている
@onready var body: AnimatedSprite2D = $Body


func _ready() -> void:
	body.play(ANIMATIONS[kind][lane])
	body.flip_h = direction > 0.0


## tree に入れる前に呼ぶ。at は体の左上 (飛ぶ敵は揺れの中心) で、そこから左へ patrol の幅を往復する
func setup(at_lane: Combat.Lane, at_kind: Kind, at: Vector2, patrol: float) -> void:
	lane = at_lane
	kind = at_kind
	position = at
	base_y = at.y
	patrol_min_x = at.x - patrol
	patrol_max_x = at.x


## delta 秒だけ往復と揺れを進める
func physics_step(delta: float) -> void:
	var next: Vector2 = patrol_step(position.x, direction, patrol_min_x, patrol_max_x, delta)
	position.x = next.x
	direction = next.y
	elapsed += delta
	position.y = base_y + bob_offset(kind, elapsed)
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


## 出現してから time 秒の enemy_kind の敵の、揺れの中心からの y のずれ。飛ぶ敵と低く飛ぶ敵は BOB_PERIOD の周期で
## 上下に bob_amplitude() だけ揺れ (出現した瞬間は中心から下へ動き始める)、地面を歩く敵は揺れない
static func bob_offset(enemy_kind: Kind, time: float) -> float:
	return sin(TAU * time / BOB_PERIOD) * bob_amplitude(enemy_kind)


## enemy_kind の敵が上下に揺れる幅 (揺れの中心から片側、px)。地面を歩く敵は 0
static func bob_amplitude(enemy_kind: Kind) -> float:
	match enemy_kind:
		Kind.FLYER:
			return BOB_AMPLITUDE
		Kind.LOW_FLYER:
			return LOW_BOB_AMPLITUDE
	return 0.0


## 足元の床の y が floor_y の時の、enemy_kind の敵の体の上端の y (飛ぶ敵・低く飛ぶ敵は揺れの中心)
static func body_top(enemy_kind: Kind, floor_y: float) -> float:
	match enemy_kind:
		Kind.FLYER:
			return floor_y - FLY_HEIGHT - SIZE.y / 2.0
		Kind.LOW_FLYER:
			return floor_y - LOW_FLY_CLEARANCE - SIZE.y
	return floor_y - SIZE.y


## x から左へ patrol の幅を往復する、足元の床の y が floor_y の enemy_kind の敵の体が、往復と揺れで通る範囲
static func patrol_area(enemy_kind: Kind, x: float, floor_y: float, patrol: float) -> Rect2:
	var bob: float = bob_amplitude(enemy_kind)
	return Rect2(
		x - patrol, body_top(enemy_kind, floor_y) - bob, patrol + SIZE.x, SIZE.y + bob * 2.0
	)
