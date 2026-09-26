extends RefCounted
## 光源による影のずれの計算。光源は scripts/stage.gd の LIGHTS の形 ({"x", "height", "zone"}) で渡す。
## 主人公の体の中心が光源をまたいだ先の反転区間にいる間だけ、影の左右の動きが主人公と逆になり (光源の x を軸に
## 折り返す)、光源の高さで決まる倍率で影の移動量・見た目の長さ・攻撃のリーチが伸び縮みする。
## 反転区間の外では影は主人公と同期する (反転区間を抜けた時点で影は主人公の真下へ戻る)。

## 倍率 1 (主人公と同じ移動量・長さ・リーチ) になる光源の高さ (px)。上の画面の地面から上端までの高さ (320 px) の
## 半分にし、画面に描ける光源の高さの中央を基準にする。上端近くの高い光源で約 0.5 倍、地面近くの低い光源で 2 倍になる
const STANDARD_HEIGHT: float = 160.0
## 倍率の下限。上の画面の上端 (地面から 320 px) の光源の倍率で、これより高い光源 (真上の光源) でも影の攻撃のリーチが
## 半分 (24 px) より短くならず、下の画面の目の前の敵に届く
const MIN_SCALE: float = 0.5
## 倍率の上限。影の高さが主人公の 2 倍 (128 px) までなら、地面や段差から跳んでも影の頭が下の画面の上端を越えない
## (段差の上から跳んだ最高点で、影の頭は下の画面の上端から約 30 px 下)
const MAX_SCALE: float = 2.0


## 主人公の体の中心が hero_center_x の時、x が light_x の光源のどちら側にいるか (-1 = 左、1 = 右)。
## 光源の真下は、またいだ側 (右) とする
static func side_of(light_x: float, hero_center_x: float) -> float:
	return 1.0 if hero_center_x >= light_x else -1.0


## lights のうち、主人公の体の中心が hero_center_x の時にその反転区間 (光源の x から右へ zone の幅) に主人公がいる光源。
## どの反転区間にもいなければ空
static func active_light(hero_center_x: float, lights: Array[Dictionary]) -> Dictionary:
	for light: Dictionary in lights:
		if side_of(light["x"], hero_center_x) > 0.0 and hero_center_x < light["x"] + light["zone"]:
			return light
	return {}


## 地面からの高さが height (px) の光源の、影の移動量・見た目の長さ・攻撃のリーチに掛ける倍率。低い光源ほど大きい
static func shadow_scale(height: float) -> float:
	return clampf(STANDARD_HEIGHT / height, MIN_SCALE, MAX_SCALE)


## 主人公の体の中心が hero_center_x の時の影の倍率。反転区間の外は 1
static func shadow_scale_at(hero_center_x: float, lights: Array[Dictionary]) -> float:
	var light: Dictionary = active_light(hero_center_x, lights)
	return 1.0 if light.is_empty() else shadow_scale(light["height"])


## 主人公の体の中心が hero_center_x の時の、主人公に対する影の左右の向き (1 = 同じ、-1 = 逆)
static func shadow_direction(hero_center_x: float, lights: Array[Dictionary]) -> float:
	return 1.0 if active_light(hero_center_x, lights).is_empty() else -1.0


## 主人公の体の中心が hero_center_x の時の影の体の中心の x。反転区間では、主人公が光源から右へ離れた距離に倍率を
## 掛けて光源の左へ写す (光源をまたいだ瞬間は主人公と同じ位置で、そこから逆へ動く)。反転区間の外は主人公と同じ
static func shadow_center_x(hero_center_x: float, lights: Array[Dictionary]) -> float:
	var light: Dictionary = active_light(hero_center_x, lights)
	if light.is_empty():
		return hero_center_x
	return light["x"] - (hero_center_x - light["x"]) * shadow_scale(light["height"])
