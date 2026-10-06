<#
check-windows-locale.ps1 - verify (and optionally apply) Windows regional settings so
they are consistent with the exit country of your proxy.

WHY THIS EXISTS
  The Clash package pins selected traffic to a fixed proxy exit in a specific country.
  If the device itself still reports a different time zone / region / format, the two
  signals contradict each other. This script makes the inconsistency visible and, with
  -Apply, fixes it.

WHAT IT CHECKS
  * Time zone            (default expected: Taipei Standard Time)
  * Home location        (default expected: 237 = Taiwan)
  * System locale        (default expected: zh-TW)
  * User culture/format  (default expected: zh-TW)
  * User language list   (expected to CONTAIN zh-TW; other languages are kept)
  * Clock sync status    (informational)

USAGE
  # check only (safe, changes nothing)
  powershell -ExecutionPolicy Bypass -File .\check-windows-locale.ps1

  # check and fix (run as Administrator for the time zone change)
  powershell -ExecutionPolicy Bypass -File .\check-windows-locale.ps1 -Apply

NOTES
  * Time zone and system locale changes are machine-wide. Depending on the Windows
    build and policy they may require Administrator rights - on some Windows 11
    machines a standard user can change the time zone. -Apply reports clearly when
    a change fails and suggests re-running elevated.
  * System locale changes take effect after a reboot; language list changes after a
    sign-out. The script tells you what still needs a restart.
  * Everything here is reversible in the Windows settings UI.
#>
param(
  [switch]$Apply,
  [string]$TimeZoneId = 'Taipei Standard Time',
  [int]$HomeLocation = 237,
  [string]$Locale = 'zh-TW'
)

$ErrorActionPreference = 'Continue'

function Write-Row([string]$Check, [string]$Current, [bool]$Ok, [string]$Expected) {
  $status = if ($Ok) { 'OK       ' } else { 'MISMATCH ' }
  $color  = if ($Ok) { 'Green' } else { 'Yellow' }
  Write-Host ("  {0} {1,-22} current: {2,-34} expected: {3}" -f $status, $Check, $Current, $Expected) -ForegroundColor $color
}

Write-Host ''
Write-Host '=== Windows regional consistency check ===' -ForegroundColor Cyan
Write-Host "  target: time zone '$TimeZoneId', home location $HomeLocation, locale '$Locale'"

