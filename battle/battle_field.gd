class_name BattleField
extends Node2D

## 塔防战场。
## 部署规则（明日方舟式）：
##   地面格 = 路线上的落脚点，只能放 墨刃 / 纸盾，会真正挡在敌人面前
##   高台格 = 路旁，只能放 墨矢 / 疗愈符
## 敌人会主动索敌并攻击友方，优先攻击「纸盾」；护甲减免每次伤害。
##
## 时间模型：所有逻辑都跑在固定的 UnitData.FIXED_DT 步长上，
## 用累加器把帧 delta 攒成整数个逻辑步。这样帧率、倍速、无头自检
## 三种情况算出来的战斗结果完全一致。

signal stats_changed()
signal selection_changed(tower: Tower)
signal battle_finished(win: bool, insight_gained: float)
signal progress_changed(killed: int, total: int)
signal new_enemy_seen(enemy_id: String)

const PATH_WIDTH := 46.0
const INK_CAP := 99.0
## 移除分身时返还投入纸笔的比例（低于 1，避免放了又拆刷纸笔）
const REFUND_RATE := 0.6
const SHIELD_AGGRO := 170.0
## 贴身距离：在这个范围内，近战友方能把远程敌人「卡住」不让它推进
const CONTACT_RANGE := 46.0

## 单帧最多补几步逻辑，防止卡顿后长时间追帧
const MAX_STEPS_PER_FRAME := 8

var level: Dictionary = {}
var level_index := 0

var towers: Array = []
var enemies: Array = []
## 投射物：{from, to, t, dur, color}
var shots: Array = []
## 飘字：{pos, text, color, life}
var floats: Array = []
## 墨点飞溅（敌人被击杀 / 分身消散）：{pos, r, life, max_life, color}
var splats: Array = []
## 交互/反馈粒子：环、纸屑、火花
## {kind, pos, t, dur, color, ...}，kind = ring / shard / spark
var fx: Array = []

var high_cells: Array = []
var ground_cells: Array = []
var routes: Array = []
## 散落的文具：占住高台格，不能在那里放分身。
## props 用来画，prop_cells 参与吸附（这样玩家点上去会看到"这里散落着文具"）
var props: Array = []
var prop_cells: Array = []

var ink := 0.0
var base_hp := 0
var base_max := 0
var elapsed := 0.0
var insight_gained := 0.0
var kill_count := 0
var last_first_clear := false
var total_enemies := 0
var running := false
var finished := false
var speed_scale := 1.0

var pending_tower := ""
var selected: Tower = null

var _spawns: Array = []
var _spawn_cursor := 0
var _last_wave := -1
var _ink_rate := 1.0
var _font: Font
var _accum := 0.0

## 格子占用索引：坐标 -> Tower。绘制和放置都靠它做 O(1) 查询，
## 不再每次都遍历整个 towers 数组。
var _cell_index := {}
## 被文具占住的格子：坐标 -> 文具种类
var _prop_cells := {}
## 按类别缓存的塔列表，供索敌使用（每逻辑步刷新一次）
var _shields: Array = []
var _blockers: Array = []
var _others: Array = []

var _backdrop: BattleBackdrop = null
var _vignette: ImageTexture = null
var _shake := 0.0
var _book_flash := 0.0

## 平衡模拟时关掉音效，免得一口气放几百个声音
var audio_enabled := true

@onready var GS: Node = get_node_or_null("/root/GameState")
@onready var AU: Node = get_node_or_null("/root/Audio")


func _ready() -> void:
	_font = UnitData.font_sans()
	_vignette = _make_vignette()
	_backdrop = BattleBackdrop.new()
	_backdrop.name = "Backdrop"
	# 父节点先画、子节点后画；静态层要垫在战场下面，所以用负 z_index
	_backdrop.z_index = -1
	_backdrop.setup(self)
	add_child(_backdrop)
	if GS != null:
		GS.upgrades_changed.connect(_on_upgrades_changed)
	set_process(true)


func design_size() -> Vector2:
	return UnitData.DESIGN_SIZE


func _make_vignette() -> ImageTexture:
	var n := 96
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (float(x) / float(n - 1)) * 2.0 - 1.0
			var v := (float(y) / float(n - 1)) * 2.0 - 1.0
			var d := clampf(sqrt(u * u + v * v) / 1.42, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.0, 0.0, 0.0, pow(d, 2.4) * 0.40))
	return ImageTexture.create_from_image(img)


