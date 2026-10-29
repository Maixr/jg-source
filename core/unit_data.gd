class_name UnitData
extends RefCounted

## 数值 / 配色 / 关卡 / 地图定义集中在这里。
## 美术接入占位图时只改 color、glyph，战斗逻辑不用动。

# --- 画面 ---
## 设计分辨率（改这个要同步 project.godot 的 viewport 设置）
const DESIGN_SIZE := Vector2(1600.0, 900.0)
## 顶部 HUD / 底部操作栏占据的高度，用来限制可放置区域
const PLAY_TOP := 86.0
const PLAY_BOTTOM := 792.0

# --- 色板 ---
const INK := Color("3a3226")
const PAPER := Color("f6efe0")
const WOOD := Color("a9763f")
const LEAF := Color("a8c46a")
const PINK := Color("e8a8c0")
const SKY := Color("9fb8d8")
const ORANGE := Color("e08a3c")
const BG := Color("2a231b")

# --- 版本号 ---
## 版号 / 标题只在这一处维护：打包脚本会用正则从这里读，
## 不用再去 export_windows.ps1 里同步 $exeName。
const GAME_TITLE := "斋悟"
const GAME_VERSION := "v0.2.1"
const GAME_CHANNEL := "试玩版"
const GAME_BUILD := "2026-10-30"

## 纸笔自然回复速率（每秒）
const INK_REGEN := 1.0 / 0.75

# --- 时间步长 ---
## 逻辑固定步长：模拟器和实机共用同一个步长，帧率与倍速都不再影响结果。
## 之前直接用帧 delta，冷却余量被丢弃，帧率越高 DPS 越高，无头平衡自检
## （0.1s 步长）和实机（约 0.017s）算出来也就不是同一回事了。
const FIXED_DT := 1.0 / 60.0
## 单帧 delta 上限：窗口被拖动或系统卡顿后不追帧，避免敌人一帧跨过判定框
const MAX_DELTA := 0.1

# --- 敌方单位 ---
## armor: 护甲，减免每次伤害（最低 1）
## attack_range: 主动攻击友方的距离（方框判定）
const ENEMIES := {
	"zao": {
		"name": "躁", "glyph": "躁", "hp": 60.0, "speed": 80.0,
		"atk": 8.0, "interval": 1.0, "armor": 0.0, "attack_range": 36.0,
		"ranged": false, "color": Color("d9573f"), "insight": 2,
		"radius": 17.0, "leak": 1,
		"info": "最普通的字。跑得快、血很薄，靠数量压过来。盾挡得住。",
	},
	"kuang": {
		"name": "狂", "glyph": "狂", "hp": 75.0, "speed": 126.0,
		"atk": 12.0, "interval": 0.7, "armor": 0.0, "attack_range": 34.0,
		"ranged": false, "color": Color("e0762a"), "insight": 3,
		"radius": 16.0, "leak": 1,
		"info": "冲刺型，移动速度极快。盾还没升级时很容易漏过去。",
	},
	"yi": {
		"name": "疑", "glyph": "疑", "hp": 105.0, "speed": 60.0,
		"atk": 11.0, "interval": 1.5, "armor": 0.0, "attack_range": 152.0,
		"ranged": true, "color": Color("3f8f7a"), "insight": 4,
		"radius": 19.0, "leak": 1,
		"info": "远程。站在路上朝你的分身扔东西，射程很远，会优先点盾。",
	},
	"mi": {
		"name": "迷", "glyph": "迷", "hp": 230.0, "speed": 42.0,
		"atk": 18.0, "interval": 1.3, "armor": 2.0, "attack_range": 38.0,
		"ranged": false, "color": Color("7c5cbf"), "insight": 6,
		"radius": 23.0, "leak": 1,
		"info": "又慢又硬，还带 2 点护甲。小伤害打它很吃亏，用墨矢磨。",
	},
	"zhi": {
		"name": "执", "glyph": "执", "hp": 300.0, "speed": 46.0,
		"atk": 15.0, "interval": 1.1, "armor": 8.0, "attack_range": 38.0,
		"ranged": false, "color": Color("6b6f8c"), "insight": 8,
		"radius": 22.0, "leak": 1,
		"info": "重甲。8 点护甲让每次伤害都大打折扣，必须靠高攻单点。",
	},
	"hui": {
		"name": "晦", "glyph": "晦", "hp": 700.0, "speed": 40.0,
		"atk": 26.0, "interval": 1.6, "armor": 4.0, "attack_range": 162.0,
		"ranged": true, "color": Color("4a2f4f"), "insight": 30,
		"radius": 28.0, "leak": 2,
		"info": "首领。血极厚、远程，漏掉一个就掉 2 点剧情完整度。",
	},
}

