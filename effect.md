# effect.md —— 表现层清单（给后面接手的人）

这个游戏的「手感」不是靠某一处特效撑起来的，是六层叠出来的。**加任何新内容时，
请逐层过一遍这张表**，不要只把玩法逻辑写完就交。

| 层 | 现在的实现 | 代码位置 | 缺什么 |
|---|---|---|---|
| 音效 | 18 个 CC0 wav + 池化播放 + 按事件节流 | `core/audio.gd`、`art/sfx/` | 背景音乐（BGM 还没有） |
| 粒子 | 战场：环 / 纸屑 / 火花；界面：按钮墨点 | `battle/battle_field.gd` 的 `_fx_*`、`ui/fx_layer.gd` | 主题化粒子（更多形状） |
| 转场 | 墨从点击处漫开盖住屏幕，切换后再化开 | `ui/ink_transition.gd` | 更多转场（翻页、书页撕裂） |
| UI 反馈 | 按钮按下墨点、结算淡入、抽屉/门开合动画 | `ui/main.gd`、`ui/home_screen.gd` | 数值滚动、卡片弹出 |
| 画面反馈 | 屏幕轻震、书本闪红、飘字、墨点飞溅 | `battle/battle_field.gd` | — |
| 美术 | 程序化线稿（文具/图标/书架/门/纸纹） | `core/ink_art.gd`、`core/icons.gd`、`ui/home_screen.gd` | 真正的插画（见 `docs/art_tasks.md`） |

---

## 一、加一个新事件时，检查这 5 条

假设你要加「某种字会分裂成两个」。除了逻辑，问自己：

1. **有声音吗？** 分裂时该响一下（`_sfx_var("split", -8)`），节流是否够。
2. **有粒子吗？** 分裂点该有环或墨点（`_fx_ring(...)`）。
3. **有画面反馈吗？** 屏幕要不要轻震（`_shake`）。
4. **玩家看得懂吗？** 要不要飘字（`_flash_text`）说明发生了什么。
5. **界面文案讲了吗？** `docs/操作说明.txt` 和关卡规则要不要补一句。

这 5 条都过了，才算「做完」。只做第 1 条就提交，下一个人还得返工。

---

## 二、怎么加音效

1. 在 `tools/prepare_sfx.py` 顶部的 `EVENTS` 表里加一行：
   `"split": ("laser_10.wav", -16.0, 0.20)` → 名字 / 素材 / 峰值 dB / 最长秒数
2. 跑 `python tools\prepare_sfx.py --src <素材目录> --out art\sfx`
   （脚本会统一做：去静音、降采样到 22050 单声道、按事件归一化、截断 + 淡出）
3. 在 `core/audio.gd` 的 `KNOWN` 数组里加上这个名字（导出包里列目录可能失败，靠它兜底）
4. 需要节流就在 `MIN_GAP` 里加毫秒（战斗类事件建议 55~120）
5. 代码里调 `_sfx("split", -8)` 或 `_sfx_var("split", -8)`（带随机音高）

**原则**：同一秒内可能发生十几次的事件（命中、出手）必须**压音量 + 节流**。
不压的话，塔一多就变成噪音 —— 这是最常见的「音效做了但很难听」的原因。

素材必须是 CC0 或已获授权，并在 `art/sfx/CREDITS.md` 里登记来源与事件对应关系。

---

## 三、怎么加粒子

### 战场（世界坐标）

`battle/battle_field.gd` 里有一个 `fx` 数组，元素是字典，`kind` 决定画法：

```gdscript
_fx_ring(pos, color, 半径, 时长)      # 一圈扩散的环：放置/升级/漏字
_fx_shards(pos, color, 数量)          # 纸屑：移除分身，带旋转和重力
_fx_sparks(pos, color, 数量)          # 碎光：升级时往上飘
```

