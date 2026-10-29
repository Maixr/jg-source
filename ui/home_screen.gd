class_name HomeScreen
extends Control

## 首页：标题「斋悟」+ 左边书架（选关卡集）+ 右边的门（进书屋）。
##
## 之前游戏一进来就是「火柴人大陆」的选关页 —— 那其实是进入某一本书之后
## 才该看到的界面。现在补回真正的首页：书架上每本书是一本书（一个关卡集），
## 推门进书屋花体悟升级。
##
## 全部程序化绘制（书架、书脊、门、墨圈），只有小屋插画用现成的美术。

signal open_levels()
signal open_house()

const TITLE := "斋悟"

## 书架上能点的书（目前只有一本真做完的）
const BOOK_TITLE := "火柴人大陆"
const BOOK_SUB := "第一本 · 五关"

const SHELF := Rect2(140.0, 300.0, 640.0, 505.0)
const DOOR := Rect2(1090.0, 320.0, 300.0, 480.0)
## 「火柴人大陆」这本书在书架上的位置（也是点击热区）
const BOOK := Rect2(206.0, 372.0, 104.0, 188.0)

var _paper: ImageTexture
var _vignette: ImageTexture
var _house: Texture2D
var _font_book: Font
var _font_sans: Font

## 抽书 / 推门的动画进度（0~1）
var _book_t := 0.0
var _door_t := 0.0
var _busy := false
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font_book = UnitData.font_book()
	_font_sans = UnitData.font_sans()
	_paper = _make_paper()
	_vignette = _make_vignette()
	if ResourceLoader.exists("res://art/house/house_intact.jpg"):
		_house = load("res://art/house/house_intact.jpg")
	set_process(true)


func reset() -> void:
	_book_t = 0.0
	_door_t = 0.0
	_busy = false
	queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	queue_redraw()


func _make_paper() -> ImageTexture:
	var n := 192
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var fiber := FastNoiseLite.new()
	fiber.seed = 20261030
	fiber.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fiber.frequency = 0.016
	var grain := FastNoiseLite.new()
	grain.seed = 77
	grain.noise_type = FastNoiseLite.TYPE_SIMPLEX
	grain.frequency = 0.5
	for y in n:
		for x in n:
			var v := fiber.get_noise_2d(float(x), float(y)) * 0.6 + grain.get_noise_2d(float(x), float(y)) * 0.4
			img.set_pixel(x, y, Color(1.0, 0.97, 0.9, clampf(0.5 + v * 0.5, 0.0, 1.0) * 0.055))
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


# --- 输入 ---

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if _busy:
		return
	if BOOK.has_point(mb.position):
		_pull_book()
	elif DOOR.has_point(mb.position):
		_push_door()


## 抽书：书往外滑出、略微放大，抽完才切到选关页
func _pull_book() -> void:
	_busy = true
	var tw := create_tween()
	tw.tween_property(self, "_book_t", 1.0, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): open_levels.emit())


## 推门：门往里开，门缝透出暖光，然后进书屋
func _push_door() -> void:
	_busy = true
	var tw := create_tween()
	tw.tween_property(self, "_door_t", 1.0, 0.38).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): open_house.emit())


# --- 绘制 ---

func _draw() -> void:
	# 先铺一层不透明的底：不然会看到下面战场的 HUD 和格子
	draw_rect(Rect2(Vector2.ZERO, UnitData.DESIGN_SIZE), UnitData.BG, true)
	if _paper != null:
		draw_texture_rect(_paper, Rect2(Vector2.ZERO, UnitData.DESIGN_SIZE), true)
	_draw_ink_circle()
	_draw_title()
	_draw_shelf()
	_draw_door()
	if _vignette != null:
		draw_texture_rect(_vignette, Rect2(Vector2.ZERO, UnitData.DESIGN_SIZE), false)
	_draw_footer()


