extends Node

## 全局进度：情感体悟、房屋重建、关卡解锁、离线收益。
## 注册为 Autoload，名字 GameState。

signal insight_changed(value: float)
signal house_changed(stage: int)

const SAVE_PATH := "user://jg_save.json"
## 设置单独放一个文件：清空存档不会把它一起清掉
const SETTINGS_PATH := "user://settings.json"
const AUTOSAVE_INTERVAL := 15.0

var insight := 0.0
var house_stage := 0
var cleared_count := 0
var last_seen := 0
## 已经出现过（弹过介绍）的敌人类型
var seen_enemies := {}
## 音效开关（存在 settings.json，和键位同一个文件）
var sfx_muted := false
## 键盘绑定：action -> Key 数字码
var binds := {
	"pause": KEY_SPACE,
	"speed": KEY_F,
	"back": KEY_ESCAPE,
	"upgrade": KEY_U,
	"remove": KEY_X,
}

var _autosave := 0.0
## 上一次广播出去的整数体悟值：只在「显示的数字」变了才发信号。
## 以前每帧都发，main 就每帧重建一遍 HUD 文本，纯属白烧 CPU。
var _emitted_insight := -1
## 跑无头自检/平衡模拟时置 false：模拟会调用 mark_cleared / add_insight，
## 如果不拦就会把模拟结果写进玩家真实存档。
var save_enabled := true


## 这些环境变量是给自检/截图用的开发入口。
## 只要带着它们启动，存档就一律只读 —— 守卫必须放在 Autoload 里，
## 而不是 main.gd：main.gd 解析失败过（也会让整局跑起来），
## 那种情况下守卫要是没生效，自检就会把玩家进度改掉。
const DEV_ENV := [
	"JG_BALANCE", "JG_GRIDCHECK", "JG_SELFTEST", "JG_SHIELDTEST",
	"JG_DEV_LEVEL", "JG_SHOT", "JG_WININFO",
]


func _ready() -> void:
	for k in DEV_ENV:
		if OS.has_environment(k):
			save_enabled = false
			print("GameState: 检测到 %s，存档改为只读" % k)
			break
	load_state()
	load_binds()
	_apply_offline_gain()
	set_process(true)


func _process(delta: float) -> void:
	var gain := read_rate() * delta
	if gain > 0.0:
		insight += gain
		# 只在显示出来的整数变化时广播：HUD 只关心 1 位小数以外的变化
		var shown := int(insight)
		if shown != _emitted_insight:
			_emitted_insight = shown
			insight_changed.emit(insight)
	_autosave += delta
	if _autosave >= AUTOSAVE_INTERVAL:
		_autosave = 0.0
		save_state()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		save_state()


# --- 派生数值 ---

## 每秒的情感体悟产出
func read_rate() -> float:
	return UnitData.READ_BASE * read_mult()


func read_mult() -> float:
	return float(UnitData.HOUSE_STAGES[house_stage]["read_mult"])


## 塔属性倍率。房屋重建会提高它，场上已有的分身也会立刻跟着变（见 BattleField）。
func tower_mult() -> float:
	return float(UnitData.HOUSE_STAGES[house_stage]["tower_mult"])


## 塔加成百分比，给界面显示用，例如 +26
func tower_bonus_percent() -> int:
	return int(round((tower_mult() - 1.0) * 100.0))


func house_name() -> String:
	return str(UnitData.HOUSE_STAGES[house_stage]["name"])


## 下一阶段花费，-1 表示已满级
func next_house_cost() -> int:
	if house_stage + 1 >= UnitData.HOUSE_STAGES.size():
		return -1
	return int(UnitData.HOUSE_STAGES[house_stage + 1]["cost"])


func next_house_name() -> String:
	if house_stage + 1 >= UnitData.HOUSE_STAGES.size():
		return ""
	return str(UnitData.HOUSE_STAGES[house_stage + 1]["name"])


# --- 交易 ---

func add_insight(amount: float) -> void:
	if amount <= 0.0:
		return
	insight += amount
	_emitted_insight = int(insight)
	insight_changed.emit(insight)


func buy_house_stage() -> bool:
	var cost := next_house_cost()
	if cost < 0 or insight < float(cost):
		return false
	insight -= float(cost)
	house_stage += 1
	insight_changed.emit(insight)
	house_changed.emit(house_stage)
	save_state()
	return true


## 买纸笔：只负责扣体悟。加纸笔由战斗层立刻给（一次性，关卡结束就没了）。
func buy_ink_pack() -> bool:
	var cost := int(UnitData.INK_PACK["cost"])
	if insight < float(cost):
		return false
	insight -= float(cost)
	insight_changed.emit(insight)
	save_state()
	return true


func ink_pack_cost() -> int:
	return int(UnitData.INK_PACK["cost"])


func ink_pack_bonus() -> int:
	return int(UnitData.INK_PACK["bonus"])


# --- 关卡进度 ---

func level_unlocked(index: int) -> bool:
	return index <= cleared_count


func mark_cleared(index: int) -> void:
	if index == cleared_count:
		cleared_count = index + 1
		save_state()


# --- 存档 ---

func save_state() -> void:
	if not save_enabled:
		return
	last_seen = int(Time.get_unix_time_from_system())
	var data := {
		"insight": insight,
		"house_stage": house_stage,
		"cleared_count": cleared_count,
		"seen_enemies": seen_enemies,
		"last_seen": last_seen,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("GameState: 无法写入存档")
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()


func load_state() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return
	var data: Dictionary = parsed
	insight = float(data.get("insight", 0.0))
	house_stage = clampi(int(data.get("house_stage", 0)), 0, UnitData.HOUSE_STAGES.size() - 1)
	cleared_count = clampi(int(data.get("cleared_count", 0)), 0, UnitData.BASE_DATA["levels"].size())
	var seen: Variant = data.get("seen_enemies", {})
	if seen is Dictionary:
		seen_enemies = seen
	last_seen = int(data.get("last_seen", 0))


func _apply_offline_gain() -> void:
	if last_seen <= 0:
		return
	var now := int(Time.get_unix_time_from_system())
	var elapsed := float(now - last_seen)
	if elapsed <= 0.0:
		return
	var capped := minf(elapsed, UnitData.OFFLINE_CAP)
	add_insight(read_rate() * capped)


func reset_progress() -> void:
	insight = 0.0
	house_stage = 0
	cleared_count = 0
	last_seen = 0
	seen_enemies = {}
	save_state()
	insight_changed.emit(insight)
	house_changed.emit(house_stage)


# --- 键位设置（写在单独的 settings.json，清空存档不会清掉）---

## 设置文件里既存键位也存音效开关；键位是平的 "action -> keycode"，
## 音效开关是额外的 sfx_muted 键，老存档没有这一项就按默认（开）处理。
func load_binds() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return
	var data: Dictionary = parsed
	for action in binds.keys():
		if data.has(action):
			binds[action] = int(data[action])
	sfx_muted = bool(data.get("sfx_muted", false))


func save_binds() -> void:
	var payload := binds.duplicate()
	payload["sfx_muted"] = sfx_muted
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()


func toggle_sfx() -> bool:
	sfx_muted = not sfx_muted
	save_binds()
	return sfx_muted


func bind_key(action: String) -> int:
	return int(binds.get(action, 0))


func set_bind(action: String, keycode: int) -> void:
	binds[action] = keycode
	save_binds()


static func key_label(keycode: int) -> String:
	if keycode == 0:
		return "未设置"
	if keycode == KEY_SPACE:
		return "空格"
	if keycode == KEY_ESCAPE:
		return "Esc"
	return OS.get_keycode_string(keycode)
