<#
  db-create.ps1
  Connects to the existing PostgreSQL 18 service with the credentials from
  config\.env and makes sure the application database exists.

  Read-only against anything except CREATE DATABASE (idempotent).
  Pure ASCII.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\db-create.ps1"
#>
[CmdletBinding()]
param(
    [string] $Database = 'qms'
)

$ErrorActionPreference = 'Stop'
$env:PGCLIENTENCODING = 'UTF8'

$cfgPath = Join-Path $PSScriptRoot '_paths.json'
$cfg = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json

if (-not (Test-Path $cfg.outDir)) { New-Item -ItemType Directory -Path $cfg.outDir -Force | Out-Null }
$reportPath = Join-Path $cfg.outDir 'db_create_report.txt'

# read .env so we get the password without hardcoding it anywhere
$envFile = Join-Path $cfg.root 'config\.env'
if (-not (Test-Path $envFile)) { throw "Missing config\.env (copy config\.env.example)" }
$vars = @{}
foreach ($line in [System.IO.File]::ReadAllLines($envFile)) {
    $t = $line.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    $i = $t.IndexOf('=')
    if ($i -lt 1) { continue }
    $vars[$t.Substring(0, $i).Trim()] = $t.Substring($i + 1).Trim()
}

$dbUrl = $vars['QMS_DB_URL']
$dbUser = $vars['QMS_DB_USER']
$dbPass = $vars['QMS_DB_PASSWORD']
if (-not $dbUrl -or -not $dbUser) { throw "QMS_DB_URL / QMS_DB_USER missing in config\.env" }

# parse host/port out of jdbc:postgresql://host:port/db
$m = [regex]::Match($dbUrl, 'jdbc:postgresql://([^:/]+)(?::(\d+))?/([^?]+)')
if (-not $m.Success) { throw "Cannot parse QMS_DB_URL: $dbUrl" }
$host_ = $m.Groups[1].Value
$port  = if ($m.Groups[2].Success) { $m.Groups[2].Value } else { '5432' }

$psql    = Join-Path $cfg.pgBin 'psql.exe'
$createdb = Join-Path $cfg.pgBin 'createdb.exe'
$env:PGPASSWORD = $dbPass

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('db-create')
$lines.Add('  host   : ' + $host_ + ':' + $port)
$lines.Add('  user   : ' + $dbUser)
$lines.Add('  target : ' + $Database)

# 1. connectivity + server version
$ver = & $psql -h $host_ -p $port -U $dbUser -d postgres -t -A -c "select version();" 2>&1
if ($LASTEXITCODE -ne 0) {
    $lines.Add('  CONNECT FAILED: ' + ($ver -join ' '))
    $lines += '  RESULT : FAIL'
    $lines | ForEach-Object { [Console]::Out.WriteLine($_) }
    $lines | Set-Content -Path $reportPath -Encoding UTF8
    exit 1
}
$lines.Add('  server : ' + ($ver -join ' '))

# 2. does the database exist?
$exists = & $psql -h $host_ -p $port -U $dbUser -d postgres -t -A -c "select 1 from pg_database where datname = '$Database';" 2>&1
if (($exists -join '').Trim() -eq '1') {
    $lines.Add('  database already exists')
} else {
    $out = & $createdb -h $host_ -p $port -U $dbUser -E UTF8 -T template0 $Database 2>&1
    if ($LASTEXITCODE -ne 0) {
        $lines.Add('  CREATE DATABASE FAILED: ' + ($out -join ' '))
        $lines += '  RESULT : FAIL'
        $lines | ForEach-Object { [Console]::Out.WriteLine($_) }
        $lines | Set-Content -Path $reportPath -Encoding UTF8
        exit 1
    }
    $lines.Add('  database created')
}

# 3. confirm we can select from it
$chk = & $psql -h $host_ -p $port -U $dbUser -d $Database -t -A -c "select current_database();" 2>&1
$lines.Add('  current_database : ' + ($chk -join ''))

# 4. is the qms schema already there?
$sch = & $psql -h $host_ -p $port -U $dbUser -d $Database -t -A -c "select count(*) from information_schema.schemata where schema_name = 'qms';" 2>&1
$lines.Add('  qms schema present : ' + (($sch -join '').Trim() -eq '1'))

$tbl = & $psql -h $host_ -p $port -U $dbUser -d $Database -t -A -c "select count(*) from information_schema.tables where table_schema = 'qms' and table_type = 'BASE TABLE';" 2>&1
$lines.Add('  qms tables : ' + (($tbl -join '').Trim()))

$lines.Add('  RESULT : PASS')
$outFile = Join-Path $cfg.outDir 'db_create_report.txt'
if (-not (Test-Path $cfg.outDir)) { New-Item -ItemType Directory -Path $cfg.outDir -Force | Out-Null }
$lines | Set-Content -Path $outFile -Encoding UTF8
$lines | ForEach-Object { [Console]::Out.WriteLine($_) }
