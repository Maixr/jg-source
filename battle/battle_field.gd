class_name BattleField
extends Node2D

## 塔防战场。
## 部署规则（明日方舟式）：
##   地面格 = 路线上的落脚点，只能放 墨刃 / 纸盾，会真正挡在敌人面前
##   高台格 = 路旁，只能放 墨矢 / 疗愈符
## 敌人会主动索敌并攻击友方，优先攻击「纸盾」；护甲减免每次伤害。

signal stats_changed()
signal selection_changed(tower: Tower)
signal battle_finished(win: bool, insight_gained: float)

const DESIGN := Vector2(1280.0, 720.0)
const PATH_WIDTH := 46.0
const INK_CAP := 99.0
const LEASH := 1.35

var level: Dictionary = {}
var level_index := 0

var towers: Array = []
var enemies: Array = []
var shots: Array = []
var floats: Array = []

var high_cells: Array = []
var ground_cells: Array = []
var path: Array = []

var ink := 0.0
var base_hp := 0
var base_max := 0
var elapsed := 0.0
var insight_gained := 0.0
var running := false
var finished := false
var speed_scale := 1.0

var pending_tower := ""
var selected: Tower = null

var _spawns: Array = []
var _spawn_cursor := 0
var _ink_rate := 1.0
var _font: SystemFont

## Autoload 通过显式取节点访问，编辑器内编译检查也能通过。
@onready var GS: Node = get_node_or_null("/root/GameState")


func _ready() -> void:
	_font = SystemFont.new()
	_font.font_names = PackedStringArray([
		"Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "Noto Sans CJK SC",
	])
	_font.allow_system_fallback = true
	path = UnitData.PATH_POINTS.duplicate()
	_build_cells()
	# 房屋升级时，场上已有的分身立刻跟着变强（而不是只管之后新放的）
	if GS != null:
		GS.house_changed.connect(_on_house_changed)
	set_process(true)


## 小屋重建后，把新倍率套用到所有已存在的分身上。
func _on_house_changed(_stage: int) -> void:
	var mult: float = GS.tower_mult()
	for t in towers:
		(t as Tower).reapply_mult(mult)
	if not towers.is_empty():
		_flash_text(
			(towers[0] as Tower).pos + Vector2(0.0, -34.0),
			"小屋重建：分身 +%d%%" % GS.tower_bonus_percent(),
			UnitData.LEAF
		)
	stats_changed.emit()
	queue_redraw()


## 养成里买纸笔：立刻加进当前这一关（一次性，本关结束就没了）
func add_ink(amount: float) -> void:
	if amount <= 0.0:
		return
	ink = minf(INK_CAP, ink + amount)
	_flash_text(Vector2(DESIGN.x * 0.5, 96.0), "+%d 纸笔" % int(amount), UnitData.ORANGE)
	stats_changed.emit()
	queue_redraw()


# --- 格子 ---

func _build_cells() -> void:
	_build_high_cells()
	_build_ground_cells()


func _build_high_cells() -> void:
	high_cells.clear()
	var step := UnitData.GRID_STEP
	var y := step * 0.5
	while y < DESIGN.y:
		var x := step * 0.5
		while x < DESIGN.x:
			var p := Vector2(x, y)
			var d := _dist_to_path(p)
			if d > UnitData.CELL_MIN_DIST and d <= UnitData.CELL_MAX_DIST:
				high_cells.append(p)
			x += step
		y += step


func _build_ground_cells() -> void:
	ground_cells.clear()
	var step := UnitData.GROUND_STEP
	var carry := 0.0
	for i in range(path.size() - 1):
		var a: Vector2 = path[i]
		var b: Vector2 = path[i + 1]
		var seg := a.distance_to(b)
		if seg <= 0.001:
			continue
		var dir := (b - a) / seg
		var t := carry
		while t < seg:
			var p := a + dir * t
			if p.x > 24.0 and p.x < DESIGN.x - 24.0 and p.y > 24.0 and p.y < DESIGN.y - 24.0:
				ground_cells.append(p)
			t += step
		carry = t - seg


