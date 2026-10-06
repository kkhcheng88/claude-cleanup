<#
install.ps1 - install the "AI account fixed exit" Clash Verge setup on this PC.

WHAT IT DOES
  1. Resolves the CURRENT Clash Verge profile and the random uid filenames of
     its 5 enhancement files (merge / rules / proxies / groups / script) from
     profiles.yaml. Those uid names differ on every PC, so nothing is hardcoded.
  2. Backs up profiles.yaml and every file it will touch.
  3. Renders configs\*.template.yaml with your proxy details and writes them
     into the resolved files (plus mobile-clash.yaml for phones/tablets).
  4. Validates the result with the bundled verge-mihomo.exe when available.
  5. Optionally installs the codex-p / claude-p launchers into %APPDATA%\npm.

USAGE
  # interactive (prompts for host/port/user/password)
  powershell -ExecutionPolicy Bypass -File .\install.ps1 -IncludeMainProfile

  # non-interactive
  powershell -ExecutionPolicy Bypass -File .\install.ps1 -IncludeMainProfile `
      -ProxyHost 203.0.113.10 -ProxyPort 50100 -ProxyUser myuser -ProxyPassword secret

  # or keep the values in a local file (never commit it - see .gitignore)
  powershell -ExecutionPolicy Bypass -File .\install.ps1 -IncludeMainProfile -SecretsFile .\local-secrets.psd1

  local-secrets.psd1 format:
    @{
      Host     = '203.0.113.10'
      Port     = 50100
      User     = 'myuser'
      Password = 'secret'
      NodeName = 'ProxySeller-TW1'   # optional
    }

NOTES
  * -IncludeMainProfile overwrites the CURRENT profile file. It refuses to run
    unless that profile is a LOCAL profile (never overwrite a subscription).
  * Everything written is UTF-8 WITHOUT BOM (a BOM breaks the mihomo YAML parser).
#>
param(
  [string]$VergeDir = "$env:APPDATA\io.github.clash-verge-rev.clash-verge-rev",
  [string]$ProxyHost,
  [int]$ProxyPort = 0,
  [string]$ProxyUser,
  [string]$ProxyPassword,
  [string]$NodeName,
  [string]$SecretsFile,
  [switch]$IncludeMainProfile,
  [switch]$SkipLaunchers,
  [switch]$SkipVergeSettings,
  [switch]$InstallService
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configDir = Join-Path $scriptDir 'configs'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Fail([string]$msg) {
  Write-Host ''
  Write-Host "ERROR: $msg" -ForegroundColor Red
  exit 1
}
function Step([string]$msg) { Write-Host ''; Write-Host "=== $msg ===" -ForegroundColor Cyan }

Step 'Clash Verge "AI account fixed exit" installer'
Write-Host "package   : $scriptDir"
Write-Host "verge dir : $VergeDir"

if (-not (Test-Path $configDir)) { Fail "configs folder not found next to this script: $configDir" }

# ---------------------------------------------------------------- secrets ----
if ($SecretsFile) {
  if (-not (Test-Path $SecretsFile)) { Fail "secrets file not found: $SecretsFile" }
  $s = Import-PowerShellDataFile -Path $SecretsFile
  if ($s.Host)     { $ProxyHost = $s.Host }
  if ($s.Port)     { $ProxyPort = [int]$s.Port }
  if ($s.User)     { $ProxyUser = $s.User }
  if ($s.Password) { $ProxyPassword = $s.Password }
  if ($s.NodeName) { $NodeName = $s.NodeName }
  Write-Host "secrets   : loaded from $(Split-Path -Leaf $SecretsFile)"
}

if (-not $NodeName)     { $NodeName = 'ProxySeller-TW1' }
if (-not $ProxyHost)    { $ProxyHost = Read-Host 'Proxy host (IP or hostname)' }
if (-not $ProxyPort -or $ProxyPort -le 0) {
  $p = Read-Host 'Proxy port'
  $ProxyPort = [int]$p
}
if (-not $ProxyUser)    { $ProxyUser = Read-Host 'Proxy username' }
if (-not $ProxyPassword) {
  $sec = Read-Host 'Proxy password' -AsSecureString
  $ProxyPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
}
if (-not $ProxyHost -or -not $ProxyPort -or -not $ProxyUser -or -not $ProxyPassword) {
  Fail 'proxy host / port / user / password must all be provided'
}

# ------------------------------------------------------------- locate verge --
$profilesYaml = Join-Path $VergeDir 'profiles.yaml'
$profDir      = Join-Path $VergeDir 'profiles'
if (-not (Test-Path $profilesYaml)) {
  Fail @"
profiles.yaml not found at $profilesYaml
       Install Clash Verge Rev, start it once, create a LOCAL profile, then re-run.
"@
}

$running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'clash-verge|verge-mihomo' })
if ($running.Count -gt 0) {
  Write-Host ''
  Write-Host "WARNING: Clash Verge seems to be running ($((($running | Select-Object -ExpandProperty ProcessName) | Sort-Object -Unique) -join ', '))." -ForegroundColor Yellow
  Write-Host '         Changes may be overwritten. Close it completely (tray -> Exit) if possible.' -ForegroundColor Yellow
} else {
  # A restricted shell cannot always enumerate other processes, so "no process found"
  # is not proof that the app is closed. The app log timestamp is a second signal.
  $logFile = Join-Path $VergeDir 'logs\latest.log'
  if (Test-Path $logFile) {
    $age = (Get-Date) - (Get-Item $logFile).LastWriteTime
    if ($age.TotalMinutes -lt 5) {
      Write-Host ''
      Write-Host ("WARNING: no Clash Verge process is visible, but its log was written {0:N0} minute(s) ago." -f $age.TotalMinutes) -ForegroundColor Yellow
      Write-Host '         It is probably running (restricted shells cannot always list processes).' -ForegroundColor Yellow
      Write-Host '         verge.yaml changes do NOT take effect until the GUI is restarted.' -ForegroundColor Yellow
    }
  }
}

# ------------------------------------------------------------- preflight ----
# Things that can silently invalidate this whole setup if they are missed.
$isAdmin = $false
try {
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch { }

Step 'preflight'
Write-Host ("  running elevated: {0}" -f $isAdmin)

# (a) other VPN / tunnel software owns routing independently of Clash
$vpnSvc = @()
try {
  $vpnSvc = @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Tailscale|WireGuard|OpenVPN|SoftEther|ZeroTier|ProtonVPN|NordVPN' })
} catch { }
if ($vpnSvc.Count -gt 0) {
  foreach ($s in $vpnSvc) { Write-Host ("  other VPN service : {0} ({1})" -f $s.Name, $s.Status) -ForegroundColor Yellow }
  Write-Host '    -> an active exit node or subnet route would take over routing and bypass' -ForegroundColor Yellow
  Write-Host '       Clash entirely. Confirm it is logged out / has no exit node enabled.' -ForegroundColor Yellow
} else {
  Write-Host '  other VPN services: none detected'
}

# (b) adapters and who owns the default route (best effort; shells may deny this)
try {
  $ad = @(Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' })
  Write-Host ('  up adapters       : ' + (($ad | ForEach-Object { $_.Name }) -join ', '))
  $def = @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop | Sort-Object RouteMetric)
  if ($def.Count -gt 0) {
    Write-Host ('  default route     : {0} (metric {1})' -f $def[0].InterfaceAlias, $def[0].RouteMetric)
  }
} catch {
  Write-Host '  adapters/routes   : unavailable in this shell (not fatal)' -ForegroundColor DarkGray
}

# (c) Clash Verge service - required for TUN mode
$svcInstaller = $null
foreach ($cand in @(
    (Join-Path $env:ProgramFiles 'Clash Verge\resources\clash-verge-service-install.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Clash Verge\resources\clash-verge-service-install.exe')
  )) {
  if ($cand -and (Test-Path $cand)) { $svcInstaller = $cand; break }
}
$cvs = Get-Service -Name clash_verge_service -ErrorAction SilentlyContinue
if ($cvs) {
  Write-Host ("  clash_verge_service: {0} / {1}" -f $cvs.Status, $cvs.StartType) -ForegroundColor Green
} else {
  Write-Host '  clash_verge_service: NOT INSTALLED (TUN mode will not work without it)' -ForegroundColor Yellow
  if ($svcInstaller) {
    Write-Host ("    installer        : {0}" -f $svcInstaller) -ForegroundColor Yellow
    Write-Host '    (note: it lives in resources\, not in the install root)' -ForegroundColor DarkGray
    if ($InstallService) {
      if (-not $isAdmin) {
        Write-Host '    -InstallService needs an elevated shell - skipped' -ForegroundColor Red
      } else {
        Write-Host '    installing the service...' -ForegroundColor Cyan
        & $svcInstaller | Out-Host
      }
    } else {
      Write-Host '    run this script again with -InstallService from an elevated shell to install it' -ForegroundColor Yellow
    }
  } else {
    Write-Host '    installer not found under Program Files\Clash Verge\resources\' -ForegroundColor DarkGray
  }
}

# ------------------------------------------------------------ parse profile --
$yaml = Get-Content $profilesYaml -Raw
$mCur = [regex]::Match($yaml, '(?m)^current:\s*(\S+)\s*$')
if (-not $mCur.Success) { Fail "cannot find the 'current:' key in profiles.yaml" }
$curUid = $mCur.Groups[1].Value

$mBlk = [regex]::Match($yaml, "(?ms)^- uid:\s*$([regex]::Escape($curUid))\s*$.*?(?=^- uid:|\z)")
if (-not $mBlk.Success) { Fail "cannot find the profile block for uid '$curUid'" }
$blk = $mBlk.Value

$mType = [regex]::Match($blk, '(?m)^\s{2}type:\s*(\S+)\s*$')
$profType = if ($mType.Success) { $mType.Groups[1].Value } else { 'unknown' }

$mFile = [regex]::Match($blk, '(?m)^\s{2}file:\s*(.+?)\s*$')
if (-not $mFile.Success) { Fail "cannot find the main profile 'file:' for uid '$curUid'" }
$mainFile = $mFile.Groups[1].Value.Trim("'`"")

