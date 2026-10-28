class_name UnitData
extends RefCounted

## 数值 / 配色 / 关卡定义集中在这里。
## 美术接入占位图时只改 color、glyph，战斗逻辑不用动。
## 色板取自《小屋》设计图：手绘线条 + 暖色平涂。

# --- 色板 ---
const INK := Color("3a3226")
const PAPER := Color("f6efe0")
const WOOD := Color("a9763f")
const LEAF := Color("a8c46a")
const PINK := Color("e8a8c0")
const SKY := Color("9fb8d8")
const ORANGE := Color("e08a3c")
const BG := Color("2a231b")

# --- 版本号：每次发试玩包改这里 ---
const GAME_VERSION := "v0.1.2"
const GAME_CHANNEL := "试玩版"
const GAME_BUILD := "2026-10-28"

## 纸笔自然回复速率（每秒）
const INK_REGEN := 1.0 / 0.75

# --- 敌方单位：会走路、会主动攻击友方的「文字」 ---
## armor: 护甲，直接减免每次伤害（最低 1）
## attack_range: 主动攻击友方的距离；ranged=true 时会停下来远程点射
const ENEMIES := {
	"zao": {
		"name": "躁", "glyph": "躁", "hp": 60.0, "speed": 80.0,
		"atk": 8.0, "interval": 1.0, "armor": 0.0, "attack_range": 56.0,
		"ranged": false, "color": Color("d9573f"), "insight": 2,
		"radius": 17.0, "leak": 1,
	},
	"kuang": {
		"name": "狂", "glyph": "狂", "hp": 75.0, "speed": 126.0,
		"atk": 12.0, "interval": 0.7, "armor": 0.0, "attack_range": 52.0,
		"ranged": false, "color": Color("e0762a"), "insight": 3,
		"radius": 16.0, "leak": 1,
	},
	"yi": {
		"name": "疑", "glyph": "疑", "hp": 105.0, "speed": 60.0,
		"atk": 11.0, "interval": 1.5, "armor": 0.0, "attack_range": 152.0,
		"ranged": true, "color": Color("3f8f7a"), "insight": 4,
		"radius": 19.0, "leak": 1,
	},
	"mi": {
		"name": "迷", "glyph": "迷", "hp": 230.0, "speed": 42.0,
		"atk": 18.0, "interval": 1.3, "armor": 2.0, "attack_range": 60.0,
		"ranged": false, "color": Color("7c5cbf"), "insight": 6,
		"radius": 23.0, "leak": 1,
	},
	"zhi": {
		"name": "执", "glyph": "执", "hp": 300.0, "speed": 46.0,
		"atk": 15.0, "interval": 1.1, "armor": 8.0, "attack_range": 62.0,
		"ranged": false, "color": Color("6b6f8c"), "insight": 8,
		"radius": 22.0, "leak": 1,
	},
	"hui": {
		"name": "晦", "glyph": "晦", "hp": 700.0, "speed": 40.0,
		"atk": 26.0, "interval": 1.6, "armor": 4.0, "attack_range": 162.0,
		"ranged": true, "color": Color("4a2f4f"), "insight": 30,
		"radius": 28.0, "leak": 2,
	},
}