func _dist_to_path(p: Vector2) -> float:
	var best := INF
	for i in range(path.size() - 1):
		best = minf(best, _dist_point_segment(p, path[i], path[i + 1]))
	return best


func _dist_point_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq <= 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)


# --- 生命周期 ---

func start_level(index: int) -> void:
	level_index = index
	level = UnitData.BASE_DATA["levels"][index]
	towers.clear()
	enemies.clear()
	shots.clear()
	floats.clear()
	selected = null
	pending_tower = ""
	elapsed = 0.0
	insight_gained = 0.0
	finished = false
	running = true
	speed_scale = 1.0
	base_max = int(level.get("base_hp", 12))
	base_hp = base_max
	ink = float(level.get("start_ink", 20))
	_ink_rate = UnitData.INK_REGEN * float(level.get("ink_mult", 1.0))
	_spawns.clear()
	_spawn_cursor = 0
	for wave in level.get("waves", []):
		var at := float(wave.get("at", 0.0))
		for group in wave.get("spawns", []):
			var count := int(group.get("count", 1))
			var gap := float(group.get("gap", 1.0))
			for i in range(count):
				_spawns.append({"at": at + float(i) * gap, "type": str(group.get("type", "zao"))})
	_spawns.sort_custom(func(a, b): return float(a["at"]) < float(b["at"]))
	stats_changed.emit()
	selection_changed.emit(null)
	queue_redraw()


func stop_battle() -> void:
	running = false


# --- 部署 ---

func set_pending(tower_id: String) -> void:
	pending_tower = tower_id if pending_tower != tower_id else ""
	selected = null
	selection_changed.emit(null)
	stats_changed.emit()
	queue_redraw()


func tower_cost(tower_id: String) -> int:
	return int((UnitData.TOWERS.get(tower_id, {}) as Dictionary).get("cost", 0))


func try_place(at: Vector2) -> bool:
	if pending_tower.is_empty() or not running:
		return false
	var err := placement_error(pending_tower, at)
	if not err.is_empty():
		_flash_text(at, err, Color("d9573f"))
		return false
	if not _place_exact(pending_tower, at):
		return false
	if ink < float(tower_cost(pending_tower)):
		pending_tower = ""
	stats_changed.emit()
	return true


## 放置是否合法。返回空串 = 可以放；否则是给玩家看的原因。
## 放置不吸附网格，直接落在光标位置，只检查「在路面上 / 在路旁 / 别重叠」。
func placement_error(tower_id: String, at: Vector2) -> String:
	if at.x < 12.0 or at.x > 1204.0 or at.y < 62.0 or at.y > 620.0:
		return "这个位置在可放置区域外"
	var kind := UnitData.tower_deploy(tower_id)
	var d := _dist_to_path(at)
	if kind == "ground":
		if d > 26.0:
			return "地面分身只能放在路面上"
	else:
		if d < 30.0:
			return "高台分身要放在路旁，不能压在路面上"
		if d > 134.0:
			return "离路线太远了"
	for t in towers:
		if (t as Tower).pos.distance_to(at) < 28.0:
			return "离已有分身太近"
	if ink < float(tower_cost(tower_id)):
		return "纸笔不够"
	return ""


func _place_exact(tower_id: String, cell: Vector2) -> bool:
	for t in towers:
		if (t as Tower).pos.distance_to(cell) < 28.0:
			return false
	var cost := tower_cost(tower_id)
	if ink < float(cost):
		return false
	var t := Tower.new()
	t.setup(tower_id, cell, GS.tower_mult())
	towers.append(t)
	ink -= float(cost)
	_flash_text(cell, "-%d 纸笔" % cost, UnitData.ORANGE)
	queue_redraw()
	return true


