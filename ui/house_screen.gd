class_name HouseScreen
extends Control

## 小魔女的书屋：在首页推门进来，用【体悟】逐条升级。
##
## 上一版把养成塞成战斗页右侧的抽屉，两个毛病：
##   1. 打着仗还要分神去点升级，节奏很碎
##   2. 只有一个线性阶段，玩家没有选择
## 现在改成独立界面 + 6 条互相独立的升级轨道。

signal closed()
signal buy_requested(id: String)

const LEFT_W := 520.0

var _rows := {}
var _lbl_insight: Label
var _lbl_progress: Label
var _house_tex: TextureRect
var _gs: Node
var _au: Node


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_gs = get_node_or_null("/root/GameState")
	_au = get_node_or_null("/root/Audio")
	_build()
	refresh()


func _sfx(name: String, db: float = 0.0) -> void:
	if _au != null:
		_au.play(name, db)


func _build() -> void:
	# 背景：半透明纸底（下面的战场/首页会透一点点出来）
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.06, 0.045, 0.96)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# --- 左栏：标题 + 插画 + 说明 ---
	var left := VBoxContainer.new()
	left.position = Vector2(70.0, 64.0)
	left.custom_minimum_size = Vector2(LEFT_W, 0.0)
	left.add_theme_constant_override("separation", 14)
	add_child(left)

	var title := UiStyle.label("小魔女的书屋", 38)
	title.add_theme_font_override("font", UnitData.font_book())
	left.add_child(title)

	var sub := UiStyle.label("把书读进去，本事就长在身上", 15, Color(0.74, 0.70, 0.62))
	left.add_child(sub)

	_house_tex = TextureRect.new()
	_house_tex.custom_minimum_size = Vector2(LEFT_W, 300.0)
	_house_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_house_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_house_tex.clip_contents = true
	if ResourceLoader.exists("res://art/house/house_intact.jpg"):
		_house_tex.texture = load("res://art/house/house_intact.jpg")
	left.add_child(_house_tex)

	var insight_row := HBoxContainer.new()
	insight_row.add_theme_constant_override("separation", 8)
	left.add_child(insight_row)
	insight_row.add_child(IconBadge.new("insight", 12.0, Color(0.91, 0.66, 0.76), true))
	_lbl_insight = UiStyle.label("体悟 0", 24, Color(0.91, 0.66, 0.76))
	insight_row.add_child(_lbl_insight)

	_lbl_progress = UiStyle.label("书屋进度 0/23", 15, Color(0.70, 0.67, 0.60))
	left.add_child(_lbl_progress)

	var tip := UiStyle.label(
		"体悟会随时间自动累积（小屋越亮，读得越快）。\n" +
		"这里的升级会影响之后所有关卡；已经放好的分身，\n" +
		"升级「分身强化」时会立刻跟着变强。", 14, Color(0.66, 0.63, 0.56))
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(LEFT_W, 0.0)
	left.add_child(tip)

	# --- 右栏：升级列表 ---
	var right := VBoxContainer.new()
	right.position = Vector2(650.0, 64.0)
	right.add_theme_constant_override("separation", 8)
	add_child(right)

	var head := UiStyle.label("升级", 26)
	head.add_theme_font_override("font", UnitData.font_book())
	right.add_child(head)

	for id in UnitData.UPGRADE_ORDER:
		right.add_child(_make_row(str(id)))

	# --- 底部：回首页 ---
	var back := Button.new()
	back.text = "回到首页"
	back.custom_minimum_size = Vector2(180.0, 46.0)
	back.position = Vector2(70.0, 812.0)
	UiStyle.apply_button(back)
	back.pressed.connect(func():
		_sfx("ui_back", -8)
		closed.emit())
	add_child(back)


