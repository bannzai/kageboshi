extends Node
## ゲーム進行の状態 (autoload の GameState)。主人公と影で共有する体力と、被弾直後の無敵時間を持つ。
## 体力が 0 になった状態をゲームオーバーとする。

## 体力の最大値。上下の画面の敵に 1 回ずつ触れても半分以上残り、立て直せる値にする
const MAX_HP: int = 5
## 被弾してから次のダメージを受けない時間 (秒)。敵に触れ続けても毎フレーム減らないようにする
const INVINCIBLE_TIME: float = 1.0

## 残りの体力
var hp: int = MAX_HP
## 無敵の残り時間 (秒)。0 より大きい間はダメージを受けない
var invincible_left: float = 0.0


## ステージの開始時の状態に戻す
func reset() -> void:
	hp = MAX_HP
	invincible_left = 0.0


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