func upgrade_selected() -> bool:
	if selected == null or not running:
		return false
	if not try_upgrade(selected):
		_flash_text(selected.pos, "纸笔不够", Color("d9573f"))
		return false
	return true


func try_upgrade(tw: Tower) -> bool:
	if tw == null or not running:
		return false
	var cost := UnitData.tower_upgrade_cost(tw.id, tw.level + 1)
	if cost < 0 or ink < float(cost):
		return false
	if not tw.upgrade(GS.tower_mult()):
		return false
	ink -= float(cost)
	_flash_text(tw.pos, "升到 %d 级" % tw.level, UnitData.LEAF)
	stats_changed.emit()
	queue_redraw()
	return true


## 模拟器用：把纸笔花在最便宜的可升级分身身上
func _auto_upgrade_once() -> bool:
	var best: Tower = null
	var best_cost := 1 << 30
	for t in towers:
		var tw := t as Tower
		if tw.level >= UnitData.tower_max_level(tw.id):
			continue
		var c := UnitData.tower_upgrade_cost(tw.id, tw.level + 1)
		if c < 0 or ink < float(c):
			continue
		if c < best_cost:
			best_cost = c
			best = tw
	if best == null:
		return false
	return try_upgrade(best)


func select_tower_at(at: Vector2) -> void:
	var best: Tower = null
	var best_d := 26.0
	for t in towers:
		var tw := t as Tower
		var d := tw.pos.distance_to(at)
		if d < best_d:
			best_d = d
			best = tw
	selected = best
	selection_changed.emit(selected)
	queue_redraw()


func _nearest_cell(at: Vector2, kind: String) -> Variant:
	var list: Array = ground_cells if kind == "ground" else high_cells
	var best: Variant = null
	var best_d := 30.0
	for c in list:
		var d := (c as Vector2).distance_to(at)
		if d < best_d:
			best_d = d
			best = c
	return best


## 找离锚点最近的空闲格子（模拟器/调试用，不限距离）
func _nearest_free_cell(at: Vector2, kind: String) -> Variant:
	var list: Array = ground_cells if kind == "ground" else high_cells
	var best: Variant = null
	var best_d := INF
	for c in list:
		var p: Vector2 = c
		if _tower_at(p) != null:
			continue
		var d := p.distance_to(at)
		if d < best_d:
			best_d = d
			best = p
	return best


func _tower_at(cell: Vector2) -> Tower:
	for t in towers:
		if (t as Tower).pos.is_equal_approx(cell):
			return t
	return null


# --- 主循环 ---

func _process(delta: float) -> void:
	if not running or finished:
		return
	var scaled := delta * speed_scale
	elapsed += scaled
	ink = minf(INK_CAP, ink + _ink_rate * scaled)
	_spawn_due()
	_update_enemies(scaled)
	_update_towers(scaled)
	_cleanup(scaled)
	_check_end()
	queue_redraw()


func _spawn_due() -> void:
	while _spawn_cursor < _spawns.size():
		var entry: Dictionary = _spawns[_spawn_cursor]
		if float(entry["at"]) > elapsed:
			break
		var e := Enemy.new()
		e.setup(
			str(entry["type"]),
			path,
			float(level.get("enemy_hp_mult", 1.0)),
			float(level.get("enemy_speed_mult", 1.0))
		)
		enemies.append(e)
		_spawn_cursor += 1


## 纸盾的「仇恨半径」。比自身射程大得多，敌人会主动走过来扑盾，
## 路上遇到墨刃也不会停下来打。
const SHIELD_AGGRO := 170.0


## 最近的、还能挡人的纸盾（已在挡这个敌人的也算）。
func _nearest_shield(en: Enemy) -> Tower:
	var best: Tower = null
	var best_d := SHIELD_AGGRO
	for t in towers:
		var tw := t as Tower
		if tw.is_dead() or tw.kind != "shield":
			continue
		if not tw.engaged.has(en) and not tw.can_block():
			continue
		var d := tw.pos.distance_to(en.pos)
		if d < best_d:
			best_d = d
			best = tw
	return best