加一种新粒子：
1. 在 `_draw_fx()` 的 `match` 里加一个分支（画法自己写）
2. 在 `_update_effects()` 里加运动规则（如果需要位移）
3. 在触发点调用一个 `_fx_xxx()` 包装函数

注意 `fx` 数组每帧都会 `filter` 掉过期元素，字典必须带 `t`（已存活）和 `dur`（总时长）。

### 界面（屏幕坐标）

`ui/fx_layer.gd` 是盖在所有面板之上的全屏 Control（`mouse_filter=IGNORE`、`z_index=100`），
只在有粒子时 `_process`，静止零开销。

```gdscript
fx_layer.puff(全局坐标, 颜色, 数量, 速度)
```

`_make_button()` 已经给**所有**按钮接了 `button_down` → 自动喷墨点，
新加的按钮只要用 `_make_button()` 创建就自动有反馈。

---

## 四、怎么加转场

```gdscript
transition.play(func(): 真正要做的切换, 点击位置)   # 播放，切换在遮罩最满那一帧执行
transition.busy                                    # 动画中，可据此忽略输入
transition.debug_hold(0.5, Vector2(800, 450))      # 调试：把画面钉在某个进度截图
```

**约定**：
- 所有「界面之间的跳转」都走 `_play_transition(...)`，不要硬切。
- `_start_level()` / `_show_level_select()` / `_show_home()` / `_show_house()` 本身保持**同步**，
  这样自检和调试入口可以直接调用，不会被动画时序干扰。转场只包在给玩家用的
  `_on_level_pressed()` / `_back_to_select()` / `_on_home_levels()` 等处理器里。
- 切换动作要能重复执行不出错（中途不要依赖上一帧状态）。

加新转场：再写一个和 `ink_transition.gd` 同接口的节点（`play(callable)` + `busy`），
在 `main.gd` 里按场景选用。

---

## 五、货币图标

`core/icons.gd` 里只有两个函数：`draw_insight()`（四角星）和 `draw_ink()`（墨滴），
由 `ui/icon_badge.gd` 这个 Control 包装成能塞进 HBox 的徽标：

```gdscript
row.add_child(IconBadge.new("insight", 10.0, Color(0.91, 0.66, 0.76)))
row.add_child(IconBadge.new("ink", 11.0, UnitData.ORANGE))
```

**想换成开源图标库（game-icons.net 之类）时**：
- 图标本身就是十几像素，靠的是**轮廓干净**，不是细节多；彩色矢量图标反而会和
  全线的线稿风格打架，先在小尺寸下对比再决定。
- SVG 可以直接当纹理用（Godot 支持 SVG 导入），但每个图标要单独确认授权并在
  `CREDITS` 里署名（game-icons 是 CC-BY 3.0，**必须署名**）。
- 换图标只需替换 `Icons.draw_ink()` / `Icons.draw_insight()` 两个函数体，
  调用方不用动。

---

## 六、现已实现的事件对照表

| 事件 | 音效 | 粒子 | 画面 | 转场 |
|---|---|---|---|---|
| 放置分身 | place | 环 + 碎光 | 飘字扣费 | — |
| 升级分身 | upgrade | 环 + 碎光 | 飘字等级 | — |
| 移除分身 | remove | 纸屑 | 飘字退款 | — |
| 远程出手 | fire（70ms 节流） | 投射物轨迹 | — | — |
| 近身出手 | swing（90ms） | — | 分身闪白 | — |
| 敌人打分身 | enemy_attack（120ms） | 投射物 | — | — |
| 击杀 | die | 墨点飞溅 | — | — |
| 漏字 | leak | 红色环 | 书本闪红 + 轻震 + 飘字 | — |
| 新字出现 | card | — | 右上卡片 | — |
| 首领登场 | boss | — | — | — |
| 首页 → 选关 | ui_click | 按钮墨点 | 书抽出 | 墨色转场 |
| 首页 → 书屋 | drawer（门） | 按钮墨点 | 门推开 + 暖光 | 墨色转场 |
| 选关 → 战斗 | ui_click | 按钮墨点 | — | 墨色转场 |
| 战斗 → 选关 | ui_back | 按钮墨点 | — | 墨色转场 |
| 结算 | win / lose | — | 面板淡入 | — |
| 书屋升级 | upgrade | 按钮墨点 | 数值刷新 | — |