# --- 友方单位 ---
## 攻击范围必须是 GRID_STEP 的半整数倍（96 / 160 / 224 / 288…），
## 这样方框边界正好压在地格边界上，视觉框与判定范围完全重合。
const TOWERS := {
	"bolt": {
		"name": "墨矢", "glyph": "矢", "kind": "ranged", "deploy": "high",
		"cost": 14, "block": 0, "color": Color("e08a3c"),
		"upgrade_costs": [12, 20, 34, 52],
		"levels": [
			{"hp": 130.0, "atk": 22.0, "range": 224.0, "interval": 1.40},
			{"hp": 175.0, "atk": 34.0, "range": 224.0, "interval": 1.25},
			{"hp": 230.0, "atk": 50.0, "range": 288.0, "interval": 1.10},
			{"hp": 300.0, "atk": 70.0, "range": 288.0, "interval": 1.00},
			{"hp": 380.0, "atk": 95.0, "range": 320.0, "interval": 0.92},
		],
	},
	"heal": {
		"name": "疗愈符", "glyph": "愈", "kind": "heal", "deploy": "high",
		"cost": 15, "block": 0, "color": Color("e8a8c0"),
		"upgrade_costs": [12, 20, 34, 52],
		"levels": [
			{"hp": 140.0, "atk": 18.0, "range": 160.0, "interval": 1.60},
			{"hp": 180.0, "atk": 30.0, "range": 224.0, "interval": 1.45},
			{"hp": 230.0, "atk": 45.0, "range": 224.0, "interval": 1.30},
			{"hp": 300.0, "atk": 62.0, "range": 256.0, "interval": 1.20},
			{"hp": 380.0, "atk": 85.0, "range": 256.0, "interval": 1.10},
		],
	},
	"blade": {
		"name": "墨刃", "glyph": "刃", "kind": "melee", "deploy": "ground",
		"cost": 16, "block": 2, "color": Color("c0392b"),
		"upgrade_costs": [14, 22, 38, 58],
		"levels": [
			{"hp": 300.0, "atk": 16.0, "range": 96.0, "interval": 1.00},
			{"hp": 400.0, "atk": 24.0, "range": 96.0, "interval": 0.90},
			{"hp": 540.0, "atk": 36.0, "range": 96.0, "interval": 0.80},
			{"hp": 720.0, "atk": 52.0, "range": 96.0, "interval": 0.72},
			{"hp": 950.0, "atk": 74.0, "range": 128.0, "interval": 0.65},
		],
	},
	"shield": {
		"name": "纸盾", "glyph": "盾", "kind": "shield", "deploy": "ground",
		"cost": 18, "block": 3, "color": Color("9fb8d8"),
		"upgrade_costs": [16, 26, 44, 66],
		"levels": [
			{"hp": 520.0, "atk": 0.0, "range": 96.0, "interval": 1.00},
			{"hp": 760.0, "atk": 0.0, "range": 96.0, "interval": 1.00},
			{"hp": 1100.0, "atk": 0.0, "range": 96.0, "interval": 1.00},
			{"hp": 1500.0, "atk": 0.0, "range": 96.0, "interval": 1.00},
			{"hp": 2000.0, "atk": 0.0, "range": 96.0, "interval": 1.00},
		],
	},
}

## 不吃书屋加成时，分身最多升到几级（第 4、5 级要靠 UPGRADES.level 解锁）
const TOWER_BASE_LEVEL_CAP := 3

const TOWER_ORDER := ["bolt", "blade", "shield", "heal"]

# --- 格子 ---
const GRID_STEP := 64.0
## 高台格：离任意一条路线 40~150 像素的网格
const CELL_MIN_DIST := 40.0
const CELL_MAX_DIST := 150.0
## 地面格：沿路线每 64 像素一个落脚点
const GROUND_STEP := 64.0

