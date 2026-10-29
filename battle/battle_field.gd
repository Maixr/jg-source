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
signal progress_changed(killed: int, total: int)
signal new_enemy_seen(enemy_id: String)

const DESIGN := Vector2(1600.0, 900.0)
const PATH_WIDTH := 46.0
const INK_CAP := 99.0
## 移除分身时返还投入纸笔的比例（低于 1，避免放了又拆刷纸笔）
const REFUND_RATE := 0.6
const LEASH := 1.35

var level: Dictionary = {}
var level_index := 0

var towers: Array = []
var enemies: Array = []
var shots: Array = []
var floats: Array = []

var high_cells: Array = []
var ground_cells: Array = []
var routes: Array = []   # [{"label": String, "points": Array[Vector2]}]

var ink := 0.0
var base_hp := 0
var base_max := 0
var elapsed := 0.0
var insight_gained := 0.0
## 打怪进度：已消灭 / 本关总数
var kill_count := 0
## 本次结算是不是"首次通关"（决定要不要给体悟奖励）
var last_first_clear := false
var total_enemies := 0
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


## 把路线坐标对齐到格子网格。
## 注意：level_routes() 返回的是 const 字典（只读），不能就地改值，
## 所以这里重建一份新的路线数组。
func _quantize_routes() -> void:
	var step := UnitData.GRID_STEP
	var quantized: Array = []
	for route in routes:
		var def: Dictionary = route
		var pts: Array = def.get("points", [])
		var snapped: Array = []
		for p in pts:
			var v: Vector2 = p
			snapped.append(Vector2(roundf(v.x / step) * step, roundf(v.y / step) * step))
		quantized.append({"label": str(def.get("label", "")), "points": snapped})
	routes = quantized


func _build_high_cells() -> void:
	high_cells.clear()
	var step := UnitData.GRID_STEP
	var y := 0.0
	while y < DESIGN.y:
		var x := 0.0
		while x < DESIGN.x:
			var p := Vector2(x, y)
			# 只要贴着任意一条路线就算高台
			var d := _dist_to_routes(p)
			if d > UnitData.CELL_MIN_DIST and d <= UnitData.CELL_MAX_DIST:
				high_cells.append(p)
			x += step
		y += step


func _build_ground_cells() -> void:
	ground_cells.clear()
	var seen := {}
	var step := UnitData.GROUND_STEP
	for route in routes:
		var pts: Array = (route as Dictionary).get("points", [])
		var carry := 0.0
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var seg := a.distance_to(b)
			if seg <= 0.001:
				continue
			var dir := (b - a) / seg
			var t := carry
			while t < seg:
				var p := a + dir * t
				if p.x > 24.0 and p.x < DESIGN.x - 24.0 and p.y > UnitData.PLAY_TOP and p.y < UnitData.PLAY_BOTTOM:
					# 用格点坐标当 key：共享段产生的重复采样点会被合并
					var gkey := "%d,%d" % [int(round(p.x)), int(round(p.y))]
					if seen.has(gkey):
						t += step
						continue
					seen[gkey] = true
					ground_cells.append(p)
				t += step
			carry = t - seg


func _dist_to_routes(p: Vector2) -> float:
	var best := INF
	for route in routes:
		var pts: Array = (route as Dictionary).get("points", [])
		for i in range(pts.size() - 1):
			best = minf(best, _dist_point_segment(p, pts[i], pts[i + 1]))
	return best


## 方框距离（切比雪夫距离）：正方形范围下判断远近
func _box_dist(a: Vector2, b: Vector2) -> float:
	return maxf(absf(a.x - b.x), absf(a.y - b.y))


func _in_box(a: Vector2, b: Vector2, radius: float) -> bool:
	return absf(a.x - b.x) <= radius and absf(a.y - b.y) <= radius


func _box_rect(center: Vector2, radius: float) -> Rect2:
	return Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0)

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
	# 本关的路线（每关地图不同），并据此重建可放置格子
	routes = UnitData.level_routes(index)
	_quantize_routes()
	_build_cells()
	_spawns.clear()
	_spawn_cursor = 0
	kill_count = 0
	total_enemies = 0
	for wave in level.get("waves", []):
		var at := float(wave.get("at", 0.0))
		for group in wave.get("spawns", []):
			var count := int(group.get("count", 1))
			var gap := float(group.get("gap", 1.0))
			var route_index := int(group.get("route", 0))
			total_enemies += count
			for i in range(count):
				_spawns.append({
					"at": at + float(i) * gap,
					"type": str(group.get("type", "zao")),
					"route": route_index,
				})
	_spawns.sort_custom(func(a, b): return float(a["at"]) < float(b["at"]))
	stats_changed.emit()
	progress_changed.emit(kill_count, total_enemies)
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
	var kind := UnitData.tower_deploy(pending_tower)
	var cell: Variant = _snap_cell(at, kind)
	if cell == null:
		var hint := "地面分身要放在路上的金色踏脚处" if kind == "ground" else "高台分身要放在路旁的绿色格子上"
		_flash_text(at, hint, Color("d9573f"))
		return false
	var err := placement_error(pending_tower, cell)
	if not err.is_empty():
		_flash_text(cell, err, Color("d9573f"))
		return false
	if not _place_exact(pending_tower, cell):
		return false
	if ink < float(tower_cost(pending_tower)):
		pending_tower = ""
	stats_changed.emit()
	return true


