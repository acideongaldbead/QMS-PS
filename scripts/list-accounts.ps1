<#
  list-accounts.ps1
  Prints the seeded login accounts with the person they belong to and the roles
  they hold, straight from the database. Use this when handing the demo to
  someone instead of reciting a list from memory.

  Pure ASCII. Paths come from _paths.json.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\list-accounts.ps1"
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

if ($vars['QMS_DEV_PASSWORD']) { $devPassword = $vars['QMS_DEV_PASSWORD'] } else { $devPassword = 'Qms@2026' }

$m = [regex]::Match($vars['QMS_DB_URL'], 'jdbc:postgresql://([^:/]+)(?::(\d+))?/([^?]+)')
$host_ = $m.Groups[1].Value
$port  = if ($m.Groups[2].Success) { $m.Groups[2].Value } else { '5432' }
$db    = $m.Groups[3].Value
$psql  = Join-Path $cfg.pgBin 'psql.exe'
$env:PGPASSWORD = $vars['QMS_DB_PASSWORD']

# One line per account, tab separated so the caller can format it.
$sql = @"
SELECT a.username
       || E'\t' || e.name
       || E'\t' || coalesce(e.job_title, '')
       || E'\t' || coalesce(string_agg(r.role_name, ', ' ORDER BY r.role_id), '(no role)')
       || E'\t' || CASE WHEN a.password_hash = 'CHANGE_ME' THEN 'not set' ELSE 'set' END
  FROM qms.user_account a
  JOIN qms.employee e ON e.employee_id = a.employee_id
  LEFT JOIN qms.user_role ur ON ur.employee_id = a.employee_id AND ur.is_deleted = false
  LEFT JOIN qms.role r ON r.role_id = ur.role_id AND r.is_deleted = false
 WHERE a.is_deleted = false
 GROUP BY a.username, e.name, e.job_title, a.password_hash, e.employee_id
 ORDER BY e.employee_id;
"@

$rows = & $psql -h $host_ -p $port -U $vars['QMS_DB_USER'] -d $db -t -A -c $sql

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('QMS login accounts  (' + $host_ + ':' + $port + '/' + $db + ')')
$lines.Add('')
$lines.Add(('{0,-16} {1,-10} {2,-18} {3,-16} {4}' -f 'ACCOUNT', 'NAME', 'JOB TITLE', 'ROLE', 'PASSWORD'))
$lines.Add(('-' * 96))

foreach ($row in @($rows)) {
    if (-not $row) { continue }
    $c = $row -split "`t"
    $lines.Add(('{0,-16} {1,-10} {2,-18} {3,-16} {4}' -f $c[0], $c[1], $c[2], $c[3], $c[4]))
}

$lines.Add('')
$lines.Add('  demo password (all accounts) : ' + $devPassword)
$lines.Add('  login page                   : http://localhost:8080')
$lines.Add('')
$lines.Add('  NOTE The password is a development convenience: V9 seeds a CHANGE_ME')
$lines.Add('       sentinel and the app hashes this value at startup under the local')
$lines.Add('       profile. No hash is stored in the repository, and production leaves')
$lines.Add('       the sentinel in place so an administrator must set real passwords.')

$lines | ForEach-Object { [Console]::Out.WriteLine($_) }
