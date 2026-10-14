<#
  ui-capture.ps1
  Drives the running app in headless Edge, logs in as each role, screenshots the
  shell (and optionally further routes) and writes tools\_out\ui\ui_capture.json
  describing what each role could see.

  Pure ASCII. Paths come from _paths.json.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\ui-capture.ps1"
  Optional:
    -Users "xiaoran.ma,siyuan.li,ying.zhou"   -Pages "/complaints,/reports"   -BaseUrl ...
#>
[CmdletBinding()]
param(
    [string] $Users = 'xiaoran.ma,siyuan.li,zhenyu.wang,zhiyuan.chen,ying.zhou',
    [string] $Pages = '',
    [string] $BaseUrl = 'http://localhost:8080',
    [string] $Password = 'Qms@2026'
)

$ErrorActionPreference = 'Continue'

$cfgPath = Join-Path $PSScriptRoot '_paths.json'
$cfg = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json

$e2e = Join-Path $cfg.root 'e2e'
$outDir = Join-Path $cfg.outDir 'ui'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

$edge = @(
    (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
    (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe')
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $edge) { throw 'msedge.exe not found' }

if (-not (Test-Path (Join-Path $e2e 'node_modules'))) {
    [Console]::Out.WriteLine('installing e2e dependencies ...')
    Push-Location $e2e
    try { & npm install --no-audit --no-fund | Out-Null } finally { Pop-Location }
}

$nodeArgs = @(
    (Join-Path $e2e 'capture.mjs'),
    ('--base=' + $BaseUrl),
    ('--out=' + $outDir),
    ('--password=' + $Password),
    ('--users=' + $Users),
    ('--edge=' + $edge)
)
if ($Pages) { $nodeArgs += ('--pages=' + $Pages) }

Push-Location $e2e
try { & node @nodeArgs } finally { Pop-Location }
