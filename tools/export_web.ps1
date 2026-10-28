# 构建可分享的 Web 试玩包
#
#   powershell -ExecutionPolicy Bypass -File D:\jg\tools\export_web.ps1
#
# 特点：从临时副本构建，**不会改动**正在编辑器里打开的项目。
# 产物：D:\jg-build\web\  +  D:\jg-build\jg-web-playtest.zip

$ErrorActionPreference = 'Stop'

$project = 'D:\jg'
$godot   = 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$outDir  = 'D:\jg-build\web'
$zipPath = 'D:\jg-build\jg-web-playtest.zip'
$preset  = 'Web'
$stage   = Join-Path $env:TEMP 'jg_export_stage'

if (-not (Test-Path $godot))   { throw "找不到 Godot：$godot" }
if (-not (Test-Path $project)) { throw "找不到项目：$project" }

# --- 0. 模板检查 ---
$tplRoot = Join-Path $env:APPDATA 'Godot\export_templates'
$need = @('web_nothreads_release.zip', 'web_nothreads_debug.zip')
$missing = @()
foreach ($n in $need) {
    if (-not (Get-ChildItem $tplRoot -Recurse -Filter $n -ErrorAction SilentlyContinue)) { $missing += $n }
}
if ($missing.Count -gt 0) {
    Write-Host "缺少导出模板：$($missing -join ', ')" -ForegroundColor Red
    Write-Host "先执行：python D:\jg\tools\fetch_templates.py fetch web_nothreads_release web_nothreads_debug version.txt"
    exit 1
}

# --- 1. 复制到临时目录（排除缓存与产物） ---
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
robocopy $project $stage /E /XD .godot build /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "复制项目失败，robocopy 退出码 $LASTEXITCODE" }
Write-Host "已复制到临时目录：$stage"

# --- 2. 剥离 MCP autoload（插件目录在导出时被排除，留着会启动报错） ---
$manifest = Join-Path $stage 'project.godot'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$lines = [System.IO.File]::ReadAllLines($manifest)
$kept = $lines | Where-Object { $_ -notmatch '^_mcp_game_helper\s*=' }
[System.IO.File]::WriteAllText($manifest, [string]::Join("`n", $kept) + "`n", $utf8)
Write-Host "已剥离 MCP autoload（$($lines.Count) 行 -> $($kept.Count) 行）"

# --- 3. 导出 ---
if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Write-Host "开始导出 Web（首次会重导入资源，请耐心等）……"
& $godot --headless --path $stage --export-release $preset (Join-Path $outDir 'index.html')
if ($LASTEXITCODE -ne 0) { throw "导出失败，退出码 $LASTEXITCODE" }

# --- 4. 校验：pck 过大说明插件漏进去了 ---
$pck = Join-Path $outDir 'index.pck'
if (-not (Test-Path $pck)) { throw "没有生成 index.pck，导出异常" }
$pckMB = (Get-Item $pck).Length / 1MB
if ($pckMB -gt 2.5) {
    Write-Host ("警告：index.pck 有 {0:N2} MB，偏大——插件可能没被排除" -f $pckMB) -ForegroundColor Yellow
} else {
    Write-Host ("index.pck = {0:N2} MB（正常，插件已排除）" -f $pckMB) -ForegroundColor Green
}

# --- 5. 打包 ---
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path (Join-Path $outDir '*') -DestinationPath $zipPath -CompressionLevel Optimal

# --- 6. 清理 + 汇报 ---
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Get-ChildItem $outDir -File | Sort-Object Length -Descending |
    Select-Object Name, @{ n = 'MB'; e = { [math]::Round($_.Length / 1MB, 2) } } |
    Format-Table -AutoSize
Write-Host ("打包完成：{0}  ({1:N1} MB)" -f $zipPath, ((Get-Item $zipPath).Length / 1MB)) -ForegroundColor Green
Write-Host ""
Write-Host "本地试玩：cd $outDir ; python -m http.server 8080  ->  http://127.0.0.1:8080"
Write-Host "发给别人：把上面的 zip 上传到 itch.io（项目类型选 HTML）或 Netlify"
