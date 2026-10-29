extends Control

## 游戏外壳：战场 + 顶部 HUD + 底部塔栏 + 右侧卷帘门式养成 + 关卡选择 + 结算。
##
## HUD 不跟着每帧刷：体悟、纸笔这些数字变化时只打一个 dirty 标记，
## _process 里按 HUD_INTERVAL 节流统一刷新一次。

const DRAWER_W := 430.0
## HUD 最短刷新间隔（秒）。战场 60Hz，界面 8Hz 已经比肉眼快。
const HUD_INTERVAL := 0.12
## 开局规则横幅停留时间（秒）
const RULE_BANNER_TIME := 7.0

## 平衡门禁：每关「小屋=废墟 + 参考布阵」下至少要赢，且剩余血量不低于这个数。
## 第 5 关是终章，允许靠升级打过去，所以 mode0（完全不升级）不强制。
## 改数值后跑 JG_BALANCE=1，不达标就退出码非 0，可以当 CI 用。
const BALANCE_MIN_BASE := {0: 5, 1: 3, 2: 1, 3: 5, 4: 1}
## 这些关必须在不升级的前提下也能过（教学到中期，不该逼玩家氪升级）
const BALANCE_MUST_WIN_UNUPGRADED := [0, 1, 2, 3]

@onready var GS: Node = get_node_or_null("/root/GameState")
@onready var AU: Node = get_node_or_null("/root/Audio")

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
var btn_sfx: Button

var drawer: Control
var drawer_open := false
var drawer_handle: Button
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

var pause_overlay: Control
var rule_banner: Control
var rule_label: Label
var rule_timer := 0.0

var _hud_dirty := true
var _hud_wait := 0.0


func _ready() -> void:
	var win := get_window()
	if win != null:
		win.title = "情感体悟 %s %s" % [UnitData.GAME_VERSION, UnitData.GAME_CHANNEL]
	# 根节点必须忽略鼠标，否则这个全屏 Control 会把所有点击吃掉，
	# 战场的 _unhandled_input 就永远收不到事件（表现为“点左键放不下单位”）。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_theme()
	_build_field()
	_build_pause_overlay()
	_build_top_bar()
	_build_bottom_bar()
	_build_drawer()
	_build_rule_banner()
	_build_level_select()
	_build_result()
	_build_confirm_panel()
	_build_enemy_card()
	_build_settings_panel()
	GS.insight_changed.connect(_mark_hud)
	GS.house_changed.connect(_mark_hud)
	GS.house_changed.connect(func(_s): _refresh_drawer())

	# --- 开发/自检入口（正式版可以删掉这一段）---
	# 这些入口会把存档写坏（例如自动打完一关就记成通关），所以统一关掉写盘。
	if OS.has_environment("JG_DEV_LEVEL") or OS.has_environment("JG_SHOT") \
			or OS.has_environment("JG_BALANCE") or OS.has_environment("JG_GRIDCHECK") \
			or OS.has_environment("JG_SELFTEST"):
		GS.save_enabled = false
	if OS.has_environment("JG_BALANCE"):
		_run_balance_check.call_deferred()
		return
	if OS.has_environment("JG_GRIDCHECK"):
		_run_grid_check.call_deferred()
		return
	if OS.has_environment("JG_WININFO"):
		var w := get_window()
		print("WININFO screen=", DisplayServer.screen_get_size(), " dpi_scale=", DisplayServer.screen_get_scale())
		print("WININFO window_size=", w.size, " pos=", w.position)
		print("WININFO visible_rect=", get_viewport().get_visible_rect().size)
		get_tree().quit()
		return
	if OS.has_environment("JG_DEV_LEVEL"):
		var dev_lv: int = clampi(int(OS.get_environment("JG_DEV_LEVEL")) - 1, 0, 4)
		dev_start(dev_lv)
		# JG_PENDING=bolt 可以直接进「选好了塔、正在找位置」的状态，方便截图
		if OS.has_environment("JG_PENDING"):
			field.set_pending(OS.get_environment("JG_PENDING"))
		if OS.has_environment("JG_DRAWER"):
			_toggle_drawer()
		if OS.has_environment("JG_SHOT"):
			_run_shot.call_deferred(OS.get_environment("JG_SHOT"))
		return
	if OS.has_environment("JG_SELFTEST"):
		_run_placement_selftest.call_deferred()
		return
	# 穿盾回归测试
	if OS.has_environment("JG_SHIELDTEST"):
		_run_shield_test.call_deferred()
		return
	# 只截图关卡选择页（不带 JG_DEV_LEVEL 时走这里）
	if OS.has_environment("JG_SHOT"):
		_show_level_select()
		_run_shot.call_deferred(OS.get_environment("JG_SHOT"))
		return

	_show_level_select()
	_flush_hud()


func _process(delta: float) -> void:
	if rule_timer > 0.0:
		rule_timer -= delta
		if rule_timer <= 0.0:
			_hide_rule_banner()
	if not _hud_dirty:
		return
	_hud_wait -= delta
	if _hud_wait > 0.0:
		return
	_flush_hud()


# --- 主题 ---

