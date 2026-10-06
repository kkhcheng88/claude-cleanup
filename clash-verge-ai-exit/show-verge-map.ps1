<#
show-verge-map.ps1 - print which random uid file plays which role.

Clash Verge names the enhancement files after a random uid (e.g. mSMymKbjj6er.yaml)
and every PC generates different uids. This script prints the mapping for the
CURRENT profile so you can tell which file is the merge / rules / proxies /
groups / script one.

Usage:
  powershell -ExecutionPolicy Bypass -File .\show-verge-map.ps1
  powershell -ExecutionPolicy Bypass -File .\show-verge-map.ps1 -VergeDir "D:\path\to\clash-verge-rev"
#>
param(
  [string]$VergeDir = "$env:APPDATA\io.github.clash-verge-rev.clash-verge-rev"
)

$ErrorActionPreference = 'Stop'
$profilesYaml = Join-Path $VergeDir 'profiles.yaml'
$profDir      = Join-Path $VergeDir 'profiles'

if (-not (Test-Path $profilesYaml)) {
  Write-Host "profiles.yaml not found at $profilesYaml" -ForegroundColor Red
  exit 1
}

# characters used to strip surrounding quotes from YAML scalars: ' and "
$trimChars = [char[]]@(39, 34)

$yaml = Get-Content $profilesYaml -Raw
$mCur = [regex]::Match($yaml, '(?m)^current:\s*(\S+)\s*$')
if (-not $mCur.Success) { Write-Host "cannot find 'current:' in profiles.yaml" -ForegroundColor Red; exit 1 }
$curUid = $mCur.Groups[1].Value

$mBlk = [regex]::Match($yaml, "(?ms)^- uid:\s*$([regex]::Escape($curUid))\s*$.*?(?=^- uid:|\z)")
if (-not $mBlk.Success) { Write-Host "cannot find profile block for uid '$curUid'" -ForegroundColor Red; exit 1 }
$blk = $mBlk.Value

Write-Host ''
Write-Host "current profile uid : $curUid" -ForegroundColor Cyan

$mName = [regex]::Match($blk, '(?m)^\s{2}name:\s*(.+?)\s*$')
$mType = [regex]::Match($blk, '(?m)^\s{2}type:\s*(\S+)\s*$')
$mFile = [regex]::Match($blk, '(?m)^\s{2}file:\s*(.+?)\s*$')

if ($mName.Success) { Write-Host ("name                : {0}" -f $mName.Groups[1].Value.Trim($trimChars)) }
if ($mType.Success) { Write-Host ("type                : {0}" -f $mType.Groups[1].Value) }
if ($mFile.Success) {
  $mf = $mFile.Groups[1].Value.Trim($trimChars)
  $mp = Join-Path $profDir $mf
  $mlen = if (Test-Path $mp) { (Get-Item $mp).Length } else { 0 }
  Write-Host ("main profile file   : {0}  ({1} bytes)" -f $mf, $mlen)
}

$mOpt = [regex]::Match($blk, '(?ms)^\s{2}option:\s*\n((?:\s{4}\w+:.*\n?)+)')
if (-not $mOpt.Success) {
  Write-Host ''
  Write-Host 'no option: block - this profile has no enhancement files yet.' -ForegroundColor Yellow
  Write-Host 'Open the enhancement editor in Clash Verge once to create them.' -ForegroundColor Yellow
  exit 0
}

Write-Host ''
Write-Host 'role      uid-file                        bytes' -ForegroundColor Cyan
Write-Host '--------  ------------------------------  -----'

foreach ($mm in [regex]::Matches($mOpt.Groups[1].Value, '(?m)^\s+(\w+):\s*(\S+)\s*$')) {
  $role = $mm.Groups[1].Value
  $uid  = $mm.Groups[2].Value

  $isScript = Test-Path (Join-Path $profDir ($uid + '.js'))
  $leaf = if ($isScript) { $uid + '.js' } else { $uid + '.yaml' }
  $full = Join-Path $profDir $leaf

  if (Test-Path $full) {
    Write-Host ("{0,-9} {1,-30} {2,5}" -f $role, $leaf, (Get-Item $full).Length)
  } else {
    Write-Host ("{0,-9} {1,-30} {2,5}  <-- MISSING" -f $role, $leaf, 0) -ForegroundColor Yellow
  }
}

Write-Host ''
Write-Host 'Global templates shared by all profiles: Merge.yaml, Script.js' -ForegroundColor DarkGray
