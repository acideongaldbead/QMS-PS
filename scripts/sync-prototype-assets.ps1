<#
  sync-prototype-assets.ps1
  Copies the already-approved design assets from the HTML prototype into the new
  frontend, byte-for-byte, so the rebuilt app keeps the exact same look:
     tokens.css / base.css / components.css  -> frontend/src/styles/
     nexperia-wordmark.png                   -> frontend/src/assets/
  Also parks reference copies of the prototype's mock data and shell script under
  docs/reference/ -- they are the source of truth for the seed data (V9) and for
  the nav / i18n / RBAC-gating logic we are porting.

  Pure ASCII. Paths come from _paths.json.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\sync-prototype-assets.ps1"
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$cfgPath = Join-Path $PSScriptRoot '_paths.json'
$cfg = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json

$src  = $cfg.prototypeDir
$root = $cfg.root

if (-not (Test-Path $src)) { throw "Prototype dir not found: $src" }

$map = @(
    @{ from = 'assets\css\tokens.css';        to = 'frontend\src\styles\tokens.css' },
    @{ from = 'assets\css\base.css';          to = 'frontend\src\styles\base.css' },
    @{ from = 'assets\css\components.css';    to = 'frontend\src\styles\components.css' },
    @{ from = 'assets\img\nexperia-wordmark.png'; to = 'frontend\src\assets\nexperia-wordmark.png' },
    @{ from = 'assets\js\shell.js';           to = 'docs\reference\shell.js' },
    @{ from = 'assets\js\mock-data.js';       to = 'docs\reference\mock-data.js' }
)

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('sync-prototype-assets')
$fail = 0

foreach ($m in $map) {
    $f = Join-Path $src $m.from
    $t = Join-Path $root $m.to
    if (-not (Test-Path $f)) {
        $lines.Add('  MISSING SOURCE: ' + $m.from)
        $fail++
        continue
    }
    $dir = Split-Path -Parent $t
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Copy-Item -LiteralPath $f -Destination $t -Force

    $a = [System.IO.File]::ReadAllBytes($f)
    $b = [System.IO.File]::ReadAllBytes($t)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $ha = [BitConverter]::ToString($sha.ComputeHash($a)).Replace('-', '')
    $hb = [BitConverter]::ToString($sha.ComputeHash($b)).Replace('-', '')
    $same = ($ha -eq $hb)
    if (-not $same) { $fail++ }
    $lines.Add(('  {0,-34} -> {1,-46} {2,8} bytes  {3}' -f $m.from, $m.to, $b.Length, $(if ($same) { 'OK' } else { 'HASH MISMATCH' })))
}

$lines.Add('  RESULT : ' + $(if ($fail -eq 0) { 'PASS' } else { "FAIL ($fail)" }))

$outDir = $cfg.outDir
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$lines | Set-Content -Path (Join-Path $outDir 'prototype_assets_report.txt') -Encoding UTF8
$lines | ForEach-Object { [Console]::Out.WriteLine($_) }
if ($fail -ne 0) { exit 1 }