func _apply_theme() -> void:
	var th := Theme.new()
	th.default_font = UnitData.font_sans()
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
	b.add_theme_stylebox_override("hover", _button_style(Color(0.20, 0.17, 0.13, 0.98), accent))
	b.add_theme_stylebox_override("pressed", _button_style(Color(0.07, 0.06, 0.05, 1.0), accent))
	b.add_theme_stylebox_override("disabled", _button_style(Color(0.11, 0.11, 0.11, 0.55), Color(0.4, 0.4, 0.4, 0.35)))
	b.add_theme_color_override("font_color", UnitData.PAPER)
	b.add_theme_color_override("font_disabled_color", Color(0.62, 0.59, 0.54))
	b.add_theme_color_override("font_hover_color", Color.WHITE)


# --- 构建 ---

func _build_field() -> void:
	field = BattleField.new()
	field.name = "BattleField"
	add_child(field)
	field.stats_changed.connect(_mark_hud)
	field.selection_changed.connect(_on_selection_changed)
	field.battle_finished.connect(_on_battle_finished)
	field.progress_changed.connect(_on_progress_changed)
	field.new_enemy_seen.connect(_on_new_enemy_seen)


## 暂停遮罩：盖住战场但放行鼠标，免得挡住底部按钮
func _build_pause_overlay() -> void:
	pause_overlay = ColorRect.new()
	pause_overlay.name = "PauseOverlay"
	pause_overlay.color = Color(0.04, 0.03, 0.02, 0.45)
	pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_overlay.offset_top = 60.0
	pause_overlay.offset_bottom = -100.0
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_overlay.visible = false
	add_child(pause_overlay)

	var l := Label.new()
	l.text = "已暂停"
	l.add_theme_font_override("font", UnitData.font_book())
	l.add_theme_font_size_override("font_size", 44)
	l.add_theme_color_override("font_color", Color(1, 0.96, 0.88, 0.9))
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_overlay.add_child(l)


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
	row.add_theme_constant_override("separation", 20)
	bar.add_child(row)

	lbl_insight = _make_label("体悟 0")
	lbl_insight.add_theme_color_override("font_color", UnitData.PINK)
	row.add_child(lbl_insight)

	lbl_stage = _make_label("火柴人大陆")
	lbl_stage.add_theme_font_override("font", UnitData.font_book())
	lbl_stage.add_theme_font_size_override("font_size", 19)
	lbl_stage.add_theme_color_override("font_color", UnitData.PAPER)
	row.add_child(lbl_stage)

	lbl_hp = _make_label("剧情完整度 12/12")
	lbl_hp.add_theme_color_override("font_color", Color(0.86, 0.84, 0.78))
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

	btn_sfx = _make_button("音效 开")
	btn_sfx.pressed.connect(_toggle_sfx)
	row.add_child(btn_sfx)

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

	for i in range(UnitData.TOWER_ORDER.size()):
		var id: String = UnitData.TOWER_ORDER[i]
		var def: Dictionary = UnitData.TOWERS[id]
		var b := _make_button("%s %d\n%s  [%d]" % [def["name"], int(def["cost"]), def["glyph"], i + 1])
		b.custom_minimum_size = Vector2(124.0, 62.0)
		b.add_theme_font_size_override("font_size", 15)
		b.tooltip_text = _tower_tooltip(id)
		b.pressed.connect(_on_tower_pressed.bind(id))
		_style_button(b, def["color"])
		row.add_child(b)
		tower_buttons[id] = b

	var grow := Control.new()
	grow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(grow)

	btn_upgrade = _make_button("选中分身可升级")
	btn_upgrade.custom_minimum_size = Vector2(196.0, 62.0)
	btn_upgrade.add_theme_font_size_override("font_size", 14)
	btn_upgrade.pressed.connect(_on_upgrade_pressed)
	btn_upgrade.disabled = true
	row.add_child(btn_upgrade)

	btn_remove = _make_button("移除")
	btn_remove.custom_minimum_size = Vector2(132.0, 62.0)
	btn_remove.add_theme_font_size_override("font_size", 14)
	btn_remove.add_theme_color_override("font_color", Color(0.88, 0.66, 0.58))
	btn_remove.pressed.connect(_on_remove_pressed)
	btn_remove.disabled = true
	row.add_child(btn_remove)


func _tower_tooltip(id: String) -> String:
	var def: Dictionary = UnitData.TOWERS[id]
	var s: Dictionary = UnitData.tower_stats(id, 1, 1.0)
	var where := "地面 · 会挡路" if str(def["deploy"]) == "ground" else "高台 · 不挡路"
	var role := ""
	match str(def["kind"]):
		"ranged":
			role = "远程单体"
		"melee":
			role = "近身范围伤害"
		"shield":
			role = "只挡不打"
		"heal":
			role = "治疗附近分身"
	var block := ""
	if int(def["block"]) > 0:
		block = "，同时挡 %d 个" % int(def["block"])
	return "%s（%s）\n%s，射程 %d%s\n一级：血 %d / 攻 %d / 间隔 %.2fs" % [
		str(def["name"]), where, role, int(s["range"]), block,
		int(s["hp"]), int(s["atk"]), float(s["interval"])]


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
	# 关着的时候推到屏幕右边界外（用设计宽度，别用写死的 1280）
	drawer.position.x = UnitData.DESIGN_SIZE.x
	drawer.visible = false
	add_child(drawer)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	drawer.add_child(col)

	var title := _make_label("养成 · 情感体悟")
	title.add_theme_font_override("font", UnitData.font_book())
	title.add_theme_font_size_override("font_size", 24)
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

	var tip := _make_label("小魔女在家中读书，体悟会随时间缓慢累积。\n重建小屋能提高分身的数值，也让她读得更快。")
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
	drawer_handle = handle