## 敌人索敌，分三档优先级：纸盾 > 其他阻挡者 > 高台单位。
## 每帧都会重新调用（见 _update_enemies），所以盾一进射程就能抢走仇恨。
func _pick_target(en: Enemy) -> Tower:
	# 第一档：纸盾。射程内就扑上去；还在稍远处就继续朝它走，
	# 这期间不理会其他单位——所以敌人会穿过墨刃去扑盾。
	var shield: Tower = _nearest_shield(en)
	if shield != null:
		if en.pos.distance_to(shield.pos) <= en.attack_range:
			return shield
		return null

	# 第二档：墨刃之类的其他阻挡者
	var best: Tower = null
	var best_d := INF
	for t in towers:
		var tw := t as Tower
		if tw.is_dead() or tw.block_capacity <= 0:
			continue
		if not tw.engaged.has(en) and not tw.can_block():
			continue
		var d := tw.pos.distance_to(en.pos)
		if d <= en.attack_range and d < best_d:
			best_d = d
			best = tw
	if best != null:
		return best

	# 第三档：高台单位（墨矢 / 疗愈符）
	for t in towers:
		var tw := t as Tower
		if tw.is_dead():
			continue
		var d := tw.pos.distance_to(en.pos)
		if d <= en.attack_range and d < best_d:
			best_d = d
			best = tw
	return best


func _detach(en: Enemy) -> void:
	if en.target != null:
		en.target.engaged.erase(en)
	en.target = null


func _update_enemies(delta: float) -> void:
	for e in enemies:
		var en := e as Enemy
		if en.is_dead():
			continue
		en.flash = maxf(0.0, en.flash - delta)
		en.cooldown = maxf(0.0, en.cooldown - delta)

		# 每帧重新索敌：盾一进入射程就抢走仇恨，
		# 而不是被最早进入射程的单位（通常是墨刃）锁死。
		var picked := _pick_target(en)
		if picked != en.target:
			_detach(en)
			en.target = picked
			if en.target != null:
				en.target.engaged.append(en)

		if en.target != null:
			if en.cooldown <= 0.0:
				en.cooldown = en.interval
				en.target.take_damage(en.atk)
				shots.append({
					"from": en.pos, "to": en.target.pos, "life": 0.12,
					"color": Color("d9573f") if not en.ranged else en.color,
				})
			continue

		en.advance(delta)


func _update_towers(delta: float) -> void:
	for t in towers:
		var tw := t as Tower
		tw.flash = maxf(0.0, tw.flash - delta)
		tw.cooldown = maxf(0.0, tw.cooldown - delta)
		if tw.is_dead():
			continue
		if tw.cooldown > 0.0:
			continue
		match tw.kind:
			"ranged":
				var target := _enemy_in_range(tw.pos, tw.atk_range)
				if target != null:
					tw.cooldown = tw.interval
					target.take_damage(maxf(1.0, tw.atk - target.armor))
					shots.append({"from": tw.pos, "to": target.pos, "life": 0.12,
						"color": tw.color})
			"melee":
				var hits := 0
				for e in enemies:
					var en := e as Enemy
					if en.is_dead():
						continue
					if tw.pos.distance_to(en.pos) <= tw.atk_range:
						en.take_damage(maxf(1.0, tw.atk - en.armor))
						hits += 1
				if hits > 0:
					tw.cooldown = tw.interval
					tw.flash = 0.14
			"heal":
				var patient := _hurt_ally(tw)
				if patient != null:
					tw.cooldown = tw.interval
					patient.hp = minf(patient.max_hp, patient.hp + tw.atk)
					shots.append({"from": tw.pos, "to": patient.pos, "life": 0.18,
						"color": tw.color})


