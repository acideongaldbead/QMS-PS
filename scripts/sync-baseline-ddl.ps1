<#
  sync-baseline-ddl.ps1
  Copies the FROZEN deliverable DDL into the Flyway baseline, byte-for-byte, and
  verifies the copy is identical and carries no UTF-8 BOM (psql chokes on a BOM).

  Pure ASCII on purpose. Paths come from _paths.json.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\sync-baseline-ddl.ps1"
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$cfgPath = Join-Path $PSScriptRoot '_paths.json'
if (-not (Test-Path $cfgPath)) { throw "Missing config: $cfgPath" }
$cfg = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json

$src = $cfg.deliverableDdl
$dst = $cfg.baselineOut

if (-not (Test-Path -LiteralPath $src)) { throw "Source DDL not found: $src" }

$dstDir = Split-Path -Parent $dst
if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }

Copy-Item -LiteralPath $src -Destination $dst -Force

$srcBytes = [System.IO.File]::ReadAllBytes($src)
$dstBytes = [System.IO.File]::ReadAllBytes($dst)

$sha = [System.Security.Cryptography.SHA256]::Create()
$srcHash = [BitConverter]::ToString($sha.ComputeHash($srcBytes)).Replace('-', '')
$dstHash = [BitConverter]::ToString($sha.ComputeHash($dstBytes)).Replace('-', '')

$identical = ($srcHash -eq $dstHash)
$hasBom = ($dstBytes.Length -ge 3 -and $dstBytes[0] -eq 0xEF -and $dstBytes[1] -eq 0xBB -and $dstBytes[2] -eq 0xBF)

$text = [System.IO.File]::ReadAllText($dst)
$tableCount = ([regex]::Matches($text, '(?m)^CREATE TABLE ')).Count
$fkCount    = ([regex]::Matches($text, '(?m)^ALTER TABLE .* ADD CONSTRAINT fk_')).Count
$idxCount   = ([regex]::Matches($text, '(?m)^CREATE INDEX ')).Count
$trgCount   = ([regex]::Matches($text, '(?m)^CREATE TRIGGER ')).Count
$cmtCount   = ([regex]::Matches($text, '(?m)^COMMENT ON ')).Count
$functionCount = ([regex]::Matches($text, '(?m)^CREATE (OR REPLACE )?FUNCTION ')).Count

$lines = @()
$lines += 'sync-baseline-ddl'
$lines += ('  source      : ' + $src)
$lines += ('  target      : ' + $dst)
$lines += ('  bytes       : ' + $dstBytes.Length)
$lines += ('  sha256 src  : ' + $srcHash)
$lines += ('  sha256 dst  : ' + $dstHash)
$lines += ('  identical   : ' + $identical)
$lines += ('  utf8-bom    : ' + $hasBom + '  (must be False)')
$lines += ('  CREATE TABLE    : ' + $tableCount + '  (expect 45)')
$lines += ('  FOREIGN KEY     : ' + $fkCount + '  (expect 86)')
$lines += ('  CREATE INDEX    : ' + $idxCount + '  (expect 113)')
$lines += ('  CREATE TRIGGER  : ' + $trgCount + '  (expect 44)')
$lines += ('  COMMENT ON      : ' + $cmtCount + '  (expect 630)')
$lines += ('  CREATE FUNCTION : ' + $functionCount + '  (expect 2)')

$ok = $identical -and (-not $hasBom) -and $tableCount -eq 45 -and $fkCount -eq 86 -and $idxCount -eq 113 -and $trgCount -eq 44
$lines += ('  RESULT      : ' + $(if ($ok) { 'PASS' } else { 'FAIL' }))

$outDir = $cfg.outDir
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$lines | Set-Content -Path (Join-Path $outDir 'baseline_ddl_report.txt') -Encoding UTF8

$lines | ForEach-Object { Write-Output $_ }
if (-not $ok) { exit 1 }
