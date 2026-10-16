<#
  ui-masterdata.ps1
  UI half of the master data task (PS-109 dictionary entries, PS-036 the
  three-level failure type tree): drives both screens in a real browser - adds a
  knowledge category and checks the knowledge centre's own sidebar picks it up,
  then builds, renames, disables and deletes a three-level branch.

  The browser half authors everything itself (dictionary UIMD-, failure type
  W / Wa / Waa), so this script only sweeps those before and after the run.

  Pure ASCII; the browser half carries the Chinese it has to look for.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\ui-masterdata.ps1"
  Optional:
    -BaseUrl http://localhost:8080   -Password Qms@2026   -KeepData
#>
[CmdletBinding()]
param(
    [string] $BaseUrl = 'http://localhost:8080',
    [string] $Password = 'Qms@2026',
    [string] $Admin = 'ying.zhou',
    [string] $Engineer = 'siyuan.li',
    [switch] $KeepData
)

$ErrorActionPreference = 'Continue'

$cfgPath = Join-Path $PSScriptRoot '_paths.json'
$cfg = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json
$outDir = Join-Path $cfg.outDir 'ui'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

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
$dbHost = $m.Groups[1].Value
$dbPort = $m.Groups[2].Value
$dbName = $m.Groups[3].Value
$dbUser = $vars['QMS_DB_USER']
$psql = Join-Path $cfg.pgBin 'psql.exe'
$env:PGCLIENTENCODING = 'UTF8'
$env:PGPASSWORD = $vars['QMS_DB_PASSWORD']

function Q([string] $sql) {
    return ((& $psql -h $dbHost -p $dbPort -U $dbUser -d $dbName -t -A -c $sql) -join '').Trim()
}

function Cleanup {
    # Leaf first, though the self-reference is ON DELETE SET NULL so order is not
    # enforced; the dictionary rows are only ever created by this script.
    Q "DELETE FROM qms.failure_type WHERE code IN ('Waa','Wa','W');" | Out-Null
    Q "DELETE FROM qms.master_data_item WHERE code LIKE 'UIMD-%';" | Out-Null
}

Cleanup

$login = Invoke-RestMethod -Uri ($BaseUrl + '/api/auth/login') -Method Post `
    -ContentType 'application/json' -TimeoutSec 20 `
    -Body (@{ username = $Admin; password = $Password } | ConvertTo-Json)
if (-not $login.accessToken) { throw 'admin login failed' }

$stamp = Get-Date -Format 'HHmmss'
$prefix = 'UIMD-' + $stamp
[Console]::Out.WriteLine('master data ui: prefix=' + $prefix)

$e2e = Join-Path $cfg.root 'e2e'
$edge = @(
    (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
    (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe')
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $edge) { throw 'msedge.exe not found' }

if (-not (Test-Path (Join-Path $e2e 'node_modules'))) {
    Push-Location $e2e
    try { & npm install --no-audit --no-fund | Out-Null } finally { Pop-Location }
}

$nodeArgs = @(
    (Join-Path $e2e 'masterdata.mjs'),
    ('--prefix=' + $prefix),
    ('--user=' + $Admin),
    ('--engineer=' + $Engineer),
    ('--base=' + $BaseUrl),
    ('--out=' + $outDir),
    ('--password=' + $Password),
    ('--edge=' + $edge)
)
Push-Location $e2e
try { $output = & node @nodeArgs 2>&1 } finally { Pop-Location }
$output | ForEach-Object { [Console]::Out.WriteLine($_) }
$nodeExit = $LASTEXITCODE

if (-not $KeepData) {
    Cleanup
    $leftDict = Q ("SELECT count(*) FROM qms.master_data_item WHERE code LIKE 'UIMD-%';")
    $leftFt = Q "SELECT count(*) FROM qms.failure_type WHERE code IN ('Waa','Wa','W');"
    [Console]::Out.WriteLine('  cleaned up: dictionary=' + $leftDict + ' failure-type=' + $leftFt)
}

if ($nodeExit -ne 0) { exit 1 }