# --- 关卡 ---
## 每关自己的路线。routes[i].points 是一条折线，最后一个点就是「书的出口」。
## 后面几关可以放多条路线（多出生点 / 多终点）。
const BASE_DATA := {
	"id": "matchman",
	"title": "火柴人大陆",
	"subtitle": "第一本 · 五关",
	"levels": [
		{
			"name": "第一页 · 字从门缝里跑出来",
			"rule_name": "教学",
			"rule": "只有「躁」在乱跑。先把纸盾放到路上挡住它，后面再补墨矢。",
			"start_ink": 16,
			"base_hp": 12,
			"ink_mult": 1.0,
			"enemy_hp_mult": 1.48,
			"enemy_speed_mult": 1.00,
			"routes": [
				{"label": "正门", "points": [
					Vector2(-70.0, 240.0), Vector2(420.0, 240.0), Vector2(420.0, 600.0),
					Vector2(980.0, 600.0), Vector2(980.0, 240.0), Vector2(1320.0, 240.0),
					Vector2(1320.0, 720.0), Vector2(1670.0, 720.0),
				]},
			],
			"waves": [
				{"at": 4.0, "spawns": [{"type": "zao", "count": 5, "gap": 2.0, "route": 0}]},
				{"at": 22.0, "spawns": [{"type": "zao", "count": 8, "gap": 1.6, "route": 0}]},
				{"at": 46.0, "spawns": [{"type": "zao", "count": 12, "gap": 1.1, "route": 0}]},
				{"at": 70.0, "spawns": [{"type": "zao", "count": 12, "gap": 1.0, "route": 0}]},
			],
		},
		{
			"name": "第二页 · 走不出的雾",
			"rule_name": "重字登场",
			"rule": "「迷」很慢很硬，还带 2 点护甲——盾挡住它，让墨刃慢慢磨。",
			"start_ink": 18,
			"base_hp": 12,
			"ink_mult": 1.0,
			"enemy_hp_mult": 1.62,
			"enemy_speed_mult": 1.00,
			"routes": [
				{"label": "雾底", "points": [
					Vector2(-70.0, 700.0), Vector2(330.0, 700.0), Vector2(330.0, 340.0),
					Vector2(760.0, 340.0), Vector2(760.0, 720.0), Vector2(1150.0, 720.0),
					Vector2(1150.0, 320.0), Vector2(1670.0, 320.0),
				]},
			],
			"waves": [
				{"at": 4.0, "spawns": [{"type": "zao", "count": 5, "gap": 1.5, "route": 0}]},
				{"at": 24.0, "spawns": [{"type": "mi", "count": 2, "gap": 3.0, "route": 0}, {"type": "zao", "count": 4, "gap": 1.4, "route": 0}]},
				{"at": 54.0, "spawns": [{"type": "mi", "count": 4, "gap": 2.4, "route": 0}]},
				{"at": 80.0, "spawns": [{"type": "zao", "count": 5, "gap": 1.1, "route": 0}]},
			],
		},
		{
			"name": "第三页 · 会还手的疑问",
			"rule_name": "远程敌人",
			"rule": "「疑」会优先点掉挡路的盾。只靠盾扛不住，得让墨矢先清它。",
			"start_ink": 20,
			"base_hp": 12,
			"ink_mult": 1.0,
			"enemy_hp_mult": 1.55,
			"enemy_speed_mult": 1.00,
			"routes": [
				{"label": "横路", "points": [
					Vector2(-64.0, 384.0), Vector2(704.0, 384.0), Vector2(704.0, 256.0),
					Vector2(1536.0, 256.0), Vector2(1664.0, 256.0),
				]},
				{"label": "竖路", "points": [
					Vector2(896.0, 64.0), Vector2(896.0, 512.0), Vector2(768.0, 512.0),
					Vector2(768.0, 896.0),
				]},
			],
			"waves": [
				{"at": 4.0, "spawns": [{"type": "zao", "count": 4, "gap": 1.5, "route": 0}]},
				{"at": 22.0, "spawns": [{"type": "yi", "count": 1, "gap": 4.0, "route": 1}, {"type": "zao", "count": 6, "gap": 1.3, "route": 0}]},
				{"at": 46.0, "spawns": [{"type": "mi", "count": 2, "gap": 3.0, "route": 1}, {"type": "yi", "count": 1, "gap": 2.8, "route": 1}, {"type": "zao", "count": 4, "gap": 1.2, "route": 1}]},
				{"at": 72.0, "spawns": [{"type": "zao", "count": 9, "gap": 1.1, "route": 0}]},
			],
		},
		{
			"name": "第四页 · 冲刺的字",
			"rule_name": "墨水稀薄 + 快攻",
			"rule": "纸笔回复只剩九成，「狂」跑得极快。盾的等级和位置比数量重要。",
			"start_ink": 20,
			"base_hp": 12,
			"ink_mult": 0.90,
			"enemy_hp_mult": 1.70,
			"enemy_speed_mult": 1.00,
			"routes": [
				{"label": "回环", "points": [
					Vector2(-64.0, 256.0), Vector2(1216.0, 256.0), Vector2(1216.0, 704.0),
					Vector2(256.0, 704.0), Vector2(256.0, 448.0), Vector2(1664.0, 448.0),
				]},
			],
			"waves": [
				{"at": 4.0, "spawns": [{"type": "zao", "count": 5, "gap": 1.4, "route": 0}]},
				{"at": 24.0, "spawns": [{"type": "kuang", "count": 3, "gap": 2.0, "route": 0}, {"type": "zao", "count": 3, "gap": 1.5, "route": 0}]},
				{"at": 48.0, "spawns": [{"type": "mi", "count": 3, "gap": 3.0, "route": 0}, {"type": "yi", "count": 1, "gap": 3.2, "route": 0}]},
				{"at": 76.0, "spawns": [{"type": "kuang", "count": 4, "gap": 1.6, "route": 0}]},
			],
		},
		{
			"name": "第五页 · 合订",
			"rule_name": "合订本",
			"rule": "整本书的字一起压上来，还有重甲的「执」和首领「晦」。升级和重建都得用上。",
			"start_ink": 22,
			"base_hp": 15,
			"ink_mult": 1.05,
			"enemy_hp_mult": 1.10,
			"enemy_speed_mult": 1.05,
			"routes": [
				{"label": "左上路", "points": [
					Vector2(-64.0, 192.0), Vector2(640.0, 192.0), Vector2(640.0, 320.0),
					Vector2(1088.0, 320.0), Vector2(1664.0, 320.0),
				]},
				{"label": "左下楼", "points": [
					Vector2(-64.0, 704.0), Vector2(640.0, 704.0), Vector2(640.0, 320.0),
					Vector2(1088.0, 320.0), Vector2(1664.0, 320.0),
				]},
				{"label": "天窗", "points": [
					Vector2(1088.0, 64.0), Vector2(1088.0, 320.0), Vector2(1664.0, 320.0),
				]},
			],
			"waves": [
				{"at": 4.0, "spawns": [{"type": "zao", "count": 6, "gap": 1.3, "route": 0}]},
				{"at": 22.0, "spawns": [{"type": "mi", "count": 2, "gap": 2.8, "route": 0}, {"type": "kuang", "count": 2, "gap": 2.2, "route": 0}]},
				{"at": 48.0, "spawns": [{"type": "zhi", "count": 3, "gap": 3.4, "route": 1}, {"type": "yi", "count": 1, "gap": 3.0, "route": 1}]},
				{"at": 78.0, "spawns": [{"type": "hui", "count": 1, "gap": 1.0, "route": 2}, {"type": "kuang", "count": 4, "gap": 1.6, "route": 2}]},
				{"at": 106.0, "spawns": [{"type": "zhi", "count": 3, "gap": 2.6, "route": 1}, {"type": "zao", "count": 5, "gap": 1.2, "route": 1}]},
			],
		},
	],
}