func _sfx(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not audio_enabled or AU == null:
		return
	AU.play(name, volume_db, pitch)


func _sfx_var(name: String, volume_db: float = 0.0, spread: float = 0.05) -> void:
	if not audio_enabled or AU == null:
		return
	AU.play_var(name, volume_db, spread)


## 书屋里点了「分身强化」之后，把新倍率套到所有已经放好的分身上
func _on_upgrades_changed() -> void:
	var mult: float = GS.tower_mult()
	for t in towers:
		(t as Tower).reapply_mult(mult)
	if not towers.is_empty():
		_flash_text((towers[0] as Tower).pos + Vector2(0.0, -34.0),
			"分身 +%d%%" % GS.tower_bonus_percent(), UnitData.LEAF)
	stats_changed.emit()
	_refresh_backdrop()
	queue_redraw()


## 养成里买纸笔：立刻加进当前这一关（一次性，本关结束就没了）
func add_ink(amount: float) -> void:
	if amount <= 0.0:
		return
	ink = minf(INK_CAP, ink + amount)
	_flash_text(Vector2(UnitData.DESIGN_SIZE.x * 0.5, 96.0), "+%d 纸笔" % int(amount), UnitData.ORANGE)
	stats_changed.emit()
	queue_redraw()


# --- 格子 ---

func _build_cells() -> void:
	_build_high_cells()
	_build_ground_cells()


## 把路线坐标对齐到格子网格。
## level_routes() 返回的是 const 字典（只读），不能就地改值，所以要重建一份。
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
	while y < UnitData.DESIGN_SIZE.y:
		var x := 0.0
		while x < UnitData.DESIGN_SIZE.x:
			var p := Vector2(x, y)
			# 必须落在「看得见也点得到」的区域里：顶部标题栏、底部操作栏、
			# 右侧养成手柄都会吞掉鼠标事件，那些格子玩家根本放不上去。
			if p.x > 24.0 and p.x < UnitData.DESIGN_SIZE.x - 60.0 \
					and p.y > UnitData.PLAY_TOP and p.y < UnitData.PLAY_BOTTOM:
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
				if p.x > 24.0 and p.x < UnitData.DESIGN_SIZE.x - 24.0 \
						and p.y > UnitData.PLAY_TOP and p.y < UnitData.PLAY_BOTTOM:
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


## 把每关「散落的文具」解析成具体格子：从可放置列表里拿走，记进 _prop_cells。
func _build_props() -> void:
	props.clear()
	prop_cells.clear()
	_prop_cells.clear()
	for spec in UnitData.level_clutter(level_index):
		var route_i := int(spec.get("route", 0))
		if route_i < 0 or route_i >= routes.size():
			continue
		var pts: Array = (routes[route_i] as Dictionary).get("points", [])
		if pts.size() < 2:
			continue
		var total := 0.0
		var seglens: Array = []
		for i in range(pts.size() - 1):
			var seg_len: float = (pts[i] as Vector2).distance_to(pts[i + 1])
			seglens.append(seg_len)
			total += seg_len
		if total <= 1.0:
			continue
		var target := total * float(spec.get("frac", 0.5))
		var acc := 0.0
		var anchor: Vector2 = pts[0]
		var dir := Vector2.RIGHT
		for i in range(seglens.size()):
			var seg_len2: float = seglens[i]
			if acc + seg_len2 >= target:
				var k := (target - acc) / seg_len2
				anchor = (pts[i] as Vector2).lerp(pts[i + 1], k)
				var d := (pts[i + 1] as Vector2) - (pts[i] as Vector2)
				if d.length_squared() > 0.0001:
					dir = d.normalized()
				break
			acc += seg_len2
		var side := 1.0 if float(spec.get("side", 1)) >= 0.0 else -1.0
		var normal := Vector2(-dir.y, dir.x) * side
		var want := anchor + normal * float(spec.get("off", 100.0))
		var cell: Variant = _nearest_cell_in(want, high_cells, 130.0)
		if cell == null:
			continue
		var key := _cell_key(cell)
		if _prop_cells.has(key):
			continue
		high_cells.erase(cell)
		prop_cells.append(cell)
		_prop_cells[key] = str(spec.get("kind", "pencil"))
		props.append({"kind": str(spec.get("kind", "pencil")), "pos": cell})


func _nearest_cell_in(at: Vector2, list: Array, max_d: float) -> Variant:
	var best: Variant = null
	var best_d := max_d
	for c in list:
		var d := (c as Vector2).distance_to(at)
		if d < best_d:
			best_d = d
			best = c
	return best


func prop_kind_at(cell: Vector2) -> String:
	return str(_prop_cells.get(_cell_key(cell), ""))


func _dist_point_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq <= 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## 方框距离（切比雪夫距离）：正方形范围下判断远近
func _box_dist(a: Vector2, b: Vector2) -> float:
	return maxf(absf(a.x - b.x), absf(a.y - b.y))


func _in_box(a: Vector2, b: Vector2, radius: float) -> bool:
	return absf(a.x - b.x) <= radius and absf(a.y - b.y) <= radius


func _box_rect(center: Vector2, radius: float) -> Rect2:
	return Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0)


# --- 生命周期 ---

func start_level(index: int) -> void:
	level_index = index
	level = UnitData.BASE_DATA["levels"][index]
	towers.clear()
	enemies.clear()
	shots.clear()
	floats.clear()
	splats.clear()
	fx.clear()
	selected = null
	pending_tower = ""
	elapsed = 0.0
	insight_gained = 0.0
	finished = false
	running = true
	speed_scale = 1.0
	_accum = 0.0
	_shake = 0.0
	_book_flash = 0.0
	_last_wave = -1
	position = Vector2.ZERO
	base_max = int(level.get("base_hp", 12))
	base_hp = base_max
	ink = float(level.get("start_ink", 20))
	_ink_rate = UnitData.INK_REGEN * float(level.get("ink_mult", 1.0)) * GS.ink_mult()
	routes = UnitData.level_routes(index)
	_quantize_routes()
	_build_cells()
	_build_props()
	_spawns.clear()
	_spawn_cursor = 0
	kill_count = 0
	total_enemies = 0
	_reindex_towers()
	var waves: Array = level.get("waves", [])
	for wi in range(waves.size()):
		var wave: Dictionary = waves[wi]
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
					"wave": wi,
				})
	_spawns.sort_custom(func(a, b): return float(a["at"]) < float(b["at"]))
	# 书屋的「开局准备」：只推迟第一波，给玩家更多布阵时间。
	# 推迟所有波次会让节奏整体变拖，就没意义了。
	var prep: float = GS.prep_time()
	if prep > 0.0 and not _spawns.is_empty():
		var first_wave: int = int((_spawns[0] as Dictionary).get("wave", 0))
		for it in _spawns:
			if int((it as Dictionary).get("wave", -1)) == first_wave:
				it["at"] = float(it["at"]) + prep
		_spawns.sort_custom(func(a, b): return float(a["at"]) < float(b["at"]))
	stats_changed.emit()
	progress_changed.emit(kill_count, total_enemies)
	selection_changed.emit(null)
	_refresh_backdrop()
	queue_redraw()


