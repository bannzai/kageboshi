extends RefCounted
## ステージの地形・敵の出現位置・光源の定義。座標は上の画面 (主人公の世界) のもので、下の画面の地形と敵は
## ここから上の画面 1 つ分 (main.gd の SCREEN_HEIGHT) だけ下にずらして置く。

## 敵の出現先の画面 (Combat.Lane)
const Combat := preload("res://scripts/combat.gd")

## ステージの ID。クリアしたステージとして保存データ (scripts/save_data.gd) に書く。変えると保存済みの進行が外れる
const ID: String = "stage1"

## ステージの横幅。カメラはこの範囲の外を映さない
const WIDTH: float = 3200.0
## 地面の上端の y 座標
const GROUND_Y: float = 320.0
## 地形 (足場・段差・壁) の矩形。上の画面ではこの矩形が当たり判定になり、下の画面には同じ形を見た目だけ置く。
## 左右の端の壁はステージの外に出さないための見えない壁
const TERRAIN: Array[Rect2] = [
	Rect2(-40.0, 0.0, 40.0, 360.0),
	Rect2(0.0, GROUND_Y, WIDTH, 40.0),
	Rect2(560.0, 272.0, 160.0, 48.0),
	Rect2(1160.0, 224.0, 160.0, 16.0),
	Rect2(1400.0, 160.0, 60.0, 160.0),
	Rect2(1900.0, 272.0, 240.0, 48.0),
	Rect2(WIDTH, 0.0, 40.0, 360.0),
]
## 上の画面の上端 (y = 0) より上に出ないための見えない天井。当たり判定だけを置き、下の画面へは写さない
## (写すと上の画面の地面に重なる)。高い地形から跳んだ主人公が上端を越えると、上の画面 1 つ分下の影も
## 下の画面の上端を越えて上の画面に描かれるため
const CEILING: Rect2 = Rect2(-40.0, -40.0, WIDTH + 80.0, 40.0)
## ゴール。主人公の体がこの矩形に入るとステージクリアになる。ステージの右端の壁の手前に置く
const GOAL: Rect2 = Rect2(WIDTH - 80.0, 0.0, 80.0, GROUND_Y)
## 敵の出現位置。x の昇順に並べる。x は出現位置 (体の左端)、floor_y は足元の y 座標 (上の画面の座標)、
## lane は出現する画面、patrol は x から左へ往復する幅。往復の範囲は地形の段差・壁と重ならないように置く
const SPAWNS: Array[Dictionary] = [
	{"x": 1760.0, "floor_y": GROUND_Y, "lane": Combat.Lane.TOP, "patrol": 240.0},
	{"x": 1860.0, "floor_y": GROUND_Y, "lane": Combat.Lane.BOTTOM, "patrol": 160.0},
	{"x": 2500.0, "floor_y": GROUND_Y, "lane": Combat.Lane.TOP, "patrol": 200.0},
	{"x": 2500.0, "floor_y": GROUND_Y, "lane": Combat.Lane.BOTTOM, "patrol": 200.0},
	{"x": 3000.0, "floor_y": GROUND_Y, "lane": Combat.Lane.BOTTOM, "patrol": 240.0},
]
## 画面の右端からこの距離だけ先の出現位置まで出現させる (画面に入る直前に置き、出現の瞬間を見せない)
const SPAWN_AHEAD: float = 80.0
## 光源 (松明・街灯)。x の昇順に並べる。x は光源の位置、height は地面からの光源の高さ (scripts/light.gd の
## shadow_scale() で影の倍率になる)、zone は光源をまたいだ先 (右) の反転区間の幅。反転区間どうしは重ならないように置く。
## 1 つ目は高い街灯 (影が縮む)、2 つ目は低い松明 (影が伸びる)。高い地形 (壁の上) から跳ぶと伸びた影の頭が
## 下の画面の上端を越え、段差のそばでは逆へ動いた影が下の画面の段差に重なるため、主人公と影が反転区間で動く範囲は
## 地面だけの平らな所にする
const LIGHTS: Array[Dictionary] = [
	{"x": 2300.0, "height": 280.0, "zone": 200.0},
	{"x": 2700.0, "height": 96.0, "zone": 160.0},
]


## 画面の右端が view_right の時に出現済みであるべき敵の数 (SPAWNS の先頭からの個数)
static func due_spawn_count(view_right: float) -> int:
	var count: int = 0
	for spawn: Dictionary in SPAWNS:
		if spawn["x"] > view_right + SPAWN_AHEAD:
			break
		count += 1
	return count
