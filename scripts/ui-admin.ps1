<#
  ui-admin.ps1
  UI half of the RBAC administration task (requirement 3.12): drives the three
  administration tabs in a real browser - reading the user list, seeing that the
  preset roles are read-only, building a custom role, ticking a permission on the
  matrix, assigning the role to somebody, resetting a password, and checking that
  a user without the permission never reaches the screen.

  The browser half authors its own role (prefix UIADM-) and resets one seeded
  account's password, so this script sweeps both afterwards: it deletes the
  UIADM roles and puts the account's original password hash back.

  Pure ASCII; the browser half carries the Chinese it has to look for.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\ui-admin.ps1"
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
    Q "DELETE FROM qms.role_permission WHERE role_id IN (SELECT role_id FROM qms.role WHERE role_name LIKE 'UIADM-%');" | Out-Null
    Q "DELETE FROM qms.user_role WHERE role_id IN (SELECT role_id FROM qms.role WHERE role_name LIKE 'UIADM-%');" | Out-Null
    Q "DELETE FROM qms.role WHERE role_name LIKE 'UIADM-%';" | Out-Null
}

Cleanup

# The reset check needs a real target. This is a seeded account no other
# verification logs in as, and its password hash is restored at the end.
$spare = Q "SELECT employee_id || '|' || username || '|' || password_hash FROM qms.user_account WHERE username <> 'siyuan.li' AND is_deleted = false AND employee_id IN ('U02','U04','U06','U07','U09') ORDER BY employee_id LIMIT 1;"
$spareParts = $spare.Split('|')
$spareId = $spareParts[0]
$spareUser = $spareParts[1]
$spareHash = $spareParts[2]
if (-not $spareId -or -not $spareUser) { throw 'no spare account is available for the reset check' }

$login = Invoke-RestMethod -Uri ($BaseUrl + '/api/auth/login') -Method Post `
    -ContentType 'application/json' -TimeoutSec 20 `
    -Body (@{ username = $Admin; password = $Password } | ConvertTo-Json)
if (-not $login.accessToken) { throw 'admin login failed' }

$stamp = Get-Date -Format 'HHmmss'
$prefix = 'UIADM-' + $stamp
[Console]::Out.WriteLine('admin ui: prefix=' + $prefix + '  spare=' + $spareUser)

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
    (Join-Path $e2e 'admin.mjs'),
    ('--prefix=' + $prefix),
    ('--user=' + $Admin),
    ('--engineer=' + $Engineer),
    ('--spare=' + $spareUser),
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
    Q ("UPDATE qms.user_account SET password_hash = '" + $spareHash + "', must_change_pwd = false, failed_attempts = 0, locked_until = NULL WHERE employee_id = '" + $spareId + "';") | Out-Null
    $left = Q "SELECT count(*) FROM qms.role WHERE role_name LIKE 'UIADM-%';"
    [Console]::Out.WriteLine('  cleaned up: UIADM roles left=' + $left + ', password of ' + $spareUser + ' restored')
}

if ($nodeExit -ne 0) { exit 1 }
