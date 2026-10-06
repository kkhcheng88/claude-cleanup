<#
fix-uwp-loopback.ps1 - AppContainer loopback exemptions for proxy / TUN setups.

THE SYMPTOM THIS FIXES
  Work or school (enterprise / edu) OneDrive hangs forever on "Signing in..." with no
  error code, while a personal OneDrive works fine - and turning Clash off makes it work
  again, which makes it look like a region or IP problem. It is not: the auth endpoints
  answer 200 and the sync backend is reachable.

THE ROOT CAUSE (capture layer, not routing layer)
  Windows blocks AppContainer (UWP sandbox) apps from connecting to loopback
  (127.0.0.1) by default. Enterprise OneDrive signs in through the WAM broker
  "Microsoft.AAD.BrokerPlugin", which IS an AppContainer app, so it must reach
  127.0.0.1:<mixed-port> to use the proxy. The sandbox silently refuses, and the
  sign-in never completes. Personal OneDrive uses a different path, so it is unaffected.

  This is why no rule can ever fix it: the rule engine only runs AFTER a connection
  reaches the proxy, and an AppContainer app cannot reach the proxy at all.
  DOMAIN-* -> DIRECT, moving the domain to a group, IPv4-only DNS policies: all
  irrelevant here.

WHAT THIS SCRIPT DOES
  * reads the current exemption list and reports it
  * resolves which of the packages that matter are actually INSTALLED
  * -Apply adds the missing ones (needs an elevated shell)
  * re-reads the list afterwards and verifies the registration really took (never
    trusts the "success" message - see the traps below)
  * -Delete removes the entries this script manages

USAGE
  # report only (safe)
  powershell -ExecutionPolicy Bypass -File .\fix-uwp-loopback.ps1

  # add the missing exemptions (run as Administrator)
  powershell -ExecutionPolicy Bypass -File .\fix-uwp-loopback.ps1 -Apply

  # revert
  powershell -ExecutionPolicy Bypass -File .\fix-uwp-loopback.ps1 -Delete

TWO TRAPS THAT COST HOURS (documented from a real deployment)
  1. CheckNetIsolation must be called through cmd.exe with a QUOTED -n="...". Passing
     -n=$var straight from PowerShell makes it print "Invalid parameter". Tells:
     the correct syntax without rights answers "Access is denied"; the wrong syntax
     answers "Invalid parameter".
  2. A printed success message is NOT proof of registration. With the wrong syntax all
     entries print success while only one is stored, shown as "AppContainer NOT FOUND"
     with identical SIDs for every entry. Always verify with -s: the name column must
     hold the package family name and every SID must be different. This script does
     that automatically.

NOTES
  * The exemption list itself usually needs elevation just to read.
  * The change is reversible: -Delete removes exactly the packages listed here.
  * Only installed packages are added, so no "NOT FOUND" junk entries are created.
#>
param(
  [switch]$Apply,
  [switch]$Delete,
  [switch]$Force
)

$ErrorActionPreference = 'Continue'

# name pattern -> human label. Resolution to a package family name happens at runtime.
$targets = @(
  @{ Pattern = 'Microsoft.AAD.BrokerPlugin';            Label = 'WAM broker (the decisive one for enterprise OneDrive)' },
  @{ Pattern = 'Microsoft.AccountsControl';             Label = 'Accounts control' },
  @{ Pattern = 'Microsoft.Windows.CloudExperienceHost'; Label = 'Cloud experience host' },
  @{ Pattern = 'Microsoft.OneDriveSync';                Label = 'OneDrive sync engine' },
  @{ Pattern = 'Microsoft.WindowsStore';                Label = 'Microsoft Store' },
  @{ Pattern = 'Microsoft.MicrosoftOfficeHub';          Label = 'Office hub' },
  @{ Pattern = 'Microsoft.XboxIdentityProvider';        Label = 'Xbox identity provider' },
  @{ Pattern = 'Microsoft.CredDialogHost';              Label = 'Credential dialog host' },
  @{ Pattern = 'Microsoft.Win32WebViewHost';            Label = 'Win32 WebView host' }
)

