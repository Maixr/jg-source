extends Control

## 游戏外壳：战场 + 顶部 HUD + 底部塔栏 + 右侧卷帘门式养成 + 关卡选择 + 结算。

const DESIGN := Vector2(1280.0, 720.0)
const DRAWER_W := 430.0

@onready var GS: Node = get_node_or_null("/root/GameState")

var field: BattleField

var lbl_ink: Label
var lbl_insight: Label
var lbl_stage: Label
var lbl_hp: Label
var lbl_wave: Label
var tower_buttons := {}
var btn_upgrade: Button
var btn_speed: Button
var btn_pause: Button
var btn_back: Button

var drawer: Control
var drawer_open := false
var drawer_house_name: Label
var drawer_house_tex: TextureRect
var drawer_rebuild: Button
var drawer_pack: Button
var drawer_rate: Label

var level_panel: Control
var level_buttons: Array = []

var result_panel: Control
var result_title: Label
var result_detail: Label


func _ready() -> void:
	# 窗口标题：用显示名，不改 project 名（避免 user:// 存档目录跟着变）
	var win := get_window()
	if win != null:
		win.title = "情感体悟 %s %s" % [UnitData.GAME_VERSION, UnitData.GAME_CHANNEL]
	# 根节点必须忽略鼠标：否则这个全屏 Control 会把所有点击吃掉，
	# 战场的 _unhandled_input 就永远收不到事件（表现为“点左键放不下单位”）。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_theme()
	_build_field()
	_build_top_bar()
	_build_bottom_bar()
	_build_drawer()
	_build_level_select()
	_build_result()
	GS.insight_changed.connect(_on_economy_changed)
	GS.house_changed.connect(_on_economy_changed)
	# 平衡自检：设置 JG_BALANCE=1 后无头启动会跑完五关并打印结果然后退出
	if OS.has_environment("JG_BALANCE"):
		_run_balance_check.call_deferred()
		return
	_show_level_select()
	_refresh_hud()


# --- 主题 ---

func _apply_theme() -> void:
	var th := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray([
		"Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "Noto Sans CJK SC",
	])
	font.allow_system_fallback = true
	th.default_font = font
	th.default_font_size = 16
	theme = th


func _panel_style(alpha: float = 0.92) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UnitData.BG.r, UnitData.BG.g, UnitData.BG.b, alpha)
	sb.border_color = Color(UnitData.WOOD.r, UnitData.WOOD.g, UnitData.WOOD.b, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	return sb


func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	return sb


func _style_button(b: Button, accent: Color = UnitData.WOOD) -> void:
	b.add_theme_stylebox_override("normal", _button_style(Color(0.10, 0.09, 0.08, 0.95), accent))
	b.add_theme_stylebox_override("hover", _button_style(Color(0.18, 0.16, 0.13, 0.98), accent))
	b.add_theme_stylebox_override("pressed", _button_style(Color(0.07, 0.06, 0.05, 1.0), accent))
	b.add_theme_stylebox_override("disabled", _button_style(Color(0.13, 0.13, 0.13, 0.6), Color(0.4, 0.4, 0.4, 0.4)))
	b.add_theme_color_override("font_color", UnitData.PAPER)
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.52, 0.48))
	b.add_theme_color_override("font_hover_color", Color.WHITE)


# --- 构建 ---

func _build_field() -> void:
	field = BattleField.new()
	field.name = "BattleField"
	add_child(field)
	field.stats_changed.connect(_refresh_hud)
	field.selection_changed.connect(_on_selection_changed)
	field.battle_finished.connect(_on_battle_finished)


