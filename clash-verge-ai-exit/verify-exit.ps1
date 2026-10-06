<#
verify-exit.ps1 - one command that produces the acceptance evidence for this package.

Run it while Clash Verge is running. It changes nothing.

WHY THESE TESTS
  * proxy IP         - the explicit proxy really reaches the AI exit
  * TUN coverage     - a request that BYPASSES every proxy setting still leaves from
                       the proxy IP, which is the only proof that TUN (or a
                       system-wide capture) is actually working. Clash Verge routes
                       ipinfo.io to the exit group, so asking ipinfo with proxy
                       settings disabled isolates exactly this question.
  * split tunnelling - a non-AI domain still leaves from the real IP (MATCH,DIRECT),
                       i.e. the setup is not proxying everything
  * exit country     - Cloudflare reports the expected country for the exit
  * DNS health       - resolution succeeds and returns fake-ip addresses
  * regional check   - the device agrees with the exit country (delegates to
                       check-windows-locale.ps1; the language list never blocks it)
  * fail-closed      - cannot be automated safely in service mode: the core is owned
                       by the Clash Verge service, so a non-elevated process cannot
                       stop it. Instructions are printed instead.

USAGE
  powershell -ExecutionPolicy Bypass -File .\verify-exit.ps1
  powershell -ExecutionPolicy Bypass -File .\verify-exit.ps1 -ExpectLoc TW
#>
param(
  [string]$Proxy = 'http://127.0.0.1:7897',
  [string]$ExpectLoc = 'TW',
  [int]$TimeoutSec = 20
)

$ErrorActionPreference = 'Continue'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ipinfo.io is routed to the AI exit group by the shipped rules, so it answers
# "did this request leave through the exit?" for any capture mode.
# Plain HTTP on purpose: the routing question does not need TLS, and some shells
# (and restricted sandboxes) have no HTTPS egress at all.
$AI_ECHO   = 'http://ipinfo.io/ip'
# a domain with no rule -> MATCH,DIRECT
$DIRECT_ECHO = 'http://api.ipify.org'

function Get-Ip([string]$url, [string[]]$curlArgs) {
  try {
    $out = & curl.exe @curlArgs -s -m $TimeoutSec $url 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $out) { return '' }
    return ($out | Select-Object -First 1).Trim()
  } catch { return '' }
}

Write-Host ''
Write-Host '=== exit verification ===' -ForegroundColor Cyan
Write-Host ("  proxy: {0}    expected country: {1}" -f $Proxy, $ExpectLoc)
Write-Host ''

$fail = 0
$rows = @()

# ---- 1. explicit / system proxy -------------------------------------------
$viaProxy = Get-Ip $AI_ECHO @('-x', $Proxy)
$okProxy = ($viaProxy -match '^\d{1,3}(\.\d{1,3}){3}$')
if (-not $okProxy) { $fail++ }
$rows += ,@('proxy path', $(if ($okProxy) { 'PASS' } else { 'FAIL' }), "ip=$viaProxy  (curl -x $Proxy)")

# ---- 2. TUN / system-wide capture (all proxy settings bypassed) -----------
$viaTun = Get-Ip $AI_ECHO @('--noproxy', '*')
$tunActive = ($viaTun -ne '' -and $viaTun -eq $viaProxy)
$rows += ,@('TUN coverage', $(if ($tunActive) { 'PASS' } else { 'INFO' }), "ip=$viaTun  (--noproxy '*')")

# ---- 3. split tunnelling: non-AI domain must be direct --------------------
$viaDirect = Get-Ip $DIRECT_ECHO @('--noproxy', '*')
$splitOk = ($viaDirect -ne '' -and $viaDirect -ne $viaProxy)
if (-not $splitOk) { $fail++ }
$rows += ,@('split tunnelling', $(if ($splitOk) { 'PASS' } else { 'FAIL' }), "ip=$viaDirect  (non-AI domain)")

# ---- 4. exit country via Cloudflare --------------------------------------
$trace = ''
$traceScheme = 'https'
try { $trace = (& curl.exe -x $Proxy -s -m $TimeoutSec 'https://claude.ai/cdn-cgi/trace' 2>$null) -join "`n" } catch { }
if (-not $trace) {
  # fall back to plain HTTP when this shell has no HTTPS egress
  $traceScheme = 'http'
  try { $trace = (& curl.exe -x $Proxy -s -m $TimeoutSec 'http://claude.ai/cdn-cgi/trace' 2>$null) -join "`n" } catch { }
}
$loc  = ([regex]::Match($trace, '(?m)^loc=(\S+)')).Groups[1].Value
$ipTr = ([regex]::Match($trace, '(?m)^ip=(\S+)')).Groups[1].Value
$okLoc = ($loc -eq $ExpectLoc)
if (-not $okLoc) { $fail++ }
$rows += ,@('exit country', $(if ($okLoc) { 'PASS' } else { 'FAIL' }), "loc=$loc ip=$ipTr via $traceScheme")

