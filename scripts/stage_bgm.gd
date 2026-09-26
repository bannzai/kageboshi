extends RefCounted
## 昼・夕方・夜の BGM と、ステージごとの BGM の割り当て。素材は scripts/dev/generate_audio.py で作り、
## assets/CREDITS.md に記録する。効果音は scenes/main.tscn の Audio の下のノードが持つ。

## 昼のステージの BGM
const BGM_DAY := preload("res://assets/audio/bgm_day.ogg")
## 夕方のステージの BGM
const BGM_EVENING := preload("res://assets/audio/bgm_evening.ogg")
## 夜のステージの BGM
const BGM_NIGHT := preload("res://assets/audio/bgm_night.ogg")
## ステージの ID (scripts/stage.gd の ID) → BGM
const STAGE_BGM: Dictionary = {"stage1": BGM_DAY}


## stage_id のステージの BGM。素材の読み込み設定 (.import) はリポジトリに置かず Ogg Vorbis の繰り返しが既定で
## 無効のため、ここで繰り返しを有効にして、ステージの間途切れずに鳴らす
static func bgm_of(stage_id: String) -> AudioStreamOggVorbis:
	var bgm: AudioStreamOggVorbis = STAGE_BGM[stage_id]
	bgm.loop = true
	return bgm