func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.name = "TopBar"
	bar.add_theme_stylebox_override("panel", _panel_style(0.9))
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 10.0
	bar.offset_right = -10.0
	bar.offset_top = 8.0
	bar.offset_bottom = 54.0
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	bar.add_child(row)

	lbl_ink = _make_label("纸笔 0")
	row.add_child(lbl_ink)
	lbl_insight = _make_label("体悟 0")
	lbl_insight.add_theme_color_override("font_color", UnitData.PINK)
	row.add_child(lbl_insight)
	lbl_stage = _make_label("第一本 · 火柴人大陆")
	lbl_stage.add_theme_color_override("font_color", UnitData.LEAF)
	row.add_child(lbl_stage)
	lbl_hp = _make_label("剧情完整度 12/12")
	row.add_child(lbl_hp)
	lbl_wave = _make_label("剩余 0")
	row.add_child(lbl_wave)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	btn_pause = _make_button("暂停")
	btn_pause.pressed.connect(_toggle_pause)
	row.add_child(btn_pause)

	btn_speed = _make_button("x1")
	btn_speed.pressed.connect(_toggle_speed)
	row.add_child(btn_speed)

	btn_back = _make_button("返回书页")
	btn_back.pressed.connect(_show_level_select)
	row.add_child(btn_back)

	var ver := _make_label("%s %s" % [UnitData.GAME_VERSION, UnitData.GAME_CHANNEL])
	ver.add_theme_color_override("font_color", Color(0.62, 0.59, 0.52))
	ver.add_theme_font_size_override("font_size", 13)
	row.add_child(ver)


func _build_bottom_bar() -> void:
	var bar := PanelContainer.new()
	bar.name = "BottomBar"
	bar.add_theme_stylebox_override("panel", _panel_style(0.9))
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 10.0
	bar.offset_right = -10.0
	bar.offset_top = -96.0
	bar.offset_bottom = -10.0
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)

	for id in UnitData.TOWER_ORDER:
		var def: Dictionary = UnitData.TOWERS[id]
		var b := _make_button("%s\n%s  %d" % [def["name"], def["glyph"], int(def["cost"])])
		b.custom_minimum_size = Vector2(118.0, 62.0)
		b.pressed.connect(_on_tower_pressed.bind(id))
		_style_button(b, def["color"])
		row.add_child(b)
		tower_buttons[id] = b

	var grow := Control.new()
	grow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(grow)

	btn_upgrade = _make_button("升级")
	btn_upgrade.custom_minimum_size = Vector2(150.0, 62.0)
	btn_upgrade.pressed.connect(_on_upgrade_pressed)
	btn_upgrade.disabled = true
	row.add_child(btn_upgrade)


func _build_drawer() -> void:
	drawer = PanelContainer.new()
	drawer.name = "Drawer"
	drawer.add_theme_stylebox_override("panel", _panel_style(0.97))
	drawer.anchor_left = 1.0
	drawer.anchor_right = 1.0
	drawer.anchor_top = 0.0
	drawer.anchor_bottom = 1.0
	drawer.offset_left = -DRAWER_W
	drawer.offset_right = 0.0
	drawer.offset_top = 58.0
	drawer.offset_bottom = -104.0
	drawer.position.x = DESIGN.x
	drawer.visible = false
	add_child(drawer)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	drawer.add_child(col)

	var title := _make_label("养成 · 情感体悟")
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", UnitData.PINK)
	col.add_child(title)

	drawer_house_tex = TextureRect.new()
	drawer_house_tex.custom_minimum_size = Vector2(0.0, 210.0)
	drawer_house_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	drawer_house_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	drawer_house_tex.clip_contents = true
	var tex := load("res://art/house/house_intact.jpg")
	if tex is Texture2D:
		drawer_house_tex.texture = tex
	col.add_child(drawer_house_tex)

	drawer_house_name = _make_label("小屋 · 废墟")
	drawer_house_name.add_theme_font_size_override("font_size", 18)
	col.add_child(drawer_house_name)

	drawer_rebuild = _make_button("重建小屋")
	drawer_rebuild.pressed.connect(_on_rebuild_pressed)
	col.add_child(drawer_rebuild)

	col.add_child(_separator())

	drawer_pack = _make_button("补充纸笔")
	drawer_pack.pressed.connect(_on_pack_pressed)
	col.add_child(drawer_pack)

	drawer_rate = _make_label("阅读产出：0.10 体悟/秒")
	drawer_rate.add_theme_color_override("font_color", UnitData.LEAF)
	col.add_child(drawer_rate)

	var tip := _make_label("小魔女在家中读书，体悟会随时间缓慢累积。\n重建小屋能提高塔的数值，也让她读得更快。")
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_color_override("font_color", Color(0.72, 0.69, 0.63))
	tip.add_theme_font_size_override("font_size", 14)
	col.add_child(tip)

	var handle := _make_button("养成")
	handle.name = "DrawerHandle"
	handle.custom_minimum_size = Vector2(40.0, 120.0)
	handle.anchor_left = 1.0
	handle.anchor_right = 1.0
	handle.anchor_top = 0.5
	handle.anchor_bottom = 0.5
	handle.offset_left = -46.0
	handle.offset_right = -6.0
	handle.offset_top = -60.0
	handle.offset_bottom = 60.0
	handle.pressed.connect(_toggle_drawer)
	add_child(handle)