func _enemy_in_range(at: Vector2, radius: float) -> Enemy:
	var best: Enemy = null
	var best_d := radius
	for e in enemies:
		var en := e as Enemy
		if en.is_dead():
			continue
		var d := at.distance_to(en.pos)
		if d <= best_d:
			best_d = d
			best = en
	return best


func _hurt_ally(healer: Tower) -> Tower:
	var best: Tower = null
	var best_ratio := 0.999
	for t in towers:
		var tw := t as Tower
		if tw == healer or tw.is_dead():
			continue
		if healer.pos.distance_to(tw.pos) > healer.atk_range:
			continue
		var ratio := tw.hp / tw.max_hp if tw.max_hp > 0.0 else 1.0
		if ratio < best_ratio:
			best_ratio = ratio
			best = tw
	return best


func _cleanup(delta: float) -> void:
	var survivors: Array = []
	for e in enemies:
		var en := e as Enemy
		if en.is_dead():
			if en.escaped:
				base_hp -= en.leak
				_flash_text(en.pos, "-%d 剧情" % en.leak, Color("d9573f"))
			else:
				insight_gained += float(en.insight_reward)
				GS.add_insight(float(en.insight_reward))
				_flash_text(en.pos, "+%d 体悟" % en.insight_reward, UnitData.PINK)
			_detach(en)
			continue
		survivors.append(en)
	enemies = survivors

	var standing: Array = []
	for t in towers:
		var tw := t as Tower
		if tw.is_dead():
			_flash_text(tw.pos, "分身消散", Color("d9573f"))
			for e2 in enemies:
				if (e2 as Enemy).target == tw:
					(e2 as Enemy).target = null
			if selected == tw:
				selected = null
				selection_changed.emit(null)
			continue
		standing.append(tw)
	towers = standing

	for s in shots:
		s["life"] = float(s["life"]) - delta
	shots = shots.filter(func(s): return float(s["life"]) > 0.0)

	for f in floats:
		f["life"] = float(f["life"]) - delta
		f["pos"] = (f["pos"] as Vector2) + Vector2(0.0, -26.0 * delta)
	floats = floats.filter(func(f): return float(f["life"]) > 0.0)


func _check_end() -> void:
	if finished:
		return
	if base_hp <= 0:
		base_hp = 0
		_finish(false)
		return
	if _spawn_cursor >= _spawns.size() and enemies.is_empty():
		_finish(true)


func _finish(win: bool) -> void:
	finished = true
	running = false
	if win:
		var bonus := 10.0 + float(level_index) * 5.0
		insight_gained += bonus
		GS.add_insight(bonus)
		GS.mark_cleared(level_index)
	stats_changed.emit()
	battle_finished.emit(win, insight_gained)
	queue_redraw()


func _flash_text(pos: Vector2, text: String, color: Color) -> void:
	floats.append({"pos": pos, "text": text, "color": color, "life": 0.9})


# --- 平衡模拟器（开发用） ---

## 运行期难度覆盖，用来扫参数而不必反复编译。
func _apply_tuning(o: Dictionary) -> void:
	if o.is_empty():
		return
	var lv: Dictionary = (level as Dictionary).duplicate(true)
	lv["enemy_hp_mult"] = float(lv.get("enemy_hp_mult", 1.0)) * float(o.get("hp", 1.0))
	lv["enemy_speed_mult"] = float(lv.get("enemy_speed_mult", 1.0)) * float(o.get("speed", 1.0))
	level = lv
	_ink_rate *= float(o.get("ink", 1.0))
	var mult := float(o.get("base", 1.0))
	if mult != 1.0:
		base_max = maxi(1, int(round(float(base_max) * mult)))
		base_hp = base_max