## 把光标位置吸附到最近的同类格子上（那就是塔最终落点，保证和格子对齐）。
## 超出吸附半径返回 null，避免光标在远处时塔"飞"到别的格子上。
func _snap_cell(at: Vector2, kind: String) -> Variant:
	var list: Array = ground_cells if kind == "ground" else high_cells
	var best: Variant = null
	var best_d := UnitData.GRID_STEP * 0.85
	for c in list:
		var d := (c as Vector2).distance_to(at)
		if d < best_d:
			best_d = d
			best = c
	return best


## 这一格能不能放。返回空串 = 可以放；否则是给玩家看的原因。
func placement_error(tower_id: String, cell: Vector2) -> String:
	if _tower_at(cell) != null:
		return "这一格已经有分身了"
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
	t.invested = cost
	towers.append(t)
	ink -= float(cost)
	_flash_text(cell, "-%d 纸笔" % cost, UnitData.ORANGE)
	queue_redraw()
	return true


## 移除选中的分身，返还一部分投入的纸笔
func remove_selected() -> bool:
	if selected == null or not running or finished:
		return false
	return remove_tower(selected)


## 移除指定分身：返还投入的 REFUND_RATE，挡住的敌人会被放走
func remove_tower(tw: Tower) -> bool:
	if tw == null or not towers.has(tw):
		return false
	var refund := int(round(float(tw.invested) * REFUND_RATE))
	ink = minf(INK_CAP, ink + float(refund))
	# 它挡着的敌人失去目标，继续往前走
	for e in enemies:
		var en := e as Enemy
		if en.target == tw:
			en.target = null
	towers.erase(tw)
	if selected == tw:
		selected = null
		selection_changed.emit(null)
	_flash_text(tw.pos, "退还 %d 纸笔" % refund, UnitData.LEAF)
	stats_changed.emit()
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
	tw.invested += cost
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
		var ri := int(entry.get("route", 0))
		var pts: Array = []
		if ri >= 0 and ri < routes.size():
			pts = (routes[ri] as Dictionary).get("points", [])
		if pts.size() < 2:
			_spawn_cursor += 1
			continue
		e.setup(
			str(entry["type"]),
			pts,
			float(level.get("enemy_hp_mult", 1.0)),
			float(level.get("enemy_speed_mult", 1.0))
		)
		var eid := str(entry["type"])
		if not GS.seen_enemies.has(eid):
			GS.seen_enemies[eid] = true
			new_enemy_seen.emit(eid)
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
		var d := _box_dist(tw.pos, en.pos)
		if d < best_d:
			best_d = d
			best = tw
	return best


## 贴身距离：在这个范围内，近战友方能把远程敌人「卡住」不让它推进
const CONTACT_RANGE := 46.0


## 远程敌人索敌：射程内优先盾，其次阻挡者，最后高台单位。
## 和近战不同，它不会为了远处的盾放弃眼前的目标。
func _pick_ranged_target(en: Enemy) -> Tower:
	var shield: Tower = null
	var blocker: Tower = null
	var other: Tower = null
	var shield_d := INF
	var blocker_d := INF
	var other_d := INF
	for t in towers:
		var tw := t as Tower
		if tw.is_dead():
			continue
		if not _in_box(en.pos, tw.pos, en.attack_range):
			continue
		var d := _box_dist(en.pos, tw.pos)
		if tw.kind == "shield":
			if (tw.engaged.has(en) or tw.can_block()) and d < shield_d:
				shield_d = d
				shield = tw
		elif tw.block_capacity > 0:
			if (tw.engaged.has(en) or tw.can_block()) and d < blocker_d:
				blocker_d = d
				blocker = tw
		elif d < other_d:
			other_d = d
			other = tw
	if shield != null:
		return shield
	if blocker != null:
		return blocker
	return other


## 贴身的近战友方（能把远程敌人按住不让它往前挪）
func _contact_blocker(en: Enemy) -> Tower:
	for t in towers:
		var tw := t as Tower
		if tw.is_dead() or tw.block_capacity <= 0:
			continue
		if not tw.engaged.has(en) and not tw.can_block():
			continue
		if _box_dist(en.pos, tw.pos) <= CONTACT_RANGE:
			return tw
	return null