func _build_level_select() -> void:
	level_panel = ColorRect.new()
	level_panel.name = "LevelSelect"
	level_panel.color = Color(0.06, 0.05, 0.04, 0.86)
	level_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	level_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(level_panel)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	level_panel.add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	center.add_child(col)

	var t := _make_label("火柴人大陆")
	t.add_theme_font_size_override("font_size", 40)
	t.add_theme_color_override("font_color", UnitData.PAPER)
	col.add_child(t)

	var sub := _make_label("第一本 · 五关 · 书里的字跑出来了")
	sub.add_theme_color_override("font_color", Color(0.7, 0.67, 0.6))
	col.add_child(sub)

	var ver_line := _make_label("%s %s · 构建 %s" % [
		UnitData.GAME_VERSION, UnitData.GAME_CHANNEL, UnitData.GAME_BUILD
	])
	ver_line.add_theme_color_override("font_color", Color(0.55, 0.52, 0.46))
	ver_line.add_theme_font_size_override("font_size", 13)
	col.add_child(ver_line)

	var levels: Array = UnitData.BASE_DATA["levels"]
	for i in range(levels.size()):
		var lv: Dictionary = levels[i]
		var b := _make_button("第 %d 关 · %s" % [i + 1, lv["name"]])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(560.0, 54.0)
		b.pressed.connect(_start_level.bind(i))
		col.add_child(b)
		level_buttons.append(b)

	var hint := _make_label(
		"选塔：点底部按钮，场上会出现落点预览（圈 + 射程）\n" +
		"放置：金色踏脚 = 路上，放墨刃/纸盾；绿色方块 = 路旁，放墨矢/疗愈符\n" +
		"升级：点场上已有的分身　取消：右键"
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(560.0, 0.0)
	hint.add_theme_color_override("font_color", Color(0.6, 0.57, 0.5))
	hint.add_theme_font_size_override("font_size", 14)
	col.add_child(hint)


func _build_result() -> void:
	result_panel = ColorRect.new()
	result_panel.name = "Result"
	result_panel.color = Color(0.06, 0.05, 0.04, 0.88)
	result_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	result_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	result_panel.visible = false
	add_child(result_panel)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	result_panel.add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)

	result_title = _make_label("")
	result_title.add_theme_font_size_override("font_size", 36)
	col.add_child(result_title)

	result_detail = _make_label("")
	result_detail.add_theme_color_override("font_color", UnitData.LEAF)
	col.add_child(result_detail)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)

	var retry := _make_button("再打一次")
	retry.pressed.connect(_on_retry_pressed)
	row.add_child(retry)

	var back := _make_button("返回书页")
	back.pressed.connect(func(): result_panel.visible = false; _show_level_select())
	row.add_child(back)


# --- 小工具 ---

func _make_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", UnitData.PAPER)
	return l


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	_style_button(b)
	return b


func _separator() -> Control:
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.12)
	line.custom_minimum_size = Vector2(0.0, 1.0)
	return line


# --- 交互 ---

func _show_level_select() -> void:
	result_panel.visible = false
	level_panel.visible = true
	field.stop_battle()
	_refresh_level_list()
	_refresh_hud()


func _refresh_level_list() -> void:
	var cleared: int = int(GS.cleared_count)
	for i in range(level_buttons.size()):
		var b: Button = level_buttons[i]
		var unlocked: bool = i <= cleared
		b.disabled = not unlocked
		var mark := "✔ " if i < cleared else ("▶ " if unlocked else "🔒 ")
		b.text = "%s第 %d 关" % [mark, i + 1]


