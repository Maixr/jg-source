class_name TitleDecor
extends Control

## 标题页装饰层。
##
## 原来的选关页就是一块深色底 + 几行字，太空了。这里补上：
##   · 纸纹和暗角（和战场同一套语言）
##   · 标题后面一圈淡墨（「写坏的字」那种笔触）
##   · 慢慢往上飘的字 —— 呼应「书里的字跑出来了」
##   · 左下角一张小屋插画卡，把养成目标摆在标题页上
##   · 画面四角散落的文具，和战场上的散落物是同一套画法（InkArt）
##
## 全部程序化绘制，不额外引入图片资源；只有小屋那张画是已有的美术。

## 飘着的字：用敌人字 + 剧情里的字，别用无关的字
const DRIFT_CHARS := ["躁", "狂", "疑", "迷", "执", "晦", "情", "感", "体", "悟", "书", "文"]
const GLYPH_COUNT := 16
## 固定随机种子：每次进标题页装饰完全一样，截图和手感都稳定
const DECOR_SEED := 20261030

var _t := 0.0
var _paper: ImageTexture
var _vignette: ImageTexture
var _glyphs: Array = []
var _font_book: Font
var _font_sans: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font_book = UnitData.font_book()
	_font_sans = UnitData.font_sans()
	_paper = _make_paper()
	_vignette = _make_vignette()
	_spawn_glyphs()
	set_process(true)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	# 注意别写 `var size := size`：size 是 Control 自己的属性，这样会遮蔽它
	var sz := size
	for g in _glyphs:
		var p: Vector2 = g["pos"]
		var v: Vector2 = g["vel"]
		p += v * delta
		# 飘出画面就从另一侧重新进来，形成循环
		if p.y < -60.0:
			p.y = sz.y + 60.0
		if p.x < -80.0:
			p.x = sz.x + 80.0
		elif p.x > sz.x + 80.0:
			p.x = -80.0
		g["pos"] = p
	queue_redraw()


func _spawn_glyphs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = DECOR_SEED
	var w := UnitData.DESIGN_SIZE.x
	var h := UnitData.DESIGN_SIZE.y
	for i in GLYPH_COUNT:
		_glyphs.append({
			"pos": Vector2(rng.randf_range(0.0, w), rng.randf_range(0.0, h)),
			"vel": Vector2(rng.randf_range(-7.0, 7.0), rng.randf_range(-17.0, -4.0)),
			"ch": DRIFT_CHARS[rng.randi_range(0, DRIFT_CHARS.size() - 1)],
			"size": rng.randi_range(36, 108),
			"alpha": rng.randf_range(0.04, 0.11),
			"rot": rng.randf_range(-0.22, 0.22),
		})


func _make_paper() -> ImageTexture:
	# 和战场同一套纸纹算法，只是这里更淡，免得抢了文字
	var n := 192
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var fiber := FastNoiseLite.new()
	fiber.seed = 20261030
	fiber.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fiber.frequency = 0.016
	var grain := FastNoiseLite.new()
	grain.seed = 31
	grain.noise_type = FastNoiseLite.TYPE_SIMPLEX
	grain.frequency = 0.5
	for y in n:
		for x in n:
			var v := fiber.get_noise_2d(float(x), float(y)) * 0.6 + grain.get_noise_2d(float(x), float(y)) * 0.4
			img.set_pixel(x, y, Color(1.0, 0.97, 0.9, clampf(0.5 + v * 0.5, 0.0, 1.0) * 0.05))
	return ImageTexture.create_from_image(img)


func _make_vignette() -> ImageTexture:
	var n := 96
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (float(x) / float(n - 1)) * 2.0 - 1.0
			var v := (float(y) / float(n - 1)) * 2.0 - 1.0
			var d := clampf(sqrt(u * u + v * v) / 1.42, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.0, 0.0, 0.0, pow(d, 2.0) * 0.55))
	return ImageTexture.create_from_image(img)


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 1.0 or h <= 1.0:
		w = UnitData.DESIGN_SIZE.x
		h = UnitData.DESIGN_SIZE.y

	if _paper != null:
		draw_texture_rect(_paper, Rect2(Vector2.ZERO, Vector2(w, h)), true)
	_draw_enso()
	_draw_glyphs()
	if _vignette != null:
		draw_texture_rect(_vignette, Rect2(Vector2.ZERO, Vector2(w, h)), false)
	_draw_stationery()


## 标题后面那圈淡墨：几道粗细不一的圆弧叠出毛笔的毛边感
func _draw_enso() -> void:
	var c := Vector2(UnitData.DESIGN_SIZE.x * 0.5, 122.0)
	draw_arc(c, 168.0, -0.55, TAU - 0.35, 72, Color(0.96, 0.92, 0.82, 0.055), 26.0, true)
	draw_arc(c, 163.0, 0.15, TAU - 0.85, 64, Color(0.96, 0.92, 0.82, 0.040), 15.0, true)
	draw_arc(c, 174.0, -1.9, TAU - 2.5, 44, Color(0.96, 0.92, 0.82, 0.030), 7.0, true)


func _draw_glyphs() -> void:
	for g in _glyphs:
		var col := Color(0.98, 0.94, 0.86, float(g["alpha"]))
		var p: Vector2 = g["pos"]
		var sz: int = int(g["size"])
		# 轻微旋转：像浮在纸上的墨迹，而不是排好的文字
		draw_set_transform(p, float(g["rot"]))
		draw_string(_font_book, Vector2(-sz * 0.5, sz * 0.34), str(g["ch"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
		draw_set_transform(Vector2.ZERO, 0.0)


## 四角散落的文具：和战场上的是同一套画法，视觉上算一套语言
func _draw_stationery() -> void:
	InkArt.draw_prop(self, "eraser", Vector2(196.0, 690.0), 0.28, 1.35, false)
	InkArt.draw_prop(self, "pencil", Vector2(300.0, 790.0), -0.42, 1.5, false)
	InkArt.draw_prop(self, "ruler", Vector2(1418.0, 636.0), 0.52, 1.5, false)
	InkArt.draw_prop(self, "ink", Vector2(1486.0, 786.0), -0.18, 1.45, false)
	InkArt.draw_prop(self, "clip", Vector2(1330.0, 812.0), 0.9, 1.3, false)
	InkArt.draw_prop(self, "notebook", Vector2(150.0, 852.0), 0.14, 1.25, false)
