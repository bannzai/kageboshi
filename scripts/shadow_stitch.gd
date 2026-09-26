extends RefCounted
## 影縫い (影を縫い止めて本体だけを動かす・本体を止めて影だけを動かす) と引き寄せの計算。
## 影のずれは、主人公から導いた同期中の影の位置 (main.gd の shadow_position) からの差 (ずれ) で表す。
## 縫い止めを解いてもずれは残り、引き寄せでずれを 0 に戻すと同期に戻る
## (.claude/rules/shadow-position-derived-from-hero.md)。

## 縫い止めているもの
enum Pin {
	NONE,  ## 縫い止めていない。影は主人公から導いた位置からずれの分だけ離れて、主人公と同じ動きをする
	SHADOW,  ## 影を縫い止めた位置に止め、主人公だけが動く
	HERO,  ## 主人公を止め、影だけが左右に動く
}

## 主人公の体の大きさと移動の速さ
const Hero := preload("res://scripts/hero.gd")
## ステージの横幅
const Stage := preload("res://scripts/stage.gd")

## 影が主人公から横に離れられる距離。主人公が画面の中央にいても影が画面の外に出ない幅にする
const MAX_OFFSET: float = 560.0
## 引き寄せで影が主人公へ戻る速さ (px/秒)。主人公の移動の速さの 3 倍で、最大のずれから約 0.6 秒で戻る
const PULL_SPEED: float = 960.0


## このフレームの縫い止め。current は前のフレームの縫い止め、*_pressed はそのボタンを押した瞬間か、
## *_held は押しているか。縫い止めはボタンを押した瞬間に始まり、押している間だけ続く。
## 引き寄せの途中 (pulling) とゲージ切れ (has_gauge が false) の間は縫い止めない
static func next_pin(
	current: Pin,
	shadow_pressed: bool,
	shadow_held: bool,
	hero_pressed: bool,
	hero_held: bool,
	pulling: bool,
	has_gauge: bool
) -> Pin:
	if pulling or not has_gauge:
		return Pin.NONE
	if current == Pin.SHADOW and shadow_held:
		return Pin.SHADOW
	if current == Pin.HERO and hero_held:
		return Pin.HERO
	if shadow_pressed:
		return Pin.SHADOW
	if hero_pressed:
		return Pin.HERO
	return Pin.NONE


## 同期中の影の位置が synced の時の、影が主人公から MAX_OFFSET より離れず、ステージの外に出ないずれ
static func clamp_offset(offset: Vector2, synced: Vector2) -> Vector2:
	var x: float = clampf(offset.x, -MAX_OFFSET, MAX_OFFSET)
	x = clampf(x, -synced.x, Stage.WIDTH - Hero.SIZE.x - synced.x)
	return Vector2(x, offset.y)


## 影を pinned に縫い止めている間の、同期中の影の位置が synced の時のずれ
static func pinned_offset(pinned: Vector2, synced: Vector2) -> Vector2:
	return clamp_offset(pinned - synced, synced)


## 主人公を止めて影だけを動かしている間の、direction (-1〜1) の左右入力で delta 秒後のずれ
static func running_offset(
	offset: Vector2, direction: float, synced: Vector2, delta: float
) -> Vector2:
	return clamp_offset(offset + Vector2(direction * Hero.MOVE_SPEED * delta, 0.0), synced)


## 縫い止めを解いた後に残すずれ。横のずれだけを残し、縦は主人公の高さに合わせ直す
## (縫い止めた影の高さのままだと、主人公が着地した時に影が地面に埋まる)
static func released_offset(offset: Vector2) -> Vector2:
	return Vector2(offset.x, 0.0)


## 引き寄せで delta 秒後のずれ。0 にちょうど届いたら同期に戻る
static func pulled_offset(offset: Vector2, delta: float) -> Vector2:
	return offset.move_toward(Vector2.ZERO, PULL_SPEED * delta)
