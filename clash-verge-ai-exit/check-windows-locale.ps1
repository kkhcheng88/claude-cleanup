<#
check-windows-locale.ps1 - verify (and optionally apply) Windows regional settings so
they are consistent with the exit country of your proxy.

WHY THIS EXISTS
  The Clash package pins selected traffic to a fixed proxy exit in a specific country.
  If the device itself still reports a different time zone / region / format, the two
  signals contradict each other. This script makes the inconsistency visible and, with
  -Apply, fixes it.

WHAT IT CHECKS (the verdict)
  * Time zone            (default expected: Taipei Standard Time)
  * Home location        (default expected: 237 = Taiwan)
  * System locale        (default expected: zh-TW)
  * User culture/format  (default expected: zh-TW)

WHAT IT ONLY REPORTS (never blocks the verdict)
  * User language list   - INFORMATIONAL. See the two Windows limitations below.
  * Clock sync status    - informational.

KNOWN WINDOWS LIMITATIONS (verified on real machines - do not waste time here)
  1. Set-WinUserLanguageList can report success and change nothing. The registry key
     HKCU\Control Panel\International\User Profile\Languages simply keeps the old
     value and no error is raised; the Settings UI can show the wanted language as
     visible but greyed out. This is Windows behaviour, not a script bug.
  2. Writing a language list is DESTRUCTIVE if done naively: a freshly created
     WinUserLanguage object carries the DEFAULT input methods for that language, so
     re-sending the list overwrites the user's real IME list (for example a Cangjie
     profile disappears). This is why this script does NOT touch the language list at
     all - not even with -Apply. Add languages in
     Settings > Time & Language > Language & region, which preserves IMEs.
  Because of (1) and (2), the language list is reported but never affects RESULT.

USAGE
  # check only (safe, changes nothing)
  powershell -ExecutionPolicy Bypass -File .\check-windows-locale.ps1

  # check and fix time zone / home location / system locale / user culture
  powershell -ExecutionPolicy Bypass -File .\check-windows-locale.ps1 -Apply

NOTES
  * System locale needs a reboot; time zone and home location apply immediately.
  * Time zone and system locale changes are machine-wide and MAY require Administrator
    rights depending on the Windows build and policy - on some Windows 11 machines a
    standard user can change the time zone. -Apply reports clearly when a change fails.
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

# ---- user language list: INFORMATIONAL ONLY ------------------------------
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
if ($langsText -eq '') { $langsText = '<unavailable>' }

$hasLocale = $false
foreach ($l in $langs) { if (Test-LocaleTag $l $Locale) { $hasLocale = $true } }

$langStatus = if ($hasLocale) { 'INFO     ' } else { 'NOTE     ' }
$langColor  = if ($hasLocale) { 'DarkGray' } else { 'DarkYellow' }
Write-Host ("  {0} {1,-22} current: {2,-34} expected: {3}" -f $langStatus, 'Language list', $langsText, "contains $Locale (informational)") -ForegroundColor $langColor
if (-not $hasLocale) {
  Write-Host '           Windows often refuses this change silently (documented limitation),' -ForegroundColor DarkGray
  Write-Host '           and writing it programmatically can delete existing IMEs. If you want' -ForegroundColor DarkGray
  Write-Host '           it anyway, add the language in Settings > Time & Language >' -ForegroundColor DarkGray
  Write-Host '           Language & region. It does NOT affect RESULT.' -ForegroundColor DarkGray
}

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
# The user language list is deliberately NOT changed here: Windows may ignore it
# silently, and rebuilding the list overwrites existing input methods (IMEs).
Write-Host ''
Write-Host '=== applying (language list is never touched) ===' -ForegroundColor Cyan
$needsReboot = $false
$failed = 0

if ($tz -ne $TimeZoneId) {
  try {
    Set-TimeZone -Id $TimeZoneId
    Write-Host ("  time zone     -> {0}" -f $TimeZoneId) -ForegroundColor Green
  } catch {
    $failed++
    Write-Host ("  time zone     -> FAILED: {0} (try again elevated)" -f $_.Exception.Message) -ForegroundColor Red
  }
}

if ($hl -ne $HomeLocation) {
  try {
    Set-WinHomeLocation -GeoId $HomeLocation
    Write-Host ("  home location -> {0}" -f $HomeLocation) -ForegroundColor Green
  } catch {
    $failed++
    Write-Host ("  home location -> FAILED: {0}" -f $_.Exception.Message) -ForegroundColor Red
  }
}

if ($sl -ne $Locale) {
  try {
    Set-WinSystemLocale -SystemLocale $Locale
    $needsReboot = $true
    Write-Host ("  system locale -> {0} (takes effect after reboot)" -f $Locale) -ForegroundColor Green
  } catch {
    $failed++
    Write-Host ("  system locale -> FAILED: {0} (try again elevated)" -f $_.Exception.Message) -ForegroundColor Red
  }
}

if ($cul -ne $Locale) {
  try {
    Set-Culture -CultureInfo $Locale
    Write-Host ("  user culture  -> {0}" -f $Locale) -ForegroundColor Green
  } catch {
    $failed++
    Write-Host ("  user culture  -> FAILED: {0}" -f $_.Exception.Message) -ForegroundColor Red
  }
}

if (-not $hasLocale) {
  Write-Host '  language list -> SKIPPED ON PURPOSE' -ForegroundColor DarkYellow
  Write-Host '                   (Windows ignores it silently and rebuilding the list can' -ForegroundColor DarkGray
  Write-Host '                    delete existing IMEs - add it in Settings if you want it)' -ForegroundColor DarkGray
}

Write-Host ''
if ($failed -gt 0) { Write-Host ("  {0} change(s) failed - retry from an elevated PowerShell." -f $failed) -ForegroundColor Yellow }
if ($needsReboot)  { Write-Host '  A REBOOT is required for the system locale change.' -ForegroundColor Yellow }
Write-Host '  Re-run this script without -Apply to confirm everything is consistent.' -ForegroundColor Cyan
