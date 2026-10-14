<#
  db-validate-migrations.ps1
  Applies every db\migration\V*.sql, in order, to a SCRATCH database so the SQL is
  proven before Flyway ever runs it (and before the app exists). The scratch DB
  is dropped afterwards unless -Keep is given, so the real `qms` database is never
  touched and Flyway still sees a clean slate.

  Pure ASCII. Paths come from _paths.json.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\db-validate-migrations.ps1"
  Optional:
    -ScratchDb qms_migtest   -Keep
#>
[CmdletBinding()]
param(
    [string] $ScratchDb = 'qms_migtest',
    [switch] $Keep
)

$ErrorActionPreference = 'Stop'
$env:PGCLIENTENCODING = 'UTF8'

$cfgPath = Join-Path $PSScriptRoot '_paths.json'
$cfg = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json
if (-not (Test-Path $cfg.outDir)) { New-Item -ItemType Directory -Path $cfg.outDir -Force | Out-Null }
$reportPath = Join-Path $cfg.outDir 'migration_validate_report.txt'

$envFile = Join-Path $cfg.root 'config\.env'
if (-not (Test-Path $envFile)) { throw "Missing config\.env" }
$vars = @{}
foreach ($line in [System.IO.File]::ReadAllLines($envFile)) {
    $t = $line.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    $i = $t.IndexOf('=')
    if ($i -lt 1) { continue }
    $vars[$t.Substring(0, $i).Trim()] = $t.Substring($i + 1).Trim()
}

$m = [regex]::Match($vars['QMS_DB_URL'], 'jdbc:postgresql://([^:/]+)(?::(\d+))?/([^?]+)')
if (-not $m.Success) { throw "Cannot parse QMS_DB_URL" }
$host_ = $m.Groups[1].Value
$port  = if ($m.Groups[2].Success) { $m.Groups[2].Value } else { '5432' }

$psql     = Join-Path $cfg.pgBin 'psql.exe'
$createdb = Join-Path $cfg.pgBin 'createdb.exe'
$dropdb   = Join-Path $cfg.pgBin 'dropdb.exe'
$env:PGPASSWORD = $vars['QMS_DB_PASSWORD']

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('db-validate-migrations')
$lines.Add('  scratch db : ' + $ScratchDb + '  @ ' + $host_ + ':' + $port)
$lines.Add('')

function Run-Psql([string] $db, [string] $sql) {
    & $psql -h $host_ -p $port -U $vars['QMS_DB_USER'] -d $db -t -A -c $sql
    return $LASTEXITCODE
}

# fresh scratch database
& $dropdb -h $host_ -p $port -U $vars['QMS_DB_USER'] --if-exists $ScratchDb
& $createdb -h $host_ -p $port -U $vars['QMS_DB_USER'] -E UTF8 -T template0 $ScratchDb
if ($LASTEXITCODE -ne 0) { throw "Could not create scratch database $ScratchDb" }

$failed = 0
# Sort by the NUMERIC version, not the file name: from V10 onwards a string sort
# puts V10 before V2, which silently validates the migrations in the wrong order.
# Flyway compares versions numerically, so this must match it.
$files = Get-ChildItem (Join-Path $cfg.root 'db\migration') -Filter 'V*.sql' |
    Sort-Object { [int]([regex]::Match($_.BaseName, '^V(\d+)').Groups[1].Value) }
$lines.Add('  applying ' + $files.Count + ' migration files')
$lines.Add('')

foreach ($f in $files) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $log = Join-Path $cfg.outDir ('_mig_' + $f.BaseName + '.log')
    & $psql -h $host_ -p $port -U $vars['QMS_DB_USER'] -d $ScratchDb -v ON_ERROR_STOP=1 -q -f $f.FullName -o $log
    $code = $LASTEXITCODE
    $sw.Stop()
    if ($code -eq 0) {
        $lines.Add(('  OK      {0,-34} {1,5}ms' -f $f.Name, [int]$sw.Elapsed.TotalMilliseconds))
    } else {
        $failed++
        $lines.Add(('  FAILED  {0,-34} exit {1}' -f $f.Name, $code))
        if (Test-Path $log) {
            foreach ($l in (Get-Content $log -Tail 12)) { $lines.Add('          | ' + $l) }
        }
    }
}

# What did we end up with?
$lines.Add('')
$lines.Add('--- resulting objects in ' + $ScratchDb + ' ---')
if ($failed -eq 0) {
    $q = "select table_schema || '.' || table_name from information_schema.tables where table_type='BASE TABLE' and table_schema in ('qms','public') order by 1;"
    $tables = & $psql -h $host_ -p $port -U $vars['QMS_DB_USER'] -d $ScratchDb -t -A -c $q
    $lines.Add('  tables : ' + (@($tables).Count))

    $counts = @(
        @{ label = 'roles';        sql = 'select count(*) from qms.role' },
        @{ label = 'permissions';  sql = 'select count(*) from qms.permission' },
        @{ label = 'role_perms';   sql = 'select count(*) from qms.role_permission' },
        @{ label = 'status_codes'; sql = 'select count(*) from qms.status_code' },
        @{ label = 'translations'; sql = 'select count(*) from qms.translation' }
    )
    foreach ($c in $counts) {
        $r = & $psql -h $host_ -p $port -U $vars['QMS_DB_USER'] -d $ScratchDb -t -A -c $c.sql
        $lines.Add(('  {0,-14}: {1}' -f $c.label, (($r -join '').Trim())))
    }

    $stage = & $psql -h $host_ -p $port -U $vars['QMS_DB_USER'] -d $ScratchDb -t -A -c "select column_default from information_schema.columns where table_schema='qms' and table_name='complaint' and column_name='current_stage';"
    $lines.Add('  complaint.current_stage default : ' + (($stage -join '').Trim()))
}

if (-not $Keep) {
    & $dropdb -h $host_ -p $port -U $vars['QMS_DB_USER'] --if-exists $ScratchDb
    $lines.Add('  (scratch database dropped)')
} else {
    $lines.Add('  (scratch database KEPT: ' + $ScratchDb + ')')
}

$lines.Add('')
$lines.Add('  RESULT : ' + $(if ($failed -eq 0) { 'PASS' } else { "FAIL ($failed files)" }))
$lines | Set-Content -Path $reportPath -Encoding UTF8
$lines | ForEach-Object { [Console]::Out.WriteLine($_) }
if ($failed -ne 0) { exit 1 }