## 开局横幅：把 unit_data 里写好的 rule 文案用上，补上「没有新手引导」的缺口
func _build_rule_banner() -> void:
	rule_banner = PanelContainer.new()
	rule_banner.name = "RuleBanner"
	rule_banner.add_theme_stylebox_override("panel", _panel_style(0.9))
	rule_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	rule_banner.anchor_left = 0.5
	rule_banner.anchor_right = 0.5
	rule_banner.offset_left = -430.0
	rule_banner.offset_right = 430.0
	rule_banner.offset_top = 62.0
	rule_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule_banner.visible = false
	add_child(rule_banner)

	rule_label = _make_label("")
	rule_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rule_label.custom_minimum_size = Vector2(830.0, 0.0)
	rule_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rule_label.add_theme_color_override("font_color", Color(0.90, 0.87, 0.80))
	rule_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule_banner.add_child(rule_label)


func _show_rule_banner(level: Dictionary) -> void:
	if rule_label == null:
		return
	# 抽屉开着的时候不弹横幅：两张卡片会叠在一起
	if drawer_open:
		return
	var name := str(level.get("rule_name", ""))
	var text := str(level.get("rule", ""))
	if text.is_empty():
		_hide_rule_banner()
		return
	rule_label.text = ("【%s】%s" % [name, text]) if not name.is_empty() else text
	rule_banner.visible = true
	rule_banner.modulate.a = 1.0
	rule_timer = RULE_BANNER_TIME


func _hide_rule_banner() -> void:
	rule_timer = 0.0
	if rule_banner == null:
		return
	var tw := create_tween()
	tw.tween_property(rule_banner, "modulate:a", 0.0, 0.45)
	tw.tween_callback(func(): rule_banner.visible = false)


func _build_level_select() -> void:
	level_panel = ColorRect.new()
	level_panel.name = "LevelSelect"
	level_panel.color = Color(0.08, 0.065, 0.05, 0.93)
	level_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	level_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(level_panel)

	# 装饰层放最前面：纸纹、飘着的字、小屋插画卡、角落文具，
	# 都在内容（标题/关卡卡）下面
	var decor := TitleDecor.new()
	decor.name = "TitleDecor"
	decor.set_anchors_preset(Control.PRESET_FULL_RECT)
	level_panel.add_child(decor)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	level_panel.add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	center.add_child(col)

	var t := _make_label("火柴人大陆")
	t.add_theme_font_override("font", UnitData.font_book())
	t.add_theme_font_size_override("font_size", 46)
	t.add_theme_color_override("font_color", UnitData.PAPER)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)

	var sub := _make_label("第一本 · 五关 · 书里的字跑出来了")
	sub.add_theme_color_override("font_color", Color(0.72, 0.69, 0.62))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	var levels: Array = UnitData.BASE_DATA["levels"]
	for i in range(levels.size()):
		var lv: Dictionary = levels[i]
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(680.0, 92.0)
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(_start_level.bind(i))
		_style_button(b, UnitData.LEAF if i % 2 == 0 else UnitData.WOOD)
		col.add_child(b)
		level_buttons.append(b)

	var hint := _make_label(
		"放分身：点底部按钮 → 战场出现落点预览 → 点格子\n" +
		"金色踏脚 = 路上（墨刃 / 纸盾）　绿色角标 = 路旁（墨矢 / 疗愈符）\n" +
		"快捷键：空格 暂停　F 倍速　U 升级　X 移除　1-4 选塔　Esc 返回")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(680.0, 0.0)
	hint.add_theme_color_override("font_color", Color(0.62, 0.59, 0.52))
	hint.add_theme_font_size_override("font_size", 14)
	col.add_child(hint)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 12)
	col.add_child(footer)

	var key_btn := _make_button("按键与音效")
	key_btn.custom_minimum_size = Vector2(160.0, 40.0)
	key_btn.pressed.connect(_open_settings)
	footer.add_child(key_btn)

	var clear_btn := _make_button("清空存档")
	clear_btn.custom_minimum_size = Vector2(160.0, 40.0)
	clear_btn.add_theme_color_override("font_color", Color(0.80, 0.58, 0.52))
	clear_btn.pressed.connect(_on_clear_requested)
	footer.add_child(clear_btn)

	var ver_line := _make_label("%s %s · 构建 %s" % [
		UnitData.GAME_VERSION, UnitData.GAME_CHANNEL, UnitData.GAME_BUILD])
	ver_line.add_theme_color_override("font_color", Color(0.55, 0.52, 0.46))
	ver_line.add_theme_font_size_override("font_size", 13)
	ver_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(ver_line)


