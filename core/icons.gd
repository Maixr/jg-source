class_name Icons
extends RefCounted

## 两种游戏内货币的程序化图标。
##
## 为什么不用图标库：这游戏所有图形都是线稿/几何，塞一套彩色矢量图标进来
## 风格会断层；而且十几像素的图标拼的是轮廓干净，不是细节多。
## 需要换成开源图标时，只要替换这两个函数（见 effect.md 的「图标」一节）。

## 体悟：四角星 + 两颗小星，意思是「灵光一现」
static func draw_insight(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var outer := r
	var inner := r * 0.28
	var pts := PackedVector2Array()
	for i in 8:
		var a := -PI * 0.5 + TAU * float(i) / 8.0
		var rad := outer if i % 2 == 0 else inner
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
	ci.draw_colored_polygon(pts, col)
	# 两颗小星：让它在小尺寸下也能看出「会闪」
	ci.draw_circle(c + Vector2(r * 0.72, -r * 0.62), maxf(1.0, r * 0.14), col)
	ci.draw_circle(c + Vector2(-r * 0.68, r * 0.60), maxf(1.0, r * 0.11), col)


## 纸笔：一滴墨 + 一点高光。比「笔尖」在小尺寸下更好认
static func draw_ink(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var body := c + Vector2(0.0, r * 0.20)
	var rr := r * 0.76
	ci.draw_circle(body, rr, col)
	ci.draw_colored_polygon(PackedVector2Array([
		c + Vector2(0.0, -r),
		body + Vector2(-rr * 0.70, -rr * 0.50),
		body + Vector2(rr * 0.70, -rr * 0.50),
	]), col)
	ci.draw_circle(body + Vector2(-rr * 0.34, -rr * 0.30), maxf(1.0, rr * 0.24),
		Color(1.0, 1.0, 1.0, 0.55))


## 按名字画（给 IconBadge 用）
static func draw_kind(ci: CanvasItem, kind: String, c: Vector2, r: float, col: Color) -> void:
	match kind:
		"ink":
			draw_ink(ci, c, r, col)
		_:
			draw_insight(ci, c, r, col)
