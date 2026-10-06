<#
proxy-bench.ps1 - Objective benchmark for candidate proxies (Windows / PowerShell)

Purpose: measure any candidate proxy (Bright Data, Oxylabs, IPRoyal, a VPS, ...)
         with the same metrics so you can compare side by side:
         exit IP / country / ASN, proxy ingress TCP RTT, TTFB to claude.ai,
         and how Cloudflare sees you (loc / colo).

Usage:
  .\proxy-bench.ps1 -Proxy "http://USER:PASS@HOST:PORT"
  .\proxy-bench.ps1 -Proxy "http://USER:PASS@HOST:PORT" -Runs 5
  .\proxy-bench.ps1 -Proxy "http://USER:PASS@HOST:PORT" -IncludeDirect

Note: this script connects to the candidate proxy DIRECTLY (it does not go through
      Clash), so you can evaluate a trial proxy before touching your Clash config.
#>
param(
  [Parameter(Mandatory = $true)][string]$Proxy,
  [int]$Runs = 3,
  [switch]$IncludeDirect
)

$ErrorActionPreference = 'Continue'

function Get-AvgMs([double[]]$Values) {
  if (-not $Values -or $Values.Count -eq 0) { return $null }
  return [math]::Round(($Values | Measure-Object -Average).Average, 0)
}

function Invoke-TimedCurl([string]$Url, [string]$ProxyArg) {
  $cargs = @()
  if ($ProxyArg) { $cargs += @('-x', $ProxyArg) }
  $cargs += @('-s', '-o', 'NUL', '-w', '%{time_connect}|%{time_starttransfer}|%{time_total}')
  $cargs += $Url
  $out = & curl.exe @cargs 2>$null
  $parts = "$out".Trim() -split '\|'
  if ($parts.Count -lt 3) { return $null }
  try {
    return [pscustomobject]@{
      Connect = [double]$parts[0]
      TTFB    = [double]$parts[1]
      Total   = [double]$parts[2]
    }
  } catch { return $null }
}

function Run-Profile([string]$Label, [string]$ProxyArg) {
  Write-Host ""
  Write-Host "===== $Label : latency to claude.ai ($Runs runs) =====" -ForegroundColor Cyan

  $targets = @(
    @{ Name = 'claude.ai/login'; Url = 'https://claude.ai/login' },
    @{ Name = 'claude.ai/';      Url = 'https://claude.ai/' }
  )

  $rows = @()
  foreach ($t in $targets) {
    $ttfbs = @()
    $conns = @()
    for ($i = 0; $i -lt $Runs; $i++) {
      $r = Invoke-TimedCurl $t.Url $ProxyArg
      if ($r) { $ttfbs += $r.TTFB; $conns += $r.Connect }
    }
    $avgT = Get-AvgMs $ttfbs
    $avgC = Get-AvgMs $conns
    if ($null -ne $avgT) {
      $rows += [pscustomobject]@{
        Target       = $t.Name
        ConnectSec   = $avgC
        TTFBSec      = $avgT
        TTFBms       = [math]::Round($avgT * 1000, 0)
      }
    } else {
      $rows += [pscustomobject]@{ Target = $t.Name; ConnectSec = 'FAILED'; TTFBSec = 'FAILED'; TTFBms = $null }
    }
  }
  $rows | Format-Table -AutoSize | Out-String -Width 120 | Write-Host

  Write-Host "===== $Label : exit identity (ipinfo) =====" -ForegroundColor Cyan
  $xargs = @()
  if ($ProxyArg) { $xargs = @('-x', $ProxyArg) }
  $info = & curl.exe @xargs -s https://ipinfo.io/json 2>$null
  if ("$info" -match '"ip"') { Write-Host $info } else { Write-Host "FAILED (proxy unreachable or timeout)" -ForegroundColor Yellow }

  Write-Host "===== $Label : how Cloudflare sees you (ip / loc / colo) =====" -ForegroundColor Cyan
  $trace = & curl.exe @xargs -s https://www.cloudflare.com/cdn-cgi/trace 2>$null
  if ("$trace" -match 'ip=') {
    ($trace -split "`n" | Where-Object { $_ -match '^(ip|loc|colo|warp)=' }) | ForEach-Object { Write-Host $_.Trim() }
  } else {
    Write-Host "FAILED" -ForegroundColor Yellow
  }
}

Write-Host "Proxy: $Proxy" -ForegroundColor Green

try {
  $u = [uri]$Proxy
  $h = $u.Host
  $pt = $u.Port
  $rtts = @()
  for ($i = 0; $i -lt $Runs; $i++) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $c = New-Object System.Net.Sockets.TcpClient
    $c.Connect($h, $pt)
    $sw.Stop()
    $c.Close()
    $rtts += $sw.Elapsed.TotalMilliseconds
  }
  $avg = Get-AvgMs $rtts
  Write-Host ("Proxy ingress TCP RTT ($h`:$pt) = $avg ms   <-- large means you are far from the proxy entry") -ForegroundColor Green
} catch {
  Write-Host "Proxy ingress TCP test failed: $($_.Exception.Message)" -ForegroundColor Yellow
}

Run-Profile 'PROXY' $Proxy

if ($IncludeDirect) {
  Run-Profile 'DIRECT (baseline)' $null
}

Write-Host ""
Write-Host "How to read the numbers:" -ForegroundColor Cyan
Write-Host "  ConnectSec large  -> your route to the proxy entry is long / detoured"
Write-Host "  TTFBms large      -> proxy-to-target latency (this dominates the browsing feel)"
Write-Host "  loc=TW            -> Cloudflare considers you to be in Taiwan (required)"
Write-Host "  colo=CDG          -> Paris (traffic detours through Europe); TPE/HKG means Asia (fast)"
Write-Host "  org=...           -> ASN; small shell ASNs tend to get more Cloudflare challenges"