# used only when package discovery is unavailable
$fallbackPfn = @{
  'Microsoft.AAD.BrokerPlugin'            = 'Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy'
  'Microsoft.AccountsControl'             = 'Microsoft.AccountsControl_cw5n1h2txyewy'
  'Microsoft.Windows.CloudExperienceHost' = 'Microsoft.Windows.CloudExperienceHost_cw5n1h2txyewy'
  'Microsoft.OneDriveSync'                = 'Microsoft.OneDriveSync_8wekyb3d8bbwe'
  'Microsoft.WindowsStore'                = 'Microsoft.WindowsStore_8wekyb3d8bbwe'
  'Microsoft.MicrosoftOfficeHub'          = 'Microsoft.MicrosoftOfficeHub_8wekyb3d8bbwe'
  'Microsoft.XboxIdentityProvider'        = 'Microsoft.XboxIdentityProvider_8wekyb3d8bbwe'
  'Microsoft.CredDialogHost'              = 'Microsoft.CredDialogHost_cw5n1h2txyewy'
  'Microsoft.Win32WebViewHost'            = 'Microsoft.Win32WebViewHost_cw5n1h2txyewy'
}

function Get-LoopbackState {
  $raw = & cmd.exe /c 'CheckNetIsolation LoopbackExempt -s' 2>&1
  $code = $LASTEXITCODE
  $text = ($raw | Out-String)
  # Language independent: a non-zero exit code means the query itself failed (in
  # practice "access is denied" when the shell is not elevated). Matching the
  # localized error text is not an option - PowerShell 5.1 reads a BOM-less UTF-8
  # script as ANSI, so non-ASCII literals here would be mojibake.
  $denied = ($code -ne 0)
  # language independent: package family names end with _<13 alphanumerics>,
  # AppContainer SIDs start with S-1-15-2-
  $pfns = @([regex]::Matches($text, '\b[A-Za-z0-9\.\-]+_[a-z0-9]{13}\b') |
            ForEach-Object { $_.Value.ToLower() } | Sort-Object -Unique)
  $sids = @([regex]::Matches($text, 'S-1-15-2-(?:\d+-)+\d+') |
            ForEach-Object { $_.Value } | Sort-Object -Unique)
  [pscustomobject]@{ Text = $text; Code = $code; Denied = $denied; Pfns = $pfns; Sids = $sids }
}

