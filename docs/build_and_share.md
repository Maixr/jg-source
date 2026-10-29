# 发给别人试玩：两个包怎么用

## 一、一句话结论

| 你想怎么发 | 发哪个文件 | 对方怎么开始 |
|---|---|---|
| **发文件（推荐）** | `情感体悟-v0.1.10-win64.zip` | 解压 → **双击 `情感体悟-v0.1.10.exe`** |
| 发链接 | `web-v0.1.10.zip` | 上传到 itch.io → 把链接发给对方 |

> 文件名里的版号是脚本从 `core/unit_data.gd` 的 `GAME_VERSION` 读出来的，
> 不用手改。

### ❗ Web 包不能解压双击

`web-v0.1.10.zip` 里没有 exe。解压后双击 `index.html` 会白屏——
浏览器对 `file://` 下的 `.wasm` 有安全限制，必须经 HTTP 服务器。
它**只能**用来上传拿链接。

---

## 二、Windows 包（推荐）

```
<项目同级>\jg-build\情感体悟-v0.1.10-win64.zip
  └─ 情感体悟-v0.1.0.exe                 105.6 MB（数据已内嵌，单文件）
  └─ 请先读我.txt
```

- **不用安装**，不依赖 Godot，拷到任何 Windows 电脑双击就能跑。
- 首次启动 Windows 可能弹“**已保护你的电脑**”蓝框：点“更多信息”→“仍要运行”。
  原因：exe 没有代码签名证书（个人试玩版普遍没有，签名证书一年几千块）。
- 存档在 `%APPDATA%\Godot\app_userdata\jg\jg_save.json`，删掉就清空进度。

---

## 三、Web 包（要发链接时用）

```
<项目同级>\jg-build\web-v0.1.10.zip
```

### 本地自己看

```powershell
cd <项目同级>\jg-build\web
python -m http.server 8080
# 浏览器打开 http://127.0.0.1:8080
```

### 发给别人（换成公开链接）

| 平台 | 做法 |
|---|---|
| **itch.io**（最省事） | Create new project → Kind of project 选 **HTML** → 上传 zip → 勾 “This file will be played in the browser” |
| Netlify / Vercel | 把 `web` 文件夹拖进后台 |
| GitHub Pages | 推到仓库开 Pages |

用的是 **nothreads** 构建，**不需要** COOP/COEP 跨域隔离头，上面平台都能直接跑。

---

## 四、重新构建

```powershell
# Windows（解压双击即玩）
powershell -ExecutionPolicy Bypass -File tools\export_windows.ps1

# Web（发链接）
powershell -ExecutionPolicy Bypass -File tools\export_web.ps1
```

产物默认落在**项目同级目录**的 `jg-build\`：

```
<jg 的上级目录>\jg-build\
  情感体悟-v0.1.10.exe
  情感体悟-v0.1.10-win64.zip
  web\  +  web-v0.1.10.zip
```

想换输出目录就设 `JGBUILD`；找不到 Godot 就设 `GODOT_BIN`（或 `GODOT_DIR`）。

两个脚本都**从临时副本构建，不会改动**正在编辑器里打开的项目。
必须带 `-ExecutionPolicy Bypass`，否则系统执行策略会拦。

### 发包前改版号

只改 [unit_data.gd](../core/unit_data.gd) 顶部两行：

```gdscript
const GAME_TITLE := "情感体悟"     # 出包文件名用
const GAME_VERSION := "v0.1.10"    # 界面、标题栏、exe/zip 名都用它
```

打包脚本会自己正则读这两个常量，**不用再去改 `$exeName`**。

---

## 五、导出模板（换版本/换电脑时需要重装）

模板不在编辑器里，放这里：

```
%APPDATA%\Godot\export_templates\4.7.2.stable\
```

Web 需要：`web_nothreads_release.zip`、`web_nothreads_debug.zip`（各 9.8MB）
Windows 需要：`windows_release_x86_64.exe`、`windows_debug_x86_64.exe`（78MB + 98MB）

### 官方下载走 GitHub，国内可能只有 20KB/s

本机实际遇到。用镜像自己抽需要的文件（HTTP Range + 16 路并行，实测 Web 46 秒 / Windows 72 秒）：

```powershell
$env:TPL_URL = "https://ghfast.top/https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz"

# Web
python tools\fetch_templates.py fetch web_nothreads_release web_nothreads_debug version.txt

# Windows
python tools\fetch_templates.py fetch windows_release_x86_64 windows_debug_x86_64 version.txt

# 看整包清单
python tools\fetch_templates.py list
```

---

## 六、打包时自动处理的两个坑

### 1. 排除 AI 插件目录

`addons/godot_ai` 占 2.1MB（项目一半以上），而且会在玩家机器上启动本地 MCP 服务。预设里的 `exclude_filter` 已排除。

### 2. 剥离 `_mcp_game_helper` autoload

`project.godot` 里这行指向插件目录；目录被排除后，游戏一启动就报 “Failed loading autoload”。
两个脚本都会在副本里删掉这行再导出。

**自检**：`index.pck` 应在 1.3MB 左右，超过 2.5MB 脚本会黄字警告（插件漏进去了）。

---

## 七、发之前建议补的

- [ ] **无音效**，反馈里大概会出现“没声音”
- [ ] 首次启动的 SmartScreen 蓝框会让部分人以为有毒（已在 exe 旁边放了说明）
- [ ] 建议在分享文案里写一句“解压后双击 exe，蓝框点仍要运行”
- [ ] 存档在本地，清浏览器数据/重装会丢
