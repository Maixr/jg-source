# Build the shareable Web playtest package.
#
#   powershell -ExecutionPolicy Bypass -File tools\export_web.ps1
#
# Builds from a temp copy, so the project opened in the editor is untouched.
# Output: $outRoot\web\ (index.html + pck) and a zip next to it.
#
# NOTE: keep this file ASCII-only. Windows PowerShell 5.1 reads .ps1 as ANSI
# unless it has a BOM, so Chinese literals here would come out mangled.

$ErrorActionPreference = 'Stop'

$project = Split-Path $PSScriptRoot -Parent
$root    = Split-Path $project -Parent
$outRoot = if ($env:JGBUILD) { $env:JGBUILD } else { Join-Path $root 'jg-build' }
$outDir  = Join-Path $outRoot 'web'
$preset  = 'Web'
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

$unitData = Join-Path $project 'core\unit_data.gd'
$title   = 'jg'
$version = 'v0.0.0'
if (Test-Path $unitData) {
    $m = Select-String -Path $unitData -Pattern 'const\s+GAME_TITLE\s*:=\s*"([^"]+)"'
    if ($m) { $title = $m.Matches[0].Groups[1].Value }
    $m = Select-String -Path $unitData -Pattern 'const\s+GAME_VERSION\s*:=\s*"([^"]+)"'
    if ($m) { $version = $m.Matches[0].Groups[1].Value }
}
$zipPath = Join-Path $outRoot "web-$version.zip"

# --- 2. check export templates --------------------------------------------
$tplRoot = Join-Path $env:APPDATA 'Godot\export_templates'
$need = @('web_nothreads_release.zip', 'web_nothreads_debug.zip')
$missing = @()
foreach ($n in $need) {
    if (-not (Get-ChildItem $tplRoot -Recurse -Filter $n -ErrorAction SilentlyContinue)) { $missing += $n }
}
if ($missing.Count -gt 0) {
    Write-Host "Missing export templates: $($missing -join ', ')" -ForegroundColor Red
    Write-Host "Run: python tools\fetch_templates.py fetch web_nothreads_release web_nothreads_debug version.txt"
    exit 1
}

# --- 3. copy to temp ------------------------------------------------------
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
robocopy $project $stage /E /XD .godot build /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed with $LASTEXITCODE" }

# --- 4. strip the MCP autoload (its folder is excluded from the build) ----
$manifest = Join-Path $stage 'project.godot'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$lines = [System.IO.File]::ReadAllLines($manifest)
$kept = $lines | Where-Object { $_ -notmatch '^_mcp_game_helper\s*=' }
[System.IO.File]::WriteAllText($manifest, [string]::Join("`n", $kept) + "`n", $utf8)
Write-Host "Stripped MCP autoload ($($lines.Count) -> $($kept.Count) lines)"

# --- 5. export ------------------------------------------------------------
if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Write-Host "Exporting Web build (first run re-imports assets, be patient)..."
& $godot --headless --path $stage --export-release $preset (Join-Path $outDir 'index.html')
if ($LASTEXITCODE -ne 0) { throw "Export failed with $LASTEXITCODE" }

# --- 6. sanity: a bloated pck means the dev addon leaked into the build ---
$pck = Join-Path $outDir 'index.pck'
if (-not (Test-Path $pck)) { throw "No index.pck produced" }
$pckMB = (Get-Item $pck).Length / 1MB
if ($pckMB -gt 2.5) {
    Write-Host ("WARNING: index.pck is {0:N2} MB - the dev addon may have leaked in" -f $pckMB) -ForegroundColor Yellow
} else {
    Write-Host ("index.pck = {0:N2} MB (ok)" -f $pckMB) -ForegroundColor Green
}

# --- 7. zip ---------------------------------------------------------------
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path (Join-Path $outDir '*') -DestinationPath $zipPath -CompressionLevel Optimal
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Get-ChildItem $outDir -File | Sort-Object Length -Descending |
    Select-Object Name, @{ n = 'MB'; e = { [math]::Round($_.Length / 1MB, 2) } } |
    Format-Table -AutoSize
Write-Host ("Done: {0}  ({1:N1} MB)" -f $zipPath, ((Get-Item $zipPath).Length / 1MB)) -ForegroundColor Green
Write-Host ""
Write-Host "Local test: cd `"$outDir`" ; python -m http.server 8080  ->  http://127.0.0.1:8080"
Write-Host "To share: upload the zip to itch.io (project kind: HTML) or Netlify."
