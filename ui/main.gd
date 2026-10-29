extends Control

## 游戏外壳：战场 + 顶部 HUD + 底部塔栏 + 右侧卷帘门式养成 + 关卡选择 + 结算。

const DESIGN := Vector2(1280.0, 720.0)
const DRAWER_W := 430.0

@onready var GS: Node = get_node_or_null("/root/GameState")

var field: BattleField

var lbl_ink: Label
var lbl_progress: Label
var progress_bar: ProgressBar
var lbl_insight: Label
var lbl_stage: Label
var lbl_hp: Label
var tower_buttons := {}
var btn_upgrade: Button
var btn_remove: Button
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
var confirm_panel: Control
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
	_build_confirm_panel()
	_build_enemy_card()
	_build_settings_panel()
	GS.insight_changed.connect(_on_economy_changed)
	GS.house_changed.connect(_on_economy_changed)
	# 平衡自检：设置 JG_BALANCE=1 后无头启动会跑完五关并打印结果然后退出
	if OS.has_environment("JG_BALANCE"):
		_run_balance_check.call_deferred()
		return
	# 一次性自检：吸附对齐 + 清空存档（会还原存档）
	if OS.has_environment("JG_GRIDCHECK"):
		_run_grid_check.call_deferred()
		return
	# 调试用：JG_DEV_LEVEL=3 直接进第 3 关并摆好一套塔，方便看画面
	if OS.has_environment("JG_WININFO"):
		var w := get_window()
		print("WININFO screen=", DisplayServer.screen_get_size(), " dpi_scale=", DisplayServer.screen_get_scale())
		print("WININFO window_size=", w.size, " pos=", w.position)
		print("WININFO visible_rect=", get_viewport().get_visible_rect().size)
		print("WININFO cs_size=", w.content_scale_size, " mode=", w.content_scale_mode, " aspect=", w.content_scale_aspect, " factor=", w.content_scale_factor)
		get_tree().quit()
		return
	# 调试用：进指定关卡 + 可选自动截图（JG_SHOT=输出路径）
	if OS.has_environment("JG_DEV_LEVEL"):
		var dev_lv: int = clampi(int(OS.get_environment("JG_DEV_LEVEL")) - 1, 0, 4)
		dev_start(dev_lv)
		if OS.has_environment("JG_SHOT"):
			_run_shot.call_deferred(OS.get_environment("JG_SHOT"))
		return
	if OS.has_environment("JG_SELFTEST"):
		_run_placement_selftest.call_deferred()
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
	field.progress_changed.connect(_on_progress_changed)
	field.new_enemy_seen.connect(_on_new_enemy_seen)


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

	lbl_insight = _make_label("体悟 0")
	lbl_insight.add_theme_color_override("font_color", UnitData.PINK)
	row.add_child(lbl_insight)
	lbl_stage = _make_label("第一本 · 火柴人大陆")
	lbl_stage.add_theme_color_override("font_color", UnitData.LEAF)
	row.add_child(lbl_stage)
	lbl_hp = _make_label("剧情完整度 12/12")
	row.add_child(lbl_hp)

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

	# 纸笔 + 打怪进度：放在操作栏左侧，视线和手都不用来回跑
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.custom_minimum_size = Vector2(186.0, 0.0)
	row.add_child(info)

	lbl_ink = _make_label("纸笔 0")
	lbl_ink.add_theme_font_size_override("font_size", 22)
	lbl_ink.add_theme_color_override("font_color", UnitData.ORANGE)
	info.add_child(lbl_ink)

	lbl_progress = _make_label("击杀 0 / 0")
	lbl_progress.add_theme_font_size_override("font_size", 15)
	lbl_progress.add_theme_color_override("font_color", Color(0.78, 0.75, 0.68))
	info.add_child(lbl_progress)

	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(180.0, 10.0)
	progress_bar.show_percentage = false
	progress_bar.max_value = 1.0
	progress_bar.value = 0.0
	info.add_child(progress_bar)

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

	btn_remove = _make_button("移除")
	btn_remove.custom_minimum_size = Vector2(126.0, 62.0)
	btn_remove.add_theme_color_override("font_color", Color(0.86, 0.62, 0.55))
	btn_remove.pressed.connect(_on_remove_pressed)
	btn_remove.disabled = true
	row.add_child(btn_remove)


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

	# 清空存档（点了还要再确认一次）
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 8.0)
	col.add_child(spacer)

	var clear_btn := _make_button("清空存档")
	clear_btn.custom_minimum_size = Vector2(160.0, 40.0)
	clear_btn.add_theme_color_override("font_color", Color(0.78, 0.55, 0.5))
	clear_btn.pressed.connect(_on_clear_requested)
	clear_btn.add_theme_color_override("font_color", Color(0.78, 0.55, 0.5))

	var key_btn := _make_button("按键设置")
	key_btn.custom_minimum_size = Vector2(160.0, 40.0)
	key_btn.pressed.connect(_open_settings)
	col.add_child(key_btn)
	col.add_child(clear_btn)


