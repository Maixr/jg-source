# Build the standalone Windows playtest package.
#
#   powershell -ExecutionPolicy Bypass -File tools\export_windows.ps1
#
# Builds from a temp copy, so the project opened in the editor is untouched.
# Output: $outDir\<title>-<version>.exe (+ manual) and a zip next to it.
#
# NOTE: keep this file ASCII-only. Windows PowerShell 5.1 reads .ps1 as ANSI
# unless it has a BOM, so Chinese literals here would come out mangled.
# Anything user-visible (title, version) is read from core/unit_data.gd.

$ErrorActionPreference = 'Stop'

$project = Split-Path $PSScriptRoot -Parent
$root    = Split-Path $project -Parent
$outRoot = if ($env:JGBUILD) { $env:JGBUILD } else { Join-Path $root 'jg-build' }
$outDir  = Join-Path $outRoot 'win'
$preset  = 'Windows'
$stage   = Join-Path $env:TEMP 'jg_export_stage'

# --- 1. locate Godot -------------------------------------------------------
$godot = $env:GODOT_BIN
if (-not $godot) {
    $exeNames = @(
        'Godot_v4.7.2-stable_win64_console.exe',
        'Godot_v4.7.2-stable_win64.exe',
        'Godot_v4.6-stable_win64_console.exe',
        'Godot_v4.5-stable_win64_console.exe',
        'godot_console.exe', 'godot.exe'
    )
    $roots = @($env:GODOT_DIR, $root, (Join-Path $env:LOCALAPPDATA 'Programs'), 'D:\.godot', 'C:\Godot')
    foreach ($r in $roots) {
        if (-not $r) { continue }
        foreach ($n in $exeNames) {
            $p = Join-Path $r $n
            if (Test-Path $p) { $godot = $p; break }
        }
        if ($godot) { break }
    }
}
if (-not $godot -or -not (Test-Path $godot)) {
    throw "Godot executable not found. Set GODOT_BIN or GODOT_DIR."
}
if (-not (Test-Path $project)) { throw "Project folder not found: $project" }

# --- 2. read title / version from the data table ---------------------------
$unitData = Join-Path $project 'core\unit_data.gd'
$title   = 'jg'
$version = 'v0.0.0'
if (Test-Path $unitData) {
    $m = Select-String -Path $unitData -Pattern 'const\s+GAME_TITLE\s*:=\s*"([^"]+)"'
    if ($m) { $title = $m.Matches[0].Groups[1].Value }
    $m = Select-String -Path $unitData -Pattern 'const\s+GAME_VERSION\s*:=\s*"([^"]+)"'
    if ($m) { $version = $m.Matches[0].Groups[1].Value }
}
$exeName = "$title-$version.exe"
$zipPath = Join-Path $outRoot "$title-$version-win64.zip"
Write-Host "Godot  : $godot"
Write-Host "Project: $project"
Write-Host "Build  : $title $version"

# --- 3. check export templates --------------------------------------------
$tplRoot = Join-Path $env:APPDATA 'Godot\export_templates'
$missing = @()
foreach ($n in @('windows_release_x86_64.exe', 'windows_debug_x86_64.exe')) {
    if (-not (Get-ChildItem $tplRoot -Recurse -Filter $n -ErrorAction SilentlyContinue)) { $missing += $n }
}
if ($missing.Count -gt 0) {
    Write-Host "Missing export templates: $($missing -join ', ')" -ForegroundColor Red
    Write-Host "Run: python tools\fetch_templates.py fetch windows_release_x86_64 windows_debug_x86_64 version.txt"
    exit 1
}

# --- 4. copy to temp ------------------------------------------------------
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
robocopy $project $stage /E /XD .godot build /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed with $LASTEXITCODE" }

# --- 5. strip the MCP autoload (its folder is excluded from the build) ----
$manifest = Join-Path $stage 'project.godot'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$lines = [System.IO.File]::ReadAllLines($manifest)
$kept = $lines | Where-Object { $_ -notmatch '^_mcp_game_helper\s*=' }
[System.IO.File]::WriteAllText($manifest, [string]::Join("`n", $kept) + "`n", $utf8)
Write-Host "Stripped MCP autoload ($($lines.Count) -> $($kept.Count) lines)"

# --- 6. export ------------------------------------------------------------
if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$exePath = Join-Path $outDir $exeName
Write-Host "Exporting Windows build..."
& $godot --headless --path $stage --export-release $preset $exePath
if ($LASTEXITCODE -ne 0) { throw "Export failed with $LASTEXITCODE" }
if (-not (Test-Path $exePath)) { throw "No exe produced" }

# --- 7. sanity: an exe with embedded data is far bigger than the bare stub -
$exeMB = (Get-Item $exePath).Length / 1MB
if ($exeMB -lt 50) {
    Write-Host ("WARNING: exe is only {0:N1} MB, data may not be embedded" -f $exeMB) -ForegroundColor Yellow
} else {
    Write-Host ("exe = {0:N1} MB (single file, data embedded)" -f $exeMB) -ForegroundColor Green
}

# --- 8. ship the manual next to the exe -----------------------------------
# the only .txt in docs\ is the player-facing manual
$manualSrc = Get-ChildItem (Join-Path $project 'docs') -Filter '*.txt' -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty FullName
if ($manualSrc -and (Test-Path $manualSrc)) {
    $body = [System.IO.File]::ReadAllText($manualSrc, [System.Text.Encoding]::UTF8)
    # manual is UTF-8 with BOM so Notepad on any Windows shows it correctly
    $utf8bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText((Join-Path $outDir 'readme-first.txt'), $body, $utf8bom)
    Write-Host "Included manual: readme-first.txt"
} else {
    Write-Host "WARNING: no manual found in docs\" -ForegroundColor Yellow
}

# --- 9. zip ---------------------------------------------------------------
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path (Join-Path $outDir '*') -DestinationPath $zipPath -CompressionLevel Optimal
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Get-ChildItem $outDir -File | Select-Object Name, @{ n = 'MB'; e = { [math]::Round($_.Length / 1MB, 1) } } | Format-Table -AutoSize
Write-Host ("Done: {0}  ({1:N1} MB)" -f $zipPath, ((Get-Item $zipPath).Length / 1MB)) -ForegroundColor Green
Write-Host ""
Write-Host "Share the zip: unzip -> double click the exe."
