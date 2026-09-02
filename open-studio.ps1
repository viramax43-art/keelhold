# Clean relaunch: rebuild place, kill old Studio, open fresh + Rojo serve
# Usage: .\open-studio.ps1
#        .\open-studio.ps1 -ExtractMap   (slow: re-extract Commission map)

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Rojo = "$env:USERPROFILE\.local\bin\rojo.exe"
$Lune = "$env:USERPROFILE\.local\bin\lune.exe"
$OutPlace = Join-Path $ProjectRoot "BridgeDefense_Commission.rbxl"

if (-not (Test-Path $Rojo)) {
    Write-Host "Rojo not found. Run .\install-tools.ps1 first." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== CLEAN RESTART ===" -ForegroundColor Cyan
Write-Host "Closing old Studio / Rojo / LogServer..." -ForegroundColor Yellow

# Stop Studio so we never keep AutoRecovery / stale place in memory
Get-Process RobloxStudioBeta -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# Free ports
Get-NetTCPConnection -LocalPort 8765 -ErrorAction SilentlyContinue | ForEach-Object {
    Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue
}
Get-NetTCPConnection -LocalPort 34872 -ErrorAction SilentlyContinue | ForEach-Object {
    Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue
}
Get-Process rojo -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# Map extraction ONLY with -ExtractMap
if ($args -contains "-ExtractMap" -and (Test-Path $Lune)) {
    Write-Host "Extracting Commission map..." -ForegroundColor Cyan
    Push-Location $ProjectRoot
    & $Lune run tools/extract-commission-map.luau
    Pop-Location
}

Write-Host "Building $OutPlace ..." -ForegroundColor Cyan
& $Rojo build "$ProjectRoot\lobby.project.json" -o $OutPlace
if ($LASTEXITCODE -ne 0) {
    Write-Host "rojo build failed" -ForegroundColor Red
    exit 1
}

if (Test-Path "$ProjectRoot\tools\Start-LogCapture.ps1") {
    & "$ProjectRoot\tools\Start-LogCapture.ps1"
}

Start-Process -FilePath $Rojo -ArgumentList "serve","lobby.project.json" -WorkingDirectory $ProjectRoot -WindowStyle Normal
Start-Sleep -Seconds 1

$studio = Get-ChildItem "$env:LOCALAPPDATA\Roblox\Versions" -Recurse -Filter "RobloxStudioBeta.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($studio) {
    Write-Host "Opening BridgeDefense_Commission.rbxl" -ForegroundColor Cyan
    Start-Process -FilePath $studio.FullName -ArgumentList "`"$OutPlace`""
} else {
    Write-Host "Roblox Studio not found - open $OutPlace manually" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " WHAT TO DO IN STUDIO (every time)" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "1. Wait until place fully loads"
Write-Host "2. Plugins tab -> Rojo -> Connect  (localhost:34872)"
Write-Host "   Status must be Connected / Synced"
Write-Host "3. Press F5 (Play Solo)"
Write-Host ""
Write-Host "HOW CHANGES APPLY:" -ForegroundColor Yellow
Write-Host " A) Code edit in src\  -> Rojo Connected? then Shift+F5 (Stop) -> F5 (Play)"
Write-Host "    No need to rebuild .rbxl if Rojo is Connected."
Write-Host " B) Rojo NOT connected / broken sync / weird bugs:"
Write-Host "    Close Studio -> run .\open-studio.ps1 again"
Write-Host " C) NEVER open AutoRecovery / Commission_place.rbxm as the game"
Write-Host "    Only: BridgeDefense_Commission.rbxl"
Write-Host "========================================" -ForegroundColor Green