## 同步跑完一关，用来批量验证数值与可玩性。
## build: [[tower_id, Vector2 锚点], ...] 按顺序、够纸笔就放置
## upgrade_mode: 0=不升级 1=铺满计划后升级 2=有钱就升级
## overrides: 运行期难度覆盖 {"hp":1.0,"speed":1.0,"ink":1.0,"base":1.0}
func dev_simulate(
	index: int,
	build: Array,
	max_seconds: float = 420.0,
	upgrade_mode: int = 1,
	overrides: Dictionary = {}
) -> Dictionary:
	set_process(false)
	start_level(index)
	_apply_tuning(overrides)
	var step := 1.0 / 30.0
	var speed := 3.0
	var t := 0.0
	var build_i := 0
	var upg_timer := 0.0
	while not finished and t < max_seconds:
		while build_i < build.size():
			var spec: Array = build[build_i]
			var tid := str(spec[0])
			var anchor: Vector2 = spec[1]
			if ink < float(tower_cost(tid)):
				break
			var kind := UnitData.tower_deploy(tid)
			var cell: Variant = _nearest_free_cell(anchor, kind)
			if cell == null:
				build_i += 1
				continue
			_place_exact(tid, cell)
			build_i += 1
		upg_timer -= step * speed
		if upg_timer <= 0.0:
			upg_timer = 1.5
			if upgrade_mode == 1 and build_i >= build.size():
				_auto_upgrade_once()
			elif upgrade_mode == 2:
				_auto_upgrade_once()
		_process(step * speed)
		t += step * speed
	var result := {
		"level": index,
		"win": not finished or base_hp > 0,
		"finished": finished,
		"base": base_hp,
		"base_max": base_max,
		"seconds": int(t),
		"placed": build_i,
		"insight": int(insight_gained),
		"towers_left": towers.size(),
		"enemies_left": enemies.size(),
	}
	set_process(true)
	running = false
	finished = true
	return result


# --- 绘制 ---

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, DESIGN), UnitData.BG, true)
	_draw_grid_backdrop()
	_draw_high_cells()
	_draw_path()
	_draw_ground_cells()
	_draw_base()
	if pending_tower != "":
		_draw_pending_hint()
	for t in towers:
		_draw_tower(t as Tower)
	for e in enemies:
		_draw_enemy(e as Enemy)
	for s in shots:
		draw_line(s["from"], s["to"], s["color"], 2.5, true)
	for f in floats:
		var a := clampf(float(f["life"]) / 0.9, 0.0, 1.0)
		var c: Color = f["color"]
		c.a = a
		_draw_centered(str(f["text"]), f["pos"], 15, c)


func _draw_grid_backdrop() -> void:
	var step := 96.0
	var y := 0.0
	while y < DESIGN.y:
		draw_line(Vector2(0.0, y), Vector2(DESIGN.x, y), Color(1, 1, 1, 0.025), 1.0)
		y += step
	var x := 0.0
	while x < DESIGN.x:
		draw_line(Vector2(x, 0.0), Vector2(x, DESIGN.y), Color(1, 1, 1, 0.025), 1.0)
		x += step


func _draw_high_cells() -> void:
	var half := UnitData.GRID_STEP * 0.5 - 3.0
	for c in high_cells:
		var p: Vector2 = c
		var occupied := _tower_at(p) != null
		var rect := Rect2(p - Vector2(half, half), Vector2(half, half) * 2.0)
		draw_rect(rect, Color(0.66, 0.77, 0.42, 0.04 if occupied else 0.07), true)
		draw_rect(rect, Color(0.66, 0.77, 0.42, 0.10 if occupied else 0.20), false, 1.0)


func _draw_path() -> void:
	for i in range(path.size() - 1):
		var a: Vector2 = path[i]
		var b: Vector2 = path[i + 1]
		draw_line(a, b, Color(0.66, 0.46, 0.25, 0.38), PATH_WIDTH, true)
		draw_line(a, b, Color(0.85, 0.78, 0.66, 0.32), PATH_WIDTH * 0.42, true)