func stop_battle() -> void:
	running = false


# --- 索引 / 缓存 ---

func _cell_key(p: Vector2) -> String:
	return "%d,%d" % [int(round(p.x)), int(round(p.y))]


func _reindex_towers() -> void:
	_cell_index.clear()
	for t in towers:
		var tw := t as Tower
		_cell_index[_cell_key(tw.pos)] = tw


func cell_occupied(p: Vector2) -> bool:
	return _cell_index.has(_cell_key(p))


func _refresh_backdrop() -> void:
	if _backdrop != null:
		_backdrop.refresh()


## 每逻辑步刷一次分类列表：索敌从「遍历全部塔 3 次」变成「遍历分类列表 1 次」
func _refresh_buckets() -> void:
	_shields.clear()
	_blockers.clear()
	_others.clear()
	for t in towers:
		var tw := t as Tower
		if tw.is_dead():
			continue
		if tw.kind == "shield":
			_shields.append(tw)
		elif tw.block_capacity > 0:
			_blockers.append(tw)
		else:
			_others.append(tw)


# --- 部署 ---

func set_pending(tower_id: String) -> void:
	pending_tower = tower_id if pending_tower != tower_id else ""
	selected = null
	selection_changed.emit(null)
	stats_changed.emit()
	# 静态层要跟着显示/隐藏「可放置格」高亮
	_refresh_backdrop()
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
		_refresh_backdrop()
	stats_changed.emit()
	return true


## 把光标位置吸附到最近的同类格子上
func _snap_cell(at: Vector2, kind: String) -> Variant:
	var best_d := UnitData.GRID_STEP * 0.85
	if kind == "ground":
		return _nearest_cell_in(at, ground_cells, best_d)
	# 高台要连「被文具占住的格子」一起参与吸附：
	# 否则光标压在铅笔上时，塔会被甩到更远的那一格，玩家会觉得是 bug
	var a: Variant = _nearest_cell_in(at, high_cells, best_d)
	var b: Variant = _nearest_cell_in(at, prop_cells, best_d)
	if a == null:
		return b
	if b == null:
		return a
	return a if (a as Vector2).distance_to(at) <= (b as Vector2).distance_to(at) else b


## 这一格能不能放。返回空串 = 可以放；否则是给玩家看的原因。
func placement_error(tower_id: String, cell: Vector2) -> String:
	if not prop_kind_at(cell).is_empty():
		return "这里有散落的文具，放不下"
	if cell_occupied(cell):
		return "这一格已经有分身了"
	if ink < float(tower_cost(tower_id)):
		return "纸笔不够"
	return ""


func _place_exact(tower_id: String, cell: Vector2) -> bool:
	if cell_occupied(cell):
		return false
	var cost := tower_cost(tower_id)
	if ink < float(cost):
		return false
	var t := Tower.new()
	t.setup(tower_id, cell, GS.tower_mult())
	t.invested = cost
	towers.append(t)
	_cell_index[_cell_key(cell)] = t
	ink -= float(cost)
	_flash_text(cell, "-%d 纸笔" % cost, UnitData.ORANGE)
	_sfx("place", -6)
	_fx_ring(cell, UnitData.ORANGE, 44.0)
	_fx_sparks(cell, UnitData.PAPER, 5)
	_refresh_backdrop()
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
	for e in enemies:
		var en := e as Enemy
		if en.target == tw:
			en.target = null
	towers.erase(tw)
	_cell_index.erase(_cell_key(tw.pos))
	if selected == tw:
		selected = null
		selection_changed.emit(null)
	_flash_text(tw.pos, "退还 %d 纸笔" % refund, UnitData.LEAF)
	_sfx("remove", -8)
	_fx_shards(tw.pos, UnitData.PAPER, 8)
	stats_changed.emit()
	_refresh_backdrop()
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
	# 等级上限来自书屋：数据里写了 5 级，没解锁就只能到 3 级
	if tw.level >= GS.tower_level_cap():
		return false
	var cost := UnitData.tower_upgrade_cost(tw.id, tw.level + 1)
	if cost < 0 or ink < float(cost):
		return false
	if not tw.upgrade(GS.tower_mult()):
		return false
	ink -= float(cost)
	tw.invested += cost
	_flash_text(tw.pos, "升到 %d 级" % tw.level, UnitData.LEAF)
	_sfx("upgrade", -4)
	_fx_ring(tw.pos, UnitData.LEAF, 54.0)
	_fx_sparks(tw.pos, UnitData.PAPER, 8)
	stats_changed.emit()
	queue_redraw()
	return true


## 模拟器用：把纸笔花在最便宜的可升级分身身上
func _auto_upgrade_once() -> bool:
	var best: Tower = null
	var best_cost := 1 << 30
	for t in towers:
		var tw := t as Tower
		if tw.level >= GS.tower_level_cap():
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


## 找离锚点最近的空闲格子（模拟器/调试用，不限距离）
func _nearest_free_cell(at: Vector2, kind: String) -> Variant:
	var list: Array = ground_cells if kind == "ground" else high_cells
	var best: Variant = null
	var best_d := INF
	for c in list:
		var p: Vector2 = c
		if cell_occupied(p):
			continue
		var d := p.distance_to(at)
		if d < best_d:
			best_d = d
			best = p
	return best


# --- 主循环 ---