func _make_row(id: String) -> Control:
	var def: Dictionary = UnitData.UPGRADES[id]
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel(0.55, 10))
	panel.custom_minimum_size = Vector2(880.0, 84.0)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)

	# 字形徽标
	var glyph := UiStyle.label(str(def.get("glyph", "?")), 24, UnitData.LEAF)
	glyph.add_theme_font_override("font", UnitData.font_book())
	glyph.custom_minimum_size = Vector2(38.0, 0.0)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(glyph)

	# 名字 + 说明
	var texts := VBoxContainer.new()
	texts.custom_minimum_size = Vector2(330.0, 0.0)
	texts.add_theme_constant_override("separation", 2)
	row.add_child(texts)
	texts.add_child(UiStyle.label(str(def["name"]), 17))
	texts.add_child(UiStyle.label(str(def["desc"]), 13, Color(0.68, 0.65, 0.58)))

	# 当前效果
	var effect := UiStyle.label("", 14, Color(0.86, 0.82, 0.72))
	effect.custom_minimum_size = Vector2(160.0, 0.0)
	row.add_child(effect)

	# 等级点
	var pips := UiStyle.label("", 16, UnitData.LEAF)
	pips.custom_minimum_size = Vector2(110.0, 0.0)
	row.add_child(pips)

	# 价格
	var cost := UiStyle.label("", 14, UnitData.ORANGE)
	cost.custom_minimum_size = Vector2(96.0, 0.0)
	row.add_child(cost)

	var btn := Button.new()
	btn.text = "升级"
	btn.custom_minimum_size = Vector2(96.0, 42.0)
	UiStyle.apply_button(btn)
	btn.pressed.connect(func():
		_sfx("ui_click", -8)
		buy_requested.emit(id))
	row.add_child(btn)

	_rows[id] = {"effect": effect, "pips": pips, "cost": cost, "btn": btn}
	return panel


func refresh() -> void:
	if _gs == null or _lbl_insight == null:
		return
	_lbl_insight.text = "体悟 %d" % int(_gs.insight)
	_lbl_progress.text = "书屋进度 %d/%d" % [_gs.house_level_sum(), _gs.house_level_total()]
	var prog := float(_gs.house_progress())
	_house_tex.modulate = Color(lerpf(0.38, 1.0, prog), lerpf(0.37, 1.0, prog),
		lerpf(0.34, 0.96, prog), 1.0)

	for id in UnitData.UPGRADE_ORDER:
		var refs: Dictionary = _rows[str(id)]
		var lv: int = _gs.up_level(str(id))
		var max_lv: int = _gs.up_max(str(id))
		var dots := ""
		for i in range(max_lv):
			dots += "●" if i < lv else "○"
		(refs["pips"] as Label).text = dots
		(refs["effect"] as Label).text = _effect_text(str(id), lv)
		var cost: int = _gs.up_cost(str(id))
		if cost < 0:
			(refs["cost"] as Label).text = "已满级"
			(refs["cost"] as Label).add_theme_color_override("font_color", Color(0.58, 0.55, 0.50))
			(refs["btn"] as Button).disabled = true
			(refs["btn"] as Button).text = "满级"
		else:
			(refs["cost"] as Label).text = "%d 体悟" % cost
			(refs["cost"] as Label).add_theme_color_override("font_color", UnitData.ORANGE)
			(refs["btn"] as Button).disabled = not _gs.can_buy_upgrade(str(id))
			(refs["btn"] as Button).text = "升级"


## 当前等级下的实际效果文案（带数值，不是只有「+30%」）
func _effect_text(id: String, lv: int) -> String:
	match id:
		"insight":
			return "体悟 %.2f/秒" % float(_gs.read_rate())
		"ink":
			return "纸笔回复 ×%.2f" % float(_gs.ink_mult())
		"power":
			return "分身 +%d%%" % int(_gs.tower_bonus_percent())
		"prep":
			return "开局 +%.1f 秒" % float(_gs.prep_time())
		"speed":
			return "倍速上限 x%d" % int(_gs.max_speed())
		"level":
			return "可升到 %d 级" % int(_gs.tower_level_cap())
	return ""
