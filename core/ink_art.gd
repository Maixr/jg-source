class_name InkArt
extends RefCounted

## 程序化画小物件：文具（铅笔/橡皮/直尺/墨水瓶/回形针/小本子）。
##
## 战场上的散落物和标题页的装饰共用这一套，风格才统一，
## 也不用为此引入图片资源（这张桌子上的东西本来就该是线稿）。
##
## 所有形状都画在以 c 为中心、按 ang 旋转的局部坐标里，
## s 是整体缩放，方便标题页放大当装饰、战场按原尺寸。

const KINDS := ["pencil", "eraser", "ruler", "ink", "clip", "notebook"]

const WOOD := Color(0.87, 0.69, 0.38)
const WOOD_DARK := Color(0.66, 0.48, 0.24)
const CREAM := Color(0.95, 0.91, 0.82)
const INK_DARK := Color(0.16, 0.15, 0.14)
const RUBBER := Color(0.90, 0.60, 0.66)
const PAPER := Color(0.93, 0.90, 0.82)
const GLASS := Color(0.30, 0.33, 0.45)
const STEEL := Color(0.72, 0.75, 0.80)


static func _rot(pts: PackedVector2Array, c: Vector2, ang: float, s: float) -> PackedVector2Array:
	var ca := cos(ang)
	var sa := sin(ang)
	var out := PackedVector2Array()
	for v in pts:
		var q := v * s
		out.append(c + Vector2(q.x * ca - q.y * sa, q.x * sa + q.y * ca))
	return out


static func _poly(ci: CanvasItem, pts: PackedVector2Array, c: Vector2, ang: float, s: float, col: Color) -> void:
	ci.draw_colored_polygon(_rot(pts, c, ang, s), col)


static func _line(ci: CanvasItem, a: Vector2, b: Vector2, c: Vector2, ang: float, s: float, col: Color, w: float) -> void:
	var ca := cos(ang)
	var sa := sin(ang)
	var pa := a * s
	var pb := b * s
	ci.draw_line(c + Vector2(pa.x * ca - pa.y * sa, pa.x * sa + pa.y * ca),
		c + Vector2(pb.x * ca - pb.y * sa, pb.x * sa + pb.y * ca), col, maxf(1.0, w * s), true)


## 跑道形（两端半圆的窄长条）轮廓点，用来画回形针
static func _stadium_pts(w: float, h: float, steps: int = 6) -> PackedVector2Array:
	var r := w * 0.5
	var top := -h * 0.5 + r
	var bot := h * 0.5 - r
	var pts := PackedVector2Array()
	# 上端半圆：从左上绕到右上
	for i in steps + 1:
		var a := PI + PI * float(i) / float(steps)
		pts.append(Vector2(cos(a) * r, top + sin(a) * r))
	# 右边直线向下
	pts.append(Vector2(r, bot))
	# 下端半圆：从右绕回左
	for i in steps + 1:
		var a := PI * float(i) / float(steps)
		pts.append(Vector2(cos(a) * r, bot + sin(a) * r))
	# 左边直线向上，闭合
	pts.append(Vector2(-r, top))
	return pts


