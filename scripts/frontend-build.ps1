<#
  frontend-build.ps1
  Type-checks and builds the Vue frontend into frontend\dist.

  Pure ASCII. Paths come from _paths.json.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\frontend-build.ps1"
  Optional:
    -SkipTypecheck   run vite build only
#>
[CmdletBinding()]
param(
    [switch] $SkipTypecheck
)

$ErrorActionPreference = 'Continue'

$cfgPath = Join-Path $PSScriptRoot '_paths.json'
$cfg = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json
$outDir = $cfg.outDir
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

$fe = Join-Path $cfg.root 'frontend'
if (-not (Test-Path (Join-Path $fe 'node_modules'))) { throw "Run frontend-install.ps1 first" }

$script = if ($SkipTypecheck) { 'build:only' } else { 'build' }
$log = Join-Path $outDir 'frontend_build.log'
$lines = New-Object System.Collections.Generic.List[string]

Push-Location $fe
try {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    & npm run $script *> $log
    $code = $LASTEXITCODE
    $sw.Stop()
} finally {
    Pop-Location
}

$lines.Add('frontend-build')
$lines.Add('  script : npm run ' + $script)
$lines.Add('  exit   : ' + $code + '  in ' + [int]$sw.Elapsed.TotalSeconds + 's')
$lines.Add('  log    : ' + $log)

$dist = Join-Path $fe 'dist'
if ($code -eq 0 -and (Test-Path $dist)) {
    $files = @(Get-ChildItem $dist -Recurse -File)
    $bytes = ($files | Measure-Object -Property Length -Sum).Sum
    $lines.Add('  dist   : ' + $files.Count + ' files, ' + [math]::Round($bytes / 1MB, 2) + ' MB')
    $lines.Add('  RESULT : PASS')
} else {
    $lines.Add('')
    $lines.Add('  --- last 30 log lines ---')
    if (Test-Path $log) { foreach ($l in (Get-Content $log -Tail 30)) { $lines.Add('  | ' + $l) } }
    $lines.Add('  RESULT : FAIL')
}

$lines | Set-Content -Path (Join-Path $outDir 'frontend_build_report.txt') -Encoding UTF8
$lines | ForEach-Object { [Console]::Out.WriteLine($_) }
if ($code -ne 0) { exit 1 }