## 敌人索敌，分三档优先级：纸盾 > 其他阻挡者 > 高台单位。
## 每帧都会重新调用（见 _update_enemies），所以盾一进射程就能抢走仇恨。
func _pick_target(en: Enemy) -> Tower:
	# 远程敌人：谁在射程内打谁（盾优先），但不会为了追盾停下脚步
	if en.ranged:
		return _pick_ranged_target(en)

	# 近战：远处有盾就朝它走过去（路上不理会墨刃）
	var shield: Tower = _nearest_shield(en)
	if shield != null:
		if _in_box(en.pos, shield.pos, en.attack_range):
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
		var d := _box_dist(tw.pos, en.pos)
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
		var d := _box_dist(tw.pos, en.pos)
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
			# 远程单位：边打边往前挪一段，逼玩家不能只靠一个盾卡死
			# （被近战友方贴身挡住时挪不动）
			if en.ranged:
				if _contact_blocker(en) != null:
					en.advance_cd = en.advance_interval
					en.advance_left = 0.0
				else:
					en.advance_cd -= delta
					if en.advance_cd <= 0.0:
						en.advance_cd = en.advance_interval
						en.advance_left = en.advance_window
					if en.advance_left > 0.0:
						en.advance_left -= delta
						en.advance(delta)
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
					if _in_box(tw.pos, en.pos, tw.atk_range):
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
		var d := _box_dist(at, en.pos)
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
		if not _in_box(healer.pos, tw.pos, healer.atk_range):
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
				kill_count += 1
				progress_changed.emit(kill_count, total_enemies)
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
	last_first_clear = false
	if win:
		# 只有第一次通关才给体悟奖励；重复刷同一关只拿击杀收益
		var first_clear: bool = level_index >= int(GS.cleared_count)
		if first_clear:
			var bonus := 10.0 + float(level_index) * 5.0
			insight_gained += bonus
			GS.add_insight(bonus)
			last_first_clear = true
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
	var half := UnitData.GRID_STEP * 0.5 - 4.0
	for c in high_cells:
		var p: Vector2 = c
		var occupied := _tower_at(p) != null
		var rect := Rect2(p - Vector2(half, half), Vector2(half, half) * 2.0)
		draw_rect(rect, Color(0.66, 0.77, 0.42, 0.04 if occupied else 0.07), true)
		draw_rect(rect, Color(0.66, 0.77, 0.42, 0.10 if occupied else 0.20), false, 1.0)


## 两条路线共用同一段路时，只画一次。
## 否则半透明描边叠两遍会变深、拐角处还会鼓出一个包，看起来像贴图错乱。
func _seg_key(a: Vector2, b: Vector2) -> String:
	var ka := "%d,%d" % [int(round(a.x)), int(round(a.y))]
	var kb := "%d,%d" % [int(round(b.x)), int(round(b.y))]
	return (ka + "|" + kb) if ka <= kb else (kb + "|" + ka)


## 画一段轴对齐的路面（用矩形，不用 draw_line）。
## 矩形能精确控制宽度和端点，不会在接头处留下圆弧或缺口。
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
	# 用不透明色画，重叠段叠起来也不会变深；
	# 半透明会把共享段画成一条更黑的印子（就是之前看到的"贴图错乱"）。
	var bg := UnitData.BG
	var outer := bg.lerp(Color(0.66, 0.46, 0.25), 0.62)
	var inner := outer.lerp(Color(0.85, 0.78, 0.66), 0.45)
	var half := PATH_WIDTH * 0.5

	# 先收集所有不重复的线段和拐点
	var segs: Array = []
	var nodes := {}
	var drawn := {}
	for route in routes:
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

	# 第一层：路面底色
	for s in segs:
		_draw_road_rect(s[0], s[1], outer, half)
	# 拐点补块：把两条路面接头的缺口填满
	for k in nodes:
		var p: Vector2 = nodes[k]
		draw_rect(Rect2(p - Vector2(half, half), Vector2(half, half) * 2.0), outer, true)

	# 第二层：路面中间亮一点的那条
	var half_in := half * 0.42
	for s in segs:
		_draw_road_rect(s[0], s[1], inner, half_in)
	for k in nodes:
		var p: Vector2 = nodes[k]
		draw_rect(Rect2(p - Vector2(half_in, half_in), Vector2(half_in, half_in) * 2.0), inner, true)