Write-Host ''
Write-Host "current profile uid  : $curUid"
Write-Host "current profile file : $mainFile   (type: $profType)"

if ($IncludeMainProfile -and $profType -ne 'local') {
  Fail @"
-IncludeMainProfile only works with a LOCAL profile, but '$curUid' is '$profType'.
       Overwriting a subscription/remote profile would break it.
       Create a LOCAL profile in Verge (Profiles -> New -> Local), reload it once,
       then re-run this script.
"@
}

$mOpt = [regex]::Match($blk, '(?ms)^\s{2}option:\s*\n((?:\s{4}\w+:.*\n?)+)')
if (-not $mOpt.Success) {
  Fail @"
this profile has no 'option:' block yet, so Clash Verge has not created the
       enhancement files.
       Do this first:
         1. Start Clash Verge.
         2. Profiles -> open the enhancement editor (Merge / Script / Rules /
            Proxies / Groups) of '$mainFile' and save once.
         3. Exit Clash Verge completely, then re-run this script.
"@
}

$map = @{}
foreach ($mm in [regex]::Matches($mOpt.Groups[1].Value, '(?m)^\s+(\w+):\s*(\S+)\s*$')) {
  $map[$mm.Groups[1].Value] = $mm.Groups[2].Value
}

# ------------------------------------------------------------ build a plan --
$plan = @(
  @{ Role = 'merge';   Src = 'enh-merge.sniffer.yaml';   Ext = '.yaml' },
  @{ Role = 'rules';   Src = 'enh-rules.ai-exit.yaml';   Ext = '.yaml' },
  @{ Role = 'proxies'; Src = 'enh-proxies.empty.yaml';   Ext = '.yaml' },
  @{ Role = 'groups';  Src = 'enh-groups.empty.yaml';    Ext = '.yaml' },
  @{ Role = 'script';  Src = 'enh-script.empty.js';      Ext = '.js'   }
)

