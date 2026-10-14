<#
  ui-wizard.ps1
  End-to-end registration test through the real UI: signs in, fills all five
  wizard steps, submits, and reports the complaint id that was created. Screenshots
  each step under tools\_out\ui\.

  Pure ASCII. Paths come from _paths.json.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\ui-wizard.ps1"
  Optional:
    -User xiaoran.ma   -BaseUrl http://localhost:8080   -Password Qms@2026
#>
[CmdletBinding()]
param(
    [string] $User = 'xiaoran.ma',
    [string] $BaseUrl = 'http://localhost:8080',
    [string] $Password = 'Qms@2026',
    # The wizard creates a real complaint. By default it is removed afterwards so
    # repeated runs do not pile up rows in the ledger.
    [switch] $KeepData
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
    (Join-Path $e2e 'wizard.mjs'),
    ('--base=' + $BaseUrl),
    ('--out=' + $outDir),
    ('--password=' + $Password),
    ('--user=' + $User),
    ('--edge=' + $edge)
)

Push-Location $e2e
try { $output = & node @nodeArgs 2>&1 } finally { Pop-Location }
$output | ForEach-Object { [Console]::Out.WriteLine($_) }

if (-not $KeepData) {
    $match = [regex]::Match(($output -join "`n"), 'created=(C\d{9})')
    if ($match.Success) {
        $id = $match.Groups[1].Value
        $envFile = Join-Path $cfg.root 'config\.env'
        $vars = @{}
        foreach ($line in [System.IO.File]::ReadAllLines($envFile)) {
            $t = $line.Trim()
            if ($t -eq '' -or $t.StartsWith('#')) { continue }
            $i = $t.IndexOf('=')
            if ($i -lt 1) { continue }
            $vars[$t.Substring(0, $i).Trim()] = $t.Substring($i + 1).Trim()
        }
        $m = [regex]::Match($vars['QMS_DB_URL'], 'jdbc:postgresql://([^:/]+)(?::(\d+))?/([^?]+)')
        $env:PGCLIENTENCODING = 'UTF8'
        $env:PGPASSWORD = $vars['QMS_DB_PASSWORD']
        & (Join-Path $cfg.pgBin 'psql.exe') -h $m.Groups[1].Value -p $m.Groups[2].Value `
            -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value -q `
            -c ("DELETE FROM qms.complaint WHERE complaint_id = '" + $id + "';") | Out-Null
        [Console]::Out.WriteLine('  cleaned up ' + $id)
    }
}
