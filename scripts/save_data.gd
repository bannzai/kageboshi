extends Node
## 設定 (キー割り当て・BGM と効果音の音量) とクリアしたステージの保存と読み込み (autoload の SaveData)。
## 保存先はローカルの user:// の JSON 1 ファイル (ADR 0001) で、起動時に読み込み、変えるたびに書き出す。
## キー割り当ての今の値は InputMap が持ち、保存データには project.godot の既定と違うアクションだけを書く。
## 読めない・形が違う保存データは壊れたものとして既定値で始め、元のファイルは BROKEN_SUFFIX を付けて残す。
## 一部の値だけがおかしい時は、その値だけを既定値にして残りを使う。

## 保存先
const SAVE_PATH: String = "user://save.json"
## 保存データの形式の版。形式を変えたら上げ、parse() で古い版を読み替える
const VERSION: int = 1
## 壊れた保存データを退避する時にファイル名へ足す文字列。次の保存で上書きして失わないよう、読み込んだ時に退避する
const BROKEN_SUFFIX: String = ".broken"
## 書き出し途中のファイル名へ足す文字列。書き終えてから保存先へ移し、途中で落ちても保存データを壊さない
const WRITING_SUFFIX: String = ".writing"
## 音量を設定できるオーディオバス (BGM と効果音)。無ければ起動時に Master へ送るバスとして作る
const VOLUME_BUSES: Array[String] = ["BGM", "SE"]
## 音量 (0.0〜1.0) の既定値。最大 (素材そのままの音量) にし、BGM と効果音の釣り合いは素材の側で整える。
## 設定はプレイヤーが好みで下げるために使う
const DEFAULT_VOLUME: float = 1.0
## 音量の刻みの数。設定画面では 1 回に 1 / VOLUME_STEPS だけ変え、保存する音量もこの刻みに丸める
const VOLUME_STEPS: int = 10
## キー割り当てを変えられない Godot 組み込みのアクションの接頭辞。設定画面の操作に使うため固定する
const FIXED_ACTION_PREFIX: String = "ui_"

## 保存先。検証 (scripts/dev/) はプレイヤーの保存データを書き換えないよう load_from() で別の場所に変える
var path: String = SAVE_PATH
## バス名 (VOLUME_BUSES) → 音量 (0.0〜1.0)
var volumes: Dictionary = {}
## クリアしたステージの ID (scripts/stage.gd の ID)
var cleared_stages: Array[String] = []
## 直近の読み込みで保存データが壊れていて既定値で始めたか。タイトルで知らせ、次に保存したら消す
var loaded_broken: bool = false


func _ready() -> void:
	add_volume_buses()
	load_from(path)


## at の保存データを読み込み、キー割り当てと音量を反映する。以降の保存先も at にする。
## 無ければ既定値で始める。壊れていたら既定値で始め、ファイルを at + BROKEN_SUFFIX へ退避する。
## 退避するため、壊れたファイルを読んだ時だけは冪等でない (2 回目は保存データが無い扱いで loaded_broken が false になる)。
## 退避しないと、次の保存で壊れたファイルを上書きして、中身を確かめる手がかりが無くなる
func load_from(at: String) -> void:
	path = at
	var data: Dictionary = default_data()
	if FileAccess.file_exists(path):
		data = parse(FileAccess.get_file_as_string(path))
	loaded_broken = data["broken"]
	if loaded_broken:
		DirAccess.rename_absolute(path, path + BROKEN_SUFFIX)
	volumes = data["volumes"]
	cleared_stages = data["cleared_stages"]
	InputMap.load_from_project_settings()
	var keys: Dictionary = data["keys"]
	var rebindable: Array[String] = rebindable_actions()
	for action: String in keys:
		if rebindable.has(action):
			_set_action_keys(action, keys[action])
	_apply_volumes()


## 今の設定と進行を保存先へ書き出す。書き出せたら壊れていた知らせを消す
func save() -> Error:
	var writing: String = path + WRITING_SUFFIX
	var file: FileAccess = FileAccess.open(writing, FileAccess.WRITE)
	if file == null:
		var open_error: Error = FileAccess.get_open_error()
		push_error("保存データを書き出せない: %s (%s)" % [writing, error_string(open_error)])
		return open_error
	file.store_string(serialize(volumes, cleared_stages, key_overrides()))
	file.close()
	var status: Error = DirAccess.rename_absolute(writing, path)
	if status != OK:
		push_error("保存データを保存先へ移せない: %s (%s)" % [path, error_string(status)])
		return status
	loaded_broken = false
	return OK