## 地面格：路线上的落脚点，可以站人挡路
func _draw_ground_cells() -> void:
	var half := 15.0
	for c in ground_cells:
		var p: Vector2 = c
		var occupied := _tower_at(p) != null
		var rect := Rect2(p - Vector2(half, half), Vector2(half, half) * 2.0)
		draw_rect(rect, Color(0.92, 0.82, 0.58, 0.05 if occupied else 0.10), true)
		draw_rect(rect, Color(0.92, 0.82, 0.58, 0.14 if occupied else 0.30), false, 1.5)


func _draw_base() -> void:
	var p := Vector2(DESIGN.x - 54.0, 612.0)
	var col := Color("c9a227") if base_hp > 0 else Color("6b2b2b")
	var size := Vector2(58.0, 84.0)
	draw_rect(Rect2(p - size * 0.5, size), Color(0.13, 0.11, 0.09, 0.85), true)
	draw_rect(Rect2(p - size * 0.5, size), col, false, 3.0)
	draw_line(p + Vector2(-12.0, -size.y * 0.5), p + Vector2(-12.0, size.y * 0.5), col, 2.0)
	_draw_centered("书", p, 26, col)

	# 立着的血条 + 数字
	var bar_w := 10.0
	var bar_h := 84.0
	var origin := p + Vector2(-46.0, -bar_h * 0.5)
	var ratio := clampf(float(base_hp) / float(maxi(base_max, 1)), 0.0, 1.0)
	draw_rect(Rect2(origin, Vector2(bar_w, bar_h)), Color(0, 0, 0, 0.6), true)
	draw_rect(Rect2(origin + Vector2(0.0, bar_h * (1.0 - ratio)), Vector2(bar_w, bar_h * ratio)),
		Color("a8c46a") if ratio > 0.4 else Color("d9573f"), true)
	draw_rect(Rect2(origin, Vector2(bar_w, bar_h)), Color(1, 1, 1, 0.25), false, 1.0)
	_draw_centered("%d" % base_hp, origin + Vector2(bar_w * 0.5, bar_h * 0.5), 13, UnitData.PAPER)


func _draw_pending_hint() -> void:
	# 预览就在光标位置，不吸附网格；放不了时在圈下写明原因
	var mouse := get_local_mouse_position()
	var err := placement_error(pending_tower, mouse)
	var ok := err.is_empty()
	var col := Color(0.95, 0.85, 0.5, 0.95) if ok else Color(0.85, 0.32, 0.26, 0.95)
	var stats := UnitData.tower_stats(pending_tower, 1, GS.tower_mult())
	draw_circle(mouse, 16.0, Color(col.r, col.g, col.b, 0.18))
	draw_arc(mouse, 16.0, 0.0, TAU, 24, col, 2.0, true)
	draw_arc(mouse, float(stats["range"]), 0.0, TAU, 48, Color(col.r, col.g, col.b, 0.22), 1.5, true)
	if not ok:
		_draw_centered(err, mouse + Vector2(0.0, 36.0), 13, col)


## 不限距离，找最近的格子（幽灵预览用）
func _nearest_cell_any(at: Vector2, kind: String) -> Variant:
	var list: Array = ground_cells if kind == "ground" else high_cells
	var best: Variant = null
	var best_d := INF
	for c in list:
		var d := (c as Vector2).distance_to(at)
		if d < best_d:
			best_d = d
			best = c
	return best