func _process(delta: float) -> void:
	if not running or finished:
		return
	# 把帧 delta 攒成整数个逻辑步；倍速作用在「要模拟多少时间」上
	_accum += minf(delta, UnitData.MAX_DELTA) * speed_scale
	var steps := 0
	while _accum >= UnitData.FIXED_DT and steps < MAX_STEPS_PER_FRAME:
		_step(UnitData.FIXED_DT)
		_accum -= UnitData.FIXED_DT
		steps += 1
		if finished:
			return
	# 落后太多（比如刚从暂停恢复）就把余量丢掉，宁可慢一点也不追帧
	if _accum > UnitData.FIXED_DT * float(MAX_STEPS_PER_FRAME):
		_accum = 0.0
	queue_redraw()


func _step(delta: float) -> void:
	elapsed += delta
	ink = minf(INK_CAP, ink + _ink_rate * delta)
	_refresh_buckets()
	_spawn_due()
	_update_enemies(delta)
	_update_towers(delta)
	_update_effects(delta)
	_cleanup()
	_check_end()


func _spawn_due() -> void:
	while _spawn_cursor < _spawns.size():
		var entry: Dictionary = _spawns[_spawn_cursor]
		if float(entry["at"]) > elapsed:
			break
		var wi := int(entry.get("wave", 0))
		if wi != _last_wave:
			_last_wave = wi
			if wi > 0:
				_sfx("wave", -10)
		var e := Enemy.new()
		var ri := int(entry.get("route", 0))
		var pts: Array = []
		if ri >= 0 and ri < routes.size():
			pts = (routes[ri] as Dictionary).get("points", [])
		if pts.size() < 2:
			_spawn_cursor += 1
			continue
		var eid := str(entry["type"])
		e.setup(eid, pts,
			float(level.get("enemy_hp_mult", 1.0)),
			float(level.get("enemy_speed_mult", 1.0)))
		if not GS.seen_enemies.has(eid):
			GS.seen_enemies[eid] = true
			new_enemy_seen.emit(eid)
		if eid == "hui":
			_sfx("boss", -4)
			_shake = maxf(_shake, 4.0)
		enemies.append(e)
		_spawn_cursor += 1


## 远程敌人索敌：射程内优先盾，其次阻挡者，最后高台单位。
func _pick_ranged_target(en: Enemy) -> Tower:
	var shield: Tower = null
	var blocker: Tower = null
	var other: Tower = null
	var shield_d := INF
	var blocker_d := INF
	var other_d := INF
	for tw in _shields:
		if not _in_box(en.pos, tw.pos, en.attack_range):
			continue
		if not tw.engaged.has(en) and not tw.can_block():
			continue
		var d := _box_dist(en.pos, tw.pos)
		if d < shield_d:
			shield_d = d
			shield = tw
	for tw in _blockers:
		if not _in_box(en.pos, tw.pos, en.attack_range):
			continue
		if not tw.engaged.has(en) and not tw.can_block():
			continue
		var d := _box_dist(en.pos, tw.pos)
		if d < blocker_d:
			blocker_d = d
			blocker = tw
	for tw in _others:
		if not _in_box(en.pos, tw.pos, en.attack_range):
			continue
		var d := _box_dist(en.pos, tw.pos)
		if d < other_d:
			other_d = d
			other = tw
	if shield != null:
		return shield
	if blocker != null:
		return blocker
	return other


## 贴身的近战友方（能把远程敌人按住不让它往前挪）
func _contact_blocker(en: Enemy) -> Tower:
	for tw in _shields:
		if tw.engaged.has(en) or tw.can_block():
			if _box_dist(en.pos, tw.pos) <= CONTACT_RANGE:
				return tw
	for tw in _blockers:
		if tw.engaged.has(en) or tw.can_block():
			if _box_dist(en.pos, tw.pos) <= CONTACT_RANGE:
				return tw
	return null


## 目标是不是还在自己前方（沿当前路段朝向判断）。
## 不加这个判断的话，敌人从盾身边过去之后还会被"吸"回去。
func _is_ahead(en: Enemy, p: Vector2) -> bool:
	var to := p - en.pos
	if to.length_squared() < 0.0001:
		return false
	return en.dir().dot(to.normalized()) > 0.15


## 挡满了、但确实横在路上的分身。
##
## 之前的表现：纸盾挡满 3 个之后，第 4 个敌人索敌失败就直接 advance()，
## 于是从盾身上"穿"过去 —— 看起来就是穿模 bug。
## 现在的规则是「挡不进去就排队」：贴着它停下等，等盾里的人被打死再顶上去。
func _jam_blocker(en: Enemy) -> Tower:
	for tw in _shields:
		if tw.is_dead() or tw.engaged.has(en) or tw.can_block():
			continue
		if _box_dist(en.pos, tw.pos) > CONTACT_RANGE:
			continue
		if _is_ahead(en, tw.pos):
			return tw
	for tw in _blockers:
		if tw.is_dead() or tw.engaged.has(en) or tw.can_block():
			continue
		if _box_dist(en.pos, tw.pos) > CONTACT_RANGE:
			continue
		if _is_ahead(en, tw.pos):
			return tw
	return null