---

## 七、已知欠账（按性价比排）

1. **背景音乐**：一条 CC0 循环 + 战斗/书屋两个变体，能立刻把氛围拉满。
2. **真正的插画**：现在首页/书屋用的还是 `art/house/house_intact.jpg`；
   `docs/art_tasks.md` 里列了清单。
3. **数值滚动**：体悟/纸笔的数字现在是直接跳变，滚动一下会高级不少。
4. **卡片弹出动画**：右下角敌人卡片目前只淡入。
5. **更多转场**：翻页、书页撕开都适合这个题材。
6. **图标**：如果愿意接受 CC-BY，可以换 game-icons 的成套图标。

---

## 八、踩过的坑（血泪，别重复）

1. **新增 `class_name` 后必须让编辑器扫一次**
   `godot --headless --editor --quit --path .`（带 `JG_EDITOR=1` 免得写存档）。
   纯 `--path` 的游戏运行**不会**重扫脚本，会报
   `Could not find type "Xxx" in the current scope` 并挂住。
2. **GDScript 的 lambda 按值捕获**
   `var n = 0; func(): n += 1` 改的是副本。要用数组/字典这种引用类型做计数器。
   （`_run_transition_test()` 里踩过，测试一直 FAIL。）
3. **Control 不给尺寸就是 0×0**
   新建的 Control 面板必须 `set_anchors_preset(PRESET_FULL_RECT)`，
   否则 `_draw` 什么都不显示（首页第一版就是这样白屏的）。
4. **全屏面板要有不透明底**
   否则下面战场的格子和书会透上来；`_hide_all_screens()` 里也要把 `field.visible` 关掉。
5. **调试入口必须不写存档，而且守卫要放在 Autoload**
   在 `GameState._ready()` 里检测 `JG_*` 环境变量（`DEV_ENV` 数组），
   不能只在 `main.gd` 里判断 —— `main.gd` 解析失败过，那时守卫不会执行。
6. **无头截图要等渲染**
   `JG_SHOT` 走 `_run_shot()`，默认等 1.8 秒；开了动画的界面用 `JG_SHOT_DELAY` 调大。
7. **别用 `[string]::Join($arrayList, "`n")` 拼文件**（PowerShell 会解析成
   ToString 重载，把整个文件写成一行）。用 `($lines -join "`n")` 并检查写入后的大小。

---

## 九、验证

改完表现层，至少跑这几条（都是无头、可进 CI）：

```powershell
cd <项目目录>
$env:JG_BALANCE=1;    godot --headless --path .   # 平衡门禁，15 项，失败退出码 1
$env:JG_GRIDCHECK=1;  godot --headless --path .
$env:JG_SELFTEST=1;   godot --headless --path .
$env:JG_SHIELDTEST=1; godot --headless --path .   # 穿盾回归
$env:JG_TRANSTEST=1;  godot --headless --path .   # 转场流程
```

截图（会自动把画面存成 PNG，不弹窗口）：

```powershell
$env:JG_HOME=1;  $env:JG_SHOT=".\shot_home.png";  godot --path .   # 首页
$env:JG_HOUSE=1; $env:JG_SHOT=".\shot_house.png"; godot --path .   # 书屋
$env:JG_SHOT=".\shot_select.png";                 godot --path .   # 选关
$env:JG_DEV_LEVEL=1; $env:JG_SHOT=".\shot_battle.png"; godot --path .
$env:JG_TRANS=0.55; $env:JG_SHOT=".\shot_trans.png"; godot --path . # 转场钉在 55%
```

全部这些入口都会把存档设成只读，跑完不会动玩家进度。
