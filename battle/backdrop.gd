class_name BattleBackdrop
extends Node2D

## 战场静态层：网格底纹 + 纸纹 + 路面 + 地面格 + 高台格。
##
## 这些内容只在「换关卡」和「放/拆分身」时变化，没必要每帧重画。
## 单独拆一层之后，BattleField._draw() 只需要画会动的东西。
##
## 顺手把格子画法从「整格方框」改成「四角刻度」：1600×900 下高台格有
## 140~200 个，整格描边叠起来像棋盘噪点，四角刻度既有提示又不抢路面。

## 注意：这里刻意不写 `var field: BattleField` —— BattleField 又引用了
## BattleBackdrop，两边都做类型标注会构成循环引用，GDScript 解析会失败。
## 所以字段保持无类型，只在 setup() 里从实例上取需要的常量。
var field = null

var _paper: ImageTexture = null
var _path_half := 23.0


func setup(f) -> void:
	field = f
	_path_half = float(f.PATH_WIDTH) * 0.5
	_paper = _make_paper_texture()
	queue_redraw()


func refresh() -> void:
	queue_redraw()


## 纸纹：低频噪声当纤维，高频噪声当颗粒，合成一张可平铺的浅色贴图
func _make_paper_texture() -> ImageTexture:
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var fiber := FastNoiseLite.new()
	fiber.seed = 20261030
	fiber.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fiber.frequency = 0.018
	var grain := FastNoiseLite.new()
	grain.seed = 7
	grain.noise_type = FastNoiseLite.TYPE_SIMPLEX
	grain.frequency = 0.55
	for y in size:
		for x in size:
			var v := fiber.get_noise_2d(float(x), float(y)) * 0.6 + grain.get_noise_2d(float(x), float(y)) * 0.4
			# 只保留一点亮度起伏，整体压在 4% 以内，不能盖住内容
			var a := clampf(0.5 + v * 0.5, 0.0, 1.0) * 0.075
			img.set_pixel(x, y, Color(1.0, 0.97, 0.9, a))
	return ImageTexture.create_from_image(img)


func _draw() -> void:
	if field == null:
		return
	var d: Vector2 = UnitData.DESIGN_SIZE
	draw_rect(Rect2(Vector2.ZERO, d), UnitData.BG, true)
	_draw_grid_lines(d)
	if _paper != null:
		draw_texture_rect(_paper, Rect2(Vector2.ZERO, d), true)
	_draw_path()
	# 格子提示只在「选了塔、正在找位置」时出现：
	# 平时把两百个格子全画出来，整个棋盘都是十字，路面反而看不出重点。
	_draw_cells()


func _draw_grid_lines(d: Vector2) -> void:
	var step := 96.0
	var col := Color(1.0, 1.0, 1.0, 0.022)
	var y := 0.0
	while y < d.y:
		draw_line(Vector2(0.0, y), Vector2(d.x, y), col, 1.0)
		y += step
	var x := 0.0
	while x < d.x:
		draw_line(Vector2(x, 0.0), Vector2(x, d.y), col, 1.0)
		x += step


## 四角刻度：只画方框的四个角，比整格描边干净得多
func _draw_cell_ticks(p: Vector2, half: float, col: Color, width: float) -> void:
	var l := half * 0.5
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var c := p + Vector2(sx * half, sy * half)
			draw_line(c, c - Vector2(sx * l, 0.0), col, width)
			draw_line(c, c - Vector2(0.0, sy * l), col, width)


## 正在放塔时才提示格子：当前塔型能放的格子高亮，另一种只留极淡的角
func _draw_cells() -> void:
	if field == null:
		return
	var pending := str(field.pending_tower)
	if pending.is_empty():
		return
	var kind := UnitData.tower_deploy(pending)
	var ground := kind == "ground"
	for c in field.high_cells:
		_draw_cell(c, not ground, false)
	for c in field.ground_cells:
		_draw_cell(c, ground, true)


