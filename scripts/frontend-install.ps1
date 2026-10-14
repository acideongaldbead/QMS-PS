<#
  frontend-install.ps1
  Installs the frontend npm dependencies. Uses `npm ci` when a lockfile exists
  (reproducible), otherwise `npm install` to create one.

  Pure ASCII. Paths come from _paths.json.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\frontend-install.ps1"
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$cfgPath = Join-Path $PSScriptRoot '_paths.json'
$cfg = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json

$fe = Join-Path $cfg.root 'frontend'
if (-not (Test-Path (Join-Path $fe 'package.json'))) { throw "No package.json in $fe" }

$npm = (Get-Command npm -ErrorAction SilentlyContinue)
if (-not $npm) { throw 'npm not found on PATH' }

Push-Location $fe
try {
    $lock = Join-Path $fe 'package-lock.json'
    $manifest = Join-Path $fe 'package.json'
    $useCi = (Test-Path $lock) -and
             ((Get-Item $lock).LastWriteTime -ge (Get-Item $manifest).LastWriteTime)
    if ($useCi) {
        # The lockfile is current, so a reproducible install is possible.
        [Console]::Out.WriteLine('npm ci')
        & npm ci
    } else {
        # Either no lockfile, or package.json was edited since it was written --
        # `npm ci` would refuse to run in that case, so install to update the lock.
        [Console]::Out.WriteLine('npm install (lockfile missing or out of date)')
        & npm install
    }
    if ($LASTEXITCODE -ne 0) { throw "npm exited with $LASTEXITCODE" }
} finally {
    Pop-Location
}

$mods = Join-Path $fe 'node_modules'
if (Test-Path $mods) {
    $n = (Get-ChildItem $mods -Directory -ErrorAction SilentlyContinue).Count
    [Console]::Out.WriteLine("node_modules packages: $n")
}
[Console]::Out.WriteLine('RESULT : PASS')