func _build_confirm_panel() -> void:
	confirm_panel = ColorRect.new()
	confirm_panel.name = "ClearConfirm"
	confirm_panel.color = Color(0.05, 0.04, 0.03, 0.93)
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
	title.add_theme_font_override("font", UnitData.font_book())
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.88, 0.55, 0.48))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var desc := _make_label(
		"情感体悟、小屋重建进度、已通关的关卡都会清零，\n这个操作没法撤销。")
	desc.add_theme_color_override("font_color", Color(0.80, 0.76, 0.70))
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
	result_panel.color = Color(0.06, 0.05, 0.04, 0.90)
	result_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	result_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	result_panel.visible = false
	add_child(result_panel)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	result_panel.add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.custom_minimum_size = Vector2(560.0, 0.0)
	center.add_child(col)

	result_title = _make_label("")
	result_title.add_theme_font_override("font", UnitData.font_book())
	result_title.add_theme_font_size_override("font_size", 40)
	result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(result_title)

	result_detail = _make_label("")
	result_detail.add_theme_color_override("font_color", UnitData.LEAF)
	result_detail.add_theme_font_size_override("font_size", 18)
	result_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(result_detail)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)

	var retry := _make_button("再打一次")
	retry.custom_minimum_size = Vector2(150.0, 46.0)
	retry.pressed.connect(_on_retry_pressed)
	row.add_child(retry)

	var back := _make_button("返回书页")
	back.custom_minimum_size = Vector2(150.0, 46.0)
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


func _sfx(name: String, volume_db: float = 0.0) -> void:
	if AU != null:
		AU.play(name, volume_db)


# --- 交互 ---

func _show_level_select() -> void:
	result_panel.visible = false
	level_panel.visible = true
	_hide_rule_banner()
	pause_overlay.visible = false
	field.stop_battle()
	_refresh_level_list()
	_flush_hud()


func _refresh_level_list() -> void:
	var cleared: int = int(GS.cleared_count)
	var levels: Array = UnitData.BASE_DATA["levels"]
	for i in range(level_buttons.size()):
		var b: Button = level_buttons[i]
		var unlocked: bool = i <= cleared
		b.disabled = not unlocked
		var lv: Dictionary = levels[i]
		var mark := ""
		if i < cleared:
			mark = "已通关　"
		elif not unlocked:
			mark = "未解锁　"
		var rule_name := str(lv.get("rule_name", ""))
		var rule := str(lv.get("rule", ""))
		if unlocked:
			b.text = "%s第 %d 关 · %s\n［%s］%s" % [mark, i + 1, str(lv["name"]), rule_name, rule]
		else:
			b.text = "%s第 %d 关 · ？？？\n通关上一关后解锁" % [mark, i + 1]


func _start_level(index: int) -> void:
	_sfx("ui_click", -8)
	level_panel.visible = false
	result_panel.visible = false
	pause_overlay.visible = false
	field.start_level(index)
	_show_rule_banner(field.level)
	_flush_hud()


func _on_tower_pressed(id: String) -> void:
	_sfx("ui_click", -8)
	field.set_pending(id)
	_mark_hud()


func _on_upgrade_pressed() -> void:
	if field.upgrade_selected():
		pass
	_mark_hud()


func _on_remove_pressed() -> void:
	field.remove_selected()
	_mark_hud()


func _toggle_pause() -> void:
	if field.finished:
		return
	field.running = not field.running
	pause_overlay.visible = not field.running and not field.finished
	_sfx("ui_click", -10)
	_mark_hud()


func _toggle_speed() -> void:
	if field.speed_scale > 1.5:
		field.speed_scale = 1.0
	else:
		field.speed_scale = 2.0
	_sfx("ui_click", -10)
	_mark_hud()


func _toggle_sfx() -> void:
	var muted: bool = GS.toggle_sfx()
	if not muted:
		_sfx("ui_click", -8)
	_mark_hud()


func _toggle_drawer() -> void:
	drawer_open = not drawer_open
	_sfx("drawer", -8)
	if drawer_open:
		drawer.visible = true
		# 打开抽屉就把规则横幅收掉，否则两张卡片会压在一起
		_hide_rule_banner()
		# 打开时把手柄挪到面板左边缘，否则会压在面板内容上
		drawer_handle.text = "收起"
		drawer_handle.offset_left = -(DRAWER_W + 46.0)
		drawer_handle.offset_right = -(DRAWER_W + 6.0)
		drawer.position.x = UnitData.DESIGN_SIZE.x
		var tw := create_tween()
		tw.tween_property(drawer, "position:x", UnitData.DESIGN_SIZE.x - DRAWER_W, 0.22) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		drawer_handle.text = "养成"
		drawer_handle.offset_left = -46.0
		drawer_handle.offset_right = -6.0
		var tw2 := create_tween()
		tw2.tween_property(drawer, "position:x", UnitData.DESIGN_SIZE.x, 0.2) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw2.tween_callback(func(): drawer.visible = false)
	_refresh_drawer()


func _on_rebuild_pressed() -> void:
	if GS.buy_house_stage():
		_sfx("upgrade", -4)
	_refresh_drawer()
	_mark_hud()


func _on_pack_pressed() -> void:
	# 一次性补给：扣体悟，纸笔立刻加进这一关，关卡结束就没了
	if not field.running or field.finished:
		return
	if GS.buy_ink_pack():
		field.add_ink(float(GS.ink_pack_bonus()))
		_sfx("place", -6)
	_refresh_drawer()
	_mark_hud()


func _on_retry_pressed() -> void:
	_sfx("ui_click", -8)
	result_panel.visible = false
	_start_level(field.level_index)


func _on_battle_finished(win: bool, gained: float) -> void:
	result_title.text = "这一页写回来了" if win else "字跑光了"
	result_title.add_theme_color_override("font_color", UnitData.LEAF if win else Color("d9573f"))
	var extra := ""
	if win:
		if field.last_first_clear:
			extra = "\n首通奖励已发放。再来只会拿到击杀收益。"
		else:
			extra = "\n本关已通关过，这次只计击杀收益。"
	result_detail.text = "获得 %d 情感体悟%s" % [int(gained), extra]
	result_panel.visible = true
	pause_overlay.visible = false
	_refresh_drawer()
	_flush_hud()


