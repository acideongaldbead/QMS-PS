<#
  ui-home.ps1
  UI half of task 2.10: drives the home dashboard in a real browser - the four
  figures, the overdue banner, the to-do groups, the announcement drawer and the
  deep link from a to-do entry into the complaint's tab.

  It creates nothing, so it cleans nothing up: the numbers it asserts on are read
  from the same API the page reads and handed to the browser script, so the check
  is "does the screen show the data" rather than "does the screen show a constant".

  Pure ASCII.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\ui-home.ps1"
  Optional:
    -BaseUrl http://localhost:8080   -Password Qms@2026   -User siyuan.li
#>
[CmdletBinding()]
param(
    [string] $BaseUrl = 'http://localhost:8080',
    [string] $Password = 'Qms@2026',
    [string] $User = 'siyuan.li'
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
$psql = Join-Path $cfg.pgBin 'psql.exe'
$env:PGCLIENTENCODING = 'UTF8'
$env:PGPASSWORD = $vars['QMS_DB_PASSWORD']

$login = Invoke-RestMethod -Uri ($BaseUrl + '/api/auth/login') -Method Post `
    -ContentType 'application/json' -TimeoutSec 20 `
    -Body (@{ username = $User; password = $Password } | ConvertTo-Json)
$token = $login.accessToken
if (-not $token) { throw 'login failed' }
$headers = @{ Authorization = 'Bearer ' + $token }

# The NEW badge is per reader, so the run needs a known starting point: this
# user's read markers are cleared, which makes every published announcement new
# again. Without it the assertion would depend on what an earlier run opened.
# The login response nests the employee under "user".
$employeeId = $login.user.employeeId
if (-not $employeeId) { throw 'login response carried no employeeId' }
& $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value -q `
    -c ("DELETE FROM qms.announcement_read WHERE employee_id = '" + $employeeId + "';") | Out-Null

$overview = Invoke-RestMethod -Uri ($BaseUrl + '/api/home/overview') -Headers $headers -TimeoutSec 30
$todos = @($overview.todos)
if ($todos.Count -eq 0) { throw 'no to-do entries: nothing to drive the home page with' }

# Assign first, wrap second: in PowerShell 5.1 Invoke-RestMethod writes a JSON
# array to the pipeline as a single object, so @(Invoke-RestMethod ...) yields one
# element whose properties are arrays, and every count below would read 1.
$announcements = Invoke-RestMethod -Uri ($BaseUrl + '/api/announcements') -Headers $headers -TimeoutSec 30
$expectNew = @($announcements | Where-Object { $_.isNew -eq $true }).Count
if ($expectNew -eq 0) { throw 'no unread announcement: the NEW badge cannot be checked' }

# The deep link is checked on an entry whose tab is not the registration tab, so
# the assertion can tell "opened the right tab" from "opened the default one".
$deep = $todos | Where-Object { $_.type -eq 'VERIFICATION' } | Select-Object -First 1
if (-not $deep) { $deep = $todos | Where-Object { $_.tab -ne 'd01' } | Select-Object -First 1 }
if (-not $deep) { $deep = $todos[0] }

[Console]::Out.WriteLine('home data: todos=' + $overview.stats.todoCount + ' types=' + $overview.stats.todoTypeCount `
    + ' urgent=' + $overview.stats.overdueTaskCount + ' mine=' + $overview.stats.myComplaintCount)
[Console]::Out.WriteLine('deep link: ' + $deep.type + ' -> ' + $deep.complaintId + ' tab ' + $deep.tab)

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
    (Join-Path $e2e 'home.mjs'),
    ('--todos=' + $overview.stats.todoCount),
    ('--mine=' + $overview.stats.myComplaintCount),
    ('--urgent=' + $overview.stats.overdueTaskCount),
    ('--pending=' + $overview.stats.pendingApprovalCount),
    ('--types=' + $overview.stats.todoTypeCount),
    ('--expectNew=' + $expectNew),
    ('--deepType=' + $deep.type),
    ('--deepComplaint=' + $deep.complaintId),
    ('--deepTab=' + $deep.tab),
    ('--user=' + $User),
    ('--base=' + $BaseUrl),
    ('--out=' + $outDir),
    ('--password=' + $Password),
    ('--edge=' + $edge)
)
Push-Location $e2e
try { $output = & node @nodeArgs 2>&1 } finally { Pop-Location }
$output | ForEach-Object { [Console]::Out.WriteLine($_) }
$nodeExit = $LASTEXITCODE

if ($nodeExit -ne 0) { exit 1 }
