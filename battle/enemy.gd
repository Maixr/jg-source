class_name Enemy
extends RefCounted

## 会走路的「文字」。沿 PATH_POINTS 推进，被阻挡时分身对峙。

var id := ""
var glyph := ""
var hp := 1.0
var max_hp := 1.0
var speed := 0.0
var atk := 0.0
var interval := 1.0
var radius := 17.0
var color := Color.WHITE
var insight_reward := 2
var leak := 1
var ranged := false
var attack_range := 0.0
var armor := 0.0

var pos := Vector2.ZERO
var seg := 0
var seg_t := 0.0
var cooldown := 0.0
var flash := 0.0
var alive := true
var escaped := false
var target: Tower = null

## 远程单位边打边往前挪的节奏控制
var advance_cd := 0.0      # 距离下次前挪还有多久
var advance_left := 0.0    # 当前这次前挪还剩多久
var advance_interval := 2.6  # 每隔多久往前挪一次
var advance_window := 0.5    # 每次往前挪多久（秒）

var _path: Array = []


func setup(enemy_id: String, path: Array, hp_mult: float, speed_mult: float) -> void:
	var def: Dictionary = UnitData.ENEMIES[enemy_id]
	id = enemy_id
	glyph = str(def["glyph"])
	max_hp = float(def["hp"]) * hp_mult
	hp = max_hp
	speed = float(def["speed"]) * speed_mult
	atk = float(def["atk"])
	interval = float(def["interval"])
	radius = float(def["radius"])
	color = def["color"]
	insight_reward = int(def["insight"])
	leak = int(def["leak"])
	ranged = bool(def["ranged"])
	attack_range = float(def["attack_range"])
	armor = float(def.get("armor", 0.0))
	_path = path
	seg = 0
	seg_t = 0.0
	pos = _path[0]


func take_damage(amount: float) -> void:
	hp -= amount
	flash = 0.16
	if hp <= 0.0:
		hp = 0.0
		alive = false


func is_dead() -> bool:
	return not alive


## 当前所在路段的朝向（归一化）。用来判断某个分身还在不在自己前方。
func dir() -> Vector2:
	if seg >= _path.size() - 1:
		return Vector2.RIGHT
	var from: Vector2 = _path[seg]
	var to: Vector2 = _path[seg + 1]
	var d := to - from
	return d.normalized() if d.length_squared() > 0.0001 else Vector2.RIGHT


## 沿路径推进。返回 true 表示已走到终点（漏怪）。
func advance(delta: float) -> bool:
	if target != null:
		return false
	if seg >= _path.size() - 1:
		escaped = true
		alive = false
		return true
	var from: Vector2 = _path[seg]
	var to: Vector2 = _path[seg + 1]
	var seg_len := from.distance_to(to)
	if seg_len <= 0.001:
		seg += 1
		return false
	seg_t += (speed * delta) / seg_len
	while seg_t >= 1.0:
		seg_t -= 1.0
		seg += 1
		if seg >= _path.size() - 1:
			pos = _path[_path.size() - 1]
			escaped = true
			alive = false
			return true
		from = _path[seg]
		to = _path[seg + 1]
		seg_len = from.distance_to(to)
		if seg_len <= 0.001:
			continue
	pos = from.lerp(to, clampf(seg_t, 0.0, 1.0))
	return false
