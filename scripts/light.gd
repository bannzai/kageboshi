extends RefCounted
## 光源による影の伸び縮みの計算。光源は scripts/stage.gd の LIGHTS の形 ({"x", "height", "zone"}) で渡す。
## 主人公の体の中心が光源の左右 zone の幅 (影響範囲) にいる間だけ、影は光源から遠ざかる向きに伸び、光源の高さで
## 決まる倍率で影の見た目の長さと、光源から遠ざかる向きへの攻撃のリーチが伸び縮みする。光源に近づく向きへの攻撃の
## リーチと、光源の真下の影は主人公と同じ。影の足元の位置と向きは影響範囲の中でも主人公と同期したまま変わらない。

## 倍率 1 (主人公と同じ長さ・リーチ) になる光源の高さ (px)。上の画面の地面から上端までの高さ (320 px) の
## 半分にし、画面に描ける光源の高さの中央を基準にする。上端近くの高い光源で約 0.5 倍、地面近くの低い光源で 2 倍になる
const STANDARD_HEIGHT: float = 160.0
## 倍率の下限。上の画面の上端 (地面から 320 px) の光源の倍率で、これより高い光源 (真上の光源) でも影の攻撃のリーチが
## 半分 (24 px) より短くならず、下の画面の目の前の敵に届く
const MIN_SCALE: float = 0.5
## 倍率の上限。影の高さが主人公の 2 倍 (128 px) までなら、地面や段差から跳んでも影の頭が下の画面の下端を越えない
## (段差の上から跳んだ最高点で、影の頭は下の画面の下端から約 30 px 上。下の画面は上下逆さまに描く)
const MAX_SCALE: float = 2.0


## 主人公の体の中心が hero_center_x の時、x が light_x の光源のどちら側にいるか (-1 = 左、1 = 右、0 = 真下)。
## 影はこの向き (光源から遠ざかる向き) に伸びる
static func side_of(light_x: float, hero_center_x: float) -> float:
	return signf(hero_center_x - light_x)


## lights のうち、主人公の体の中心が hero_center_x の時にその影響範囲 (光源の x から左右へ zone の幅) に主人公が
## いる光源。どの影響範囲にもいなければ空
static func active_light(hero_center_x: float, lights: Array[Dictionary]) -> Dictionary:
	for light: Dictionary in lights:
		if absf(hero_center_x - light["x"]) < light["zone"]:
			return light
	return {}


## 地面からの高さが height (px) の光源の、影の見た目の長さ・攻撃のリーチに掛ける倍率。低い光源ほど大きい
static func shadow_scale(height: float) -> float:
	return clampf(STANDARD_HEIGHT / height, MIN_SCALE, MAX_SCALE)


## 主人公の体の中心が hero_center_x の時に影が伸びる向き (-1 = 左、1 = 右)。影響範囲の外と光源の真下では 0
static func stretch_direction(hero_center_x: float, lights: Array[Dictionary]) -> float:
	var light: Dictionary = active_light(hero_center_x, lights)
	return 0.0 if light.is_empty() else side_of(light["x"], hero_center_x)


## 主人公の体の中心が hero_center_x の時の影の見た目の長さの倍率。影響範囲の外と光源の真下では 1
static func shadow_scale_at(hero_center_x: float, lights: Array[Dictionary]) -> float:
	if stretch_direction(hero_center_x, lights) == 0.0:
		return 1.0
	return shadow_scale(active_light(hero_center_x, lights)["height"])


## 主人公の体の中心が hero_center_x で facing (-1 = 左、1 = 右) を向いている時の影の攻撃のリーチの倍率。
## 影が伸びる向き (光源から遠ざかる向き) を向いている時だけ影の長さの倍率で、それ以外は 1
static func reach_scale_at(hero_center_x: float, facing: float, lights: Array[Dictionary]) -> float:
	if facing != stretch_direction(hero_center_x, lights):
		return 1.0
	return shadow_scale_at(hero_center_x, lights)
