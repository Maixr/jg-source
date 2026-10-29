class_name FxLayer
extends Control

## 界面层的交互粒子：按钮按下时在按钮中心喷一小簇墨点。
##
## 为什么单独一层：按钮是 Control，战场是 Node2D 在下面，
## 想让粒子画在界面之上又不吃鼠标，最省事的就是一个
## mouse_filter=IGNORE 的全屏 Control + 高 z_index。
##
## 只在有粒子时才 _process 与重绘，静止时零开销。

const MAX_PUFFS := 64

var _puffs: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 100
	set_process(false)


## 在某个位置喷一簇墨点（n 个，向上散开，带重力）
func puff(pos: Vector2, color: Color = Color(0.95, 0.85, 0.62), n: int = 6,
		speed: float = 120.0) -> void:
	for i in n:
		var a := -PI * 0.5 + randf_range(-0.9, 0.9)
		var sp := speed * randf_range(0.55, 1.0)
		_puffs.append({
			"pos": pos + Vector2(randf_range(-6.0, 6.0), randf_range(-4.0, 4.0)),
			"vel": Vector2(cos(a), sin(a)) * sp,
			"r": randf_range(1.6, 3.4),
			"t": 0.0,
			"dur": randf_range(0.28, 0.5),
			"color": color,
		})
	if _puffs.size() > MAX_PUFFS:
		_puffs = _puffs.slice(_puffs.size() - MAX_PUFFS)
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	if _puffs.is_empty():
		set_process(false)
		return
	for p in _puffs:
		p["t"] = float(p["t"]) + delta
		p["vel"] = (p["vel"] as Vector2) + Vector2(0.0, 620.0) * delta
		p["pos"] = (p["pos"] as Vector2) + (p["vel"] as Vector2) * delta
	_puffs = _puffs.filter(func(p): return float(p["t"]) < float(p["dur"]))
	queue_redraw()
	if _puffs.is_empty():
		set_process(false)


func _draw() -> void:
	for p in _puffs:
		var k := clampf(float(p["t"]) / float(p["dur"]), 0.0, 1.0)
		var c: Color = p["color"]
		c.a = (1.0 - k) * 0.85
		draw_circle(p["pos"], float(p["r"]) * (1.0 - k * 0.55), c)