## 二次确认弹窗：清空存档不可撤销，必须再点一次"确定清空"
func _build_confirm_panel() -> void:
	confirm_panel = ColorRect.new()
	confirm_panel.name = "ClearConfirm"
	confirm_panel.color = Color(0.05, 0.04, 0.03, 0.92)
	confirm_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	confirm_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	confirm_panel.visible = false
	add_child(confirm_panel)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	confirm_panel.add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	center.add_child(col)

	var title := _make_label("确定清空存档？")
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.85, 0.5, 0.45))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var desc := _make_label(
		"情感体悟、小屋重建进度、已通关的关卡都会清零，\n这个操作没法撤销。"
	)
	desc.add_theme_color_override("font_color", Color(0.78, 0.74, 0.68))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 16)
	col.add_child(desc)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	col.add_child(row)

	var yes := _make_button("确定清空")
	yes.custom_minimum_size = Vector2(150.0, 46.0)
	yes.pressed.connect(_on_clear_confirmed)
	row.add_child(yes)

	var no := _make_button("取消")
	no.custom_minimum_size = Vector2(150.0, 46.0)
	no.pressed.connect(_on_clear_cancelled)
	row.add_child(no)


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


func _on_remove_pressed() -> void:
	field.remove_selected()
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


# --- 清空存档 ---

func _on_clear_requested() -> void:
	confirm_panel.visible = true


func _on_clear_cancelled() -> void:
	confirm_panel.visible = false


func _on_clear_confirmed() -> void:
	confirm_panel.visible = false
	GS.reset_progress()
	# 回到第一关、进度归零的状态
	_show_level_select()
	_refresh_drawer()
	result_panel.visible = false


func _on_economy_changed(_value: Variant) -> void:
	_refresh_hud()
	_refresh_drawer()


# --- 打怪进度 ---

func _on_progress_changed(killed: int, total: int) -> void:
	if lbl_progress == null:
		return
	lbl_progress.text = "击杀 %d / %d" % [killed, total]
	progress_bar.max_value = maxf(1.0, float(total))
	progress_bar.value = float(killed)


# --- 新敌人介绍弹窗（右上角，可关闭）---

var enemy_card: Control
var enemy_card_title: Label
var enemy_card_body: Label