## 敌人索敌，分三档优先级：纸盾 > 其他阻挡者 > 高台单位。
## 每步都重新算，所以盾一进射程就能抢走仇恨。
func _pick_target(en: Enemy) -> Tower:
	if en.ranged:
		return _pick_ranged_target(en)

	# 近战：170 像素内有还能挡人的盾，就朝它走过去（路上不理会墨刃）
	var shield: Tower = null
	var best_d := SHIELD_AGGRO
	for tw in _shields:
		if not tw.engaged.has(en) and not tw.can_block():
			continue
		var d := _box_dist(tw.pos, en.pos)
		if d < best_d:
			best_d = d
			shield = tw
	if shield != null:
		return shield if _in_box(en.pos, shield.pos, en.attack_range) else null

	# 第二档：墨刃之类的其他阻挡者
	var blocker: Tower = null
	var bd := INF
	for tw in _blockers:
		if not tw.engaged.has(en) and not tw.can_block():
			continue
		var d := _box_dist(tw.pos, en.pos)
		if d <= en.attack_range and d < bd:
			bd = d
			blocker = tw
	if blocker != null:
		return blocker

	# 第三档：高台单位（墨矢 / 疗愈符）
	var other: Tower = null
	var od := INF
	for tw in _others:
		var d := _box_dist(tw.pos, en.pos)
		if d <= en.attack_range and d < od:
			od = d
			other = tw
	return other


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
		en.cooldown -= delta

		var picked := _pick_target(en)
		if picked != en.target:
			_detach(en)
			en.target = picked
			if en.target != null:
				en.target.engaged.append(en)

		if en.target != null:
			if en.cooldown <= 0.0:
				# 冷却用「加」不用「等」：把多出来的时间留到下一次，
				# 否则高帧率下每秒会多打一点，帧率就成了隐藏的难度系数。
				en.cooldown += en.interval
				if en.cooldown < 0.0:
					en.cooldown = 0.0
				en.target.take_damage(en.atk)
				_sfx_var("enemy_attack", -12)
				shots.append({"from": en.pos, "to": en.target.pos, "t": 0.0, "dur": 0.16,
					"color": Color("d9573f") if not en.ranged else en.color})
			# 远程单位：边打边往前挪一段，逼玩家不能只靠一个盾卡死
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

		# 没目标时不让冷却一路跌成负数，否则一进射程会连打好几下
		if en.cooldown < 0.0:
			en.cooldown = 0.0
		# 前面横着一个已经挡满了的分身 → 排队等着，不许从它身上走过去
		if _jam_blocker(en) != null:
			continue
		en.advance(delta)


