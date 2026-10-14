<#
  db-check.ps1
  Reports the state of the live application database: which migrations Flyway has
  applied, and how much master / business data is present. Read-only.

  Pure ASCII. Paths come from _paths.json.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\db-check.ps1"
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$env:PGCLIENTENCODING = 'UTF8'

$cfgPath = Join-Path $PSScriptRoot '_paths.json'
$cfg = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json

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
$host_ = $m.Groups[1].Value
$port  = if ($m.Groups[2].Success) { $m.Groups[2].Value } else { '5432' }
$db    = $m.Groups[3].Value
$psql  = Join-Path $cfg.pgBin 'psql.exe'
$env:PGPASSWORD = $vars['QMS_DB_PASSWORD']
$user = $vars['QMS_DB_USER']

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('db-check  ->  ' + $host_ + ':' + $port + '/' + $db)

function Q([string] $sql) {
    $r = & $psql -h $host_ -p $port -U $user -d $db -t -A -c $sql
    return (($r -join ' ').Trim())
}

$lines.Add('')
$lines.Add('--- flyway ---')
$hasHist = Q "select count(*) from information_schema.tables where table_schema='qms' and table_name='flyway_schema_history';"
if ($hasHist -eq '1') {
    $applied = & $psql -h $host_ -p $port -U $user -d $db -t -A -c "select version || ' | ' || description || ' | ' || case when success then 'OK' else 'FAILED' end from qms.flyway_schema_history order by installed_rank;"
    foreach ($a in @($applied)) { $lines.Add('  ' + $a) }
} else {
    $lines.Add('  (no flyway_schema_history in schema qms)')
}

$lines.Add('')
$lines.Add('--- structure ---')
$lines.Add('  tables in qms : ' + (Q "select count(*) from information_schema.tables where table_schema='qms' and table_type='BASE TABLE';"))
$lines.Add('  views in qms  : ' + (Q "select count(*) from information_schema.views where table_schema='qms';"))
$lines.Add('  foreign keys  : ' + (Q "select count(*) from pg_constraint c join pg_namespace n on n.oid=c.connamespace where c.contype='f' and n.nspname='qms';"))

$lines.Add('')
$lines.Add('--- master data ---')
$checks = @(
    @{ label = 'employees';      sql = 'select count(*) from qms.employee' },
    @{ label = 'login accounts'; sql = 'select count(*) from qms.user_account' },
    @{ label = 'roles';          sql = 'select count(*) from qms.role' },
    @{ label = 'permissions';    sql = 'select count(*) from qms.permission' },
    @{ label = 'role x perm';    sql = 'select count(*) from qms.role_permission' },
    @{ label = 'user x role';    sql = 'select count(*) from qms.user_role' },
    @{ label = 'status codes';   sql = 'select count(*) from qms.status_code' },
    @{ label = 'master items';   sql = 'select count(*) from qms.master_data_item' },
    @{ label = 'failure types';  sql = 'select count(*) from qms.failure_type' },
    @{ label = 'customers';      sql = 'select count(*) from qms.customer' },
    @{ label = 'contacts';      sql = 'select count(*) from qms.contact_person' },
    @{ label = 'ship-to';        sql = 'select count(*) from qms.ship_to_sold_to' },
    @{ label = 'products';       sql = 'select count(*) from qms.product_master' },
    @{ label = 'production md';  sql = 'select count(*) from qms.production_master' },
    @{ label = 'tpt rules';      sql = 'select count(*) from qms.notification_rule' },
    @{ label = 'announcements';  sql = 'select count(*) from qms.system_announcement' },
    @{ label = 'complaints';     sql = 'select count(*) from qms.complaint' }
)
foreach ($c in $checks) {
    $lines.Add(('  {0,-16}: {1}' -f $c.label, (Q $c.sql)))
}

$lines.Add('')
$lines.Add('--- accounts with a placeholder password ---')
$ph = Q "select coalesce(string_agg(username, ', ' order by username), '(none)') from qms.user_account where password_hash = 'CHANGE_ME';"
$lines.Add('  ' + $ph)

$outPath = Join-Path $cfg.outDir 'db_check_report.txt'
if (-not (Test-Path $cfg.outDir)) { New-Item -ItemType Directory -Path $cfg.outDir -Force | Out-Null }
$lines | Set-Content -Path $outPath -Encoding UTF8
$lines | ForEach-Object { [Console]::Out.WriteLine($_) }
