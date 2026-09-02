# Установка Rojo и плагина для Roblox Studio

$RojoDir = "$env:USERPROFILE\.local\bin"
New-Item -ItemType Directory -Force -Path $RojoDir | Out-Null

Write-Host "Скачиваю Rojo..." -ForegroundColor Cyan
$release = Invoke-RestMethod -Uri "https://api.github.com/repos/rojo-rbx/rojo/releases/latest" -UseBasicParsing
$zipAsset = $release.assets | Where-Object { $_.name -match 'windows-x86_64\.zip$' } | Select-Object -First 1
$zipPath = "$env:TEMP\rojo.zip"
Invoke-WebRequest -Uri $zipAsset.browser_download_url -OutFile $zipPath -UseBasicParsing
Expand-Archive -Path $zipPath -DestinationPath "$env:TEMP\rojo-extract" -Force
$rojoExe = Get-ChildItem "$env:TEMP\rojo-extract" -Filter "rojo.exe" -Recurse | Select-Object -First 1
Copy-Item $rojoExe.FullName "$RojoDir\rojo.exe" -Force
& "$RojoDir\rojo.exe" --version

Write-Host "Устанавливаю плагин Rojo в Studio..." -ForegroundColor Cyan
$pluginAsset = $release.assets | Where-Object { $_.name -match 'Rojo\.rbxm$' } | Select-Object -First 1
$pluginsDir = "$env:LOCALAPPDATA\Roblox\Plugins"
New-Item -ItemType Directory -Force -Path $pluginsDir | Out-Null
Invoke-WebRequest -Uri $pluginAsset.browser_download_url -OutFile "$pluginsDir\Rojo.rbxm" -UseBasicParsing

Write-Host "Готово. Rojo: $RojoDir\rojo.exe" -ForegroundColor Green
Write-Host "Перезапустите Roblox Studio, чтобы увидеть плагин Rojo."