func _update_towers(delta: float) -> void:
	for t in towers:
		var tw := t as Tower
		tw.flash = maxf(0.0, tw.flash - delta)
		if tw.is_dead():
			continue
		if tw.cooldown > 0.0:
			tw.cooldown -= delta
			if tw.cooldown > 0.0:
				continue
		# 冷却到点（或本来就没冷却）
		match tw.kind:
			"ranged":
				var target := _enemy_in_range(tw.pos, tw.atk_range)
				if target != null:
					tw.cooldown += tw.interval
					if tw.cooldown < 0.0:
						tw.cooldown = 0.0
					target.take_damage(maxf(1.0, tw.atk - target.armor))
					_sfx_var("fire", -9)
					shots.append({"from": tw.pos, "to": target.pos, "t": 0.0, "dur": 0.14,
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
					tw.cooldown += tw.interval
					if tw.cooldown < 0.0:
						tw.cooldown = 0.0
					tw.flash = 0.14
					_sfx_var("swing", -8)
			"heal":
				var patient := _hurt_ally(tw)
				if patient != null:
					tw.cooldown += tw.interval
					if tw.cooldown < 0.0:
						tw.cooldown = 0.0
					patient.hp = minf(patient.max_hp, patient.hp + tw.atk)
					_sfx("heal", -18)
					shots.append({"from": tw.pos, "to": patient.pos, "t": 0.0, "dur": 0.22,
						"color": tw.color})
		if tw.cooldown < 0.0:
			tw.cooldown = 0.0


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


func _update_effects(delta: float) -> void:
	for s in shots:
		s["t"] = float(s["t"]) + delta
	shots = shots.filter(func(s): return float(s["t"]) < float(s["dur"]))

	for f in floats:
		f["life"] = float(f["life"]) - delta
		f["pos"] = (f["pos"] as Vector2) + Vector2(0.0, -26.0 * delta)
	floats = floats.filter(func(f): return float(f["life"]) > 0.0)

	for sp in splats:
		sp["life"] = float(sp["life"]) - delta
	splats = splats.filter(func(sp): return float(sp["life"]) > 0.0)

	for f in fx:
		f["t"] = float(f["t"]) + delta
		var kind := str(f["kind"])
		if kind == "shard":
			f["pos"] = (f["pos"] as Vector2) + (f["vel"] as Vector2) * delta
			f["vel"] = (f["vel"] as Vector2) + Vector2(0.0, 900.0) * delta
			f["rot"] = float(f["rot"]) + float(f["spin"]) * delta
		elif kind == "spark":
			f["pos"] = (f["pos"] as Vector2) + (f["vel"] as Vector2) * delta
			f["vel"] = (f["vel"] as Vector2) + Vector2(0.0, 260.0) * delta
	fx = fx.filter(func(f): return float(f["t"]) < float(f["dur"]))

	_book_flash = maxf(0.0, _book_flash - delta * 2.4)
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 14.0)
		var t := Time.get_ticks_msec() / 1000.0
		position = Vector2(sin(t * 61.0), cos(t * 47.0)) * _shake
	elif position != Vector2.ZERO:
		position = Vector2.ZERO


func _cleanup() -> void:
	var survivors: Array = []
	for e in enemies:
		var en := e as Enemy
		if en.is_dead():
			if en.escaped:
				base_hp -= en.leak
				_book_flash = 1.0
				_shake = maxf(_shake, 6.0)
				_sfx("leak", -2)
				_fx_ring(en.pos, Color("d9573f"), 62.0, 0.55)
				_flash_text(en.pos, "-%d 剧情" % en.leak, Color("d9573f"))
			else:
				kill_count += 1
				progress_changed.emit(kill_count, total_enemies)
				insight_gained += float(en.insight_reward)
				GS.add_insight(float(en.insight_reward))
				_sfx_var("die", -12, 0.08)
				_splat(en.pos, en.color, en.radius)
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
			_cell_index.erase(_cell_key(tw.pos))
			_splat(tw.pos, tw.color, 20.0)
			_sfx("remove", -10)
			for e2 in enemies:
				if (e2 as Enemy).target == tw:
					(e2 as Enemy).target = null
			if selected == tw:
				selected = null
				selection_changed.emit(null)
			continue
		standing.append(tw)
	if standing.size() != towers.size():
		towers = standing
		_refresh_backdrop()


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
		_sfx("win", -2)
	else:
		_sfx("lose", -2)
	stats_changed.emit()
	battle_finished.emit(win, insight_gained)
	queue_redraw()


func _flash_text(pos: Vector2, text: String, color: Color) -> void:
	floats.append({"pos": pos, "text": text, "color": color, "life": 0.9})


func _splat(pos: Vector2, color: Color, radius: float) -> void:
	for i in 5:
		var a := TAU * float(i) / 5.0 + float(i) * 0.7
		var off := Vector2(cos(a), sin(a)) * radius * (0.35 + 0.12 * float(i % 3))
		splats.append({
			"pos": pos + off,
			"r": radius * (0.16 + 0.05 * float(i % 3)),
			"life": 0.30 + 0.05 * float(i % 3),
			"max_life": 0.30 + 0.05 * float(i % 3),
			"color": color,
		})


# --- 交互粒子 ---

## 一圈扩散的环：放置/升级/漏字都靠它给"这一下发生了"的确认感
func _fx_ring(pos: Vector2, color: Color, r1: float, dur: float = 0.42) -> void:
	fx.append({"kind": "ring", "pos": pos, "t": 0.0, "dur": dur,
		"r0": 6.0, "r1": r1, "color": color})


## 纸屑：移除分身时飞出去的碎纸片（带旋转和重力）
func _fx_shards(pos: Vector2, color: Color, n: int = 7) -> void:
	for i in n:
		var a := randf_range(-PI, 0.0)
		fx.append({
			"kind": "shard", "pos": pos, "t": 0.0,
			"dur": randf_range(0.45, 0.8),
			"vel": Vector2(cos(a), sin(a)) * randf_range(60.0, 160.0),
			"rot": randf_range(0.0, TAU), "spin": randf_range(-9.0, 9.0),
			"size": randf_range(3.0, 6.0), "color": color,
		})


## 火花/碎光：升级时向上飘的一点亮
func _fx_sparks(pos: Vector2, color: Color, n: int = 6) -> void:
	for i in n:
		var a := -PI * 0.5 + randf_range(-1.1, 1.1)
		fx.append({
			"kind": "spark", "pos": pos + Vector2(randf_range(-8.0, 8.0), randf_range(-6.0, 6.0)),
			"t": 0.0, "dur": randf_range(0.35, 0.6),
			"vel": Vector2(cos(a), sin(a)) * randf_range(70.0, 150.0),
			"size": randf_range(1.6, 3.2), "color": color,
		})


func _draw_fx() -> void:
	for f in fx:
		var k := clampf(float(f["t"]) / float(f["dur"]), 0.0, 1.0)
		var c: Color = f["color"]
		match str(f["kind"]):
			"ring":
				var r := lerpf(float(f["r0"]), float(f["r1"]), ease(k, 0.35))
				c.a = (1.0 - k) * 0.8
				draw_arc(f["pos"], r, 0.0, TAU, 40, c, 3.0 * (1.0 - k * 0.7), true)
			"shard":
				c.a = 1.0 - k * 0.85
				var s := float(f["size"])
				var pts := PackedVector2Array([
					Vector2(-s, -s * 0.4), Vector2(s, -s * 0.4),
					Vector2(s, s * 0.4), Vector2(-s, s * 0.4)])
				var rot := float(f["rot"])
				for i in pts.size():
					pts[i] = (f["pos"] as Vector2) + pts[i].rotated(rot)
				draw_colored_polygon(pts, c)
			"spark":
				c.a = 1.0 - k
				draw_circle(f["pos"], float(f["size"]) * (1.0 - k * 0.6), c)


# --- 平衡模拟器（开发用） ---

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
## 用的是和实机完全相同的固定步长，所以结论可以直接迁移到真玩。
## upgrade_mode: 0=不升级 1=铺不动了再升级 2=有钱就升级
func dev_simulate(
	index: int,
	build: Array,
	max_seconds: float = 420.0,
	upgrade_mode: int = 1,
	overrides: Dictionary = {}
) -> Dictionary:
	set_process(false)
	audio_enabled = false
	start_level(index)
	_apply_tuning(overrides)
	var dt := UnitData.FIXED_DT
	var t := 0.0
	var build_i := 0
	var upg_timer := 0.0
	var starve := 0.0
	while not finished and t < max_seconds:
		var placed := false
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
			if _place_exact(tid, cell):
				placed = true
			build_i += 1
		starve = 0.0 if placed else starve + dt

		upg_timer -= dt
		if upg_timer <= 0.0:
			upg_timer = 1.5
			if upgrade_mode == 2:
				_auto_upgrade_once()
			elif upgrade_mode == 1 and (build_i >= build.size() or starve > 6.0):
				# 计划铺完了，或者纸笔已经 6 秒花不出去 → 转去升级
				if _auto_upgrade_once():
					starve = 0.0

		_step(dt)
		t += dt

	var result := {
		"level": index,
		"win": base_hp > 0 and finished,
		"timeout": not finished,
		"finished": finished,
		"base": base_hp,
		"base_max": base_max,
		"seconds": int(t),
		"placed": build_i,
		"insight": int(insight_gained),
		"towers_left": towers.size(),
		"levels_sum": _tower_level_sum(),
		"enemies_left": enemies.size(),
	}
	set_process(true)
	audio_enabled = true
	running = false
	finished = true
	return result


func _tower_level_sum() -> int:
	var s := 0
	for t in towers:
		s += (t as Tower).level
	return s


# --- 绘制（只画会动的东西；静态层在 BattleBackdrop） ---

func _draw() -> void:
	_draw_base()
	if pending_tower != "":
		_draw_pending_hint()
	for t in towers:
		_draw_tower(t as Tower)
	for e in enemies:
		_draw_enemy(e as Enemy)
	_draw_shots()
	_draw_splats()
	_draw_fx()
	for f in floats:
		var a := clampf(float(f["life"]) / 0.9, 0.0, 1.0)
		var c: Color = f["color"]
		c.a = a
		_draw_centered(str(f["text"]), f["pos"], 15, c)
	if _vignette != null:
		draw_texture_rect(_vignette, Rect2(Vector2.ZERO, UnitData.DESIGN_SIZE), false)


func _draw_shots() -> void:
	for s in shots:
		var from: Vector2 = s["from"]
		var to: Vector2 = s["to"]
		var k := clampf(float(s["t"]) / float(s["dur"]), 0.0, 1.0)
		var head := from.lerp(to, k)
		var tail := from.lerp(to, maxf(0.0, k - 0.35))
		var col: Color = s["color"]
		col.a = 0.75 * (1.0 - k * 0.5)
		draw_line(tail, head, col, 2.6, true)
		draw_circle(head, 2.6, col)


func _draw_splats() -> void:
	for sp in splats:
		var k := clampf(float(sp["life"]) / float(sp["max_life"]), 0.0, 1.0)
		var c: Color = sp["color"]
		c.a = 0.55 * k
		draw_circle(sp["pos"], float(sp["r"]) * (1.6 - k * 0.6), c)


## 每个出口画一本「书」，就是敌人要逃进去的地方
func _draw_base() -> void:
	for route in routes:
		var pts: Array = (route as Dictionary).get("points", [])
		if pts.is_empty():
			continue
		var raw: Vector2 = pts[pts.size() - 1]
		var p := Vector2(
			clampf(raw.x, 60.0, UnitData.DESIGN_SIZE.x - 60.0),
			clampf(raw.y, UnitData.PLAY_TOP + 50.0, UnitData.PLAY_BOTTOM - 50.0))
		_draw_book(p)

	# 总血量条：竖在右上角，离多个出口都远
	var bar_w := 12.0
	var bar_h := 96.0
	var origin := Vector2(UnitData.DESIGN_SIZE.x - 36.0, UnitData.PLAY_TOP + 16.0)
	var ratio := clampf(float(base_hp) / float(maxi(base_max, 1)), 0.0, 1.0)
	draw_rect(Rect2(origin, Vector2(bar_w, bar_h)), Color(0, 0, 0, 0.6), true)
	draw_rect(Rect2(origin + Vector2(0.0, bar_h * (1.0 - ratio)), Vector2(bar_w, bar_h * ratio)),
		Color("a8c46a") if ratio > 0.4 else Color("d9573f"), true)
	draw_rect(Rect2(origin, Vector2(bar_w, bar_h)), Color(1, 1, 1, 0.25), false, 1.0)
	_draw_centered("%d" % base_hp, origin + Vector2(bar_w * 0.5, bar_h * 0.5), 13, UnitData.PAPER)


func _draw_book(p: Vector2) -> void:
	var alive_col := Color("c9a227")
	var col := alive_col if base_hp > 0 else Color("6b2b2b")
	var size := Vector2(58.0, 84.0)
	# 漏字时书会闪红，给玩家一个明确的「这里在失血」的信号
	if _book_flash > 0.0:
		col = col.lerp(Color("e14b3a"), 0.8 * _book_flash)
		draw_rect(Rect2(p - size * 0.5 - Vector2(6, 6), size + Vector2(12, 12)),
			Color(0.88, 0.25, 0.2, 0.10 * _book_flash), true)
	draw_rect(Rect2(p - size * 0.5, size), Color(0.13, 0.11, 0.09, 0.85), true)
	draw_rect(Rect2(p - size * 0.5, size), col, false, 3.0)
	draw_line(p + Vector2(-12.0, -size.y * 0.5), p + Vector2(-12.0, size.y * 0.5), col, 2.0)
	_draw_centered("书", p, 26, col)


func _draw_pending_hint() -> void:
	# 预览画在「吸附到的格子」上，和最终落点完全一致，不会出现视觉偏移
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
		var half := UnitData.GRID_STEP * 0.5 - 3.0
		var rect := Rect2(anchor - Vector2(half, half), Vector2(half, half) * 2.0)
		draw_rect(rect, Color(col.r, col.g, col.b, 0.14), true)
		draw_rect(rect, col, false, 2.0)

	var stats := UnitData.tower_stats(pending_tower, 1, GS.tower_mult())
	var range_box := _box_rect(anchor, float(stats["range"]))
	draw_rect(range_box, Color(col.r, col.g, col.b, 0.07), true)
	draw_rect(range_box, Color(col.r, col.g, col.b, 0.38), false, 1.5)
	_draw_unit_shape(pending_tower, anchor, 15.0, Color(col.r, col.g, col.b, 0.25))
	if not ok:
		_draw_centered(err, anchor + Vector2(0.0, 38.0), 13, col)


## 不同分身用不同剪影：竖条符纸 / 盾 / 刀头 / 圆符
func _unit_shape(kind: String, c: Vector2, r: float) -> PackedVector2Array:
	match kind:
		"ranged":
			var w := r * 0.76
			return PackedVector2Array([
				c + Vector2(-w, -r), c + Vector2(w, -r), c + Vector2(w, r * 0.70),
				c + Vector2(0.0, r * 1.06), c + Vector2(-w, r * 0.70)])
		"shield":
			var w2 := r * 0.92
			return PackedVector2Array([
				c + Vector2(-w2, -r * 0.88), c + Vector2(w2, -r * 0.88),
				c + Vector2(w2, r * 0.22), c + Vector2(0.0, r * 1.12),
				c + Vector2(-w2, r * 0.22)])
		"melee":
			return PackedVector2Array([
				c + Vector2(0.0, -r * 1.10), c + Vector2(r * 0.86, 0.0),
				c + Vector2(0.0, r * 1.10), c + Vector2(-r * 0.86, 0.0)])
		_:
			var pts := PackedVector2Array()
			for i in 18:
				var a := TAU * float(i) / 18.0
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			return pts


func _draw_unit_shape(kind: String, c: Vector2, r: float, fill: Color) -> void:
	draw_colored_polygon(_unit_shape(kind, c, r), fill)


func _draw_shadow(c: Vector2, rx: float, ry: float, alpha: float = 0.30) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * float(i) / 16.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry + 2.0))
	draw_colored_polygon(pts, Color(0.0, 0.0, 0.0, alpha))