func _draw_ink_circle() -> void:
	var c := Vector2(800.0, 128.0)
	draw_arc(c, 150.0, -0.5, TAU - 0.4, 64, Color(0.96, 0.92, 0.82, 0.06), 24.0, true)
	draw_arc(c, 143.0, 0.2, TAU - 0.9, 56, Color(0.96, 0.92, 0.82, 0.04), 13.0, true)


func _draw_title() -> void:
	var c := Vector2(800.0, 150.0)
	var txt := TITLE
	var f := _font_book
	var sz := 92
	var m := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz)
	draw_string(f, Vector2(c.x - m.x * 0.5, c.y + m.y * 0.28), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0.96, 0.93, 0.86))
	var sub := "把跑掉的剧情，一个个收回来"
	var ms := _font_sans.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	draw_string(_font_sans, Vector2(c.x - ms.x * 0.5, 210.0), sub,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.74, 0.70, 0.62))


func _draw_shelf() -> void:
	# 柜体
	var wood := Color(0.42, 0.29, 0.18)
	var wood_dark := Color(0.30, 0.20, 0.12)
	# 柜内比外面亮一点点，书才显得在柜子里而不是浮在背景上
	draw_rect(SHELF, Color(0.22, 0.16, 0.11, 0.96), true)
	draw_rect(SHELF, wood, false, 6.0)
	# 两块隔板
	for y in [SHELF.position.y + 268.0, SHELF.position.y + 470.0]:
		draw_rect(Rect2(SHELF.position.x, y, SHELF.size.x, 10.0), wood_dark, true)
		draw_rect(Rect2(SHELF.position.x, y - 3.0, SHELF.size.x, 4.0), wood, true)

	# 上层：主角书 + 几本装饰书
	_draw_book(BOOK, BOOK_TITLE, Color(0.72, 0.84, 0.55), Color(0.86, 0.94, 0.70), true)
	var x := 330.0
	var deco := [
		[46.0, 150.0, Color(0.55, 0.35, 0.30)],
		[38.0, 176.0, Color(0.36, 0.42, 0.52)],
		[52.0, 132.0, Color(0.58, 0.50, 0.30)],
		[40.0, 164.0, Color(0.40, 0.34, 0.46)],
		[34.0, 118.0, Color(0.50, 0.42, 0.34)],
	]
	for d in deco:
		var w: float = d[0]
		var h: float = d[1]
		var base_y := SHELF.position.y + 268.0
		draw_rect(Rect2(x, base_y - h, w, h), d[2], true)
		draw_rect(Rect2(x, base_y - h, w, h), Color(0, 0, 0, 0.25), false, 1.0)
		x += w + 6.0

	# 下层：几本还没写完的书（灰一点，点不动）
	x = SHELF.position.x + 24.0
	var base2 := SHELF.position.y + 470.0
	for i in 7:
		var w2 := 38.0 + float(i % 3) * 12.0
		var h2 := 120.0 + float(i % 4) * 22.0
		draw_rect(Rect2(x, base2 - h2, w2, h2), Color(0.30, 0.27, 0.25), true)
		draw_rect(Rect2(x, base2 - h2, w2, h2), Color(0, 0, 0, 0.3), false, 1.0)
		x += w2 + 8.0
	# 一本横放的书，压在灰书上
	draw_rect(Rect2(x + 6.0, base2 - 34.0, 96.0, 30.0), Color(0.34, 0.30, 0.26), true)

	var tip := "点这本《%s》→ 选关" % BOOK_TITLE
	var mt := _font_sans.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
	draw_string(_font_sans, Vector2(SHELF.get_center().x - mt.x * 0.5, SHELF.position.y + SHELF.size.y + 34.0),
		tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.70, 0.66, 0.58))