func _on_selection_changed(_tower: Tower) -> void:
	_mark_hud()


# --- 清空存档 ---

func _on_clear_requested() -> void:
	_sfx("ui_click", -8)
	confirm_panel.visible = true


func _on_clear_cancelled() -> void:
	_sfx("ui_back", -8)
	confirm_panel.visible = false


func _on_clear_confirmed() -> void:
	confirm_panel.visible = false
	GS.reset_progress()
	_show_level_select()
	_refresh_drawer()
	result_panel.visible = false


# --- 进程/经济 ---

func _on_progress_changed(killed: int, total: int) -> void:
	if lbl_progress == null:
		return
	lbl_progress.text = "击杀 %d / %d" % [killed, total]
	progress_bar.max_value = maxf(1.0, float(total))
	progress_bar.value = float(killed)


# --- 新敌人介绍弹窗 ---

var enemy_card: Control
var enemy_card_title: Label
var enemy_card_body: Label


func _build_enemy_card() -> void:
	enemy_card = PanelContainer.new()
	enemy_card.name = "EnemyCard"
	enemy_card.add_theme_stylebox_override("panel", _panel_style(0.97))
	enemy_card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	enemy_card.offset_left = -450.0
	enemy_card.offset_top = 74.0
	enemy_card.offset_right = -14.0
	enemy_card.offset_bottom = 74.0
	enemy_card.custom_minimum_size = Vector2(436.0, 0.0)
	enemy_card.visible = false
	enemy_card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(enemy_card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	enemy_card.add_child(col)

	enemy_card_title = _make_label("新的字")
	enemy_card_title.add_theme_font_override("font", UnitData.font_book())
	enemy_card_title.add_theme_font_size_override("font_size", 24)
	enemy_card_title.add_theme_color_override("font_color", UnitData.PINK)
	enemy_card_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	enemy_card_title.custom_minimum_size = Vector2(410.0, 0.0)
	col.add_child(enemy_card_title)

	enemy_card_body = _make_label("")
	enemy_card_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	enemy_card_body.custom_minimum_size = Vector2(410.0, 0.0)
	enemy_card_body.add_theme_color_override("font_color", Color(0.84, 0.81, 0.74))
	enemy_card_body.add_theme_font_size_override("font_size", 15)
	col.add_child(enemy_card_body)

	var close := _make_button("知道了")
	close.pressed.connect(_close_enemy_card)
	col.add_child(close)


func _close_enemy_card() -> void:
	_sfx("ui_back", -10)
	enemy_card.visible = false


func _on_new_enemy_seen(enemy_id: String) -> void:
	var def: Dictionary = UnitData.ENEMIES.get(enemy_id, {})
	if def.is_empty() or enemy_card == null:
		return
	enemy_card_title.text = "出现了新的字：「%s」" % str(def["name"])
	enemy_card_body.text = "%s\n\n生命 %d　　移动 %d　　护甲 %d　　漏掉扣 %d" % [
		str(def.get("info", "")), int(def["hp"]), int(def["speed"]),
		int(def["armor"]), int(def["leak"])]
	enemy_card.visible = true
	_sfx("card", -6)


# --- 快捷键 ---

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
var btn_sfx_setting: Button


func _ui_blocking() -> bool:
	return level_panel.visible or result_panel.visible or confirm_panel.visible or settings_panel.visible


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return

	# 正在等玩家按新键
	if awaiting_action != "":
		if k.keycode != KEY_ESCAPE:
			GS.set_bind(awaiting_action, k.keycode)
		awaiting_action = ""
		_refresh_bind_buttons()
		get_viewport().set_input_as_handled()
		return

	if k.keycode == GS.bind_key("pause"):
		if not _ui_blocking():
			_toggle_pause()
			get_viewport().set_input_as_handled()
	elif k.keycode == GS.bind_key("speed"):
		if not _ui_blocking():
			_toggle_speed()
			get_viewport().set_input_as_handled()
	elif k.keycode == GS.bind_key("upgrade"):
		if not _ui_blocking():
			_on_upgrade_pressed()
			get_viewport().set_input_as_handled()
	elif k.keycode == GS.bind_key("remove"):
		if not _ui_blocking():
			_on_remove_pressed()
			get_viewport().set_input_as_handled()
	elif k.keycode >= KEY_1 and k.keycode <= KEY_4:
		if not _ui_blocking():
			_on_tower_pressed(UnitData.TOWER_ORDER[k.keycode - KEY_1])
			get_viewport().set_input_as_handled()
	elif k.keycode == GS.bind_key("back"):
		if level_panel.visible == false and settings_panel.visible == false:
			_show_level_select()
			get_viewport().set_input_as_handled()


func _build_settings_panel() -> void:
	settings_panel = ColorRect.new()
	settings_panel.name = "KeySettings"
	settings_panel.color = Color(0.05, 0.04, 0.03, 0.94)
	settings_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_panel.visible = false
	add_child(settings_panel)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_panel.add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size = Vector2(460.0, 0.0)
	center.add_child(col)

	var title := _make_label("按键与音效")
	title.add_theme_font_override("font", UnitData.font_book())
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var tip := _make_label("点右边的按钮，然后按下你想用的键（按 Esc 取消）")
	tip.add_theme_color_override("font_color", Color(0.72, 0.69, 0.62))
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.add_theme_font_size_override("font_size", 14)
	col.add_child(tip)

	for row_def in BIND_ROWS:
		var action := str(row_def[0])
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 16)
		col.add_child(hb)

		var name_label := _make_label(str(row_def[1]))
		name_label.custom_minimum_size = Vector2(230.0, 0.0)
		hb.add_child(name_label)

		var btn := _make_button("")
		btn.custom_minimum_size = Vector2(170.0, 40.0)
		btn.pressed.connect(_on_bind_pressed.bind(action))
		hb.add_child(btn)
		bind_buttons[action] = btn

	col.add_child(_separator())

	var sfx_row := HBoxContainer.new()
	sfx_row.add_theme_constant_override("separation", 16)
	col.add_child(sfx_row)

	var sfx_label := _make_label("音效")
	sfx_label.custom_minimum_size = Vector2(230.0, 0.0)
	sfx_row.add_child(sfx_label)

	btn_sfx_setting = _make_button("")
	btn_sfx_setting.custom_minimum_size = Vector2(170.0, 40.0)
	btn_sfx_setting.pressed.connect(_toggle_sfx)
	sfx_row.add_child(btn_sfx_setting)

	var close := _make_button("关闭")
	close.custom_minimum_size = Vector2(160.0, 44.0)
	close.pressed.connect(_close_settings)
	col.add_child(close)
	_refresh_bind_buttons()


