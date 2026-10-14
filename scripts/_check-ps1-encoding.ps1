<#
  _check-ps1-encoding.ps1
  Guard for the convention: a .ps1 must either be pure ASCII, or carry a UTF-8
  BOM. A file with non-ASCII bytes and no BOM is decoded as GBK by PowerShell
  5.1, which turns Chinese literals into mojibake -- and worse, can swallow the
  closing quote of a string literal, producing parse errors far from the cause.

  Run this after editing any script. Exit code 1 when a file violates the rule.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\_check-ps1-encoding.ps1"
  Optional:
    -Directory <path>    default: this script's folder
#>
[CmdletBinding()]
param(
    [string] $Directory = $PSScriptRoot
)

$ErrorActionPreference = 'Continue'

$violations = New-Object System.Collections.Generic.List[string]
$checked = 0

foreach ($file in Get-ChildItem -Path $Directory -Filter *.ps1 -File) {
    $checked++
    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)

    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $nonAscii = $false
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        if ($bytes[$i] -ge 0x80) { $nonAscii = $true; break }
    }

    if ($nonAscii -and -not $hasBom) {
        # Report where the first offending byte is, to make the fix quick.
        $line = 1
        $column = 1
        for ($i = 0; $i -lt $bytes.Length; $i++) {
            if ($bytes[$i] -eq 0x0A) { $line++; $column = 1; continue }
            if ($bytes[$i] -ge 0x80) { break }
            $column++
        }
        $violations.Add(('  {0}  (first non-ASCII byte at line {1}, column {2})' -f $file.Name, $line, $column))
    }
}

[Console]::Out.WriteLine('ps1 encoding check: ' + $checked + ' script(s) in ' + $Directory)
if ($violations.Count -eq 0) {
    [Console]::Out.WriteLine('  every script is pure ASCII or carries a BOM')
    [Console]::Out.WriteLine('  RESULT : PASS')
} else {
    [Console]::Out.WriteLine('  VIOLATIONS (non-ASCII without a BOM -- PowerShell 5.1 will mis-decode these):')
    $violations | ForEach-Object { [Console]::Out.WriteLine($_) }
    [Console]::Out.WriteLine('  FIX: move the Chinese into scripts\_verify_expectations.json, or add a UTF-8 BOM')
    [Console]::Out.WriteLine('  RESULT : FAIL (' + $violations.Count + ')')
    exit 1
}
