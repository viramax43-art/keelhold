# LogServer.ps1 — TCP: логи + сохранение профилей Studio (persist без DataStore API)

param(
    [int]$Port = 8765
)

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$LogDir = Join-Path $ProjectRoot "logs"
$LogFile = Join-Path $LogDir "game.log"
$ProfileDir = Join-Path $LogDir "profiles"

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
New-Item -ItemType Directory -Force -Path $ProfileDir | Out-Null

if (-not (Test-Path $LogFile)) {
    $header = "=== Bridge Defense game.log ===`nStarted: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`nPort: $Port`n"
    Set-Content -Path $LogFile -Value $header -Encoding UTF8
} else {
    Add-Content -Path $LogFile -Value "`n--- LogServer restarted $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ---" -Encoding UTF8
}

function Read-RequestBody {
    param([System.IO.StreamReader]$Reader)

    $headers = @{}
    $line = $Reader.ReadLine()
    while ($line -and $line.Length -gt 0) {
        $idx = $line.IndexOf(":")
        if ($idx -gt 0) {
            $name = $line.Substring(0, $idx).Trim().ToLower()
            $value = $line.Substring($idx + 1).Trim()
            $headers[$name] = $value
        }
        $line = $Reader.ReadLine()
    }

    $contentLength = 0
    if ($headers.ContainsKey("content-length")) {
        [void][int]::TryParse($headers["content-length"], [ref]$contentLength)
    }

    if ($contentLength -le 0) {
        return ""
    }

    $buffer = New-Object char[] $contentLength
    $read = 0
    while ($read -lt $contentLength) {
        $n = $Reader.Read($buffer, $read, $contentLength - $read)
        if ($n -le 0) { break }
        $read += $n
    }
    return -join $buffer
}

function Send-HttpResponse {
    param(
        [System.Net.Sockets.TcpClient]$Client,
        [int]$StatusCode = 200,
        [string]$ContentType = "text/plain",
        [string]$Body = "ok"
    )

    $statusText = switch ($StatusCode) {
        200 { "OK" }
        404 { "Not Found" }
        400 { "Bad Request" }
        default { "Error" }
    }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $response = "HTTP/1.1 $StatusCode $statusText`r`nContent-Type: $ContentType`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n"
    $stream = $Client.GetStream()
    $out = [System.Text.Encoding]::UTF8.GetBytes($response)
    $stream.Write($out, 0, $out.Length)
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush()
}

function Get-SafeUserId {
    param([string]$Raw)
    if ($Raw -match '^\d+$') { return $Raw }
    return $null
}

try {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
    $listener.Start()
} catch {
    Write-Host "LogServer: cannot bind port $Port" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    exit 1
}

Write-Host "LogServer listening on 127.0.0.1:$Port" -ForegroundColor Green
Write-Host "Writing logs to: $LogFile" -ForegroundColor Cyan
Write-Host "Profiles dir: $ProfileDir" -ForegroundColor Cyan

while ($true) {
    $client = $null
    try {
        $client = $listener.AcceptTcpClient()
        $stream = $client.GetStream()
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $false, 8192, $true)

        $requestLine = $reader.ReadLine()
        if (-not $requestLine) {
            Send-HttpResponse -Client $client -StatusCode 404 -Body "empty"
            continue
        }

        $parts = $requestLine.Split(" ")
        $method = $parts[0]
        $path = if ($parts.Length -gt 1) { $parts[1] } else { "/" }

        if ($method -eq "POST" -and ($path -eq "/log" -or $path -eq "/")) {
            $body = Read-RequestBody -Reader $reader
            if ($body -and $body.Trim().Length -gt 0) {
                Add-Content -Path $LogFile -Value $body -Encoding UTF8
            }
            Send-HttpResponse -Client $client -StatusCode 200 -Body "ok"
        }
        elseif ($method -eq "GET" -and $path -match '^/profile/(\d+)$') {
            $userId = Get-SafeUserId $Matches[1]
            $file = Join-Path $ProfileDir "$userId.json"
            if ($userId -and (Test-Path $file)) {
                $json = Get-Content -Path $file -Raw -Encoding UTF8
                Send-HttpResponse -Client $client -StatusCode 200 -ContentType "application/json" -Body $json
            } else {
                Send-HttpResponse -Client $client -StatusCode 404 -Body "missing"
            }
        }
        elseif ($method -eq "POST" -and $path -match '^/profile/(\d+)$') {
            $userId = Get-SafeUserId $Matches[1]
            $body = Read-RequestBody -Reader $reader
            if (-not $userId -or -not $body) {
                Send-HttpResponse -Client $client -StatusCode 400 -Body "bad"
            } else {
                $file = Join-Path $ProfileDir "$userId.json"
                Set-Content -Path $file -Value $body -Encoding UTF8
                Send-HttpResponse -Client $client -StatusCode 200 -Body "saved"
            }
        }
        else {
            Send-HttpResponse -Client $client -StatusCode 404 -Body "not found"
        }
    } catch {
        Write-Host "LogServer error: $($_.Exception.Message)" -ForegroundColor Red
    } finally {
        if ($client) {
            $client.Close()
        }
    }
}