func _build_enemy_card() -> void:
	enemy_card = PanelContainer.new()
	enemy_card.name = "EnemyCard"
	enemy_card.add_theme_stylebox_override("panel", _panel_style(0.97))
	enemy_card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	enemy_card.offset_left = -440.0
	enemy_card.offset_top = 74.0
	enemy_card.offset_right = -14.0
	enemy_card.offset_bottom = 74.0
	enemy_card.custom_minimum_size = Vector2(426.0, 0.0)
	enemy_card.visible = false
	enemy_card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(enemy_card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	enemy_card.add_child(col)

	enemy_card_title = _make_label("新的字")
	enemy_card_title.add_theme_font_size_override("font_size", 22)
	enemy_card_title.add_theme_color_override("font_color", UnitData.PINK)
	enemy_card_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	enemy_card_title.custom_minimum_size = Vector2(400.0, 0.0)
	col.add_child(enemy_card_title)

	enemy_card_body = _make_label("")
	enemy_card_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	enemy_card_body.custom_minimum_size = Vector2(400.0, 0.0)
	enemy_card_body.add_theme_color_override("font_color", Color(0.82, 0.79, 0.72))
	enemy_card_body.add_theme_font_size_override("font_size", 15)
	col.add_child(enemy_card_body)

	var close := _make_button("知道了")
	close.pressed.connect(func(): enemy_card.visible = false)
	col.add_child(close)


func _on_new_enemy_seen(enemy_id: String) -> void:
	var def: Dictionary = UnitData.ENEMIES.get(enemy_id, {})
	if def.is_empty() or enemy_card == null:
		return
	enemy_card_title.text = "出现了新的字：「%s」" % str(def["name"])
	enemy_card_body.text = "%s\n生命 %d　　移动 %d　　护甲 %d" % [
		str(def.get("info", "")), int(def["hp"]), int(def["speed"]), int(def["armor"])
	]
	enemy_card.visible = true


# --- 快捷键（可在按键设置里改；设置存独立文件，清空存档不影响）---

const BIND_ROWS := [
	["pause", "暂停 / 继续"],
	["speed", "切换 x1 / x2"],
	["back", "返回书页"],
	["upgrade", "升级选中的分身"],
	["remove", "移除选中的分身"],
]

var settings_panel: Control
var bind_buttons := {}
var awaiting_action := ""


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return

	# 正在等待玩家按新键
	if awaiting_action != "":
		if k.keycode != KEY_ESCAPE:
			GS.set_bind(awaiting_action, k.keycode)
		awaiting_action = ""
		_refresh_bind_buttons()
		get_viewport().set_input_as_handled()
		return

	if k.keycode == GS.bind_key("pause"):
		if not level_panel.visible and not result_panel.visible and not confirm_panel.visible:
			_toggle_pause()
			get_viewport().set_input_as_handled()
	elif k.keycode == GS.bind_key("speed"):
		if not level_panel.visible and not result_panel.visible:
			_toggle_speed()
			get_viewport().set_input_as_handled()
	elif k.keycode == GS.bind_key("upgrade"):
		if not level_panel.visible and not result_panel.visible:
			_on_upgrade_pressed()
			get_viewport().set_input_as_handled()
	elif k.keycode == GS.bind_key("remove"):
		if not level_panel.visible and not result_panel.visible:
			_on_remove_pressed()
			get_viewport().set_input_as_handled()
	elif k.keycode >= KEY_1 and k.keycode <= KEY_4:
		if not level_panel.visible and not result_panel.visible:
			_on_tower_pressed(UnitData.TOWER_ORDER[k.keycode - KEY_1])
			get_viewport().set_input_as_handled()
	elif k.keycode == GS.bind_key("back"):
		if not level_panel.visible:
			_show_level_select()
			get_viewport().set_input_as_handled()


func _build_settings_panel() -> void:
	settings_panel = ColorRect.new()
	settings_panel.name = "KeySettings"
	settings_panel.color = Color(0.05, 0.04, 0.03, 0.93)
	settings_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_panel.visible = false
	add_child(settings_panel)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_panel.add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)

	var title := _make_label("按键设置")
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var tip := _make_label("点右边的按钮，然后按下你想用的键（按 Esc 取消）")
	tip.add_theme_color_override("font_color", Color(0.7, 0.67, 0.6))
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tip)

	for row_def in BIND_ROWS:
		var action := str(row_def[0])
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 16)
		col.add_child(hb)

		var name_label := _make_label(str(row_def[1]))
		name_label.custom_minimum_size = Vector2(220.0, 0.0)
		hb.add_child(name_label)

		var btn := _make_button("")
		btn.custom_minimum_size = Vector2(170.0, 40.0)
		btn.pressed.connect(_on_bind_pressed.bind(action))
		hb.add_child(btn)
		bind_buttons[action] = btn

	var close := _make_button("关闭")
	close.custom_minimum_size = Vector2(160.0, 44.0)
	close.pressed.connect(_close_settings)
	col.add_child(close)
	_refresh_bind_buttons()