## bus の音量を volume (0.0〜1.0。VOLUME_STEPS の刻みに丸める) にして反映し、保存する
func set_volume(bus: String, volume: float) -> void:
	volumes[bus] = snap_volume(volume)
	_apply_volumes()
	save()


## action のキーを keycode (物理キーコード) だけにして保存する。keycode を使っていた別のアクションの扱いは rebound()
func rebind(action: String, keycode: int) -> void:
	var bindings: Dictionary = rebound(current_bindings(), action, keycode)
	for bound: String in bindings:
		_set_action_keys(bound, bindings[bound])
	save()


## キー割り当てを project.godot の既定に戻して保存する
func reset_keys() -> void:
	InputMap.load_from_project_settings()
	save()


## stage_id のステージをクリア済みにして保存する。クリア済みなら何もしない
func mark_cleared(stage_id: String) -> void:
	if cleared_stages.has(stage_id):
		return
	cleared_stages.append(stage_id)
	save()


## 変えられるアクションごとの、project.godot の既定と違う今のキー (アクション → 物理キーコードの配列)
func key_overrides() -> Dictionary:
	var overrides: Dictionary = {}
	var current: Dictionary = current_bindings()
	var defaults: Dictionary = default_bindings()
	for action: String in current:
		if current[action] != defaults.get(action, []):
			overrides[action] = current[action]
	return overrides


## VOLUME_BUSES のうち無いバスを、Master へ送るバスとして足す。あるバスはそのままにする
static func add_volume_buses() -> void:
	for bus: String in VOLUME_BUSES:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var index: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus)
			AudioServer.set_bus_send(index, &"Master")


## action の今のキーの表示名 (「Left, A」のようにカンマで区切る)
static func key_names(action: String) -> String:
	var names: PackedStringArray = []
	for keycode: int in action_keys(action):
		names.append(OS.get_keycode_string(keycode))
	return ", ".join(names)


## action の今の 1 つ目のキーの表示名 (画面の操作の案内に使う)。キーが無ければ "-"
static func first_key_name(action: String) -> String:
	var keys: Array[int] = action_keys(action)
	return OS.get_keycode_string(keys[0]) if not keys.is_empty() else "-"


## キー割り当てを変えられるアクション (project.godot で定義したゲームのアクション)。
## Godot 組み込みのアクション (ui_* と、名前に "/" を含むエディタのアクション) は除く
static func rebindable_actions() -> Array[String]:
	var actions: Array[String] = []
	for action: StringName in InputMap.get_actions():
		var action_name: String = String(action)
		if not action_name.begins_with(FIXED_ACTION_PREFIX) and not action_name.contains("/"):
			actions.append(action_name)
	return actions


## 変えられるアクションごとの今のキー (アクション → 物理キーコードの配列)
static func current_bindings() -> Dictionary:
	var bindings: Dictionary = {}
	for action: String in rebindable_actions():
		bindings[action] = action_keys(action)
	return bindings


## 変えられるアクションごとの project.godot の既定のキー (アクション → 物理キーコードの配列)
static func default_bindings() -> Dictionary:
	var bindings: Dictionary = {}
	for action: String in rebindable_actions():
		var setting: Dictionary = ProjectSettings.get_setting("input/" + action, {})
		bindings[action] = _key_codes(setting.get("events", []))
	return bindings


## InputMap の action に割り当てたキーの物理キーコード
static func action_keys(action: String) -> Array[int]:
	return _key_codes(InputMap.action_get_events(action))


## event がキーを押した入力なら、その物理キーコード (物理キーコードが無い入力はキーコード)。それ以外は 0
static func pressed_key_code(event: InputEvent) -> int:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return 0
	return key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode


## bindings (アクション → 物理キーコードの配列) で action のキーを keycode だけにした割り当て。
## keycode を使っていた別のアクションからは keycode を外し、そのアクションのキーが無くなる場合は action が
## 使っていた残りのキーを譲る (入れ替え)。譲れるキーも無ければ、操作できなくならないよう keycode を残す
static func rebound(bindings: Dictionary, action: String, keycode: int) -> Dictionary:
	var released: Array[int] = []
	for old: int in bindings.get(action, []):
		if old != keycode:
			released.append(old)
	var result: Dictionary = {}
	for other: String in bindings:
		var keys: Array[int] = []
		keys.assign(bindings[other])
		if other != action and keys.has(keycode):
			keys.erase(keycode)
			if keys.is_empty() and not released.is_empty():
				keys.assign(released)
			elif keys.is_empty():
				keys.append(keycode)
		result[other] = keys
	var only: Array[int] = [keycode]
	result[action] = only
	return result