## 画一件文具。with_shadow 给战场用（落在地上的投影），标题页会自动关掉。
static func draw_prop(ci: CanvasItem, kind: String, c: Vector2, ang: float = 0.0,
		s: float = 1.0, with_shadow: bool = true) -> void:
	if with_shadow:
		ci.draw_circle(c + Vector2(2.0, 3.5) * s, 12.0 * s, Color(0.0, 0.0, 0.0, 0.22))
	match kind:
		"pencil":
			# 笔杆
			_poly(ci, PackedVector2Array([
				Vector2(-17.0, -4.5), Vector2(9.0, -4.5), Vector2(9.0, 4.5), Vector2(-17.0, 4.5)]),
				c, ang, s, WOOD)
			# 削出来的木头
			_poly(ci, PackedVector2Array([
				Vector2(9.0, -4.5), Vector2(18.0, 0.0), Vector2(9.0, 4.5)]), c, ang, s, CREAM)
			# 笔芯
			_poly(ci, PackedVector2Array([
				Vector2(14.5, -2.0), Vector2(18.0, 0.0), Vector2(14.5, 2.0)]), c, ang, s, INK_DARK)
			# 尾端的橡皮
			_poly(ci, PackedVector2Array([
				Vector2(-17.0, -4.5), Vector2(-12.0, -4.5), Vector2(-12.0, 4.5), Vector2(-17.0, 4.5)]),
				c, ang, s, RUBBER)
		"eraser":
			_poly(ci, PackedVector2Array([
				Vector2(-13.0, -7.0), Vector2(11.0, -8.0), Vector2(13.0, 7.0), Vector2(-11.0, 8.0)]),
				c, ang, s, RUBBER)
			_poly(ci, PackedVector2Array([
				Vector2(-13.0, -7.0), Vector2(-6.0, -7.4), Vector2(-4.4, 7.6), Vector2(-11.0, 8.0)]),
				c, ang, s, CREAM)
			_line(ci, Vector2(-6.0, -7.4), Vector2(-4.4, 7.6), c, ang, s, WOOD_DARK, 1.2)
		"ruler":
			_poly(ci, PackedVector2Array([
				Vector2(-20.0, -5.5), Vector2(20.0, -5.5), Vector2(20.0, 5.5), Vector2(-20.0, 5.5)]),
				c, ang, s, WOOD)
			for i in 4:
				var x := -14.0 + float(i) * 8.0
				var h := 3.0 if i % 2 == 0 else 2.0
				_line(ci, Vector2(x, -5.5), Vector2(x, -5.5 + h), c, ang, s, WOOD_DARK, 1.0)
			_line(ci, Vector2(-20.0, 3.0), Vector2(20.0, 3.0), c, ang, s, WOOD_DARK, 1.0)
		"ink":
			# 瓶身
			_poly(ci, PackedVector2Array([
				Vector2(-10.0, -2.0), Vector2(10.0, -2.0), Vector2(8.0, 12.0), Vector2(-8.0, 12.0)]),
				c, ang, s, GLASS)
			# 瓶颈
			_poly(ci, PackedVector2Array([
				Vector2(-4.0, -8.0), Vector2(4.0, -8.0), Vector2(4.0, -2.0), Vector2(-4.0, -2.0)]),
				c, ang, s, GLASS)
			# 瓶盖
			_poly(ci, PackedVector2Array([
				Vector2(-6.0, -13.0), Vector2(6.0, -13.0), Vector2(6.0, -8.0), Vector2(-6.0, -8.0)]),
				c, ang, s, INK_DARK)
			# 液面高光
			_poly(ci, PackedVector2Array([
				Vector2(-7.0, 4.0), Vector2(7.0, 4.0), Vector2(6.0, 7.0), Vector2(-6.0, 7.0)]),
				c, ang, s, Color(0.42, 0.46, 0.60))
		"clip":
			# 回形针：两圈跑道形描边。以前用两段圆弧画，小尺寸下像"禁止通行"的斜杠圈
			var outer := _stadium_pts(11.0, 21.0)
			ci.draw_polyline(_rot(outer, c, ang, s), STEEL, maxf(1.2, 2.0 * s), true)
			var inner_p := PackedVector2Array()
			for v in _stadium_pts(6.0, 15.0):
				inner_p.append(v + Vector2(0.0, -1.5))
			ci.draw_polyline(_rot(inner_p, c, ang, s), STEEL, maxf(1.2, 2.0 * s), true)
		"notebook":
			_poly(ci, PackedVector2Array([
				Vector2(-13.0, -16.0), Vector2(13.0, -16.0), Vector2(13.0, 16.0), Vector2(-13.0, 16.0)]),
				c, ang, s, PAPER)
			_poly(ci, PackedVector2Array([
				Vector2(-13.0, -16.0), Vector2(-8.0, -16.0), Vector2(-8.0, 16.0), Vector2(-13.0, 16.0)]),
				c, ang, s, WOOD_DARK)
			for i in 3:
				var y := -7.0 + float(i) * 8.0
				_line(ci, Vector2(-4.0, y), Vector2(9.0, y), c, ang, s, Color(0.62, 0.58, 0.50), 1.0)
		_:
			# 兜底：画成一小片纸
			_poly(ci, PackedVector2Array([
				Vector2(-11.0, -9.0), Vector2(11.0, -11.0), Vector2(12.0, 10.0), Vector2(-10.0, 9.0)]),
				c, ang, s, CREAM)
