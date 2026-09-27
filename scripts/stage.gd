extends RefCounted
## ステージ 1 本の地形・敵の出現位置・光源・空の色。座標は上の画面 (主人公の世界) のもので、下の画面の地形と敵は
## ここから上の画面 1 つ分 (main.gd の SCREEN_HEIGHT) だけ下にずらして置く (描画では仕切り線を軸に上下反転する。
## main.gd の bottom_lane)。
## 遊ぶ順に並べたステージの一覧は scripts/stages.gd に置く。

## 敵の種類 (Enemy.Kind)
const Enemy := preload("res://scripts/enemy.gd")

## 地面の上端の y 座標。全ステージで共通
const GROUND_Y: float = 320.0
## 画面の右端からこの距離だけ先の出現位置まで出現させる (画面に入る直前に置き、出現の瞬間を見せない)
const SPAWN_AHEAD: float = 80.0
## ゴールの横幅。ゴールはステージの右端の壁の手前に置く
const GOAL_WIDTH: float = 80.0
## 左右の端の見えない壁・見えない天井の厚み
const BOUND_THICKNESS: float = 40.0

## ステージの ID。クリアしたステージとして保存データ (scripts/save_data.gd) に書く。変えると保存済みの進行が外れる
var id: String = ""
## 画面に出すステージの名前
var title: String = ""
## ステージの横幅。カメラはこの範囲の外を映さない
var width: float = 0.0
## 上の画面の空の色
var sky: Color = Color.WHITE
## 地面と左右の端の見えない壁を除いた地形 (足場・段差・壁) の矩形。x の昇順に並べる
var obstacles: Array[Rect2] = []
## 敵の出現位置。x の昇順に並べる。x は出現位置 (体の左端)、floor_y は足元の床の y 座標 (上の画面の座標)、
## lane は出現する画面 (scripts/combat.gd の Lane)、patrol は x から左へ往復する幅、kind は敵の種類
## (scripts/enemy.gd の Kind。書かなければ地面を歩く敵。spawn_kind())。往復の範囲は地形の段差・壁と重ならないように
## 置く。空を飛ぶ敵は、地形とその上に立つ主人公に触れず、地上の敵と往復の範囲が重ならない所に置く
var spawns: Array[Dictionary] = []
## 光源 (松明・街灯)。x の昇順に並べる。x は光源の位置、height は地面からの光源の高さ (scripts/light.gd の
## shadow_scale() で影の倍率になる)、zone は光源をまたいだ先 (右) の反転区間の幅。反転区間どうしは重ならないように置く。
## 高い地形から跳ぶと伸びた影の頭が下の画面の下端を越え、段差のそばでは逆へ動いた影が下の画面の段差に重なるため、
## 主人公と影が反転区間で動く範囲は地面だけの平らな所にする
var lights: Array[Dictionary] = []


## 各引数は同じ名前 (stage_ を除いた名前) のプロパティの値
func _init(
	stage_id: String,
	stage_title: String,
	stage_width: float,
	stage_sky: Color,
	stage_obstacles: Array[Rect2],
	stage_spawns: Array[Dictionary],
	stage_lights: Array[Dictionary]
) -> void:
	id = stage_id
	title = stage_title
	width = stage_width
	sky = stage_sky
	obstacles = stage_obstacles
	spawns = stage_spawns
	lights = stage_lights


## 地形の矩形。上の画面ではこの矩形が当たり判定になり、下の画面には同じ形を見た目だけ置く。
## 左の端の壁・地面・obstacles・右の端の壁の順に並べる。左右の端の壁はステージの外に出さないための見えない壁
func terrain() -> Array[Rect2]:
	var rects: Array[Rect2] = [
		Rect2(-BOUND_THICKNESS, 0.0, BOUND_THICKNESS, GROUND_Y + BOUND_THICKNESS),
		Rect2(0.0, GROUND_Y, width, BOUND_THICKNESS),
	]
	rects.append_array(obstacles)
	rects.append(Rect2(width, 0.0, BOUND_THICKNESS, GROUND_Y + BOUND_THICKNESS))
	return rects


## 上の画面の上端 (y = 0) より上に出ないための見えない天井。当たり判定だけを置き、下の画面へは写さない。
## 高い地形から跳んだ主人公が上端を越えると、上下反転して描く下の画面の影も下の画面の下端を越えて画面の外に出るため
func ceiling() -> Rect2:
	return Rect2(-BOUND_THICKNESS, -BOUND_THICKNESS, width + BOUND_THICKNESS * 2.0, BOUND_THICKNESS)


## ゴール。主人公の体がこの矩形に入るとステージクリアになる。ステージの右端の壁の手前に置く
func goal() -> Rect2:
	return Rect2(width - GOAL_WIDTH, 0.0, GOAL_WIDTH, GROUND_Y)


## spawn (spawns の要素) の敵の種類。kind を書いていない出現位置は地面を歩く敵にする。出現位置の大半は地面を歩く敵で、
## 全部に kind を書くと 1 行が lint の上限 (100 文字) を越えて 1 体ごとに複数行になるため、飛ぶ敵にだけ書く
static func spawn_kind(spawn: Dictionary) -> Enemy.Kind:
	return spawn.get("kind", Enemy.Kind.WALKER)


## 画面の右端が view_right の時に出現済みであるべき敵の数 (spawns の先頭からの個数)
func due_spawn_count(view_right: float) -> int:
	var count: int = 0
	for spawn: Dictionary in spawns:
		if spawn["x"] > view_right + SPAWN_AHEAD:
			break
		count += 1
	return count