func _draw_tower(t: Tower) -> void:
	if t.is_dead():
		return
	if t == selected:
		var rb := _box_rect(t.pos, t.atk_range)
		draw_rect(rb, Color(0.95, 0.85, 0.5, 0.07), true)
		draw_rect(rb, Color(0.95, 0.85, 0.5, 0.40), false, 2.0)

	_draw_shadow(t.pos, 16.0, 7.0)
	var body := t.color
	if t.flash > 0.0:
		body = body.lerp(Color.WHITE, 0.55)
	# 双层多边形代替描边：外面一圈暗色，里面一圈本体色
	_draw_unit_shape(t.kind, t.pos, 17.5, Color(0.10, 0.09, 0.07, 0.95))
	_draw_unit_shape(t.kind, t.pos, 14.6, body)
	_draw_centered(t.glyph, t.pos + Vector2(0.0, 1.0), 17, Color(0.11, 0.10, 0.08))

	# 等级点
	for i in range(t.level - 1):
		draw_circle(t.pos + Vector2(-6.0 + float(i) * 12.0, -22.0), 2.8, UnitData.PAPER)

	# 血条：常显
	var w := 36.0
	var topleft := t.pos + Vector2(-w * 0.5, -20.0)
	var ratio := clampf(t.hp / t.max_hp, 0.0, 1.0)
	draw_rect(Rect2(topleft, Vector2(w, 4.5)), Color(0, 0, 0, 0.65), true)
	draw_rect(Rect2(topleft, Vector2(w * ratio, 4.5)),
		Color("a8c46a") if ratio > 0.35 else Color("d9573f"), true)

	# 阻挡格：剩余格数用小方块显示
	if t.block_capacity > 0:
		var free := t.block_capacity - t.engaged.size()
		for i in range(t.block_capacity):
			var c := Color("9fb8d8") if i < free else Color(0.35, 0.4, 0.5, 0.55)
			draw_rect(Rect2(t.pos + Vector2(-8.0 + float(i) * 6.0, 12.0), Vector2(4.0, 4.0)), c, true)

	if t == selected:
		_draw_centered("%d/%d" % [int(t.hp), int(t.max_hp)], t.pos + Vector2(0.0, -30.0), 12, UnitData.PAPER)