$targets = @()
foreach ($p in $plan) {
  if (-not $map.ContainsKey($p.Role)) {
    Write-Host "WARNING: no '$($p.Role)' entry in option: - skipping" -ForegroundColor Yellow
    continue
  }
  $targets += @{
    Role = $p.Role
    Src  = Join-Path $configDir $p.Src
    Dst  = Join-Path $profDir ($map[$p.Role] + $p.Ext)
  }
}
if ($IncludeMainProfile) {
  $targets += @{ Role = 'main'; Src = (Join-Path $configDir 'main-profile.template.yaml'); Dst = (Join-Path $profDir $mainFile) }
}
# the mobile config is generated next to this script (transfer it to devices later)
$mobileDst = Join-Path $scriptDir 'mobile-clash.yaml'

Step 'plan'
foreach ($t in $targets) {
  $state = if (Test-Path $t.Dst) { 'overwrite' } else { 'NEW      ' }
  Write-Host ("  {0,-7} {1}  {2}" -f $t.Role, $state, (Split-Path -Leaf $t.Dst))
}
Write-Host ("  {0,-7} {1}  {2}" -f 'mobile', 'generate ', (Split-Path -Leaf $mobileDst))

# ------------------------------------------------------------------ backup --
$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$bakDir = Join-Path $scriptDir "backup-$stamp"
New-Item -ItemType Directory -Force -Path $bakDir | Out-Null
Copy-Item $profilesYaml (Join-Path $bakDir 'profiles.yaml') -Force
$vergeYaml = Join-Path $VergeDir 'verge.yaml'
if (Test-Path $vergeYaml) { Copy-Item $vergeYaml (Join-Path $bakDir 'verge.yaml') -Force }
foreach ($t in $targets) {
  if (Test-Path $t.Dst) { Copy-Item $t.Dst (Join-Path $bakDir (Split-Path -Leaf $t.Dst)) -Force }
}
Step 'backup'
Write-Host "  $bakDir"

