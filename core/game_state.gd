extends Node

## 全局进度：情感体悟、房屋重建、关卡解锁、离线收益。
## 注册为 Autoload，名字 GameState。

signal insight_changed(value: float)
signal house_changed(stage: int)

const SAVE_PATH := "user://jg_save.json"
const AUTOSAVE_INTERVAL := 15.0

var insight := 0.0
var house_stage := 0
var cleared_count := 0
var last_seen := 0

var _autosave := 0.0


func _ready() -> void:
	load_state()
	_apply_offline_gain()
	set_process(true)


func _process(delta: float) -> void:
	var gain := read_rate() * delta
	if gain > 0.0:
		insight += gain
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
	last_seen = int(Time.get_unix_time_from_system())
	var data := {
		"insight": insight,
		"house_stage": house_stage,
		"cleared_count": cleared_count,
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
	save_state()
	insight_changed.emit(insight)
	house_changed.emit(house_stage)
