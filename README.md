# 情感体悟

一个 2D 塔防 + 养成的小游戏。用 Godot 4.7.2 制作。

> 这个世界存在魔法，「情感体悟」是通用货币，文字与故事具有生命，施法必须要有纸笔。
>
> 小魔女在炼药时不小心发生了爆炸，书屋被毁了，剧情文字跑了出去。
> 迫于无奈，小魔女只好去收集飘落的剧情，重建小屋。

**当前版本：v0.1.10（试玩版）**

---

## 怎么跑起来

1. 装 [Godot 4.7.2](https://godotengine.org/download)（标准版即可，不需要 .NET）
2. 用 Godot 打开本目录下的 `project.godot`
3. 按 **F5** 运行

第一次打开会自动导入资源，等十几秒。

---

## 玩法

- 地图上有条路，敌人（会跑的字）从左边往右边的「书」冲
- 花「纸笔」在路上 / 路旁放小纸人（施法分身）拦住它们
- 漏一个敌人扣 1 点剧情完整度，扣光就输
- 打赢获得「情感体悟」，用来养成（重建小屋、买纸笔补给）

### 两类格子（核心规则）

| 格子 | 位置 | 能放 | 效果 |
|---|---|---|---|
| **地面** | 就在路上 | 墨刃、纸盾 | 真的会站在路上挡人 |
| **高台** | 路旁 | 墨矢、疗愈符 | 输出和加血，够不着路 |

格子提示**只在你选了塔的时候出现**（平时不显示，免得棋盘太花）；
金色角标 = 地面格，绿色角标 = 高台格。射程用**方框**判定，和画出来的框完全一致。

### 四种分身

| 名字 | 位置 | 费用 | 特点 |
|---|---|---|---|
| 墨矢 | 高台 | 14 | 远程单体，主力输出 |
| 墨刃 | 地面 | 16 | 近身范围伤害，挡 2 个 |
| 纸盾 | 地面 | 18 | 血厚，挡 3 个，不攻击 |
| 疗愈符 | 高台 | 15 | 给附近分身回血 |

每个分身能升 2 次（共 3 级）。升级按钮会直接显示这一级 +多少攻 / +多少血。

### 敌人

| 名字 | 特点 |
|---|---|
| 躁 | 最基础，快而脆 |
| 狂 | 极快冲刺 |
| 疑 | 远程，会点你的塔 |
| 迷 | 慢、血厚、2 点护甲 |
| 执 | 8 点护甲，硬 |
| 晦 | 首领，远程 |

敌人会**优先扑向纸盾**：170 像素内有盾就穿过墨刃直奔过去。
有护甲的字外面会套一圈冷色环，不用记数字也能看出该用什么打。

---

## 目录结构

```
core/       数据表（数值/配色/关卡）与存档
  unit_data.gd      ★所有数值、关卡、路线都在这里，调平衡只改这个文件
  game_state.gd     体悟、小屋、离线收益、键位与音效开关（Autoload）
  audio.gd          音效播放（Autoload）：预加载、复音池、节流、静音
battle/     战斗
  battle_field.gd   战场：格子、索敌、固定步长模拟、绘制
  backdrop.gd       静态层：网格、纸纹、路面（只在换关/放置时重画）
  tower.gd          施法分身
  enemy.gd          文字敌人
ui/         界面
  main.gd, main.tscn   HUD、卷帘门养成、关卡选择、结算、按键设置
art/        美术与音频
  house/            小屋插画
  sfx/              ★音效（15 个小 wav，CC0，见 sfx/CREDITS.md）
docs/       文档
  操作说明.txt        给玩家看的说明书
  art_tasks.md        给美术的需求清单
  build_and_share.md  打包与分发说明
tools/      构建脚本
  export_windows.ps1  打 Windows 包
  export_web.ps1      打网页版
  fetch_templates.py  抓 Godot 导出模板（国内网络用）
  prepare_sfx.py      把原始音效素材处理成游戏用的小 wav
```

---

## 几个工程上的讲究

- **固定步长**：所有战斗逻辑都跑在 `UnitData.FIXED_DT`（1/60 秒）上，
  用累加器把帧 delta 攒成整数步。帧率、倍速、无头自检三种情况结果一致。
- **冷却保留余量**：冷却到点后是「加上间隔」而不是「重置为间隔」，
  否则帧率越高 DPS 越高，帧率就成了隐藏的难度系数。
- **静态层分离**：网格/纸纹/路面单独一层，只在换关和放/拆分身时重画；
  战场每帧只画会动的东西。
- **格子索引**：占用的格子存在字典里，放置和绘制都是 O(1) 查询，
  不再每次遍历整个分身数组。
- **HUD 节流**：数字变化只打 dirty 标记，界面按 8Hz 统一刷新，不跟 60Hz 战场。

---

## 开发自检（可以直接当 CI 用）

全部靠环境变量驱动，无头就能跑：

```powershell
# 平衡门禁：跑完 15 组（5 关 × 3 种升级策略），不达标退出码非 0
$env:JG_BALANCE=1; godot --headless --path .; echo "exit=$LASTEXITCODE"

# 格子几何：验证所有格子落在 64px 格点上、互不重叠
$env:JG_GRIDCHECK=1; godot --headless --path .

# 放置吸附 + 移除返还 + 清空存档（会还原存档）
$env:JG_SELFTEST=1; godot --headless --path .

# 直接进第 3 关并摆好测试布阵，可选自动截图
$env:JG_DEV_LEVEL=3; $env:JG_SHOT="D:\shot.png"; godot --path .

# 只截关卡选择页 / 看「选好塔正在找位置」的状态
$env:JG_SHOT="D:\select.png"; godot --path .
$env:JG_DEV_LEVEL=1; $env:JG_PENDING=bolt; $env:JG_SHOT="D:\placing.png"; godot --path .
```

调试入口会**自动关掉存档写入**，不会把你自己的进度改坏。

平衡门禁的判定标准在 `ui/main.gd` 的 `BALANCE_MIN_BASE` /
`BALANCE_MUST_WIN_UNUPGRADED` 里：前四关要求在「小屋=废墟、完全不升级」
的前提下也能过，第 5 关允许靠升级打过去。

---

## 打包给别人玩

```powershell
# Windows（解压双击 exe）
powershell -ExecutionPolicy Bypass -File tools\export_windows.ps1

# 网页版（上传拿链接）
powershell -ExecutionPolicy Bypass -File tools\export_web.ps1
```

产物默认在项目**同级**目录的 `jg-build\`（可用环境变量 `JGBUILD` 改）。
脚本会自己找 Godot（`GODOT_BIN` / `GODOT_DIR` / 同级目录 / `D:\.godot`），
版号从 `unit_data.gd` 的 `GAME_VERSION` 读，不用手动同步文件名。
细节见 `docs/build_and_share.md`。

> 两个脚本都会**从临时副本构建**，不会改动正在编辑器里打开的项目。
> 打包时会自动排除 `addons/godot_ai` 并移除它的 autoload，
> 也会排除 `art/fx_explosion.mp4` 这个暂时没用的素材。

---

## 依赖与授权

- **Godot 4.7.2**（MIT）
- **Godot AI** 插件（`addons/godot_ai`，MIT，见其目录内 LICENSE）
  用于在开发时让 AI 直接操作编辑器，**不参与游戏运行时**，打包时已排除。
- **音效**：IgnisForge Free SFX Sampler，**CC0 1.0**（公有领域，无需署名）。
  原始素材经 `tools/prepare_sfx.py` 处理，见 [art/sfx/CREDITS.md](art/sfx/CREDITS.md)。
- **字体**：不随仓库分发字体文件，只按名字指定系统字体
  （标题优先楷体，正文回落到雅黑/苹方等），避免字体授权问题。

游戏本体代码与美术请自行按需授权。

---

## 已知未做

- 只有第一本书《火柴人大陆》五关
- 没有背景音乐（音效已补齐）
- 安卓版尚未构建
- 美术仍是几何 + 汉字占位，等 `docs/art_tasks.md` 的图到位
