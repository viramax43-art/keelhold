# Watch-Logs.ps1 — копирует Output Studio (BridgeDefense) в logs/game.log

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$OutFile = Join-Path $ProjectRoot "logs\game.log"
$Filter = "BridgeDefense"

$logDirs = @(
    "$env:LOCALAPPDATA\Roblox\logs",
    "$env:LOCALAPPDATA\Roblox\Logs"
)

function Get-LatestRobloxLog {
    $latest = $null
    foreach ($dir in $logDirs) {
        if (-not (Test-Path $dir)) { continue }
        $f = Get-ChildItem $dir -Filter "*.log" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($f -and (-not $latest -or $f.LastWriteTime -gt $latest.LastWriteTime)) {
            $latest = $f
        }
    }
    return $latest
}

New-Item -ItemType Directory -Force -Path (Split-Path $OutFile) | Out-Null

if (-not (Test-Path $OutFile)) {
    Set-Content -Path $OutFile -Value "=== Studio watch -> game.log started $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" -Encoding UTF8
} else {
    Add-Content -Path $OutFile -Value "`n--- Studio watch restarted $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ---" -Encoding UTF8
}

Write-Host "Watching Roblox Studio Output -> $OutFile" -ForegroundColor Cyan

$currentFile = $null
$lastSize = 0

while ($true) {
    $latest = Get-LatestRobloxLog
    if ($latest) {
        if (-not $currentFile -or $currentFile.FullName -ne $latest.FullName) {
            $currentFile = $latest
            $lastSize = 0
            Add-Content -Path $OutFile -Value "--- Source: $($latest.FullName) ---" -Encoding UTF8
        }

        if ($latest.Length -gt $lastSize) {
            $stream = [System.IO.File]::Open($latest.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $stream.Seek($lastSize, [System.IO.SeekOrigin]::Begin) | Out-Null
            $reader = New-Object System.IO.StreamReader($stream)
            while (-not $reader.EndOfStream) {
                $line = $reader.ReadLine()
                if ($line -and $line.Contains($Filter)) {
                    Add-Content -Path $OutFile -Value $line -Encoding UTF8
                }
            }
            $lastSize = $stream.Position
            $reader.Close()
            $stream.Close()
        }
    }
    Start-Sleep -Milliseconds 750
}