func _on_bind_pressed(action: String) -> void:
	_sfx("ui_click", -10)
	awaiting_action = action
	_refresh_bind_buttons()


func _close_settings() -> void:
	_sfx("ui_back", -10)
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
	if btn_sfx_setting != null:
		btn_sfx_setting.text = "已关闭（点开启）" if GS.sfx_muted else "开启"


func _open_settings() -> void:
	_sfx("ui_click", -8)
	awaiting_action = ""
	_refresh_bind_buttons()
	settings_panel.visible = true


# --- HUD 刷新 ---

## 只打标记，真正刷新由 _process 按 HUD_INTERVAL 节流。
## 带一个可选参数是因为 insight_changed 会带值发信号。
func _mark_hud(_value: Variant = null) -> void:
	_hud_dirty = true


func _flush_hud() -> void:
	_hud_dirty = false
	_hud_wait = HUD_INTERVAL
	_refresh_hud()


func _refresh_hud() -> void:
	if field == null or lbl_ink == null:
		return
	lbl_ink.text = "纸笔 %d" % int(field.ink)
	lbl_progress.text = "击杀 %d / %d" % [field.kill_count, field.total_enemies]
	progress_bar.max_value = maxf(1.0, float(field.total_enemies))
	progress_bar.value = float(field.kill_count)
	lbl_insight.text = "体悟 %d" % int(GS.insight)
	var levels: Array = UnitData.BASE_DATA["levels"]
	if field.level_index >= 0 and field.level_index < levels.size():
		var lv: Dictionary = levels[field.level_index]
		lbl_stage.text = "%s　［%s］" % [str(lv["name"]), str(lv.get("rule_name", ""))]
	if field.base_max > 0:
		lbl_hp.text = "剧情完整度 %d/%d" % [maxi(field.base_hp, 0), field.base_max]
	else:
		lbl_hp.text = "剧情完整度 —"

	for id in tower_buttons:
		var b: Button = tower_buttons[id]
		var cost: int = int(UnitData.TOWERS[id]["cost"])
		b.disabled = field.ink < float(cost)
		var glyph := str(UnitData.TOWERS[id]["glyph"])
		var idx := UnitData.TOWER_ORDER.find(id) + 1
		if field.pending_tower == id:
			b.text = "▶%s %d\n%s  [%d]" % [str(UnitData.TOWERS[id]["name"]), cost, glyph, idx]
		else:
			b.text = "%s %d\n%s  [%d]" % [str(UnitData.TOWERS[id]["name"]), cost, glyph, idx]

	if field.selected != null:
		var t: Tower = field.selected
		var max_lv: int = UnitData.tower_max_level(t.id)
		var next_cost: int = UnitData.tower_upgrade_cost(t.id, t.level + 1)
		if next_cost < 0:
			btn_upgrade.text = "已最高级"
			btn_upgrade.disabled = true
		else:
			# 升级到底值不值，得把数值差摆出来，否则玩家没法判断
			var mult: float = GS.tower_mult()
			var now: Dictionary = UnitData.tower_stats(t.id, t.level, mult)
			var nxt: Dictionary = UnitData.tower_stats(t.id, t.level + 1, mult)
			btn_upgrade.text = "升 %d→%d级（%d）\n攻+%d 血+%d" % [
				t.level, t.level + 1, next_cost,
				int(round(float(nxt["atk"]) - float(now["atk"]))),
				int(round(float(nxt["hp"]) - float(now["hp"])))]
			btn_upgrade.disabled = field.ink < float(next_cost) or t.level >= max_lv
		var refund := int(round(float(t.invested) * BattleField.REFUND_RATE))
		btn_remove.text = "移除\n退 %d 纸笔" % refund
		btn_remove.disabled = not field.running or field.finished
	else:
		btn_upgrade.text = "点场上的分身\n可查看升级"
		btn_upgrade.disabled = true
		btn_remove.text = "移除"
		btn_remove.disabled = true

	btn_pause.text = "继续" if not field.running and not field.finished else "暂停"
	btn_speed.text = "x2" if field.speed_scale > 1.5 else "x1"
	btn_sfx.text = "音效 关" if GS.sfx_muted else "音效 开"
	btn_sfx.add_theme_color_override("font_color",
		Color(0.66, 0.63, 0.58) if GS.sfx_muted else UnitData.PAPER)
	_refresh_drawer()


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
			str(UnitData.HOUSE_STAGES[int(GS.house_stage) + 1]["name"]), cost]
		drawer_rebuild.disabled = float(GS.insight) < float(cost)

	drawer_pack.text = "立刻补 %d 纸笔（%d 体悟，仅本关）" % [
		GS.ink_pack_bonus(), GS.ink_pack_cost()]
	var can_buy := field.running and not field.finished and float(GS.insight) >= float(GS.ink_pack_cost())
	drawer_pack.disabled = not can_buy
	drawer_rate.text = "阅读产出：%.2f 体悟/秒　｜　分身加成：+%d%%" % [
		float(GS.read_rate()), GS.tower_bonus_percent()]

	# 小屋占位表现：越接近完整，画面越亮越有颜色
	var stage := float(GS.house_stage) / float(UnitData.HOUSE_STAGES.size() - 1)
	var lum := lerpf(0.34, 1.0, stage)
	drawer_house_tex.modulate = Color(lum, lum * 0.98, lum * 0.94, 1.0)