# ---- 5. HTTP version used through the proxy ------------------------------
$ver = ''
try { $ver = (& curl.exe -x $Proxy -s -o NUL -m $TimeoutSec -w '%{http_version}' 'https://claude.ai/' 2>$null) } catch { }
# HTTP/3 can only be observed over TLS. If this shell has no HTTPS egress the test is
# not testable - report INFO rather than inventing a pass or a failure.
$verTestable = ($ver -eq '1.1' -or $ver -like '2*' -or $ver -eq '3')
$okVer = ($ver -eq '1.1' -or $ver -like '2*')
if ($verTestable -and -not $okVer) { $fail++ }
$rows += ,@('no HTTP/3 via proxy',
  $(if (-not $verTestable) { 'INFO' } elseif ($okVer) { 'PASS' } else { 'FAIL' }),
  $(if (-not $verTestable) { 'not testable here (no HTTPS egress)' } else { "http_version=$ver" }))

# ---- 6. DNS health (fake-ip) --------------------------------------------
$dnsText = ''
$dnsOk = $false
try {
  $a = Resolve-DnsName 'claude.ai' -Type A -ErrorAction Stop | Where-Object { $_.IPAddress } | Select-Object -First 1
  $dnsText = [string]$a.IPAddress
  $dnsOk = ($dnsText -match '^198\.18\.')
} catch { $dnsText = '<resolution failed>' }
# Informational only: fake-ip answers can persist in the DNS cache (and in the
# resolver configuration) even while the core is stopped, so this row proves nothing
# on its own - it tells you whether lookups still resolve at all.
$rows += ,@('DNS (fake-ip)', 'INFO', "claude.ai -> $dnsText (fake-ip may persist in cache)")

# ---- 7. regional consistency -------------------------------------------
$locOut = ''
$locResult = ''
$locScript = Join-Path $scriptDir 'check-windows-locale.ps1'
if (Test-Path $locScript) {
  $locOut = (& powershell -NoProfile -ExecutionPolicy Bypass -File $locScript 2>&1) -join "`n"
  $locResult = ([regex]::Match($locOut, 'RESULT: (.*)')).Groups[1].Value.Trim()
}
$okReg = ($locResult -like 'all settings are consistent*')
if (-not $okReg) { $fail++ }
$rows += ,@('regional check', $(if ($okReg) { 'PASS' } else { 'FAIL' }), $locResult)

# ---- report -------------------------------------------------------------
Write-Host ('  {0,-20} {1,-6} {2}' -f 'test', 'result', 'evidence') -ForegroundColor Cyan
Write-Host ('  {0,-20} {1,-6} {2}' -f '----', '------', '--------')
foreach ($r in $rows) { Write-Host ('  {0,-20} {1,-6} {2}' -f $r[0], $r[1], $r[2]) }

Write-Host ''
if ($fail -gt 0 -and $viaProxy -eq '') {
  Write-Host "  HINT: nothing answered on $Proxy - is Clash Verge running?" -ForegroundColor Yellow
  Write-Host '        Start it, reload the profile, then run this script again.' -ForegroundColor DarkGray
  Write-Host ''
}
if ($viaTun -ne '' -and -not $tunActive) {
  Write-Host "  NOTE: TUN coverage is not active (bypassed request left from $viaTun)." -ForegroundColor DarkYellow
  Write-Host '        That is expected if TUN is intentionally off and every app is configured' -ForegroundColor DarkGray
  Write-Host '        explicitly - but then each app that touches AI services must be verified' -ForegroundColor DarkGray
  Write-Host '        individually (see proxy-logger.py in this folder).' -ForegroundColor DarkGray
  Write-Host ''
}

Write-Host '  Remaining manual checks (cannot be automated):' -ForegroundColor Cyan
Write-Host '    1. Browser: open https://claude.ai/cdn-cgi/trace and confirm ip= is the proxy IP'
Write-Host '       (curl passing proves nothing about the browser).'
Write-Host '    2. Clash Verge -> Connections: claude.ai must show the exit group, not DIRECT.'
Write-Host '       In service mode the mihomo log line is the authoritative proof, e.g.'
Write-Host '         [TCP] 127.0.0.1:58593(msedge.exe) --> claude.ai:443'
Write-Host '               match DomainKeyword(claude) using AI-Exit[<node>]'
Write-Host '    3. fail-closed: see SETUP.md section 14 (service mode makes stopping the'
Write-Host '       core impossible without the GUI).'

Write-Host ''
if ($fail -eq 0) {
  Write-Host '  RESULT: all automated checks passed.' -ForegroundColor Green
  exit 0
} else {
  Write-Host ("  RESULT: {0} automated check(s) failed." -f $fail) -ForegroundColor Red
  exit 1
}