# --- 友方单位：魔女的施法分身 ---
## deploy: "ground" 只能放在路径上（会挡路） | "high" 只能放在路旁高台
## kind: ranged | melee | shield | heal
## block: 能同时挡住的敌人数
const TOWERS := {
	"bolt": {
		"name": "墨矢", "glyph": "矢", "kind": "ranged", "deploy": "high",
		"cost": 14, "block": 0, "color": Color("e08a3c"),
		"upgrade_costs": [12, 20],
		"levels": [
			{"hp": 130.0, "atk": 22.0, "range": 200.0, "interval": 1.40},
			{"hp": 175.0, "atk": 34.0, "range": 220.0, "interval": 1.25},
			{"hp": 230.0, "atk": 50.0, "range": 240.0, "interval": 1.10},
		],
	},
	"heal": {
		"name": "疗愈符", "glyph": "愈", "kind": "heal", "deploy": "high",
		"cost": 15, "block": 0, "color": Color("e8a8c0"),
		"upgrade_costs": [12, 20],
		"levels": [
			{"hp": 140.0, "atk": 18.0, "range": 175.0, "interval": 1.60},
			{"hp": 180.0, "atk": 30.0, "range": 195.0, "interval": 1.45},
			{"hp": 230.0, "atk": 45.0, "range": 215.0, "interval": 1.30},
		],
	},
	"blade": {
		"name": "墨刃", "glyph": "刃", "kind": "melee", "deploy": "ground",
		"cost": 16, "block": 2, "color": Color("c0392b"),
		"upgrade_costs": [14, 22],
		"levels": [
			{"hp": 300.0, "atk": 16.0, "range": 84.0, "interval": 1.00},
			{"hp": 400.0, "atk": 24.0, "range": 94.0, "interval": 0.90},
			{"hp": 540.0, "atk": 36.0, "range": 104.0, "interval": 0.80},
		],
	},
	"shield": {
		"name": "纸盾", "glyph": "盾", "kind": "shield", "deploy": "ground",
		"cost": 18, "block": 3, "color": Color("9fb8d8"),
		"upgrade_costs": [16, 26],
		"levels": [
			{"hp": 520.0, "atk": 0.0, "range": 60.0, "interval": 1.00},
			{"hp": 760.0, "atk": 0.0, "range": 60.0, "interval": 1.00},
			{"hp": 1100.0, "atk": 0.0, "range": 60.0, "interval": 1.00},
		],
	},
}

const TOWER_ORDER := ["bolt", "blade", "shield", "heal"]

# --- 关卡 ---
## 一条折线作为行军路线（像素坐标，设计分辨率 1280x720）
const PATH_POINTS := [
	Vector2(-40.0, 168.0),
	Vector2(320.0, 168.0),
	Vector2(320.0, 444.0),
	Vector2(756.0, 444.0),
	Vector2(756.0, 168.0),
	Vector2(1044.0, 168.0),
	Vector2(1044.0, 612.0),
	Vector2(1330.0, 612.0),
]

const GRID_STEP := 44.0
## 高台格：离路线 34~118 像素的网格
const CELL_MIN_DIST := 34.0
const CELL_MAX_DIST := 118.0
## 地面格：沿路线每 44 像素一个落脚点
const GROUND_STEP := 44.0

