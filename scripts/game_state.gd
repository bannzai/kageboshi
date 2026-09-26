extends Node
## ゲーム進行の状態 (autoload の GameState)。いま表示している画面 (タイトル・プレイ中・ポーズ・ゲームオーバー・
## ステージクリア・設定) と遊んでいるステージ、主人公と影で共有する体力、被弾直後の無敵時間、影縫いのゲージを持つ。
## 体力が 0 になるとゲームオーバーの画面に移る。

## 表示している画面。ステージが進むのは PLAYING の間だけ
enum Screen { TITLE, PLAYING, PAUSED, GAME_OVER, CLEAR, SETTINGS }
## 画面を切り替える操作 (project.godot の入力の confirm / pause / quit_to_title / open_settings と、
## 設定画面を閉じる操作 (Godot 組み込みの ui_cancel。scripts/settings_menu.gd が送る))
enum Command { CONFIRM, PAUSE, QUIT, SETTINGS, BACK }

## 遊ぶ順に並べたステージの一覧
const Stages := preload("res://scripts/stages.gd")
## ステージ 1 本の定義
const Stage := preload("res://scripts/stage.gd")

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
## 画面ごとに受け付ける操作と、その操作で移る画面。ここに無い操作はその画面では何もしない。
## ゲームオーバーとステージクリアへは操作ではなく、体力 (take_damage) とゴール (clear_stage) で移る。
## 最後のステージのクリアの画面では、CONFIRM でプレイ中ではなくタイトルへ移る (next_screen)
const TRANSITIONS: Dictionary = {
	Screen.TITLE: {Command.CONFIRM: Screen.PLAYING, Command.SETTINGS: Screen.SETTINGS},
	Screen.PLAYING: {Command.PAUSE: Screen.PAUSED},
	Screen.PAUSED: {Command.PAUSE: Screen.PLAYING, Command.QUIT: Screen.TITLE},
	Screen.GAME_OVER: {Command.CONFIRM: Screen.PLAYING, Command.QUIT: Screen.TITLE},
	Screen.CLEAR: {Command.CONFIRM: Screen.PLAYING},
	Screen.SETTINGS: {Command.BACK: Screen.TITLE},
}

## 表示している画面。起動時はタイトル
var screen: Screen = Screen.TITLE
## 遊んでいるステージの番号 (Stages.all() の添字)。起動時とタイトルへ戻った時は最初のステージ
var stage_index: int = 0
## 残りの体力
var hp: int = MAX_HP
## 無敵の残り時間 (秒)。0 より大きい間はダメージを受けない
var invincible_left: float = 0.0
## 影縫いのゲージの残り。0 の間は縫い止められない
var gauge: float = MAX_GAUGE


## ステージの開始時の体力とゲージに戻す
func reset() -> void:
	hp = MAX_HP
	invincible_left = 0.0
	gauge = MAX_GAUGE


## ステージが進む画面 (プレイ中) か
func is_playing() -> bool:
	return screen == Screen.PLAYING


## 体力が 0 になってゲームオーバーの画面にいるか
func is_game_over() -> bool:
	return screen == Screen.GAME_OVER


## 遊んでいるステージ
func current_stage() -> Stage:
	return Stages.all()[stage_index]


## 遊んでいるステージが最後のステージか
func is_last_stage() -> bool:
	return stage_index >= Stages.count() - 1


## 無敵の間か
func is_invincible() -> bool:
	return invincible_left > 0.0


## amount だけ体力を減らし、無敵時間を始める。無敵の間とゲームオーバー後は減らさない。減らしたら true。
## 0 になったらゲームオーバーの画面に移る
func take_damage(amount: int) -> bool:
	if is_game_over() or is_invincible():
		return false
	hp = maxi(hp - amount, 0)
	invincible_left = INVINCIBLE_TIME
	if hp == 0:
		screen = Screen.GAME_OVER
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


## プレイ中にゴールへ着いた時に、ステージクリアの画面に移る。プレイ中でなければ何もしない。移ったら true
func clear_stage() -> bool:
	if not is_playing():
		return false
	screen = Screen.CLEAR
	return true


## command の操作で画面を移す。遊んでいたステージを捨てて最初から作り直す遷移なら、体力を戻して true を返す
## (呼び出し側はステージのシーンを読み込み直す)
func send(command: Command) -> bool:
	var next: Screen = next_screen(screen, command, is_last_stage())
	if next == screen:
		return false
	var restart: bool = restarts_stage(screen, next)
	stage_index = next_stage_index(screen, next, stage_index)
	screen = next
	if restart:
		reset()
	return restart


## from の画面で command を操作した時に移る画面。受け付けない操作なら from のまま。
## last_stage は遊んでいるステージが最後のステージか (最後のステージのクリアからはタイトルへ移る)
static func next_screen(from: Screen, command: Command, last_stage: bool) -> Screen:
	var commands: Dictionary = TRANSITIONS.get(from, {})
	var next: Screen = commands.get(command, from)
	if from == Screen.CLEAR and next == Screen.PLAYING and last_stage:
		return Screen.TITLE
	return next


## from から to の画面へ移る時に、遊んでいたステージを最初から作り直すか。タイトルへ戻る時、
## ゲームオーバーからやり直す時と、ステージクリアから次のステージへ進む時に作り直す
## (ポーズからの再開とタイトルからの開始は、今のステージのまま続ける)。
## 設定画面はタイトルからしか開かず、ステージは始まる前のままなので、設定画面からタイトルへ戻る時は作り直さない
static func restarts_stage(from: Screen, to: Screen) -> bool:
	if from == Screen.SETTINGS:
		return false
	return (
		to == Screen.TITLE
		or (to == Screen.PLAYING and (from == Screen.GAME_OVER or from == Screen.CLEAR))
	)


## from から to の画面へ移った後に遊ぶステージの番号。index は移る前のステージの番号。
## タイトルへ戻ると最初のステージに、ステージクリアからプレイ中へ移ると次のステージになる
static func next_stage_index(from: Screen, to: Screen, index: int) -> int:
	if to == Screen.TITLE:
		return 0
	if from == Screen.CLEAR and to == Screen.PLAYING:
		return index + 1
	return index
