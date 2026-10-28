# 构建 Windows 试玩包：解压 -> 双击 exe 即玩
#
#   powershell -ExecutionPolicy Bypass -File D:\jg\tools\export_windows.ps1
#
# 产物：D:\jg-build\win\情感体悟-v0.1.0.exe + 操作说明.txt
#       D:\jg-build\情感体悟-v0.1.0-win64.zip
# 特点：从临时副本构建，不动正在编辑器里打开的项目；数据内嵌在 exe 里。

$ErrorActionPreference = 'Stop'

$project = 'D:\jg'
$godot   = 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$outDir  = 'D:\jg-build\win'
$preset  = 'Windows'
$stage   = Join-Path $env:TEMP 'jg_export_stage'
$exeName = '情感体悟-v0.1.3.exe'
$zipPath = 'D:\jg-build\情感体悟-v0.1.3-win64.zip'
$utf8bom = New-Object System.Text.UTF8Encoding($true)

if (-not (Test-Path $godot))   { throw "找不到 Godot：$godot" }
if (-not (Test-Path $project)) { throw "找不到项目：$project" }

# --- 0. 模板检查 ---
$tplRoot = Join-Path $env:APPDATA 'Godot\export_templates'
$missing = @()
foreach ($n in @('windows_release_x86_64.exe', 'windows_debug_x86_64.exe')) {
    if (-not (Get-ChildItem $tplRoot -Recurse -Filter $n -ErrorAction SilentlyContinue)) { $missing += $n }
}
if ($missing.Count -gt 0) {
    Write-Host "缺少 Windows 导出模板：$($missing -join ', ')" -ForegroundColor Red
    Write-Host "先执行：python D:\jg\tools\fetch_templates.py fetch windows_release_x86_64 windows_debug_x86_64 version.txt"
    exit 1
}

# --- 1. 复制到临时目录 ---
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
robocopy $project $stage /E /XD .godot build /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "复制项目失败，robocopy 退出码 $LASTEXITCODE" }

# --- 2. 剥离 MCP autoload ---
$manifest = Join-Path $stage 'project.godot'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$lines = [System.IO.File]::ReadAllLines($manifest)
$kept = $lines | Where-Object { $_ -notmatch '^_mcp_game_helper\s*=' }
[System.IO.File]::WriteAllText($manifest, [string]::Join("`n", $kept) + "`n", $utf8)
Write-Host "已剥离 MCP autoload（$($lines.Count) 行 -> $($kept.Count) 行）"

# --- 3. 导出 ---
if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$exePath = Join-Path $outDir $exeName
Write-Host "开始导出 Windows……"
& $godot --headless --path $stage --export-release $preset $exePath
if ($LASTEXITCODE -ne 0) { throw "导出失败，退出码 $LASTEXITCODE" }
if (-not (Test-Path $exePath)) { throw "没有生成 exe，导出异常" }

# --- 4. 校验：内嵌数据的 exe 应该远大于空壳模板 ---
$exeMB = (Get-Item $exePath).Length / 1MB
if ($exeMB -lt 50) {
    Write-Host ("警告：exe 只有 {0:N1} MB，数据可能没内嵌进去" -f $exeMB) -ForegroundColor Yellow
} else {
    Write-Host ("exe = {0:N1} MB（数据已内嵌，单文件可运行）" -f $exeMB) -ForegroundColor Green
}

# --- 5. 附带操作说明书 ---
$manualSrc = Join-Path $project 'docs\操作说明.txt'
if (Test-Path $manualSrc) {
    $body = [System.IO.File]::ReadAllText($manualSrc, [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText((Join-Path $outDir '操作说明.txt'), $body, $utf8bom)
    Write-Host "已附带 操作说明.txt"
} else {
    Write-Host "警告：没找到 docs\操作说明.txt，包里将没有说明书" -ForegroundColor Yellow
}

# --- 6. 打包 ---
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path (Join-Path $outDir '*') -DestinationPath $zipPath -CompressionLevel Optimal
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Get-ChildItem $outDir -File | Select-Object Name, @{ n = 'MB'; e = { [math]::Round($_.Length / 1MB, 1) } } | Format-Table -AutoSize
Write-Host ("打包完成：{0}  ({1:N1} MB)" -f $zipPath, ((Get-Item $zipPath).Length / 1MB)) -ForegroundColor Green
Write-Host ""
Write-Host "发给别人：发这个 zip。对方解压 -> 双击 exe -> 看 操作说明.txt"
