extends Node

## 全局进度：情感体悟、书屋升级、关卡解锁、离线收益。
## 注册为 Autoload，名字 GameState。

signal insight_changed(value: float)
## 任何一条书屋升级变化（战斗层据此把新倍率套到已放的分身上）
signal upgrades_changed()

const SAVE_PATH := "user://jg_save.json"
## 设置单独放一个文件：清空存档不会把它一起清掉
const SETTINGS_PATH := "user://settings.json"
const AUTOSAVE_INTERVAL := 15.0

var insight := 0.0
## 书屋升级：id -> 等级（id 见 UnitData.UPGRADE_ORDER）
var upgrades := {}
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
## 跑无头自检/截图/平衡模拟时置 false：这些流程会调用 mark_cleared / add_insight，
## 如果不拦就会把模拟结果写进玩家真实存档。
var save_enabled := true
## 上一次广播出去的整数体悟值：只在「显示的数字」变了才发信号。
## 以前每帧都发，main 就每帧重建一遍 HUD 文本，纯属白烧 CPU。
var _emitted_insight := -1

## 这些环境变量是给自检/截图用的开发入口。
## 只要带着它们启动，存档就一律只读 —— 守卫必须放在 Autoload 里，
## 而不是 main.gd：main.gd 解析失败过（也会让整局跑起来），
## 那种情况下守卫要是没生效，自检就会把玩家进度改掉。
const DEV_ENV := [
	"JG_BALANCE", "JG_GRIDCHECK", "JG_SELFTEST", "JG_SHIELDTEST", "JG_TRANSTEST",
	"JG_DEV_LEVEL", "JG_SHOT", "JG_WININFO", "JG_HOME", "JG_HOUSE", "JG_TRANS", "JG_EDITOR",
]


func _ready() -> void:
	for k in DEV_ENV:
		if OS.has_environment(k):
			save_enabled = false
			print("GameState: 检测到 %s，存档改为只读" % k)
			break
	_init_upgrades()
	load_state()
	load_binds()
	_apply_offline_gain()
	set_process(true)


func _init_upgrades() -> void:
	upgrades.clear()
	for id in UnitData.UPGRADE_ORDER:
		upgrades[id] = 0


# --- 派生数值 ---

## 每秒的情感体悟产出
func read_rate() -> float:
	return UnitData.READ_BASE * read_mult()


func read_mult() -> float:
	return 1.0 + 0.30 * float(up_level("insight"))


## 纸笔自然回复倍率（战斗层用它乘到每关的回复速度上）
func ink_mult() -> float:
	return 1.0 + 0.12 * float(up_level("ink"))


## 分身属性倍率。升级后场上已有的分身也会立刻跟着变（见 BattleField）
func tower_mult() -> float:
	return 1.0 + 0.10 * float(up_level("power"))


## 塔加成百分比，给界面显示用，例如 +20
func tower_bonus_percent() -> int:
	return int(round((tower_mult() - 1.0) * 100.0))


## 第一波敌人额外延迟（秒）
func prep_time() -> float:
	return 1.5 * float(up_level("prep"))


## 战斗里能开到的最大倍速
func max_speed() -> float:
	return 2.0 + float(up_level("speed"))


## 分身能升到的最高等级
func tower_level_cap() -> int:
	return UnitData.TOWER_BASE_LEVEL_CAP + up_level("level")


## 书屋进度（0~1），用来给小屋插画调亮度
func house_progress() -> float:
	var total := 0
	var got := 0
	for id in UnitData.UPGRADE_ORDER:
		total += int(UnitData.UPGRADES[id]["max"])
		got += up_level(id)
	if total <= 0:
		return 0.0
	return float(got) / float(total)


func house_level_sum() -> int:
	var got := 0
	for id in UnitData.UPGRADE_ORDER:
		got += up_level(id)
	return got


func house_level_total() -> int:
	var total := 0
	for id in UnitData.UPGRADE_ORDER:
		total += int(UnitData.UPGRADES[id]["max"])
	return total


# --- 书屋升级 ---

func up_level(id: String) -> int:
	return int(upgrades.get(id, 0))


func up_max(id: String) -> int:
	return int((UnitData.UPGRADES.get(id, {}) as Dictionary).get("max", 0))


## 下一级价格；-1 = 已满级
func up_cost(id: String) -> int:
	var def: Dictionary = UnitData.UPGRADES.get(id, {})
	var costs: Array = def.get("costs", [])
	var lv := up_level(id)
	if lv >= int(def.get("max", 0)) or lv >= costs.size():
		return -1
	return int(costs[lv])