$isAdmin = $false
try {
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch { }
Write-Host ("  running elevated: {0}" -f $isAdmin)
Write-Host ''

$mismatch = 0

# ---- time zone -------------------------------------------------------------
$tz = ''
try { $tz = (Get-TimeZone).Id } catch { $tz = '<error>' }
$ok = ($tz -eq $TimeZoneId); if (-not $ok) { $mismatch++ }
Write-Row 'Time zone' $tz $ok $TimeZoneId

# ---- home location ---------------------------------------------------------
$hl = -1
try {
  $hlRaw = (Get-WinHomeLocation).HomeLocation
  # HomeLocation is a GeoId value; it may come back as an enum or as a name string.
  try { $hl = [int]$hlRaw } catch { $hl = -1 }
  if ($hl -lt 0 -and "$hlRaw".Trim() -eq 'Taiwan') { $hl = 237 }
} catch { }
$ok = ($hl -eq $HomeLocation); if (-not $ok) { $mismatch++ }
Write-Row 'Home location (GeoId)' ([string]$hl) $ok ([string]$HomeLocation)

# ---- system locale --------------------------------------------------------
$sl = ''
try { $sl = (Get-WinSystemLocale).Name } catch { $sl = '<error>' }
$ok = ($sl -eq $Locale); if (-not $ok) { $mismatch++ }
Write-Row 'System locale' $sl $ok $Locale

# ---- user culture / formats ----------------------------------------------
$cul = (Get-Culture).Name
$ok = ($cul -eq $Locale); if (-not $ok) { $mismatch++ }
Write-Row 'User culture (formats)' $cul $ok $Locale

# ---- user language list (must contain, not equal) ------------------------
# A tag matches when language and region match, ignoring the script subtag:
# zh-TW and zh-Hant-TW both mean "Chinese, Taiwan".
function Test-LocaleTag([string]$tag, [string]$wanted) {
  $t = $tag -split '-'
  $w = $wanted -split '-'
  if ($t.Count -lt 2 -or $w.Count -lt 2) { return ($tag -eq $wanted) }
  return (($t[0] -eq $w[0]) -and ($t[$t.Count - 1] -eq $w[$w.Count - 1]))
}

$langs = @()
try { $langs = @((Get-WinUserLanguageList) | ForEach-Object { $_.LanguageTag }) } catch { }
$langsText = ($langs -join ', ')
if ($langsText -eq '') { $langsText = '<error>' }

$hasLocale = $false
foreach ($l in $langs) { if (Test-LocaleTag $l $Locale) { $hasLocale = $true } }
if (-not $hasLocale) { $mismatch++ }
Write-Host ("  {0} {1,-22} current: {2,-34} expected: {3}" -f `
  $(if ($hasLocale) { 'OK       ' } else { 'MISMATCH ' }), 'Language list', $langsText, "contains $Locale") `
  -ForegroundColor $(if ($hasLocale) { 'Green' } else { 'Yellow' })

# ---- clock sync (informational) ------------------------------------------
$w32 = ''
try { $w32 = (w32tm /query /status 2>$null | Select-String -Pattern 'Source|Last Successful Sync Time' | ForEach-Object { $_.Line.Trim() }) -join ' | ' } catch { }
if (-not $w32) { $w32 = '<unavailable - informational only>' }
Write-Host ("  {0} {1,-22} {2}" -f 'INFO     ', 'Clock sync', $w32) -ForegroundColor DarkGray

# ---- summary --------------------------------------------------------------
Write-Host ''
if ($mismatch -eq 0) {
  Write-Host '  RESULT: all settings are consistent.' -ForegroundColor Green
} else {
  Write-Host ("  RESULT: {0} item(s) mismatch." -f $mismatch) -ForegroundColor Yellow
}

if (-not $Apply) {
  if ($mismatch -gt 0) {
    Write-Host ''
    Write-Host '  To fix, run this script again as Administrator with -Apply:' -ForegroundColor Cyan
    Write-Host '    powershell -ExecutionPolicy Bypass -File .\check-windows-locale.ps1 -Apply'
  }
  exit 0
}

# ---- apply ---------------------------------------------------------------
Write-Host ''
Write-Host '=== applying ===' -ForegroundColor Cyan
$needsReboot = $false
$needsSignOut = $false

if ($tz -ne $TimeZoneId) {
  try {
    Set-TimeZone -Id $TimeZoneId
    Write-Host ("  time zone     -> {0}" -f $TimeZoneId) -ForegroundColor Green
  } catch {
    Write-Host ("  time zone     -> FAILED: {0} (run as Administrator)" -f $_.Exception.Message) -ForegroundColor Red
  }
}

if ($hl -ne $HomeLocation) {
  try {
    Set-WinHomeLocation -GeoId $HomeLocation
    Write-Host ("  home location -> {0}" -f $HomeLocation) -ForegroundColor Green
  } catch {
    Write-Host ("  home location -> FAILED: {0}" -f $_.Exception.Message) -ForegroundColor Red
  }
}

if ($sl -ne $Locale) {
  try {
    Set-WinSystemLocale -SystemLocale $Locale
    $needsReboot = $true
    Write-Host ("  system locale -> {0} (takes effect after reboot)" -f $Locale) -ForegroundColor Green
  } catch {
    Write-Host ("  system locale -> FAILED: {0} (run as Administrator)" -f $_.Exception.Message) -ForegroundColor Red
  }
}

if ($cul -ne $Locale) {
  try {
    Set-Culture -CultureInfo $Locale
    Write-Host ("  user culture  -> {0}" -f $Locale) -ForegroundColor Green
  } catch {
    Write-Host ("  user culture  -> FAILED: {0}" -f $_.Exception.Message) -ForegroundColor Red
  }
}

if (-not $hasLocale) {
  # NOTE: @(Get-WinUserLanguageList) returns a FIXED-SIZE object[] that wraps the list
  # as a single element, so calling .Add() on it always throws
  # "collection is of a fixed size". Build a mutable ArrayList instead, keep the
  # existing order (the first entry is the display language) and append the new
  # locale at the end.
  try {
    $flat = New-Object System.Collections.ArrayList
    foreach ($x in (Get-WinUserLanguageList)) { [void]$flat.Add($x) }
    foreach ($x in (New-WinUserLanguageList $Locale)) { [void]$flat.Add($x) }
    Set-WinUserLanguageList -LanguageList $flat.ToArray() -Force
    $needsSignOut = $true
    Write-Host ("  language list -> appended {0} (takes effect after sign-out)" -f $Locale) -ForegroundColor Green
    Write-Host '                   NOTE: Windows may silently ignore this call. Re-run the check' -ForegroundColor DarkGray
    Write-Host '                   to confirm; if it still reports MISMATCH, add the language' -ForegroundColor DarkGray
    Write-Host '                   manually in Settings > Time & Language > Language & region.' -ForegroundColor DarkGray
  } catch {
    Write-Host ("  language list -> FAILED: {0}" -f $_.Exception.Message) -ForegroundColor Red
    Write-Host '                   Fallback: add the language manually in Settings > Time &' -ForegroundColor DarkGray
    Write-Host '                   Language > Language & region.' -ForegroundColor DarkGray
  }
}

Write-Host ''
if ($needsReboot)  { Write-Host '  A REBOOT is required for the system locale change.' -ForegroundColor Yellow }
if ($needsSignOut) { Write-Host '  A SIGN-OUT (or reboot) is required for the language list change.' -ForegroundColor Yellow }
Write-Host '  Re-run this script without -Apply to confirm everything is consistent.' -ForegroundColor Cyan
