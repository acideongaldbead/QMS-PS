<#
  verify-auth.ps1
  Stage-1 acceptance for login and RBAC, run against a live backend.

  Pure ASCII (Chinese assertions are expressed as permission codes, not text).

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\verify-auth.ps1"
  Optional:
    -BaseUrl http://localhost:8080   -Password Qms@2026
#>
[CmdletBinding()]
param(
    [string] $BaseUrl = 'http://localhost:8080',
    [string] $Password = 'Qms@2026'
)

$ErrorActionPreference = 'Continue'

$cfgPath = Join-Path $PSScriptRoot '_paths.json'
$cfg = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json
if (-not (Test-Path $cfg.outDir)) { New-Item -ItemType Directory -Path $cfg.outDir -Force | Out-Null }

$pass = 0
$fail = 0
$lines = New-Object System.Collections.Generic.List[string]
function Check([string] $name, [bool] $ok, [string] $detail) {
    if ($ok) { $script:pass++; $lines.Add(('  PASS  {0}' -f $name)) }
    else     { $script:fail++; $lines.Add(('  FAIL  {0}  -> {1}' -f $name, $detail)) }
}

function Login([string] $user, [string] $pwd) {
    try {
        $body = @{ username = $user; password = $pwd } | ConvertTo-Json
        return Invoke-RestMethod -Uri ($BaseUrl + '/api/auth/login') -Method Post `
            -ContentType 'application/json' -Body $body -TimeoutSec 20
    } catch {
        return $null
    }
}

function MeWith([string] $token) {
    try {
        return Invoke-RestMethod -Uri ($BaseUrl + '/api/auth/me') -Method Get `
            -Headers @{ Authorization = ('Bearer ' + $token) } -TimeoutSec 20
    } catch {
        return $null
    }
}

$lines.Add('verify-auth  ->  ' + $BaseUrl)
$lines.Add('')

# --- health -----------------------------------------------------------------
try {
    $h = Invoke-RestMethod -Uri ($BaseUrl + '/actuator/health') -TimeoutSec 10
    Check 'backend health is UP' ($h.status -eq 'UP') ('status=' + $h.status)
} catch {
    Check 'backend health is UP' $false $_.Exception.Message
    $lines.Add('  aborted: backend not reachable')
    $lines | Set-Content -Path (Join-Path $cfg.outDir 'verify_auth_report.txt') -Encoding UTF8
    $lines | ForEach-Object { [Console]::Out.WriteLine($_) }
    exit 1
}

# --- unauthenticated access is refused --------------------------------------
$anon = $null
try {
    $anon = Invoke-RestMethod -Uri ($BaseUrl + '/api/auth/me') -TimeoutSec 10
} catch {
    $anon = $null
}
Check 'GET /api/auth/me without a token is refused' ($null -eq $anon) 'it returned data'

# --- Sales Quality ----------------------------------------------------------
$sales = Login 'xiaoran.ma' $Password
Check 'sales quality can log in' ($null -ne $sales -and $sales.accessToken) 'login failed'
if ($sales) {
    $me = MeWith $sales.accessToken
    Check 'sales quality /me returns a profile' ($null -ne $me) 'no profile'
    Check 'sales quality has report:send' ($me.permissions -contains 'report:send') ($me.permissions -join ',')
    Check 'sales quality has complaint:create' ($me.permissions -contains 'complaint:create') ($me.permissions -join ',')
    Check 'sales quality does NOT have report:approve' (-not ($me.permissions -contains 'report:approve')) ($me.permissions -join ',')
    Check 'sales quality does NOT have admin.all' (-not ($me.permissions -contains 'admin.all')) ($me.permissions -join ',')
}

# --- Auditor ----------------------------------------------------------------
$aud = Login 'zhiyuan.chen' $Password
Check 'auditor can log in' ($null -ne $aud -and $aud.accessToken) 'login failed'
if ($aud) {
    $me = MeWith $aud.accessToken
    Check 'auditor has report:approve' ($me.permissions -contains 'report:approve') ($me.permissions -join ',')
    Check 'auditor has audit:view' ($me.permissions -contains 'audit:view') ($me.permissions -join ',')
    Check 'auditor does NOT have complaint:create' (-not ($me.permissions -contains 'complaint:create')) ($me.permissions -join ',')
}

# --- Administrator ----------------------------------------------------------
$admin = Login 'ying.zhou' $Password
Check 'administrator can log in' ($null -ne $admin -and $admin.accessToken) 'login failed'
if ($admin) {
    $me = MeWith $admin.accessToken
    Check 'administrator has admin.all' ($me.permissions -contains 'admin.all') ($me.permissions -join ',')
    Check 'administrator has rbac:manage' ($me.permissions -contains 'rbac:manage') ($me.permissions -join ',')
    Check 'administrator permission count is the full set' ($me.permissions.Count -ge 25) ('count=' + $me.permissions.Count)
}

# --- Quality engineer -------------------------------------------------------
$qe = Login 'siyuan.li' $Password
Check 'quality engineer can log in' ($null -ne $qe -and $qe.accessToken) 'login failed'
if ($qe) {
    $me = MeWith $qe.accessToken
    Check 'quality engineer has rootcause:edit' ($me.permissions -contains 'rootcause:edit') ($me.permissions -join ',')
    Check 'quality engineer does NOT have report:send' (-not ($me.permissions -contains 'report:send')) ($me.permissions -join ',')
}

# --- bad credentials --------------------------------------------------------
$bad = Login 'xiaoran.ma' 'definitely-wrong'
Check 'wrong password is rejected' ($null -eq $bad) 'login unexpectedly succeeded'

# --- unknown user -----------------------------------------------------------
$ghost = Login 'nobody.here' $Password
Check 'unknown account is rejected' ($null -eq $ghost) 'login unexpectedly succeeded'

$lines.Add('')
$lines.Add(('  RESULT : ' + $(if ($fail -eq 0) { 'PASS' } else { "FAIL ($fail)" }) + '   passed=' + $pass + ' failed=' + $fail))
$report = Join-Path $cfg.outDir 'verify_auth_report.txt'
$lines | Set-Content -Path $report -Encoding UTF8
$lines | ForEach-Object { [Console]::Out.WriteLine($_) }
if ($fail -ne 0) { exit 1 }
