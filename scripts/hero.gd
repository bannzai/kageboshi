extends CharacterBody2D
## 上の画面の主人公。position は体の左上で、地形 (scripts/stage.gd の TERRAIN) と当たり判定する。
## 入力は main.gd が読み、physics_step() で 1 物理フレームずつ進める (影・カメラと同じフレームで更新するため)。

## 体の大きさ。scenes/main.tscn の Hero の CollisionShape2D と Body の大きさと同じ値
const SIZE: Vector2 = Vector2(40.0, 64.0)
## 横移動の速さ (px/秒)。1 秒で画面幅の 1/4 進む
const MOVE_SPEED: float = 320.0
## ジャンプの初速 (px/秒。負が上)。GRAVITY と合わせて最高点が約 114 px (体の高さの約 1.8 倍) になる
const JUMP_VELOCITY: float = -640.0
## 重力加速度 (px/秒²)。滞空が約 0.7 秒になる
const GRAVITY: float = 1800.0
## 攻撃が届く範囲の横幅 (体の前方)。敵 1 体分 (32 px) より少し長い
const ATTACK_REACH: float = 48.0
## 攻撃が届く範囲の高さ。ATTACK_TOP と合わせて、地面に立つ敵 (高さ 32 px) に届く高さにする
const ATTACK_HEIGHT: float = 32.0
## 攻撃の範囲の上端の、体の上端からの距離
const ATTACK_TOP: float = 16.0
## 攻撃が当たる時間 (秒)
const ATTACK_TIME: float = 0.15
## 攻撃を始めてから次の攻撃を始められるまでの時間 (秒)
const ATTACK_INTERVAL: float = 0.3

## 向いている向き (-1 = 左、1 = 右)。攻撃はこの向きに出る
var facing: float = 1.0
## 攻撃が当たる残り時間 (秒)。0 より大きい間は攻撃中
var attack_left: float = 0.0
## 次の攻撃を始められるまでの残り時間 (秒)
var attack_cooldown_left: float = 0.0

## 攻撃の範囲の見た目。攻撃中だけ表示する
@onready var attack_visual: ColorRect = $Attack


## direction (-1〜1) の左右入力と jump の入力で 1 物理フレーム進め、地形に沿って動かす
func physics_step(direction: float, jump: bool, delta: float) -> void:
	if direction != 0.0:
		facing = signf(direction)
	velocity = next_velocity(velocity, direction, jump, is_on_floor(), delta)
	move_and_slide()
	_tick_attack(delta)


## その場に止めたまま 1 物理フレーム進める (影縫いで主人公を縫い止めている間)。空中でも落ちず、
## 攻撃の時間だけが進む。縫い止めを解いた時に止める前の勢いで飛び出さないよう、速度は捨てる
func hold_step(delta: float) -> void:
	velocity = Vector2.ZERO
	_tick_attack(delta)


## 攻撃を始める。前の攻撃から ATTACK_INTERVAL 経っていなければ始めない。始めたら true
func start_attack() -> bool:
	if attack_cooldown_left > 0.0:
		return false
	attack_left = ATTACK_TIME
	attack_cooldown_left = ATTACK_INTERVAL
	_update_attack_visual()
	return true


## 攻撃中か
func is_attacking() -> bool:
	return attack_left > 0.0


## 体の矩形 (ステージ上の座標)
func body_rect() -> Rect2:
	return Rect2(position, SIZE)


func _tick_attack(delta: float) -> void:
	attack_left = maxf(attack_left - delta, 0.0)
	attack_cooldown_left = maxf(attack_cooldown_left - delta, 0.0)
	_update_attack_visual()


func _update_attack_visual() -> void:
	attack_visual.visible = is_attacking()
	attack_visual.position = attack_area(Vector2.ZERO, facing).position


## 体の左上が at で facing を向いている時の攻撃の範囲
static func attack_area(at: Vector2, facing_direction: float) -> Rect2:
	var left: float = at.x + SIZE.x if facing_direction > 0.0 else at.x - ATTACK_REACH
	return Rect2(left, at.y + ATTACK_TOP, ATTACK_REACH, ATTACK_HEIGHT)


## 入力と接地状態から求めた delta 秒後の速度。横は入力で決まり、縦は接地中のジャンプで初速を与え、
## それ以外は重力で加速する
static func next_velocity(
	current: Vector2, direction: float, jump: bool, on_floor: bool, delta: float
) -> Vector2:
	var vertical: float = current.y + GRAVITY * delta
	if jump and on_floor:
		vertical = JUMP_VELOCITY
	return Vector2(direction * MOVE_SPEED, vertical)