## 保存データの文字列。値の順序を固定し、同じ内容からは同じ文字列を作る
static func serialize(volume_by_bus: Dictionary, stages: Array[String], keys: Dictionary) -> String:
	return JSON.stringify(
		{"version": VERSION, "volumes": volume_by_bus, "cleared_stages": stages, "keys": keys},
		"\t",
		true
	)


## 保存データの文字列を解釈した値 (default_data() と同じ形)。JSON として読めない・
## 最上位が辞書でない・版が違う時は broken を true にして既定値を返す。値ごとに型や範囲がおかしいものは
## その値だけ既定値にする (音量は 0.0〜1.0 に収め、キーコードでない値・重複したステージは捨てる)
static func parse(text: String) -> Dictionary:
	var data: Dictionary = default_data()
	var json: JSON = JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		data["broken"] = true
		return data
	var root: Dictionary = json.data
	var version: Variant = root.get("version")
	if not _is_number(version) or version != VERSION:
		data["broken"] = true
		return data
	var volumes_in: Variant = root.get("volumes")
	if volumes_in is Dictionary:
		for bus: String in VOLUME_BUSES:
			var volume: Variant = volumes_in.get(bus)
			if _is_number(volume):
				data["volumes"][bus] = snap_volume(volume)
	var stages_in: Variant = root.get("cleared_stages")
	if stages_in is Array:
		var stages: Array[String] = data["cleared_stages"]
		for stage: Variant in stages_in:
			if stage is String and not stages.has(stage):
				stages.append(stage)
	var keys_in: Variant = root.get("keys")
	if keys_in is Dictionary:
		for action: Variant in keys_in:
			var codes: Array[int] = _valid_key_codes(keys_in[action])
			if action is String and not codes.is_empty():
				data["keys"][action] = codes
	return data


## 保存データが無い時の値。broken は壊れていたか、volumes はバス名 → 音量、cleared_stages はクリアした
## ステージの ID、keys は既定と違うアクション → 物理キーコードの配列
static func default_data() -> Dictionary:
	var volume_by_bus: Dictionary = {}
	for bus: String in VOLUME_BUSES:
		volume_by_bus[bus] = DEFAULT_VOLUME
	var stages: Array[String] = []
	return {"broken": false, "volumes": volume_by_bus, "cleared_stages": stages, "keys": {}}


## volume を 0.0〜1.0 に収め、1 / VOLUME_STEPS の刻みに丸めた音量。刻みの数で割って丸め、0.1 * 3 のような
## 誤差 (0.30000000000000004) を保存データに書かないようにする
static func snap_volume(volume: float) -> float:
	return clampf(roundf(volume * VOLUME_STEPS) / VOLUME_STEPS, 0.0, 1.0)


## action のキーを keycodes (物理キーコード) に差し替える。キー以外の入力 (ゲームパッド等) は残す
static func _set_action_keys(action: String, keycodes: Array[int]) -> void:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			InputMap.action_erase_event(action, event)
	for keycode: int in keycodes:
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = keycode as Key
		InputMap.action_add_event(action, event)


## volumes の音量を VOLUME_BUSES のバスに反映する。0 はミュートにする (linear_to_db(0) が -inf になるため)
func _apply_volumes() -> void:
	for bus: String in VOLUME_BUSES:
		var index: int = AudioServer.get_bus_index(bus)
		if index == -1:
			continue
		var volume: float = volumes[bus]
		AudioServer.set_bus_mute(index, volume == 0.0)
		if volume > 0.0:
			AudioServer.set_bus_volume_db(index, linear_to_db(volume))


## events のうちキーの入力の物理キーコード (物理キーコードが無い入力はキーコード)
static func _key_codes(events: Array) -> Array[int]:
	var codes: Array[int] = []
	for event: Variant in events:
		if event is InputEventKey:
			var key: InputEventKey = event
			var code: int = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
			if code != KEY_NONE and not codes.has(code):
				codes.append(code)
	return codes


## 保存データの 1 アクション分のキー (value) のうち、キーコードとして正しい値。配列でなければ空。
## 整数でない・範囲外の値が 1 つでもあれば、そのアクションの保存値ごと捨てる (空を返す)
static func _valid_key_codes(value: Variant) -> Array[int]:
	var codes: Array[int] = []
	if not (value is Array):
		return codes
	for code: Variant in value:
		if not _is_number(code) or code != floorf(code) or code <= 0 or code > KEY_CODE_MASK:
			codes.clear()
			return codes
		if not codes.has(int(code)):
			codes.append(int(code))
	return codes


## value が数 (JSON の数は float になる) か
static func _is_number(value: Variant) -> bool:
	return value is int or value is float
