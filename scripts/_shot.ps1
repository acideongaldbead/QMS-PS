<#
  _shot.ps1
  Renders a URL with headless Edge and saves a PNG, so a change can be seen and
  verified rather than assumed.

  Pure ASCII. Paths come from _paths.json.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\_shot.ps1" -Url "http://localhost:8080/" -Name login
  Optional:
    -Width 1680 -Height 1500 -WaitMs 2500
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $Url,
    [Parameter(Mandatory = $true)][string] $Name,
    [int] $Width = 1680,
    [int] $Height = 1500,
    [int] $WaitMs = 2500
)

$ErrorActionPreference = 'Continue'

$cfgPath = Join-Path $PSScriptRoot '_paths.json'
$cfg = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json

$shotDir = Join-Path $cfg.outDir 'shots'
if (-not (Test-Path $shotDir)) { New-Item -ItemType Directory -Path $shotDir -Force | Out-Null }
$outFile = Join-Path $shotDir ($Name + '.png')

$edge = @(
    (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
    (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe')
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

if (-not $edge) { throw 'msedge.exe not found' }

# A throwaway profile each run: headless Edge otherwise reuses session state.
$profile = Join-Path $cfg.outDir ('_edge_' + $Name)
if (Test-Path $profile) { Remove-Item -Recurse -Force $profile -ErrorAction SilentlyContinue }

$edgeArgs = @(
    '--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
    '--hide-scrollbars',
    ('--user-data-dir=' + $profile),
    ('--window-size=' + $Width + ',' + $Height),
    ('--virtual-time-budget=' + $WaitMs),
    ('--screenshot=' + $outFile),
    $Url
)

& $edge @edgeArgs 2>$null | Out-Null
Start-Sleep -Milliseconds 500

if (Test-Path $outFile) {
    [Console]::Out.WriteLine('shot : ' + $outFile + '  (' + [math]::Round((Get-Item $outFile).Length / 1KB, 1) + ' KB)')
} else {
    [Console]::Out.WriteLine('shot FAILED: ' + $outFile)
    exit 1
}