# --- 散落的文具 ---
## 路上以外的空地里散着一些文具，占住高台格，那一格就放不了分身。
##
## 位置不用绝对坐标写，而是「沿某条路线走到 frac 处，朝 side 那侧偏 off 像素」，
## 建格子时自动吸附到最近的高台格。这样改地图布局时文具会跟着走，不用重算坐标。
## 也不随机：随机会让同一关每次难度不同，玩家也没法记住地形。
const CLUTTER := {
	# 第 1 关：教学关，少放几件，别一上来就堵住
	0: [
		{"kind": "pencil", "route": 0, "frac": 0.10, "side": -1, "off": 100},
		{"kind": "eraser", "route": 0, "frac": 0.20, "side": 1, "off": 96},
		{"kind": "ruler", "route": 0, "frac": 0.34, "side": -1, "off": 104},
		{"kind": "ink", "route": 0, "frac": 0.46, "side": 1, "off": 100},
		{"kind": "clip", "route": 0, "frac": 0.60, "side": -1, "off": 96},
		{"kind": "notebook", "route": 0, "frac": 0.72, "side": 1, "off": 104},
		{"kind": "pencil", "route": 0, "frac": 0.86, "side": -1, "off": 100},
	],
	# 第 2 关：W 形折返，两侧空间多，撒得开一点
	1: [
		{"kind": "eraser", "route": 0, "frac": 0.08, "side": -1, "off": 100},
		{"kind": "ruler", "route": 0, "frac": 0.18, "side": 1, "off": 96},
		{"kind": "notebook", "route": 0, "frac": 0.28, "side": -1, "off": 104},
		{"kind": "pencil", "route": 0, "frac": 0.38, "side": 1, "off": 100},
		{"kind": "ink", "route": 0, "frac": 0.48, "side": -1, "off": 96},
		{"kind": "clip", "route": 0, "frac": 0.58, "side": 1, "off": 104},
		{"kind": "eraser", "route": 0, "frac": 0.68, "side": -1, "off": 100},
		{"kind": "ruler", "route": 0, "frac": 0.78, "side": 1, "off": 96},
		{"kind": "notebook", "route": 0, "frac": 0.88, "side": -1, "off": 104},
		{"kind": "pencil", "route": 0, "frac": 0.95, "side": 1, "off": 100},
	],
	# 第 3 关：十字交叉，两条路各撒几件
	2: [
		{"kind": "pencil", "route": 0, "frac": 0.16, "side": 1, "off": 100},
		{"kind": "ruler", "route": 0, "frac": 0.36, "side": -1, "off": 96},
		{"kind": "ink", "route": 0, "frac": 0.58, "side": 1, "off": 104},
		{"kind": "eraser", "route": 0, "frac": 0.82, "side": -1, "off": 100},
		{"kind": "notebook", "route": 1, "frac": 0.14, "side": -1, "off": 100},
		{"kind": "clip", "route": 1, "frac": 0.34, "side": 1, "off": 96},
		{"kind": "pencil", "route": 1, "frac": 0.54, "side": -1, "off": 104},
		{"kind": "ink", "route": 1, "frac": 0.74, "side": 1, "off": 100},
		{"kind": "ruler", "route": 1, "frac": 0.92, "side": -1, "off": 96},
		{"kind": "eraser", "route": 0, "frac": 0.94, "side": 1, "off": 100},
	],
	# 第 4 关：自环，路绕回来圈出一大片空地
	3: [
		{"kind": "pencil", "route": 0, "frac": 0.06, "side": 1, "off": 100},
		{"kind": "notebook", "route": 0, "frac": 0.16, "side": -1, "off": 104},
		{"kind": "eraser", "route": 0, "frac": 0.26, "side": 1, "off": 96},
		{"kind": "ruler", "route": 0, "frac": 0.36, "side": -1, "off": 100},
		{"kind": "clip", "route": 0, "frac": 0.46, "side": 1, "off": 104},
		{"kind": "ink", "route": 0, "frac": 0.56, "side": -1, "off": 96},
		{"kind": "pencil", "route": 0, "frac": 0.66, "side": 1, "off": 100},
		{"kind": "notebook", "route": 0, "frac": 0.76, "side": -1, "off": 104},
		{"kind": "eraser", "route": 0, "frac": 0.84, "side": 1, "off": 96},
		{"kind": "ruler", "route": 0, "frac": 0.92, "side": -1, "off": 100},
	],
	# 第 5 关：三条路汇流，汇流前那段最挤，别把两边都堵死
	4: [
		{"kind": "ink", "route": 0, "frac": 0.12, "side": 1, "off": 100},
		{"kind": "pencil", "route": 0, "frac": 0.30, "side": -1, "off": 96},
		{"kind": "eraser", "route": 0, "frac": 0.55, "side": 1, "off": 104},
		{"kind": "ruler", "route": 1, "frac": 0.12, "side": -1, "off": 100},
		{"kind": "notebook", "route": 1, "frac": 0.34, "side": 1, "off": 96},
		{"kind": "clip", "route": 1, "frac": 0.62, "side": -1, "off": 104},
		{"kind": "pencil", "route": 2, "frac": 0.18, "side": 1, "off": 100},
		{"kind": "ink", "route": 2, "frac": 0.42, "side": -1, "off": 96},
		{"kind": "eraser", "route": 0, "frac": 0.80, "side": -1, "off": 104},
		{"kind": "ruler", "route": 0, "frac": 0.92, "side": 1, "off": 100},
	],
}

