extends RefCounted
## 遊ぶ順 (昼 → 夕方 → 夜) に並べたステージ。昼は高い光源だけで影が縮み、夕方は低い光源だけで影が伸び、
## 夜は高さの違う光源が点在して反転区間ごとに影が伸び縮みする。ステージ 1 本の形は scripts/stage.gd。

## ステージ 1 本の定義
const Stage := preload("res://scripts/stage.gd")
## 敵の出現先の画面 (Combat.Lane)
const Combat := preload("res://scripts/combat.gd")

## 昼の地形。地面から 1 回では越えられない高さの壁 (x = 1400) の手前に段 (x = 1340) を置き、段から跳び移れる
## ようにする。足場 (x = 1140) は段の前で跳ぶ主人公の頭に当たらないよう、段の手前で主人公の体の幅より広く空ける
const DAY_OBSTACLES: Array[Rect2] = [
	Rect2(560.0, 272.0, 160.0, 48.0),
	Rect2(1140.0, 224.0, 140.0, 16.0),
	Rect2(1340.0, 240.0, 60.0, 80.0),
	Rect2(1400.0, 160.0, 60.0, 160.0),
	Rect2(1900.0, 272.0, 240.0, 48.0),
]
## 昼の敵の出現位置
const DAY_SPAWNS: Array[Dictionary] = [
	{"x": 1760.0, "floor_y": Stage.GROUND_Y, "lane": Combat.Lane.TOP, "patrol": 240.0},
	{"x": 1860.0, "floor_y": Stage.GROUND_Y, "lane": Combat.Lane.BOTTOM, "patrol": 160.0},
	{"x": 2500.0, "floor_y": Stage.GROUND_Y, "lane": Combat.Lane.TOP, "patrol": 200.0},
	{"x": 2500.0, "floor_y": Stage.GROUND_Y, "lane": Combat.Lane.BOTTOM, "patrol": 200.0},
	{"x": 3000.0, "floor_y": Stage.GROUND_Y, "lane": Combat.Lane.BOTTOM, "patrol": 240.0},
]
## 昼の光源。どちらも高い街灯で、影が縮む
const DAY_LIGHTS: Array[Dictionary] = [
	{"x": 2300.0, "height": 280.0, "zone": 200.0},
	{"x": 2700.0, "height": 300.0, "zone": 160.0},
]

## 夕方の地形。x = 1300 と x = 1380 の 2 段を続けて登る
const EVENING_OBSTACLES: Array[Rect2] = [
	Rect2(480.0, 256.0, 120.0, 64.0),
	Rect2(900.0, 272.0, 200.0, 48.0),
	Rect2(1300.0, 240.0, 80.0, 80.0),
	Rect2(1380.0, 176.0, 80.0, 144.0),
	Rect2(2640.0, 264.0, 120.0, 56.0),
]
## 夕方の敵の出現位置
const EVENING_SPAWNS: Array[Dictionary] = [
	{"x": 1180.0, "floor_y": Stage.GROUND_Y, "lane": Combat.Lane.TOP, "patrol": 60.0},
	{"x": 1700.0, "floor_y": Stage.GROUND_Y, "lane": Combat.Lane.BOTTOM, "patrol": 160.0},
	{"x": 2300.0, "floor_y": Stage.GROUND_Y, "lane": Combat.Lane.TOP, "patrol": 120.0},
	{"x": 2980.0, "floor_y": Stage.GROUND_Y, "lane": Combat.Lane.TOP, "patrol": 180.0},
	{"x": 2980.0, "floor_y": Stage.GROUND_Y, "lane": Combat.Lane.BOTTOM, "patrol": 180.0},
	{"x": 3250.0, "floor_y": Stage.GROUND_Y, "lane": Combat.Lane.BOTTOM, "patrol": 160.0},
]
## 夕方の光源。どちらも低い松明で、影が伸びる
const EVENING_LIGHTS: Array[Dictionary] = [
	{"x": 1800.0, "height": 96.0, "zone": 160.0},
	{"x": 2400.0, "height": 80.0, "zone": 140.0},
]

## 夜の地形。x = 1780 と x = 1900 の 2 段を続けて登る
const NIGHT_OBSTACLES: Array[Rect2] = [
	Rect2(500.0, 272.0, 160.0, 48.0),
	Rect2(1150.0, 256.0, 80.0, 64.0),
	Rect2(1780.0, 272.0, 120.0, 48.0),
	Rect2(1900.0, 224.0, 80.0, 96.0),
	Rect2(3100.0, 256.0, 160.0, 64.0),
]
## 夜の敵の出現位置
const NIGHT_SPAWNS: Array[Dictionary] = [
	{"x": 1100.0, "floor_y": Stage.GROUND_Y, "lane": Combat.Lane.BOTTOM, "patrol": 40.0},
	{"x": 1720.0, "floor_y": Stage.GROUND_Y, "lane": Combat.Lane.TOP, "patrol": 40.0},
	{"x": 2500.0, "floor_y": Stage.GROUND_Y, "lane": Combat.Lane.TOP, "patrol": 100.0},
	{"x": 2500.0, "floor_y": Stage.GROUND_Y, "lane": Combat.Lane.BOTTOM, "patrol": 100.0},
	{"x": 3040.0, "floor_y": Stage.GROUND_Y, "lane": Combat.Lane.BOTTOM, "patrol": 60.0},
	{"x": 3450.0, "floor_y": Stage.GROUND_Y, "lane": Combat.Lane.TOP, "patrol": 150.0},
]
## 夜の光源。高さの違う街灯と松明が点在し、影が縮む区間と伸びる区間が交互に来る
const NIGHT_LIGHTS: Array[Dictionary] = [
	{"x": 900.0, "height": 200.0, "zone": 140.0},
	{"x": 1500.0, "height": 120.0, "zone": 140.0},
	{"x": 2200.0, "height": 240.0, "zone": 160.0},
	{"x": 2800.0, "height": 100.0, "zone": 140.0},
]


## 遊ぶ順に並べたステージ。呼ぶたびに作り直す (Stage は定数の配列を参照するだけで状態を持たない)
static func all() -> Array[Stage]:
	var stages: Array[Stage] = [
		Stage.new(
			"DAY", 3200.0, Color(0.79, 0.84, 0.89, 1.0), DAY_OBSTACLES, DAY_SPAWNS, DAY_LIGHTS
		),
		Stage.new(
			"EVENING",
			3400.0,
			Color(0.93, 0.64, 0.45, 1.0),
			EVENING_OBSTACLES,
			EVENING_SPAWNS,
			EVENING_LIGHTS
		),
		Stage.new(
			"NIGHT", 3600.0, Color(0.11, 0.13, 0.25, 1.0), NIGHT_OBSTACLES, NIGHT_SPAWNS, NIGHT_LIGHTS
		),
	]
	return stages


## ステージの数
static func count() -> int:
	return all().size()