# --- 开发入口（正式版可以删） ---

## 无头平衡自检：JG_BALANCE=1 启动后跑完全部关卡。
## 会按 BALANCE_MIN_BASE 判断达标，不达标就非 0 退出码 —— 可以当 CI 门禁用。
func _run_balance_check() -> void:
	# 模拟会调用 mark_cleared / add_insight，必须关掉存档写入，否则污染玩家存档
	GS.save_enabled = false
	var saved_stage: int = GS.house_stage
	var saved_cleared: int = GS.cleared_count
	GS.house_stage = 0
	GS.cleared_count = 0
	field.audio_enabled = false
	print("=== 平衡自检（小屋=废墟，无房屋加成，固定步长 %.4fs）===" % UnitData.FIXED_DT)
	var failures := 0
	for i in UnitData.BASE_DATA["levels"].size():
		for mode in [0, 1, 2]:
			GS.cleared_count = 0
			var plan: Array = dev_build_plan(i)
			var r: Dictionary = field.dev_simulate(i, plan, 300.0, mode)
			var required: bool = mode != 0 or BALANCE_MUST_WIN_UNUPGRADED.has(i)
			var ok: bool = (not required) or (bool(r["win"]) and int(r["base"]) >= int(BALANCE_MIN_BASE.get(i, 1)))
			if not ok:
				failures += 1
			print("L%d mode%d %s base=%d/%d t=%ds placed=%d lvsum=%d insight=%d%s" % [
				i + 1, mode, "WIN " if r["win"] else ("TIME" if r["timeout"] else "LOSE"),
				r["base"], r["base_max"], r["seconds"], r["placed"], r["levels_sum"],
				r["insight"], "" if ok else "   <== FAIL"])
	GS.house_stage = saved_stage
	GS.cleared_count = saved_cleared
	if failures == 0:
		print("=== 自检通过（%d 项全达标）===" % (UnitData.BASE_DATA["levels"].size() * 3))
	else:
		print("=== 自检失败：%d 项未达标 ===" % failures)
	get_tree().quit(1 if failures > 0 else 0)


## 调试截图：等渲染完成后把整帧存成 PNG（不依赖窗口管理）。
## JG_SHOT_DELAY 可以指定等待秒数（默认 1.8），想截「打起来」的画面就调大。
func _run_shot(path: String) -> void:
	var delay := 1.8
	if OS.has_environment("JG_SHOT_DELAY"):
		delay = maxf(0.2, float(OS.get_environment("JG_SHOT_DELAY")))
	await get_tree().create_timer(delay).timeout
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
		# 散落文具也要落在格点上，而且不能和可放置格重叠
		var prop_overlap := 0
		for c in field.prop_cells:
			var pv := c as Vector2
			var pdx := absf(pv.x - roundf(pv.x / step) * step)
			var pdy := absf(pv.y - roundf(pv.y / step) * step)
			if pdx > 0.01 or pdy > 0.01:
				offgrid += 1
			if h.has(c):
				prop_overlap += 1
		print("GRID L%d ground=%d high=%d props=%d min_ground_ground=%.1f min_ground_high=%.1f off_lattice=%d prop_overlap=%d" % [
			i + 1, g.size(), h.size(), field.prop_cells.size(), min_gg, min_gh, offgrid, prop_overlap])
	get_tree().quit()