# --- 书屋（养成）---
## 在首页推门进屋，用「体悟」一条条升级，每条的等级单独存。
## 老版本只有一个线性的 house_stage，乐趣太少；现在拆成 6 条独立轨道，
## 玩家可以自己决定先点哪个（先多产纸笔？还是先多几秒布阵时间？）。
##
## 每条轨道：max 级数、costs 每级价格、以及 GameState 里派生的加成公式。
const UPGRADES := {
	"insight": {
		"name": "阅读产出", "glyph": "悟",
		"desc": "小魔女读得更快，体悟自动累积得更多",
		"effect": "+30% 体悟/秒", "max": 5,
		"costs": [40, 90, 170, 300, 460],
	},
	"ink": {
		"name": "纸笔效率", "glyph": "笔",
		"desc": "施法更省，纸笔自然回复更快",
		"effect": "+12% 纸笔回复", "max": 5,
		"costs": [50, 110, 200, 340, 520],
	},
	"power": {
		"name": "分身强化", "glyph": "身",
		"desc": "所有分身的攻击与生命一起提高",
		"effect": "+10% 攻/血", "max": 5,
		"costs": [60, 130, 240, 400, 600],
	},
	"prep": {
		"name": "开局准备", "glyph": "息",
		"desc": "第一个字出现得更晚，开局多几秒布阵",
		"effect": "+1.5 秒", "max": 4,
		"costs": [70, 150, 270, 430],
	},
	"speed": {
		"name": "加速上限", "glyph": "速",
		"desc": "提高战斗里能开到的倍速上限",
		"effect": "倍速 +1 档", "max": 2,
		"costs": [120, 300],
	},
	"level": {
		"name": "升级上限", "glyph": "阶",
		"desc": "分身能升到的等级上限 +1，解锁第 4/5 级",
		"effect": "上限 +1", "max": 2,
		"costs": [180, 420],
	},
}