# ------------------------------------------------------------------ render --
$repl = @{
  '__PROXY_HOST__'     = $ProxyHost
  '__PROXY_PORT__'     = [string]$ProxyPort
  '__PROXY_USER__'     = $ProxyUser
  '__PROXY_PASSWORD__' = $ProxyPassword
  '__NODE_NAME__'      = $NodeName
}

function Render([string]$path) {
  $text = Get-Content $path -Raw
  foreach ($k in $repl.Keys) { $text = $text.Replace($k, $repl[$k]) }
  # fail loudly if a placeholder survived
  $left = [regex]::Matches($text, '__[A-Z_]+__')
  if ($left.Count -gt 0) { Fail "unreplaced placeholder(s) in $(Split-Path -Leaf $path): $((($left | ForEach-Object { $_.Value }) | Sort-Object -Unique) -join ', ')" }
  return $text
}

Step 'writing'
foreach ($t in $targets) {
  $text = Render $t.Src
  [System.IO.File]::WriteAllText($t.Dst, $text, $utf8NoBom)
  Write-Host ("  {0,-7} -> {1}" -f $t.Role, (Split-Path -Leaf $t.Dst))
}
$mobileText = Render (Join-Path $configDir 'mobile-clash.template.yaml')
[System.IO.File]::WriteAllText($mobileDst, $mobileText, $utf8NoBom)
Write-Host ("  {0,-7} -> {1}" -f 'mobile', (Split-Path -Leaf $mobileDst))

# ---------------------------------------------------------------- launchers --
if (-not $SkipLaunchers) {
  $launcherDir = Join-Path $scriptDir 'launchers'
  $npmDir = Join-Path $env:APPDATA 'npm'
  if ((Test-Path $launcherDir) -and (Test-Path $npmDir)) {
    foreach ($f in Get-ChildItem $launcherDir -Filter '*.cmd') {
      Copy-Item $f.FullName (Join-Path $npmDir $f.Name) -Force
      Write-Host "  launcher -> $(Join-Path $npmDir $f.Name)"
    }
  } else {
    Write-Host '  launchers skipped (no launchers folder or no %APPDATA%\npm)' -ForegroundColor Yellow
  }
}

# --------------------------------------------------- verge.yaml defaults ----
# The package's recommended defaults, so a new machine needs no decisions:
#   system proxy ON -> browsers and WinINET apps fail loudly when the core is
#                      down, instead of silently leaving from the real IP
#   proxy guard ON  -> re-apply the system proxy if another program changes it
# TUN is deliberately NOT touched here: it needs the Clash Verge service, which
# may not be installed. Turn it on in the app when available (it adds coverage).
if (-not $SkipVergeSettings) {
  Step 'verge.yaml recommended defaults'
  if (-not (Test-Path $vergeYaml)) {
    Write-Host "  verge.yaml not found at $vergeYaml - skipped" -ForegroundColor Yellow
  } else {
    $vy = Get-Content $vergeYaml -Raw
    $pairs = @(
      @{ Key = 'enable_system_proxy'; Want = 'true' },
      @{ Key = 'enable_proxy_guard';  Want = 'true' }
    )
    foreach ($pr in $pairs) {
      $k = $pr.Key
      $w = $pr.Want
      $pat = '(?m)^{0}:\s*(\S+)\s*$' -f [regex]::Escape($k)
      if ($vy -match $pat) {
        $cur = $Matches[1]
        if ($cur -eq $w) {
          Write-Host ("  {0} already {1}" -f $k, $w)
        } else {
          $vy = [regex]::Replace($vy, $pat, ('{0}: {1}' -f $k, $w))
          Write-Host ("  {0} : {1} -> {2}" -f $k, $cur, $w) -ForegroundColor Green
        }
      } else {
        $vy = $vy.TrimEnd() + "`n" + ('{0}: {1}' -f $k, $w) + "`n"
        Write-Host ("  {0} : (absent) -> {1}" -f $k, $w) -ForegroundColor Green
      }
    }
    [System.IO.File]::WriteAllText($vergeYaml, $vy, $utf8NoBom)
    Write-Host '  Verge must be restarted for these to take effect.'
  }
}

