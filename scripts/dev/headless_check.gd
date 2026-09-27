extends "res://scripts/dev/game_driver.gd"
## headless で実行する検証 (scripts/dev/selfcheck.gd と scripts/dev/integration.gd) が継承する土台。
## 検証の失敗の記録と、GameState の体力の比べ方を持つ (キー入力の送り方は scripts/dev/game_driver.gd)。

## 体力を持つ体を表す画面 (上の画面は主人公、下の画面は影)
const Combat := preload("res://scripts/combat.gd")

## 検証が 1 件でも失敗したか。true なら exit code 1 で終わる
var failed: bool = false


## cond が false なら label を ERROR として出し、失敗として記録する。
## ERROR の行頭には実行した検証のスクリプトの名前 (selfcheck / integration) を付ける
func _check(cond: bool, label: String) -> void:
	if not cond:
		push_error("%s FAIL: %s" % [get_script().resource_path.get_file().get_basename(), label])
		failed = true


## game_state (GameState のインスタンス) の主人公の体力が hero_hp、影の体力が shadow_hp か
func _hp_is(game_state: Node, hero_hp: int, shadow_hp: int) -> bool:
	return (
		game_state.hp[Combat.Lane.TOP] == hero_hp and game_state.hp[Combat.Lane.BOTTOM] == shadow_hp
	)
