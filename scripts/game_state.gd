extends Node
## ゲーム進行の状態 (autoload の GameState)。主人公と影で共有する体力と、被弾直後の無敵時間、
## 影縫いのゲージを持つ。体力が 0 になった状態をゲームオーバーとする。

## 体力の最大値。上下の画面の敵に 1 回ずつ触れても半分以上残り、立て直せる値にする
const MAX_HP: int = 5
## 被弾してから次のダメージを受けない時間 (秒)。敵に触れ続けても毎フレーム減らないようにする
const INVINCIBLE_TIME: float = 1.0
## 影縫いのゲージの最大値
const MAX_GAUGE: float = 1.0
## 縫い止めている間に 1 秒で減るゲージ。満タンから 2 秒縫い止められる
const GAUGE_DRAIN: float = 0.5
## 同期している間に 1 秒で回復するゲージ。空から 4 秒で満タンに戻る
const GAUGE_RECOVER: float = 0.25

## 残りの体力
var hp: int = MAX_HP
## 無敵の残り時間 (秒)。0 より大きい間はダメージを受けない
var invincible_left: float = 0.0
## 影縫いのゲージの残り。0 の間は縫い止められない
var gauge: float = MAX_GAUGE


## ステージの開始時の状態に戻す
func reset() -> void:
	hp = MAX_HP
	invincible_left = 0.0
	gauge = MAX_GAUGE


## 体力が 0 になっているか
func is_game_over() -> bool:
	return hp <= 0


## 無敵の間か
func is_invincible() -> bool:
	return invincible_left > 0.0


## amount だけ体力を減らし、無敵時間を始める。無敵の間とゲームオーバー後は減らさない。減らしたら true
func take_damage(amount: int) -> bool:
	if is_game_over() or is_invincible():
		return false
	hp = maxi(hp - amount, 0)
	invincible_left = INVINCIBLE_TIME
	return true


## delta 秒だけ無敵時間を進める
func tick(delta: float) -> void:
	invincible_left = maxf(invincible_left - delta, 0.0)


## ゲージが残っていて縫い止められるか
func has_gauge() -> bool:
	return gauge > 0.0


## delta 秒縫い止めた分だけゲージを減らす
func spend_gauge(delta: float) -> void:
	gauge = maxf(gauge - GAUGE_DRAIN * delta, 0.0)


## delta 秒同期した分だけゲージを回復する
func recover_gauge(delta: float) -> void:
	gauge = minf(gauge + GAUGE_RECOVER * delta, MAX_GAUGE)