func _draw_enemy(e: Enemy) -> void:
	if e.is_dead():
		return
	var col := e.color
	if e.flash > 0.0:
		col = col.lerp(Color.WHITE, 0.6)
	_draw_shadow(e.pos, e.radius * 0.95, e.radius * 0.42, 0.26)
	draw_circle(e.pos, e.radius + 3.0, Color(0.13, 0.11, 0.09, 0.85))
	draw_circle(e.pos, e.radius, col)
	# 有护甲就套一圈冷色，玩家不用看数字也知道该用什么打
	if e.armor > 0.0:
		var w := 2.0 if e.armor < 8.0 else 3.0
		draw_arc(e.pos, e.radius + 1.5, 0.0, TAU, 28, Color(0.78, 0.82, 0.92, 0.85), w, true)
	_draw_centered(e.glyph, e.pos + Vector2(0.0, 1.0), int(e.radius * 1.15), Color(0.97, 0.95, 0.91))

	# 血条：常显
	var bw := e.radius * 2.4
	var topleft := e.pos + Vector2(-bw * 0.5, -e.radius - 10.0)
	var ratio := clampf(e.hp / e.max_hp, 0.0, 1.0)
	draw_rect(Rect2(topleft, Vector2(bw, 4.0)), Color(0, 0, 0, 0.65), true)
	draw_rect(Rect2(topleft, Vector2(bw * ratio, 4.0)),
		Color("e8a8c0") if not e.ranged else Color("9fb8d8"), true)

	# 正在攻击友方时画一条细线提示
	if e.target != null:
		draw_line(e.pos, e.target.pos, Color(0.85, 0.35, 0.3, 0.35), 1.2, true)


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
			_refresh_backdrop()
			queue_redraw()
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	# 用 to_local 而不是直接用事件坐标：屏幕震动时节点位置会偏几像素，
	# 直接用画布坐标会让落点跟光标对不上。
	var at := to_local(mb.position)
	if pending_tower != "":
		try_place(at)
	else:
		select_tower_at(at)
	get_viewport().set_input_as_handled()
