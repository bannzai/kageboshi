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


## direction (-1〜1) の左右入力と jump の入力で 1 物理フレーム進め、地形に沿って動かす
func physics_step(direction: float, jump: bool, delta: float) -> void:
	velocity = next_velocity(velocity, direction, jump, is_on_floor(), delta)
	move_and_slide()


## 入力と接地状態から求めた delta 秒後の速度。横は入力で決まり、縦は接地中のジャンプで初速を与え、
## それ以外は重力で加速する
static func next_velocity(
	current: Vector2, direction: float, jump: bool, on_floor: bool, delta: float
) -> Vector2:
	var vertical: float = current.y + GRAVITY * delta
	if jump and on_floor:
		vertical = JUMP_VELOCITY
	return Vector2(direction * MOVE_SPEED, vertical)