const BASE_DATA := {
	"id": "matchman",
	"title": "火柴人大陆",
	"subtitle": "第一本 · 五关",
	"levels": [
		{
			"name": "第一页 · 字从门缝里跑出来",
			"rule_name": "教学",
			"rule": "只有「躁」在乱跑。先把纸盾放到路上挡住它，后面再补墨矢。",
			"start_ink": 20,
			"base_hp": 12,
			"ink_mult": 1.0,
			"enemy_hp_mult": 1.00,
			"enemy_speed_mult": 1.00,
			"waves": [
				{"at": 4.0, "spawns": [{"type": "zao", "count": 3, "gap": 2.4}]},
				{"at": 22.0, "spawns": [{"type": "zao", "count": 4, "gap": 1.9}]},
				{"at": 46.0, "spawns": [{"type": "zao", "count": 6, "gap": 1.5}]},
			],
		},
		{
			"name": "第二页 · 走不出的雾",
			"rule_name": "重字登场",
			"rule": "「迷」很慢很硬，还带 2 点护甲——盾挡住它，让墨刃慢慢磨。",
			"start_ink": 20,
			"base_hp": 12,
			"ink_mult": 1.0,
			"enemy_hp_mult": 1.00,
			"enemy_speed_mult": 1.00,
			"waves": [
				{"at": 4.0, "spawns": [{"type": "zao", "count": 4, "gap": 1.7}]},
				{"at": 24.0, "spawns": [{"type": "mi", "count": 2, "gap": 3.2}, {"type": "zao", "count": 3, "gap": 1.6}]},
				{"at": 54.0, "spawns": [{"type": "mi", "count": 3, "gap": 2.6}]},
			],
		},
		{
			"name": "第三页 · 会还手的疑问",
			"rule_name": "远程敌人",
			"rule": "「疑」会优先点掉挡路的盾。只靠盾扛不住，得让墨矢先清它。",
			"start_ink": 22,
			"base_hp": 12,
			"ink_mult": 1.0,
			"enemy_hp_mult": 1.00,
			"enemy_speed_mult": 1.00,
			"waves": [
				{"at": 4.0, "spawns": [{"type": "zao", "count": 4, "gap": 1.5}]},
				{"at": 22.0, "spawns": [{"type": "yi", "count": 2, "gap": 4.0}, {"type": "zao", "count": 4, "gap": 1.4}]},
				{"at": 46.0, "spawns": [{"type": "mi", "count": 2, "gap": 3.0}, {"type": "yi", "count": 2, "gap": 2.8}]},
				{"at": 72.0, "spawns": [{"type": "zao", "count": 7, "gap": 1.2}]},
			],
		},
		{
			"name": "第四页 · 冲刺的字",
			"rule_name": "墨水稀薄 + 快攻",
			"rule": "纸笔回复只剩八成，「狂」跑得极快。盾的等级和位置比数量重要。",
			"start_ink": 22,
			"base_hp": 12,
			"ink_mult": 0.90,
			"enemy_hp_mult": 1.05,
			"enemy_speed_mult": 1.00,
			"waves": [
				{"at": 4.0, "spawns": [{"type": "zao", "count": 5, "gap": 1.4}]},
				{"at": 24.0, "spawns": [{"type": "kuang", "count": 3, "gap": 2.0}, {"type": "zao", "count": 3, "gap": 1.5}]},
				{"at": 50.0, "spawns": [{"type": "mi", "count": 2, "gap": 3.0}, {"type": "yi", "count": 2, "gap": 3.2}]},
				{"at": 78.0, "spawns": [{"type": "kuang", "count": 4, "gap": 1.6}]},
			],
		},
		{
			"name": "第五页 · 合订",
			"rule_name": "合订本",
			"rule": "整本书的字一起压上来，还有带 8 点护甲的「执」和首领「晦」。升级和重建都得用上。",
			"start_ink": 24,
			"base_hp": 15,
			"ink_mult": 1.15,
			"enemy_hp_mult": 0.95,
			"enemy_speed_mult": 1.05,
			"waves": [
				{"at": 4.0, "spawns": [{"type": "zao", "count": 6, "gap": 1.3}]},
				{"at": 22.0, "spawns": [{"type": "mi", "count": 2, "gap": 2.8}, {"type": "kuang", "count": 2, "gap": 2.2}]},
				{"at": 48.0, "spawns": [{"type": "zhi", "count": 2, "gap": 3.4}, {"type": "yi", "count": 2, "gap": 3.0}]},
				{"at": 78.0, "spawns": [{"type": "hui", "count": 1, "gap": 1.0}, {"type": "kuang", "count": 4, "gap": 1.6}]},
				{"at": 106.0, "spawns": [{"type": "zhi", "count": 3, "gap": 2.6}, {"type": "zao", "count": 5, "gap": 1.2}]},
			],
		},
	],
}

# --- 养成 ---
const HOUSE_STAGES := [
	{"name": "废墟", "cost": 0, "tower_mult": 1.00, "read_mult": 1.00},
	{"name": "清出空地", "cost": 30, "tower_mult": 1.06, "read_mult": 1.25},
	{"name": "修好屋顶", "cost": 70, "tower_mult": 1.12, "read_mult": 1.55},
	{"name": "补上书架", "cost": 140, "tower_mult": 1.20, "read_mult": 1.90},
	{"name": "重新点亮", "cost": 260, "tower_mult": 1.30, "read_mult": 2.40},
]

const READ_BASE := 0.10
const INK_PACK := {"cost": 20, "bonus": 6}
const OFFLINE_CAP := 8.0 * 3600.0


static func tower_stats(tower_id: String, level: int, tower_mult: float) -> Dictionary:
	var def: Dictionary = TOWERS.get(tower_id, {})
	var levels: Array = def.get("levels", [])
	var idx: int = clampi(level - 1, 0, levels.size() - 1)
	var stats: Dictionary = (levels[idx] as Dictionary).duplicate()
	stats["hp"] = float(stats["hp"]) * tower_mult
	stats["atk"] = float(stats["atk"]) * tower_mult
	return stats


static func tower_max_level(tower_id: String) -> int:
	return (TOWERS.get(tower_id, {}).get("levels", []) as Array).size()


static func tower_upgrade_cost(tower_id: String, target_level: int) -> int:
	var costs: Array = TOWERS.get(tower_id, {}).get("upgrade_costs", [])
	var idx: int = target_level - 2
	if idx < 0 or idx >= costs.size():
		return -1
	return int(costs[idx])


static func tower_deploy(tower_id: String) -> String:
	return str((TOWERS.get(tower_id, {}) as Dictionary).get("deploy", "high"))
