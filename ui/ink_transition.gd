class_name InkTransition
extends Control

## 转场：一团墨从点击处漫开盖住屏幕，切换完再从中间化开露出新画面。
##
## 为什么用墨而不是黑屏淡入：这游戏的画面语言就是纸和墨，
## 硬切黑屏反而出戏。墨点本身是程序化画的（几十个偏心圆），不引资源。
##
## 用法：
##     transition.play(func(): 真正要做的切换, 点击位置)
## 切换动作在「屏幕已经被盖住」的那一帧执行，所以玩家永远看不到中间态。
## 动画期间吃掉鼠标事件，避免连点两次触发两次切换。

## 一次转场结束（露出新画面）时发出；自检/流程代码可以 await 它
signal finished

## 一次转场是否正在进行（外部可以据此忽略输入）
var busy := false

var _progress := 0.0
var _from := Vector2.ZERO
var _lobes: Array = []
var _droplets: Array = []
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	_build_shape()
	visible = false


## 墨边的不规则形状：角度 + 半径抖动，固定种子保证每次同样好看
func _build_shape() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 861130
	for i in 22:
		_lobes.append({
			"a": TAU * float(i) / 22.0 + rng.randf_range(-0.10, 0.10),
			"j": rng.randf_range(0.78, 1.16),
		})
	for i in 10:
		_droplets.append({
			"a": TAU * float(i) / 10.0 + rng.randf_range(-0.22, 0.22),
			"d": rng.randf_range(1.12, 1.46),
			"r": rng.randf_range(0.030, 0.070),
		})


func play(mid_action: Callable, from := Vector2.ZERO, cover := 0.30, reveal := 0.40) -> void:
	if busy:
		return
	busy = true
	var center := UnitData.DESIGN_SIZE * 0.5
	_from = from if from != Vector2.ZERO else center
	# 从屏幕外点进来（比如右边缘的养成按钮）时，夹回画面内再起笔
	_from = Vector2(
		clampf(_from.x, 0.0, UnitData.DESIGN_SIZE.x),
		clampf(_from.y, 0.0, UnitData.DESIGN_SIZE.y))
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_progress = 0.0
	queue_redraw()

	_tween = create_tween()
	_tween.tween_method(_set_progress, 0.0, 1.0, cover) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	# 屏幕全黑这一帧才做真正的切换
	_tween.tween_callback(func():
		if mid_action.is_valid():
			mid_action.call())
	_tween.tween_interval(0.07)
	_tween.tween_method(_set_progress, 1.0, 0.0, reveal) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_finish)


func _set_progress(v: float) -> void:
	_progress = v
	queue_redraw()


func _finish() -> void:
	busy = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress = 0.0
	queue_redraw()


## 立刻收掉（自检/截图这类流程里避免残留遮罩）
func cancel() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	_finish()


## 调试用：把画面钉在某个进度上，方便截图看墨的形态（不播放动画）
func debug_hold(p: float, from := Vector2.ZERO) -> void:
	busy = true
	_from = from if from != Vector2.ZERO else UnitData.DESIGN_SIZE * 0.5
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_progress = clampf(p, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	if _progress <= 0.002:
		return
	var d: Vector2 = UnitData.DESIGN_SIZE
	var max_r: float = Vector2(d.x * 0.5, d.y * 0.5).length() * 1.12
	var base: float = max_r * _progress
	var ink := Color(UnitData.BG.r, UnitData.BG.g, UnitData.BG.b, 1.0)

	# 主体：一个中心圆 + 一圈偏心圆，边界才是不规则的墨边
	draw_circle(_from, base * 0.94, ink)
	for l in _lobes:
		var ang := float(l["a"])
		var r := base * 0.72 * float(l["j"])
		if r <= 0.5:
			continue
		draw_circle(_from + Vector2(cos(ang), sin(ang)) * (base * 0.46), r, ink)

	# 外围飞溅：只在「漫开」的过程中出现，像墨被冲开
	if _progress < 0.92:
		var a := (1.0 - _progress) * 0.55
		var col := Color(ink.r, ink.g, ink.b, a)
		for l in _droplets:
			var ang2 := float(l["a"])
			var r2 := base * float(l["r"])
			if r2 <= 0.6:
				continue
			draw_circle(_from + Vector2(cos(ang2), sin(ang2)) * (base * float(l["d"])), r2, col)
