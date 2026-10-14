<#
  db-clear-complaints.ps1
  Deletes every complaint (and, by cascade, its quality partner / product /
  failure description / sample rows). Intended for resetting the demo database
  before reseeding; there is nothing else to remove because the schema keeps all
  child rows tied to the complaint.

  Destructive on purpose, so it refuses to run without -Force.

  Audit rows are deliberately left in place: the audit trail is the one thing
  that should survive a data reset.

  Pure ASCII. Paths come from _paths.json.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\db-clear-complaints.ps1" -Force
#>
[CmdletBinding()]
param(
    [switch] $Force
)

$ErrorActionPreference = 'Stop'
$env:PGCLIENTENCODING = 'UTF8'

if (-not $Force) {
    throw 'Refusing to delete data without -Force'
}

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
$user  = $vars['QMS_DB_USER']
$psql  = Join-Path $cfg.pgBin 'psql.exe'
$env:PGPASSWORD = $vars['QMS_DB_PASSWORD']

function Q([string] $sql) {
    return ((& $psql -h $host_ -p $port -U $user -d $db -t -A -c $sql) -join ' ').Trim()
}

$before = Q 'SELECT count(*) FROM qms.complaint;'
& $psql -h $host_ -p $port -U $user -d $db -q -c 'DELETE FROM qms.complaint;' | Out-Null
$after = Q 'SELECT count(*) FROM qms.complaint;'

[Console]::Out.WriteLine('db-clear-complaints  ->  ' + $host_ + ':' + $port + '/' + $db)
[Console]::Out.WriteLine('  complaints before : ' + $before)
[Console]::Out.WriteLine('  complaints now    : ' + $after)
[Console]::Out.WriteLine('  child rows left   : ' + (Q 'SELECT (SELECT count(*) FROM qms.sample) + (SELECT count(*) FROM qms.quality_partner) + (SELECT count(*) FROM qms.product_info) + (SELECT count(*) FROM qms.failure_description);'))
[Console]::Out.WriteLine('  audit rows kept   : ' + (Q "SELECT count(*) FROM qms.audit_log WHERE biz_type = 'Complaint';"))