## 地面格：路线上的落脚点，可以站人挡路
func _draw_ground_cells() -> void:
	var half := UnitData.GRID_STEP * 0.5 - 4.0
	for c in ground_cells:
		var p: Vector2 = c
		var occupied := _tower_at(p) != null
		var rect := Rect2(p - Vector2(half, half), Vector2(half, half) * 2.0)
		# 路面格必须一眼看得出来：先压一层暗底和路面区分，再描一道亮金边
		draw_rect(rect, Color(0.10, 0.08, 0.06, 0.10 if occupied else 0.22), true)
		draw_rect(rect, Color(0.96, 0.86, 0.62, 0.35 if occupied else 0.85), false, 2.0)


## 每条路线尽头画一本「书」，就是敌人要逃进去的出口
func _draw_base() -> void:
	for route in routes:
		var pts: Array = (route as Dictionary).get("points", [])
		if pts.is_empty():
			continue
		var raw: Vector2 = pts[pts.size() - 1]
		var p := Vector2(clampf(raw.x, 60.0, DESIGN.x - 60.0), clampf(raw.y, UnitData.PLAY_TOP + 50.0, UnitData.PLAY_BOTTOM - 50.0))
		_draw_book(p)

	# 总血量条：画在右上角出口上方，避免和多个出口重叠
	var bar_w := 12.0
	var bar_h := 96.0
	var origin := Vector2(DESIGN.x - 36.0, UnitData.PLAY_TOP + 16.0)
	var ratio := clampf(float(base_hp) / float(maxi(base_max, 1)), 0.0, 1.0)
	draw_rect(Rect2(origin, Vector2(bar_w, bar_h)), Color(0, 0, 0, 0.6), true)
	draw_rect(Rect2(origin + Vector2(0.0, bar_h * (1.0 - ratio)), Vector2(bar_w, bar_h * ratio)),
		Color("a8c46a") if ratio > 0.4 else Color("d9573f"), true)
	draw_rect(Rect2(origin, Vector2(bar_w, bar_h)), Color(1, 1, 1, 0.25), false, 1.0)
	_draw_centered("%d" % base_hp, origin + Vector2(bar_w * 0.5, bar_h * 0.5), 13, UnitData.PAPER)


func _draw_book(p: Vector2) -> void:
	var col := Color("c9a227") if base_hp > 0 else Color("6b2b2b")
	var size := Vector2(58.0, 84.0)
	draw_rect(Rect2(p - size * 0.5, size), Color(0.13, 0.11, 0.09, 0.85), true)
	draw_rect(Rect2(p - size * 0.5, size), col, false, 3.0)
	draw_line(p + Vector2(-12.0, -size.y * 0.5), p + Vector2(-12.0, size.y * 0.5), col, 2.0)
	_draw_centered("书", p, 26, col)


func _draw_pending_hint() -> void:
	# 预览画在「吸附到的格子」上，和最终落点完全一致，这样不会出现视觉偏移。
	# 格子会被高亮成一个方框，圈住的就是塔将占据的位置。
	var kind := UnitData.tower_deploy(pending_tower)
	var mouse := get_local_mouse_position()
	var cell: Variant = _snap_cell(mouse, kind)
	var anchor: Vector2 = mouse if cell == null else cell
	var err := ""
	if cell == null:
		err = "靠近格子才能放"
	else:
		err = placement_error(pending_tower, anchor)
	var ok := err.is_empty()
	var col := Color(0.95, 0.85, 0.5, 0.95) if ok else Color(0.85, 0.32, 0.26, 0.95)

	if cell != null:
		# 高亮整格：框内就是塔的实际占地
		var half := UnitData.GRID_STEP * 0.5 - 4.0
		draw_rect(Rect2(anchor - Vector2(half, half), Vector2(half, half) * 2.0),
			Color(col.r, col.g, col.b, 0.16), true)
		draw_rect(Rect2(anchor - Vector2(half, half), Vector2(half, half) * 2.0),
			col, false, 2.0)

	var stats := UnitData.tower_stats(pending_tower, 1, GS.tower_mult())
	draw_circle(anchor, 11.0, Color(col.r, col.g, col.b, 0.22))
	draw_arc(anchor, 11.0, 0.0, TAU, 24, col, 2.0, true)
	draw_rect(_box_rect(anchor, float(stats["range"])), Color(col.r, col.g, col.b, 0.08), true)
	draw_rect(_box_rect(anchor, float(stats["range"])), Color(col.r, col.g, col.b, 0.42), false, 1.5)
	if not ok:
		_draw_centered(err, anchor + Vector2(0.0, 38.0), 13, col)


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
		draw_rect(_box_rect(t.pos, t.atk_range), Color(0.95, 0.85, 0.5, 0.08), true)
		draw_rect(_box_rect(t.pos, t.atk_range), Color(0.95, 0.85, 0.5, 0.45), false, 2.0)
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