func _draw_cell(c: Variant, active: bool, is_ground: bool) -> void:
	var p: Vector2 = c
	var half := UnitData.GRID_STEP * 0.5 - 3.0
	var occupied: bool = field.cell_occupied(p)
	var base := Color(0.96, 0.86, 0.62) if is_ground else Color(0.66, 0.80, 0.50)
	if not active:
		# 不能放的那一类：留一点角标，让玩家知道这里是另一种格子
		_draw_cell_ticks(p, half, Color(base.r, base.g, base.b, 0.10), 1.5)
		return
	if occupied:
		_draw_cell_ticks(p, half, Color(base.r, base.g, base.b, 0.14), 1.5)
		return
	draw_rect(Rect2(p - Vector2(half, half), Vector2(half, half) * 2.0),
		Color(base.r, base.g, base.b, 0.10), true)
	_draw_cell_ticks(p, half, Color(base.r, base.g, base.b, 0.75), 2.0)


func _seg_key(a: Vector2, b: Vector2) -> String:
	var ka := "%d,%d" % [int(round(a.x)), int(round(a.y))]
	var kb := "%d,%d" % [int(round(b.x)), int(round(b.y))]
	return (ka + "|" + kb) if ka <= kb else (kb + "|" + ka)


## 画一段轴对齐的路面。用矩形而不是 draw_line：
## 矩形能精确控制宽度和端点，接头处不会留圆弧或缺口。
func _draw_road_rect(a: Vector2, b: Vector2, col: Color, half: float) -> void:
	if absf(a.y - b.y) < 0.5:
		var x0 := minf(a.x, b.x) - half
		var x1 := maxf(a.x, b.x) + half
		draw_rect(Rect2(Vector2(x0, a.y - half), Vector2(x1 - x0, half * 2.0)), col, true)
	else:
		var y0 := minf(a.y, b.y) - half
		var y1 := maxf(a.y, b.y) + half
		draw_rect(Rect2(Vector2(a.x - half, y0), Vector2(half * 2.0, y1 - y0)), col, true)


func _draw_path() -> void:
	# 多条路线共用同一段路时只画一次：半透明描边叠两遍会变深，
	# 拐角处还会鼓出一个包，看起来像贴图错乱。
	var outer: Color = UnitData.BG.lerp(Color(0.66, 0.46, 0.25), 0.62)
	var inner: Color = outer.lerp(Color(0.85, 0.78, 0.66), 0.45)
	var edge: Color = UnitData.BG.lerp(Color(0.95, 0.82, 0.55), 0.30)
	var half: float = _path_half

	var segs: Array = []
	var nodes := {}
	var drawn := {}
	for route in field.routes:
		var pts: Array = (route as Dictionary).get("points", [])
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var key := _seg_key(a, b)
			nodes[_seg_key(a, a)] = a
			nodes[_seg_key(b, b)] = b
			if drawn.has(key):
				continue
			drawn[key] = true
			segs.append([a, b])

	# 外描边：比路面宽一点，让路面从深底上「浮」起来
	for s in segs:
		_draw_road_rect(s[0], s[1], edge, half + 3.0)
	for k in nodes:
		var p: Vector2 = nodes[k]
		draw_rect(Rect2(p - Vector2(half + 3.0, half + 3.0),
			Vector2(half + 3.0, half + 3.0) * 2.0), edge, true)

	# 路面底色
	for s in segs:
		_draw_road_rect(s[0], s[1], outer, half)
	for k in nodes:
		var p2: Vector2 = nodes[k]
		draw_rect(Rect2(p2 - Vector2(half, half), Vector2(half, half) * 2.0), outer, true)

	# 中间那条亮带
	var half_in := half * 0.40
	for s in segs:
		_draw_road_rect(s[0], s[1], inner, half_in)
	for k in nodes:
		var p3: Vector2 = nodes[k]
		draw_rect(Rect2(p3 - Vector2(half_in, half_in), Vector2(half_in, half_in) * 2.0), inner, true)
