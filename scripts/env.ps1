<#
  env.ps1
  Dot-source this to prepare the current shell for QMS work:
    - loads <root>\config\.env into environment variables
    - puts the portable JDK / Maven / Git and the PostgreSQL client on PATH
    - sets PGCLIENTENCODING=UTF8 (Windows psql otherwise writes UTF-8 as GBK mojibake)

  Usage (single line, note the leading dot):
    . "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\env.ps1"

  Pure ASCII.
#>

$__cfgPath = Join-Path $PSScriptRoot '_paths.json'
if (-not (Test-Path $__cfgPath)) { throw "Missing config: $__cfgPath" }
$__cfg = [System.IO.File]::ReadAllText($__cfgPath) | ConvertFrom-Json

$__envFile = Join-Path $__cfg.root 'config\.env'
if (Test-Path $__envFile) {
    foreach ($line in [System.IO.File]::ReadAllLines($__envFile)) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        $i = $t.IndexOf('=')
        if ($i -lt 1) { continue }
        $k = $t.Substring(0, $i).Trim()
        $v = $t.Substring($i + 1).Trim()
        [Environment]::SetEnvironmentVariable($k, $v, 'Process')
    }
}

$__jdk = Join-Path $__cfg.toolsDir 'jdk-21'
$__mvn = Join-Path $__cfg.toolsDir 'maven\bin'
$__git = Join-Path $__cfg.toolsDir 'git\cmd'

$env:JAVA_HOME = $__jdk
$env:PGCLIENTENCODING = 'UTF8'

$add = @($__jdk, (Join-Path $__jdk 'bin'), $__mvn, $__git, $__cfg.pgBin) | Where-Object { Test-Path $_ }
$env:PATH = (($add -join ';') + ';' + $env:PATH)