func _start_level(index: int) -> void:
	level_panel.visible = false
	result_panel.visible = false
	field.start_level(index)
	_refresh_hud()


func _on_tower_pressed(id: String) -> void:
	field.set_pending(id)
	_refresh_hud()


func _on_upgrade_pressed() -> void:
	field.upgrade_selected()
	_refresh_hud()


func _toggle_pause() -> void:
	# 之前这里有个逻辑反了的提前返回：暂停时 running=false，
	# 反而被 `if not field.running ... return` 挡住，导致暂停后点不动。
	if field.finished:
		return
	field.running = not field.running
	_refresh_hud()


func _toggle_speed() -> void:
	if field.speed_scale > 1.5:
		field.speed_scale = 1.0
		btn_speed.text = "x1"
	else:
		field.speed_scale = 2.0
		btn_speed.text = "x2"


func _toggle_drawer() -> void:
	drawer_open = not drawer_open
	if drawer_open:
		drawer.visible = true
		drawer.position.x = DESIGN.x
		var tw := create_tween()
		tw.tween_property(drawer, "position:x", DESIGN.x - DRAWER_W, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		var tw := create_tween()
		tw.tween_property(drawer, "position:x", DESIGN.x, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.tween_callback(func(): drawer.visible = false)
	_refresh_drawer()


func _on_rebuild_pressed() -> void:
	GS.buy_house_stage()
	_refresh_drawer()
	_refresh_hud()


func _on_pack_pressed() -> void:
	# 一次性补给：扣体悟，纸笔立刻加进这一关，关卡结束就没了
	if not field.running or field.finished:
		return
	if GS.buy_ink_pack():
		field.add_ink(float(GS.ink_pack_bonus()))
	_refresh_drawer()
	_refresh_hud()


func _on_retry_pressed() -> void:
	result_panel.visible = false
	field.start_level(field.level_index)
	_refresh_hud()


func _on_battle_finished(win: bool, gained: float) -> void:
	result_title.text = "这一页写回来了" if win else "字跑光了"
	result_title.add_theme_color_override("font_color", UnitData.LEAF if win else Color("d9573f"))
	result_detail.text = "获得 %d 情感体悟" % int(gained)
	result_panel.visible = true
	_refresh_drawer()
	_refresh_hud()


func _on_selection_changed(tower: Tower) -> void:
	_refresh_hud()


func _on_economy_changed(_value: Variant) -> void:
	_refresh_hud()
	_refresh_drawer()


# --- 刷新 ---

func _refresh_hud() -> void:
	if field == null:
		return
	lbl_ink.text = "纸笔 %d" % int(field.ink)
	lbl_insight.text = "体悟 %d" % int(GS.insight)
	var levels: Array = UnitData.BASE_DATA["levels"]
	if field.level_index >= 0 and field.level_index < levels.size():
		lbl_stage.text = str(levels[field.level_index]["name"])
	lbl_hp.text = "剧情完整度 %d/%d" % [maxi(field.base_hp, 0), field.base_max]
	lbl_wave.text = "敌 %d" % field.enemies.size()

	for id in tower_buttons:
		var b: Button = tower_buttons[id]
		var cost: int = int(UnitData.TOWERS[id]["cost"])
		b.disabled = field.ink < float(cost)
		if field.pending_tower == id:
			b.text = "▶ %s\n%s  %d" % [UnitData.TOWERS[id]["name"], UnitData.TOWERS[id]["glyph"], cost]
		else:
			b.text = "%s\n%s  %d" % [UnitData.TOWERS[id]["name"], UnitData.TOWERS[id]["glyph"], cost]

	if field.selected != null:
		var next_cost: int = UnitData.tower_upgrade_cost(field.selected.id, field.selected.level + 1)
		if next_cost < 0:
			btn_upgrade.text = "已最高级"
			btn_upgrade.disabled = true
		else:
			btn_upgrade.text = "升级 %d → %d 级（%d）" % [field.selected.level, field.selected.level + 1, next_cost]
			btn_upgrade.disabled = field.ink < float(next_cost)
	else:
		btn_upgrade.text = "选中分身可升级"
		btn_upgrade.disabled = true

	btn_pause.text = "暂停" if field.running else "继续"
	btn_speed.text = "x2" if field.speed_scale > 1.5 else "x1"


func _refresh_drawer() -> void:
	if drawer_house_name == null:
		return
	drawer_house_name.text = "小屋 · %s" % str(GS.house_name())
	var cost: int = int(GS.next_house_cost())
	if cost < 0:
		drawer_rebuild.text = "小屋已重建完成"
		drawer_rebuild.disabled = true
	else:
		drawer_rebuild.text = "重建：%s（%d 体悟）" % [
			str(UnitData.HOUSE_STAGES[int(GS.house_stage) + 1]["name"]), cost
		]
		drawer_rebuild.disabled = float(GS.insight) < float(cost)

	drawer_pack.text = "立刻补 %d 纸笔（%d 体悟，仅本关）" % [
		GS.ink_pack_bonus(), GS.ink_pack_cost()
	]
	# 只能在关卡进行中买，否则买了就浪费了
	var can_buy := field.running and not field.finished and float(GS.insight) >= float(GS.ink_pack_cost())
	drawer_pack.disabled = not can_buy
	drawer_rate.text = "阅读产出：%.2f 体悟/秒　｜　分身加成：+%d%%（攻击/生命）" % [
		float(GS.read_rate()), GS.tower_bonus_percent()
	]

	# 小屋占位表现：越接近完整，画面越亮越有颜色
	var stage := float(GS.house_stage) / float(UnitData.HOUSE_STAGES.size() - 1)
	var lum := lerpf(0.34, 1.0, stage)
	drawer_house_tex.modulate = Color(lum, lum * 0.98, lum * 0.94, 1.0)


# --- 调试入口（开发期便捷，正式版可以删掉） ---

## 无头平衡自检：JG_BALANCE=1 启动后跑完全部关卡并打印结果。
## 调整五关难度就用它验证，不用打开编辑器。
func _run_balance_check() -> void:
	var plan := dev_build_plan()
	# 必须按「废墟」阶段（无房屋加成）来算，这是玩家的下限；事后还原免得改坏存档
	var saved_stage: int = GS.house_stage
	GS.house_stage = 0
	print("=== 平衡自检（小屋=废墟，无房屋加成）===")
	for i in UnitData.BASE_DATA["levels"].size():
		for mode in [0, 1]:
			var r: Dictionary = field.dev_simulate(i, plan, 300.0, mode)
			var lvsum := 0
			for tw in field.towers:
				lvsum += tw.level
			print("L%d mode%d %s base=%d/%d t=%ds placed=%d lvsum=%d" % [
				i + 1, mode, "WIN " if r["win"] else "LOSE",
				r["base"], r["base_max"], r["seconds"], r["placed"], lvsum
			])
	GS.house_stage = saved_stage
	print("=== 自检结束 ===")
	get_tree().quit()


## 一套通用的测试布阵：锚点位置 + 塔种，模拟器会就近找对应类型的空格。
## 顺序即建造顺序（模拟器按纸笔是否够来决定何时放下）。
func dev_build_plan() -> Array:
	return [
		["shield", Vector2(320.0, 300.0)],
		["bolt", Vector2(386.0, 300.0)],
		["blade", Vector2(320.0, 392.0)],
		["heal", Vector2(254.0, 300.0)],
		["bolt", Vector2(540.0, 380.0)],
		["shield", Vector2(756.0, 300.0)],
		["bolt", Vector2(822.0, 300.0)],
		["blade", Vector2(540.0, 444.0)],
		["bolt", Vector2(978.0, 400.0)],
		["shield", Vector2(1044.0, 520.0)],
	]


## 直接开局并摆好整套测试布阵，方便快速看画面。
func dev_start(index: int) -> void:
	_start_level(index)
	for spec in dev_build_plan():
		field.ink = 90.0
		var tid := str(spec[0])
		var cell: Variant = field._nearest_free_cell(spec[1], UnitData.tower_deploy(tid))
		if cell != null:
			field._place_exact(tid, cell)
	field.ink = 60.0
	_refresh_hud()