func can_buy_upgrade(id: String) -> bool:
	var cost := up_cost(id)
	return cost >= 0 and insight >= float(cost)


func buy_upgrade(id: String) -> bool:
	var cost := up_cost(id)
	if cost < 0 or insight < float(cost):
		return false
	insight -= float(cost)
	upgrades[id] = up_level(id) + 1
	_emitted_insight = int(insight)
	insight_changed.emit(insight)
	upgrades_changed.emit()
	save_state()
	return true


# --- 交易 ---

func add_insight(amount: float) -> void:
	if amount <= 0.0:
		return
	insight += amount
	_emitted_insight = int(insight)
	insight_changed.emit(insight)


## 买纸笔：只负责扣体悟。加纸笔由战斗层立刻给（一次性，关卡结束就没了）
func buy_ink_pack() -> bool:
	var cost := int(UnitData.INK_PACK["cost"])
	if insight < float(cost):
		return false
	insight -= float(cost)
	_emitted_insight = int(insight)
	insight_changed.emit(insight)
	save_state()
	return true


func ink_pack_cost() -> int:
	return int(UnitData.INK_PACK["cost"])


func ink_pack_bonus() -> int:
	return int(UnitData.INK_PACK["bonus"])


# --- 关卡进度 ---

func mark_cleared(index: int) -> void:
	if index == cleared_count:
		cleared_count = index + 1
		save_state()


# --- 存档 ---

## 写存档。force 只给 reset_progress() 用 —— 只有「玩家明确点了清档」才允许把进度写成全零。
##
## 这道保险是踩过坑加的：某次自检/编辑器流程在 save_enabled 没生效的瞬间调了 reset，
## 结果把玩家几千体悟和整套书屋升级写成了 0。写之前比一下磁盘上的旧档，
## 发现「内存里全空、磁盘上有进度」就拒绝，宁可这一帧不存。
func save_state(force := false) -> void:
	if not save_enabled:
		return
	if not force and _is_blank_progress() and _disk_has_progress():
		push_warning("GameState: 拒绝用空进度覆盖存档（不是明确清档）")
		return
	last_seen = int(Time.get_unix_time_from_system())
	var data := {
		"insight": insight,
		"upgrades": upgrades,
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


## 内存里的进度是否已经「空」了（被打回初始状态）
func _is_blank_progress() -> bool:
	if insight > 0.5 or cleared_count > 0:
		return false
	for id in UnitData.UPGRADE_ORDER:
		if up_level(id) > 0:
			return false
	return true


## 磁盘上的旧档是否还有进度
func _disk_has_progress() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return false
	var d: Dictionary = parsed
	if float(d.get("insight", 0.0)) > 0.5 or int(d.get("cleared_count", 0)) > 0:
		return true
	var ups: Variant = d.get("upgrades", null)
	if ups is Dictionary:
		for id in UnitData.UPGRADE_ORDER:
			if int((ups as Dictionary).get(id, 0)) > 0:
				return true
	return int(d.get("house_stage", 0)) > 0


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
	cleared_count = clampi(int(data.get("cleared_count", 0)), 0, UnitData.BASE_DATA["levels"].size())
	var seen: Variant = data.get("seen_enemies", {})
	if seen is Dictionary:
		seen_enemies = seen
	last_seen = int(data.get("last_seen", 0))

	# 升级表：逐条读，越界就夹住；老存档没有这个字段就走下面的迁移
	var ups: Variant = data.get("upgrades", null)
	if ups is Dictionary:
		for id in UnitData.UPGRADE_ORDER:
			if (ups as Dictionary).has(id):
				upgrades[id] = clampi(int(ups[id]), 0, up_max(id))
	elif data.has("house_stage"):
		# v0.1.11 之前只有线性的 house_stage（0~4，同时给塔倍率和阅读倍率）。
		# 迁移成两条轨道，尽量保留原来的手感。
		var stage := clampi(int(data["house_stage"]), 0, 5)
		upgrades["power"] = clampi(stage, 0, up_max("power"))
		upgrades["insight"] = clampi(stage, 0, up_max("insight"))
	_emitted_insight = int(insight)


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
	_init_upgrades()
	cleared_count = 0
	last_seen = 0
	seen_enemies = {}
	save_state(true)
	_emitted_insight = int(insight)
	insight_changed.emit(insight)
	upgrades_changed.emit()


# --- 进程 ---

func _process(delta: float) -> void:
	var gain := read_rate() * delta
	if gain > 0.0:
		insight += gain
		# 只在显示出来的整数变化时广播：HUD 只关心这个粒度
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


# --- 键位 / 音效设置（写在单独的 settings.json，清空存档不会清掉）---

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