func _on_bind_pressed(action: String) -> void:
	awaiting_action = action
	_refresh_bind_buttons()


func _close_settings() -> void:
	awaiting_action = ""
	settings_panel.visible = false
	_refresh_bind_buttons()


func _refresh_bind_buttons() -> void:
	for action in bind_buttons.keys():
		var btn: Button = bind_buttons[action]
		if awaiting_action == action:
			btn.text = "按任意键…"
		else:
			btn.text = GS.key_label(GS.bind_key(str(action)))


func _open_settings() -> void:
	awaiting_action = ""
	_refresh_bind_buttons()
	settings_panel.visible = true


# --- 刷新 ---

func _refresh_hud() -> void:
	if field == null:
		return
	lbl_ink.text = "纸笔 %d" % int(field.ink)
	lbl_progress.text = "击杀 %d / %d" % [field.kill_count, field.total_enemies]
	progress_bar.max_value = maxf(1.0, float(field.total_enemies))
	progress_bar.value = float(field.kill_count)
	lbl_insight.text = "体悟 %d" % int(GS.insight)
	var levels: Array = UnitData.BASE_DATA["levels"]
	if field.level_index >= 0 and field.level_index < levels.size():
		lbl_stage.text = str(levels[field.level_index]["name"])
	lbl_hp.text = "剧情完整度 %d/%d" % [maxi(field.base_hp, 0), field.base_max]

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
		# 移除：显示能退多少纸笔
		var refund := int(round(float(field.selected.invested) * BattleField.REFUND_RATE))
		btn_remove.text = "移除（退 %d）" % refund
		btn_remove.disabled = not field.running or field.finished
	else:
		btn_upgrade.text = "选中分身可升级"
		btn_upgrade.disabled = true
		btn_remove.text = "移除"
		btn_remove.disabled = true

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
	# 模拟会调用 mark_cleared / add_insight，必须关掉存档写入，否则污染玩家存档
	GS.save_enabled = false
	# 自检必须在「废墟」阶段跑，算是玩家的下限；事后还原，免得把存档改坏
	var saved_stage: int = GS.house_stage
	GS.house_stage = 0
	print("=== 平衡自检（小屋=废墟，无房屋加成）===")
	for i in UnitData.BASE_DATA["levels"].size():
		for mode in [0, 1]:
			var level_plan: Array = dev_build_plan(i)
			var r: Dictionary = field.dev_simulate(i, level_plan, 300.0, mode)
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


## 调试截图：等渲染完成后把整帧存成 PNG（不依赖窗口管理，headless 也能用）
func _run_shot(path: String) -> void:
	await get_tree().create_timer(1.6).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("SHOT saved=", path, " err=", err, " size=", img.get_size())
	get_tree().quit()


## 格子几何自检：验证所有格子都落在格点上、且互不重叠。
func _run_grid_check() -> void:
	GS.save_enabled = false
	var step := UnitData.GRID_STEP
	for i in UnitData.BASE_DATA["levels"].size():
		field.start_level(i)
		field.stop_battle()
		var g: Array = field.ground_cells
		var h: Array = field.high_cells
		var min_gg := INF
		for a in range(g.size()):
			for b in range(a + 1, g.size()):
				min_gg = minf(min_gg, (g[a] as Vector2).distance_to(g[b]))
		var min_gh := INF
		for a in g:
			for b in h:
				min_gh = minf(min_gh, (a as Vector2).distance_to(b))
		var offgrid := 0
		for c in g + h:
			var v := c as Vector2
			var dx := absf(v.x - roundf(v.x / step) * step)
			var dy := absf(v.y - roundf(v.y / step) * step)
			if dx > 0.01 or dy > 0.01:
				offgrid += 1
		print("GRID L%d ground=%d high=%d min_ground_ground=%.1f min_ground_high=%.1f off_lattice=%d" % [i + 1, g.size(), h.size(), min_gg, min_gh, offgrid])
	get_tree().quit()


