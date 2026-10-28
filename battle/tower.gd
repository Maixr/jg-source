class_name Tower
extends RefCounted

## 魔女的施法分身。数值来自 UnitData，等级 1~3。

var id := ""
var level := 1
var pos := Vector2.ZERO
var hp := 1.0
var max_hp := 1.0
var atk := 0.0
var atk_range := 0.0
var interval := 1.0
var block_capacity := 0
var kind := ""
var color := Color.WHITE
var glyph := ""

var cooldown := 0.0
var flash := 0.0
var engaged: Array = []
## 累计投入的纸笔（放置 + 升级），移除时按比例返还
var invested := 0


func setup(tower_id: String, cell: Vector2, mult: float) -> void:
	var def: Dictionary = UnitData.TOWERS[tower_id]
	id = tower_id
	pos = cell
	kind = str(def["kind"])
	color = def["color"]
	glyph = str(def["glyph"])
	block_capacity = int(def["block"])
	_refresh(mult)


func _refresh(mult: float) -> void:
	var stats := UnitData.tower_stats(id, level, mult)
	max_hp = float(stats["hp"])
	hp = max_hp
	atk = float(stats["atk"])
	atk_range = float(stats["range"])
	interval = float(stats["interval"])


## 升级：返回 false 表示已满级
func upgrade(mult: float) -> bool:
	if level >= UnitData.tower_max_level(id):
		return false
	var ratio := hp / max_hp if max_hp > 0.0 else 1.0
	level += 1
	_refresh(mult)
	hp = max_hp * ratio
	return true


## 房屋重建后重新套用倍率：攻击/血量立刻变强，当前血量按比例保留
func reapply_mult(mult: float) -> void:
	var ratio := hp / max_hp if max_hp > 0.0 else 1.0
	_refresh(mult)
	hp = max_hp * ratio


func can_block() -> bool:
	return block_capacity > 0 and engaged.size() < block_capacity


func take_damage(amount: float) -> void:
	hp -= amount
	flash = 0.18


func is_dead() -> bool:
	return hp <= 0.0


func is_support() -> bool:
	return kind == "heal"


func is_blocker() -> bool:
	return kind == "shield"
