# Start-LogCapture.ps1 — фоновый захват логов в папку logs/

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$LogDir = Join-Path $ProjectRoot "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$serverScript = Join-Path $PSScriptRoot "LogServer.ps1"
$watchScript = Join-Path $PSScriptRoot "Watch-Logs.ps1"

Write-Host "Starting log capture..." -ForegroundColor Cyan
Write-Host "  logs\game.log  <- Studio Output + HTTP from game" -ForegroundColor Green

Start-Process powershell -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$watchScript`""
) -WindowStyle Minimized

Start-Process powershell -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$serverScript`""
) -WindowStyle Minimized

Write-Host "Log capture started (2 minimized windows)." -ForegroundColor Green
