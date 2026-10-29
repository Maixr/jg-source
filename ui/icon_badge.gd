class_name IconBadge
extends Control

## 货币图标的小徽标：图标 + 可选底圈。
## 放进 HBox 里就能和 Label 并排显示（例如「◈ 体悟 318」）。

var kind := "insight"
var color := Color(0.85, 0.65, 0.72)
var radius := 9.0
var with_disc := false


func _init(k: String = "insight", r: float = 9.0, col: Color = Color(0.85, 0.65, 0.72),
		disc: bool = false) -> void:
	kind = k
	radius = r
	color = col
	with_disc = disc
	custom_minimum_size = Vector2(r * 2.4, r * 2.4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 * 0.72
	if with_disc:
		draw_circle(c, r * 1.45, Color(color.r, color.g, color.b, 0.16))
		draw_arc(c, r * 1.45, 0.0, TAU, 28, Color(color.r, color.g, color.b, 0.55), 1.5, true)
	Icons.draw_kind(self, kind, c, r, color)