func _draw_tower(t: Tower) -> void:
	if t.is_dead():
		return
	var r := 17.0
	if t == selected:
		draw_arc(t.pos, t.atk_range, 0.0, TAU, 48, Color(0.95, 0.85, 0.5, 0.26), 2.0, true)
		draw_arc(t.pos, r + 6.0, 0.0, TAU, 24, Color(0.95, 0.85, 0.5, 0.9), 2.0, true)

	var body := t.color
	if t.flash > 0.0:
		body = body.lerp(Color.WHITE, 0.55)
	draw_circle(t.pos, r, Color(0.13, 0.11, 0.09, 0.9))
	draw_circle(t.pos, r - 2.5, body)
	_draw_centered(t.glyph, t.pos + Vector2(0.0, 1.0), 19, Color(0.13, 0.11, 0.09))

	# 等级点
	for i in range(t.level - 1):
		draw_circle(t.pos + Vector2(-6.0 + float(i) * 12.0, r + 7.0), 2.6, UnitData.PAPER)

	# 血条：常显
	var w := 36.0
	var topleft := t.pos + Vector2(-w * 0.5, -r - 11.0)
	var ratio := clampf(t.hp / t.max_hp, 0.0, 1.0)
	draw_rect(Rect2(topleft, Vector2(w, 4.5)), Color(0, 0, 0, 0.65), true)
	draw_rect(Rect2(topleft, Vector2(w * ratio, 4.5)),
		Color("a8c46a") if ratio > 0.35 else Color("d9573f"), true)

	# 阻挡格：剩余格数用小方块显示
	if t.block_capacity > 0:
		var free := t.block_capacity - t.engaged.size()
		for i in range(t.block_capacity):
			var c := Color("9fb8d8") if i < free else Color(0.35, 0.4, 0.5, 0.55)
			draw_rect(Rect2(t.pos + Vector2(-8.0 + float(i) * 6.0, r + 11.0), Vector2(4.0, 4.0)), c, true)

	if t == selected:
		_draw_centered("%d/%d" % [int(t.hp), int(t.max_hp)], t.pos + Vector2(0.0, -r - 20.0), 12, UnitData.PAPER)


func _draw_enemy(e: Enemy) -> void:
	if e.is_dead():
		return
	var col := e.color
	if e.flash > 0.0:
		col = col.lerp(Color.WHITE, 0.6)
	draw_circle(e.pos, e.radius + 3.0, Color(0.13, 0.11, 0.09, 0.85))
	draw_circle(e.pos, e.radius, col)
	_draw_centered(e.glyph, e.pos + Vector2(0.0, 1.0), int(e.radius * 1.15), Color(0.97, 0.95, 0.91))

	# 血条：常显
	var w := e.radius * 2.4
	var topleft := e.pos + Vector2(-w * 0.5, -e.radius - 10.0)
	var ratio := clampf(e.hp / e.max_hp, 0.0, 1.0)
	draw_rect(Rect2(topleft, Vector2(w, 4.0)), Color(0, 0, 0, 0.65), true)
	draw_rect(Rect2(topleft, Vector2(w * ratio, 4.0)),
		Color("e8a8c0") if not e.ranged else Color("9fb8d8"), true)

	# 护甲标记
	if e.armor > 0.0:
		draw_rect(Rect2(e.pos + Vector2(-e.radius, e.radius + 3.0), Vector2(5.0, 5.0)),
			Color(0.75, 0.78, 0.88), true)
		if e.armor >= 8.0:
			draw_rect(Rect2(e.pos + Vector2(-e.radius + 7.0, e.radius + 3.0), Vector2(5.0, 5.0)),
				Color(0.75, 0.78, 0.88), true)

	# 正在攻击友方时画一条连线提示
	if e.target != null:
		draw_line(e.pos, e.target.pos, Color(0.85, 0.35, 0.3, 0.45), 1.5, true)


func _draw_centered(text: String, center: Vector2, size: int, color: Color) -> void:
	if _font == null or text.is_empty():
		return
	var measured := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var pos := center + Vector2(-measured.x * 0.5, measured.y * 0.32)
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


# --- 输入 ---

func _unhandled_input(event: InputEvent) -> void:
	if not running or finished:
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		if pending_tower != "":
			pending_tower = ""
			stats_changed.emit()
			queue_redraw()
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if pending_tower != "":
		try_place(mb.position)
	else:
		select_tower_at(mb.position)
	get_viewport().set_input_as_handled()