$isAdmin = $false
try {
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch { }

Write-Host ''
Write-Host '=== AppContainer loopback exemptions ===' -ForegroundColor Cyan
Write-Host ("  running elevated: {0}" -f $isAdmin)

$state = Get-LoopbackState
if ($state.Denied) {
  Write-Host '  could not read the exemption list (access denied) - run this script elevated.' -ForegroundColor Yellow
} else {
  Write-Host ("  current exemptions: {0} package(s), {1} distinct SID(s)" -f $state.Pfns.Count, $state.Sids.Count) -ForegroundColor Gray
  if ($state.Pfns.Count -gt 0) {
    $state.Pfns | ForEach-Object { Write-Host ("    - {0}" -f $_) -ForegroundColor DarkGray }
  } else {
    Write-Host '    (empty - AppContainer apps cannot use a loopback proxy in this state)' -ForegroundColor Yellow
  }
}

# ---- resolve which target packages are installed -------------------------
$all = @()
try { $all = @(Get-AppxPackage -ErrorAction Stop) } catch { }
$discovery = ($all.Count -gt 0)
if (-not $discovery) {
  Write-Host '  package discovery unavailable (Get-AppxPackage was refused); using the known' -ForegroundColor Yellow
  Write-Host '  family-name table instead. Run elevated for exact resolution.' -ForegroundColor Yellow
}

$plan = @()
foreach ($t in $targets) {
  $pfn = $null
  if ($discovery) {
    $hit = $all | Where-Object { $_.Name -eq $t.Pattern } | Select-Object -First 1
    if ($hit) { $pfn = $hit.PackageFamilyName }
  } else {
    $pfn = $fallbackPfn[$t.Pattern]
  }
  $plan += [pscustomobject]@{
    Label     = $t.Label
    Installed = [bool]$pfn
    Pfn       = $pfn
    Exempt    = ($pfn -and ($state.Pfns -contains $pfn.ToLower()))
  }
}

Write-Host ''
Write-Host '  package                                       installed  exempt' -ForegroundColor Cyan
foreach ($p in $plan) {
  $name = if ($p.Pfn) { $p.Pfn } else { $p.Label }
  Write-Host ("  {0,-45} {1,-10} {2}" -f $name, $(if ($p.Installed) { 'yes' } else { 'no' }), $(if ($p.Exempt) { 'yes' } else { 'NO' })) -ForegroundColor $(if ($p.Exempt -or -not $p.Installed) { 'Gray' } else { 'Yellow' })
}

$missing = @($plan | Where-Object { $_.Installed -and -not $_.Exempt })
$present = @($plan | Where-Object { $_.Installed -and $_.Exempt })

Write-Host ''
if ($missing.Count -eq 0 -and $present.Count -gt 0) {
  Write-Host '  RESULT: every installed package that matters is already exempt.' -ForegroundColor Green
} elseif ($present.Count -eq 0 -and $missing.Count -gt 0) {
  Write-Host ("  RESULT: {0} package(s) still need an exemption - enterprise OneDrive sign-in will hang while the system proxy is on." -f $missing.Count) -ForegroundColor Yellow
} else {
  Write-Host ("  RESULT: {0} exempt, {1} missing." -f $present.Count, $missing.Count) -ForegroundColor Yellow
}

if ($missing.Count -eq 0) { exit 0 }

# ---- apply / delete ------------------------------------------------------
if (-not $Apply -and -not $Delete) {
  Write-Host ''
  Write-Host '  To fix, run this from an ELEVATED shell:' -ForegroundColor Cyan
  Write-Host '    powershell -ExecutionPolicy Bypass -File .\fix-uwp-loopback.ps1 -Apply'
  Write-Host ''
  Write-Host '  (manual form, note the quoted -n="...")' -ForegroundColor DarkGray
  foreach ($m in $missing) { Write-Host ('    CheckNetIsolation LoopbackExempt -a -n="{0}"' -f $m.Pfn) -ForegroundColor DarkGray }
  exit 0
}

if (-not $isAdmin) {
  Write-Host ''
  Write-Host '  ERROR: adding or removing exemptions needs an elevated shell.' -ForegroundColor Red
  exit 1
}

# Refuse to write from the fallback table unless forced: adding a family name whose
# package is not installed creates exactly the broken "AppContainer NOT FOUND" entries
# (identical SIDs) that this script exists to avoid.
if (-not $discovery -and -not $Force) {
  Write-Host ''
  Write-Host '  ERROR: installed packages could not be enumerated, so the fallback family-name' -ForegroundColor Red
  Write-Host '         table cannot be trusted for writes. Run elevated so Get-AppxPackage works,' -ForegroundColor Red
  Write-Host '         or pass -Force deliberately.' -ForegroundColor Red
  exit 1
}

Write-Host ''
if ($Delete) {
  Write-Host '=== removing ===' -ForegroundColor Cyan
  foreach ($m in ($plan | Where-Object { $_.Installed })) {
    $cmd = 'CheckNetIsolation LoopbackExempt -d -n="' + $m.Pfn + '"'
    $o = (& cmd.exe /c $cmd 2>&1 | Out-String).Trim()
    Write-Host ("  {0,-45} {1}" -f $m.Pfn, $(if ($o) { $o } else { 'ok' }))
  }
} else {
  Write-Host '=== adding (through cmd.exe with a quoted -n) ===' -ForegroundColor Cyan
  foreach ($m in $missing) {
    $cmd = 'CheckNetIsolation LoopbackExempt -a -n="' + $m.Pfn + '"'
    $o = (& cmd.exe /c $cmd 2>&1 | Out-String).Trim()
    Write-Host ("  {0,-45} {1}" -f $m.Pfn, $(if ($o) { $o } else { 'ok' }))
  }
}

# ---- verify: never trust the success message -----------------------------
Write-Host ''
Write-Host '=== verifying against the real list ===' -ForegroundColor Cyan
$after = Get-LoopbackState
$verified = 0
$failed = 0
foreach ($p in $plan) {
  if (-not $p.Installed) { continue }
  $ok = ($after.Pfns -contains $p.Pfn.ToLower())
  if ($Delete) { $ok = -not $ok }
  if ($ok) { $verified++ } else { $failed++; Write-Host ("  NOT registered: {0}" -f $p.Pfn) -ForegroundColor Red }
}
Write-Host ("  exemptions now: {0} package(s), {1} distinct SID(s)" -f $after.Pfns.Count, $after.Sids.Count)
# the classic symptom of the quoting trap: one SID repeated for every entry
if ($after.Pfns.Count -gt 1 -and $after.Sids.Count -lt $after.Pfns.Count) {
  Write-Host '  WARNING: fewer distinct SIDs than packages - some entries are broken' -ForegroundColor Red
  Write-Host '           ("AppContainer NOT FOUND" entries). Re-add them from cmd.exe with -n="..."' -ForegroundColor Red
}

Write-Host ''
if ($failed -eq 0) {
  Write-Host ("  RESULT: verified - {0} package(s) {1}." -f $verified, $(if ($Delete) { 'removed' } else { 'exempt' })) -ForegroundColor Green
  if (-not $Delete) {
    Write-Host '  Sign out and back in (or restart) before retrying the OneDrive sign-in.' -ForegroundColor Cyan
  }
  exit 0
} else {
  Write-Host ("  RESULT: {0} package(s) did NOT register - see the warning above." -f $failed) -ForegroundColor Red
  exit 1
}
