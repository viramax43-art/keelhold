# Build Commission map + backend, open Studio, Rojo serve, LogServer (profiles)
# ASCII-only messages so Windows PowerShell 5.x parses the file reliably.

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Rojo = "$env:USERPROFILE\.local\bin\rojo.exe"
$Lune = "$env:USERPROFILE\.local\bin\lune.exe"
$OutPlace = Join-Path $ProjectRoot "BridgeDefense_Commission.rbxl"

if (-not (Test-Path $Rojo)) {
    Write-Host "Rojo not found. Run .\install-tools.ps1 first." -ForegroundColor Red
    exit 1
}

# Fresh LogServer (needed for Gold/XP saves in Studio)
Get-NetTCPConnection -LocalPort 8765 -ErrorAction SilentlyContinue | ForEach-Object {
    Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Milliseconds 400

# Map extraction ONLY with -ExtractMap (normal start stays fast)
if ($args -contains "-ExtractMap" -and (Test-Path $Lune)) {
    Write-Host "Extracting Commission map..." -ForegroundColor Cyan
    Push-Location $ProjectRoot
    & $Lune run tools/extract-commission-map.luau
    Pop-Location
}

Write-Host "Building $OutPlace (latest scripts)..." -ForegroundColor Cyan
& $Rojo build "$ProjectRoot\lobby.project.json" -o $OutPlace
if ($LASTEXITCODE -ne 0) {
    Write-Host "rojo build failed" -ForegroundColor Red
    exit 1
}

Get-Process rojo -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

$studio = Get-ChildItem "$env:LOCALAPPDATA\Roblox\Versions" -Recurse -Filter "RobloxStudioBeta.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($studio) {
    Write-Host "Opening BridgeDefense_Commission.rbxl" -ForegroundColor Cyan
    Start-Process -FilePath $studio.FullName -ArgumentList "`"$OutPlace`""
} else {
    Write-Host "Roblox Studio not found - open $OutPlace manually" -ForegroundColor Yellow
}

if (Test-Path "$ProjectRoot\tools\Start-LogCapture.ps1") {
    & "$ProjectRoot\tools\Start-LogCapture.ps1"
}

Start-Sleep -Seconds 1
try {
    Invoke-WebRequest -Uri "http://127.0.0.1:8765/profile/0" -UseBasicParsing -TimeoutSec 2 | Out-Null
} catch {
    # 404 = server is alive
}

Start-Process -FilePath $Rojo -ArgumentList "serve","lobby.project.json" -WorkingDirectory $ProjectRoot -WindowStyle Normal

Write-Host ""
Write-Host "=== LAUNCH ===" -ForegroundColor Green
Write-Host "1. Opened: BridgeDefense_Commission.rbxl  (NOT AutoRecovery, NOT Commission_place)"
Write-Host "2. Rojo plugin -> Connect  (REQUIRED - otherwise code changes will not sync)"
Write-Host "3. F5 (Play)"
Write-Host "Studio progress: logs\profiles\<UserId>.json (LogServer) - also works via Studio fallback files"
Write-Host "Look in log for: Loaded Studio backup / Studio saved / Profile written to file"
