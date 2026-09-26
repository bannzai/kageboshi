extends RefCounted
## 攻撃の当たりと同期ボーナスの計算。上の画面と下の画面のどちらで当たったかを Lane で表す。

## 敵がいる画面・攻撃が当たった画面
enum Lane { TOP, BOTTOM }

## 1 回の攻撃が敵に与えるダメージ
const BASE_DAMAGE: int = 1
## 上下で同時に攻撃が当たったとみなす時間幅 (秒)。上下の当たりの時刻の差がこの値以下なら同時とする。
## 影の攻撃が数フレーム遅れて当たる場合も同時に数えるため、60 fps で 9 フレーム分の幅を取る
const SYNC_WINDOW: float = 0.15
## 同期ボーナスのダメージの倍率。敵の体力 (scripts/enemy.gd の MAX_HP) と同じにし、そろえた 1 回で倒せる
const SYNC_MULTIPLIER: int = 3


## 上の画面の最後の当たりが top_hit_time、下の画面の最後の当たりが bottom_hit_time (秒。当たりが無ければ負)
## の時、上下で同時に攻撃が当たったか
static func is_sync_hit(top_hit_time: float, bottom_hit_time: float) -> bool:
	if top_hit_time < 0.0 or bottom_hit_time < 0.0:
		return false
	return absf(top_hit_time - bottom_hit_time) <= SYNC_WINDOW


## 同期ボーナスの有無 sync で決まる 1 回の当たりのダメージ
static func hit_damage(sync: bool) -> int:
	return BASE_DAMAGE * SYNC_MULTIPLIER if sync else BASE_DAMAGE


## 同期ボーナスが後から成立した時に、先に通常のダメージで当たっていた敵へ足すダメージ
static func sync_extra_damage() -> int:
	return hit_damage(true) - hit_damage(false)