# --------------------------------------------------------------- validation --
Step 'validation (verge-mihomo -t)'
$candidates = @(
  'C:\Program Files\Clash Verge\verge-mihomo.exe',
  (Join-Path $VergeDir 'verge-mihomo.exe')
)
$mihomo = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $mihomo) {
  Write-Host '  verge-mihomo.exe not found - skipped (verify inside Clash Verge instead)' -ForegroundColor Yellow
} else {
  $tmp = Join-Path $scriptDir 'miho'
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  foreach ($f in @($mobileDst) + ($targets | Where-Object { $_.Role -eq 'main' } | ForEach-Object { $_.Dst })) {
    $out = & $mihomo -t -d $tmp -f $f 2>&1 | Select-Object -Last 1
    Write-Host ("  {0,-24} {1}" -f (Split-Path -Leaf $f), $out)
  }
}

# -------------------------------------------------------------- next steps --
Step 'DONE - do these steps in Clash Verge'
Write-Host @'
  1. Start Clash Verge -> Profiles -> click the profile card to reload it.
     The log should NOT contain "initial rule provider error" or YAML errors.
     (verge.yaml edits only take effect after the GUI restarts.)

  2. Browser: disable QUIC or HTTP/3 can bypass the domain rules.
       Edge   -> edge://flags/#enable-quic   -> Disabled
       Chrome -> chrome://flags/#enable-quic -> Disabled
     Then restart the browser completely.

  3. Acceptance - one command that produces the evidence:
       powershell -ExecutionPolicy Bypass -File .\verify-exit.ps1
     It must end with "RESULT: all automated checks passed."

  4. curl does NOT prove the browser. Check the browser directly:
       open https://claude.ai/cdn-cgi/trace -> ip= must be the proxy IP, loc= the target country
     Clash Verge -> Connections: claude.ai must show the exit group, never DIRECT.
     In service mode the authoritative proof is the mihomo log line:
       [TCP] 127.0.0.1:58593(msedge.exe) --> claude.ai:443
             match DomainKeyword(claude) using AI-Exit[<node>]

  5. Windows regional consistency:
       powershell -ExecutionPolicy Bypass -File .\check-windows-locale.ps1
     Must end with "RESULT: all settings are consistent."
     The language list is informational only - Windows can silently refuse it, and the
     script never rewrites it (rewriting can delete existing IMEs).

  6. Claude Code: add the proxy env block to %USERPROFILE%\.claude\settings.json
     (see DEVICES.md).

  7. Phones/tablets: transfer mobile-clash.yaml to the device and follow DEVICES.md.

  8. TUN (optional - adds coverage for programs that ignore proxy settings):
       a. install the service from an ELEVATED shell:
            powershell -ExecutionPolicy Bypass -File .\install.ps1 -InstallService
       b. restart the Clash Verge GUI
       c. set enable_tun_mode AND enable_dns_settings to true TOGETHER
          (Verge only injects the dns: block when TUN is on), then restart the GUI again
       d. re-run verify-exit.ps1: the "TUN coverage" row must say PASS
     In service mode a non-elevated process can no longer stop verge-mihomo, so verify
     by reloading the profile in the GUI - and the sidecar log stops updating.

  9. Note: the generated runtime config (clash-verge.yaml) contains the proxy password in
     plain text. That is inherent to mihomo. Keep it machine-local; the secret files in
     this folder stay gitignored.
'@