## 一本书：竖排书名。pulled 时按 _book_t 往外抽
func _draw_book(r: Rect2, title: String, spine: Color, edge: Color, interactive: bool) -> void:
	var rr := r
	if interactive and _book_t > 0.0:
		rr.position.y -= 54.0 * _book_t
		var grow := 1.0 + 0.22 * _book_t
		rr = Rect2(rr.position - Vector2((rr.size.x * (grow - 1.0)) * 0.5, 0.0),
			Vector2(rr.size.x * grow, rr.size.y * grow))
		# 抽出来的书投个影，才有离开书架的感觉
		draw_rect(Rect2(rr.position + Vector2(7.0, 9.0), rr.size), Color(0, 0, 0, 0.35), true)
	draw_rect(rr, spine, true)
	draw_rect(rr, Color(0, 0, 0, 0.35), false, 2.0)
	# 书脊高光
	draw_rect(Rect2(rr.position + Vector2(6.0, 6.0), Vector2(7.0, rr.size.y - 12.0)),
		Color(edge.r, edge.g, edge.b, 0.6), true)
	draw_rect(Rect2(rr.position + Vector2(rr.size.x - 12.0, 6.0), Vector2(6.0, rr.size.y - 12.0)),
		Color(0, 0, 0, 0.22), true)

	# 竖排书名：一个字一行
	var sz := 21
	var chars := title.length()
	var line_h := float(sz) + 3.0
	var total := line_h * float(chars)
	var top := rr.position.y + (rr.size.y - total) * 0.5
	for i in chars:
		var ch := title.substr(i, 1)
		var cm := _font_book.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, sz)
		draw_string(_font_book,
			Vector2(rr.position.x + (rr.size.x - cm.x) * 0.5 - 2.0, top + line_h * float(i) + float(sz)),
			ch, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0.14, 0.12, 0.10))
	if interactive and _book_t < 0.5:
		var sub := "点击抽出"
		var ms := _font_sans.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
		draw_string(_font_sans, Vector2(rr.get_center().x - ms.x * 0.5, rr.position.y + rr.size.y + 20.0),
			sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.82, 0.78, 0.66))


func _draw_door() -> void:
	var frame := DOOR
	var wood := Color(0.45, 0.30, 0.18)
	var wood_light := Color(0.58, 0.40, 0.24)

	# 门框
	draw_rect(frame, Color(0.12, 0.09, 0.07, 0.95), true)
	draw_rect(frame, wood, false, 7.0)

	var leaf := Rect2(frame.position + Vector2(16.0, 16.0),
		Vector2(frame.size.x - 32.0, frame.size.y - 16.0))
	# 门后：推门时露出暖光（书屋的灯）
	var glow := Color(0.95, 0.78, 0.42, 0.10 + 0.55 * _door_t)
	if _door_t > 0.01:
		draw_rect(leaf, glow, true)

	# 门扇：绕左边框横向压扁 = 往里推开
	var squash := 1.0 - 0.90 * _door_t
	draw_set_transform(leaf.position + Vector2(0.0, leaf.size.y * 0.5), 0.0,
		Vector2(maxf(0.04, squash), 1.0))
	var local := Rect2(Vector2(0.0, -leaf.size.y * 0.5), leaf.size)
	draw_rect(local, wood, true)
	draw_rect(local, Color(0, 0, 0, 0.35), false, 2.0)
	# 门板上的木纹
	for i in 3:
		var x := local.size.x * (0.24 + 0.26 * float(i))
		draw_line(Vector2(x, local.position.y + 14.0), Vector2(x, local.position.y + local.size.y - 14.0),
			Color(0.30, 0.19, 0.11, 0.7), 2.0)
	# 把手
	draw_circle(Vector2(local.size.x - 26.0, 6.0), 7.0, wood_light)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var tip := "推门进书屋"
	var mt := _font_sans.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
	draw_string(_font_sans, Vector2(frame.get_center().x - mt.x * 0.5, frame.position.y + frame.size.y + 34.0),
		tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.70, 0.66, 0.58))


func _draw_footer() -> void:
	var line: String = "%s · 情感体悟 %s %s" % [TITLE, UnitData.GAME_VERSION, UnitData.GAME_CHANNEL]
	var m := _font_sans.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	draw_string(_font_sans, Vector2(800.0 - m.x * 0.5, 862.0), line,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.52, 0.49, 0.43))
