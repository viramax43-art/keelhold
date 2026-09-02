# Export-Logs.ps1 — одноразовый снимок логов Studio в logs/export-snapshot.log
# Основной файл во время теста: logs/game.log (LogServer, запускается с open-studio.ps1)

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$OutFile = Join-Path $ProjectRoot "logs\export-snapshot.log"
$Filter = "BridgeDefense"

$logDirs = @(
    "$env:LOCALAPPDATA\Roblox\logs",
    "$env:LOCALAPPDATA\Roblox\Logs"
)

$latestLog = $null
foreach ($dir in $logDirs) {
    if (Test-Path $dir) {
        $f = Get-ChildItem $dir -Filter "*.log" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($f -and (-not $latestLog -or $f.LastWriteTime -gt $latestLog.LastWriteTime)) {
            $latestLog = $f
        }
    }
}

New-Item -ItemType Directory -Force -Path (Split-Path $OutFile) | Out-Null

$header = @"
=== Bridge Defense Log Export ===
Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@

$body = @()

if ($latestLog) {
    $body += "Source: $($latestLog.FullName)"
    $body += ""
    $matched = Select-String -Path $latestLog.FullName -Pattern $Filter -SimpleMatch -ErrorAction SilentlyContinue
    if ($matched) {
        $body += ($matched | ForEach-Object { $_.Line })
    } else {
        $body += "(No lines matching '$Filter' in latest Roblox log)"
        $body += "Last 80 lines of Roblox log:"
        $body += (Get-Content $latestLog.FullName -Tail 80 -ErrorAction SilentlyContinue)
    }
} else {
    $body += "Roblox log folder not found."
}

# Also append ServerStorage export hint
$body += ""
$gameLog = Join-Path $ProjectRoot "logs\game.log"
if (Test-Path $gameLog) {
    $body += ""
    $body += "=== Contents of logs/game.log (last 150 lines) ==="
    $body += (Get-Content $gameLog -Tail 150 -ErrorAction SilentlyContinue)
}

$out = ($header, ($body -join "`n")) -join "`n`n"
Set-Content -Path $OutFile -Value $out -Encoding UTF8

Write-Host "Saved: $OutFile" -ForegroundColor Green
Write-Host "Lines: $(($body | Measure-Object -Line).Lines)" -ForegroundColor Cyan