## 一次性自检：吸附对齐 + 清空存档。跑完会还原存档，不动玩家进度。
## 用法：设置 JG_SELFTEST=1 后无头启动。
func _run_placement_selftest() -> void:
	var save_path := "user://jg_save.json"
	var backup := ""
	if FileAccess.file_exists(save_path):
		backup = FileAccess.get_file_as_string(save_path)
	GS.save_enabled = false

	_start_level(0)
	field.ink = 100.0
	field.set_pending("shield")
	if field.ground_cells.is_empty():
		print("SELFTEST placement SKIP: 没有地面格")
		get_tree().quit()
		return
	var cursor: Vector2 = field.ground_cells[0]
	var ok: bool = field.try_place(cursor)
	var landed := Vector2(-1.0, -1.0)
	if not field.towers.is_empty():
		landed = (field.towers[0] as Tower).pos
	var aligned := false
	for c in field.ground_cells:
		if (c as Vector2).is_equal_approx(landed):
			aligned = true
	print("SELFTEST placement ok=%s cursor=%s landed=%s on_cell=%s" % [
		str(ok), str(cursor), str(landed), str(aligned)
	])

	# 移除返还测试
	var t1: Tower = field.towers[0]
	var invested: int = t1.invested
	field.ink = 0.0
	field.selected = t1
	var removed: bool = field.remove_selected()
	var expected := int(round(float(invested) * BattleField.REFUND_RATE))
	print("SELFTEST remove ok=%s invested=%d refunded=%d expected=%d towers_left=%d" % [
		str(removed), invested, int(field.ink), expected, field.towers.size()
	])

	var before_cleared: int = GS.cleared_count
	var before_insight: int = int(GS.insight)
	_on_clear_confirmed()
	print("SELFTEST clear before(cleared=%d insight=%d) after(cleared=%d insight=%d)" % [
		before_cleared, before_insight, GS.cleared_count, int(GS.insight)
	])

	if backup != "":
		var f := FileAccess.open(save_path, FileAccess.WRITE)
		if f != null:
			f.store_string(backup)
			f.close()
	GS.load_state()
	print("SELFTEST restored cleared=%d insight=%d" % [GS.cleared_count, int(GS.insight)])
	get_tree().quit()


## 测试布阵：按这一关的路线自动取锚点，保证换地图后依然能跑平衡自检。
## 顺序即建造顺序（模拟器按纸笔是否够来决定何时放下）。
func dev_build_plan(index: int) -> Array:
	var plan: Array = []
	var routes: Array = UnitData.level_routes(index)
	if routes.is_empty():
		return plan
	# 每条路线都摆一套，避免多路线关卡有一路完全没人管
	for route in routes:
		var pts: Array = (route as Dictionary).get("points", [])
		if pts.size() < 2:
			continue
		var seglens: Array = []
		var total := 0.0
		for i in range(pts.size() - 1):
			var d: float = (pts[i] as Vector2).distance_to(pts[i + 1])
			seglens.append(d)
			total += d
		if total <= 1.0:
			continue
		var fracs := [0.10, 0.26, 0.42, 0.58, 0.74]
		for f in fracs:
			var target := total * float(f)
			var acc := 0.0
			var anchor: Vector2 = pts[0]
			for i in range(seglens.size()):
				var seg_len: float = seglens[i]
				if acc + seg_len >= target:
					anchor = (pts[i] as Vector2).lerp(pts[i + 1], (target - acc) / seg_len)
					break
				acc += seg_len
			plan.append(["shield", anchor])
			plan.append(["bolt", anchor])
			plan.append(["heal", anchor])
			plan.append(["blade", anchor])
	return plan


## 直接开局并摆好整套测试布阵，方便快速看画面。
func dev_start(index: int) -> void:
	level_panel.visible = false
	_start_level(index)
	var plan: Array = dev_build_plan(index)
	for spec in plan:
		field.ink = 90.0
		var tid := str(spec[0])
		var cell: Variant = field._nearest_free_cell(spec[1], UnitData.tower_deploy(tid))
		if cell != null:
			field._place_exact(tid, cell)
	field.ink = 60.0
	_refresh_hud()