## 穿盾回归测试：JG_SHIELDTEST=1
##
## 场景：一个纸盾（挡 3）+ 6 个敌人。3 个挡住之后，剩下 3 个必须**排队**等着，
## 不能从盾身上走过去 —— v0.1.10 修的就是「第 4 个开始穿模」。
## 断言：没有任何活着的敌人越过盾所在的沿路位置。
func _run_shield_test() -> void:
	GS.save_enabled = false
	field.audio_enabled = false
	field.start_level(0)
	field.stop_battle()
	# 把自动波次和场景清空，只留我们自己摆的东西
	field._spawns.clear()
	field._spawn_cursor = 0
	field.enemies.clear()
	field.towers.clear()
	field._reindex_towers()

	var path: Array = (field.routes[0] as Dictionary).get("points", [])
	if path.size() < 2 or field.ground_cells.size() < 6:
		print("SHIELDTEST SKIP: 关卡数据不足")
		get_tree().quit(2)
		return

	var cum := _path_cumulative(path)
	var shield_cell: Vector2 = field.ground_cells[5]
	field.ink = 999.0
	field._place_exact("shield", shield_cell)
	var shield: Tower = field.towers[0]
	var shield_along := _along_pos(shield.pos, path, cum)

	for i in 6:
		var en := Enemy.new()
		en.setup("zao", path, 1.0, 1.0)
		field.enemies.append(en)

	var dt := UnitData.FIXED_DT
	var t := 0.0
	while t < 9.0:
		field._step(dt)
		t += dt
		if shield.is_dead():
			break

	var alive := 0
	var passed := 0
	var engaged := 0
	for e in field.enemies:
		var en := e as Enemy
		if en.is_dead():
			continue
		alive += 1
		if en.target == shield:
			engaged += 1
		if _along_at(en, path, cum) > shield_along + 8.0:
			passed += 1

	var ok: bool = passed == 0 and alive >= 5
	print("SHIELDTEST %s alive=%d passed_through=%d engaged=%d shield_hp=%d" % [
		"PASS" if ok else "FAIL", alive, passed, engaged, int(shield.hp)])
	# 退出前清干净，免得 Godot 报 ObjectDB leak 警告
	field.enemies.clear()
	field.towers.clear()
	get_tree().quit(0 if ok else 1)


func _path_cumulative(path: Array) -> Array:
	var cum: Array = [0.0]
	for i in range(path.size() - 1):
		cum.append(float(cum[i]) + (path[i] as Vector2).distance_to(path[i + 1]))
	return cum


## 敌人已经沿路走了多远
func _along_at(en: Enemy, path: Array, cum: Array) -> float:
	if en.seg >= path.size() - 1:
		return float(cum[path.size() - 1])
	var seg_l: float = (path[en.seg] as Vector2).distance_to(path[en.seg + 1])
	return float(cum[en.seg]) + en.seg_t * seg_l


## 某个世界坐标投影到路线上的里程
func _along_pos(p: Vector2, path: Array, cum: Array) -> float:
	var best := INF
	var best_a := 0.0
	for i in range(path.size() - 1):
		var a: Vector2 = path[i]
		var b: Vector2 = path[i + 1]
		var ab := b - a
		var len_sq := ab.length_squared()
		if len_sq <= 0.0001:
			continue
		var k := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
		var d := p.distance_to(a + ab * k)
		if d < best:
			best = d
			best_a = float(cum[i]) + k * sqrt(len_sq)
	return best_a


## 一次性自检：吸附对齐 + 移除返还 + 清空存档。跑完会还原存档。
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
	print("SELFTEST placement ok=%s cursor=%s landed=%s on_cell=%s occupied=%s" % [
		str(ok), str(cursor), str(landed), str(aligned), str(field.cell_occupied(landed))])

	var t1: Tower = field.towers[0]
	var invested: int = t1.invested
	field.ink = 0.0
	field.selected = t1
	var removed: bool = field.remove_selected()
	var expected := int(round(float(invested) * BattleField.REFUND_RATE))
	print("SELFTEST remove ok=%s invested=%d refunded=%d expected=%d towers_left=%d still_occupied=%s" % [
		str(removed), invested, int(field.ink), expected, field.towers.size(),
		str(field.cell_occupied(landed))])

	var before_cleared: int = GS.cleared_count
	var before_insight: int = int(GS.insight)
	_on_clear_confirmed()
	print("SELFTEST clear before(cleared=%d insight=%d) after(cleared=%d insight=%d)" % [
		before_cleared, before_insight, GS.cleared_count, int(GS.insight)])

	if backup != "":
		var f := FileAccess.open(save_path, FileAccess.WRITE)
		if f != null:
			f.store_string(backup)
			f.close()
	GS.load_state()
	print("SELFTEST restored cleared=%d insight=%d" % [GS.cleared_count, int(GS.insight)])
	get_tree().quit()


## 测试布阵：按路线自动取锚点，各塔型错开位置，尽量贴近真人打法。
## 顺序即建造顺序（模拟器按纸笔是否够来决定何时放下）。
func dev_build_plan(index: int) -> Array:
	var plan: Array = []
	var routes: Array = UnitData.level_routes(index)
	if routes.is_empty():
		return plan
	# 先铺便宜的输出和盾：纸笔是主要瓶颈，贵的放后面才铺得开
	var recipe := ["bolt", "shield", "blade", "bolt", "heal", "shield", "blade", "bolt", "heal", "shield"]
	var fracs := [0.10, 0.18, 0.26, 0.34, 0.42, 0.50, 0.58, 0.66, 0.74, 0.82]
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
		for k in range(recipe.size()):
			var target := total * float(fracs[k % fracs.size()])
			var acc := 0.0
			var anchor: Vector2 = pts[0]
			for i in range(seglens.size()):
				var seg_len: float = seglens[i]
				if acc + seg_len >= target:
					anchor = (pts[i] as Vector2).lerp(pts[i + 1], (target - acc) / seg_len)
					break
				acc += seg_len
			plan.append([str(recipe[k]), anchor])
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
	_flush_hud()