## 升级轨道的显示顺序
const UPGRADE_ORDER := ["insight", "ink", "power", "prep", "speed", "level"]

const READ_BASE := 0.10
## 战斗里买纸笔：一次性，立刻加进当前关卡。
## 体悟主要该花在书屋里，所以这里刻意给得不划算。
const INK_PACK := {"cost": 45, "bonus": 12}
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


## 某一关的路线数组
static func level_routes(index: int) -> Array:
	var levels: Array = BASE_DATA["levels"]
	if index < 0 or index >= levels.size():
		return []
	return (levels[index] as Dictionary).get("routes", [])


## 某一关散落的文具（定义见 CLUTTER；实际坐标由 BattleField._build_props 解析）
static func level_clutter(index: int) -> Array:
	if not CLUTTER.has(index):
		return []
	return CLUTTER[index]


# --- 字体 ---
## 正文用无衬线（小字号清晰），标题用楷/宋（有书卷气）。
## 优先挑「系统里可能装了的」手写/古籍体，最后一定回落到雅黑之类的安全项，
## 所以这里只列名字、不分发字体文件，避免字体授权问题。
const FONT_SANS := [
	"Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC",
	"Noto Sans CJK SC", "Source Han Sans SC", "WenQuanYi Micro Hei", "SimHei",
]
const FONT_BOOK := [
	"LXGW WenKai", "霞鹜文楷", "KaiTi", "楷体", "STKaiti", "Kaiti SC", "Zhi Mang Xing",
	"Source Han Serif SC", "Noto Serif CJK SC", "Songti SC", "STSong", "SimSun",
]

static var _font_sans: SystemFont
static var _font_book: SystemFont


static func _make_system_font(names: Array) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(names)
	f.allow_system_fallback = true
	return f


static func font_sans() -> SystemFont:
	if _font_sans == null:
		_font_sans = _make_system_font(FONT_SANS)
	return _font_sans


## 标题字体：楷体优先，没有就回落到正文那套
static func font_book() -> SystemFont:
	if _font_book == null:
		_font_book = _make_system_font(FONT_BOOK + FONT_SANS)
	return _font_book
