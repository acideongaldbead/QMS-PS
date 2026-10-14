<#
  verify-masterdata.ps1
  Stage-1 acceptance for the master-data read APIs, including the negative
  permission case (a quality engineer must not reach the RBAC lists).

  Pure ASCII.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\verify-masterdata.ps1"
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
    $body = @{ username = $user; password = $pwd } | ConvertTo-Json
    return (Invoke-RestMethod -Uri ($BaseUrl + '/api/auth/login') -Method Post `
        -ContentType 'application/json' -Body $body -TimeoutSec 20)
}

function Get-Api([string] $path, [string] $token) {
    return Invoke-RestMethod -Uri ($BaseUrl + $path) -Method Get `
        -Headers @{ Authorization = ('Bearer ' + $token) } -TimeoutSec 20
}

# Returns the HTTP status code, for the endpoints that must be refused.
function Get-ApiStatus([string] $path, [string] $token) {
    try {
        Invoke-RestMethod -Uri ($BaseUrl + $path) -Method Get `
            -Headers @{ Authorization = ('Bearer ' + $token) } -TimeoutSec 20 | Out-Null
        return 200
    } catch {
        return [int]$_.Exception.Response.StatusCode
    }
}

$lines.Add('verify-masterdata  ->  ' + $BaseUrl)
$lines.Add('')

$qe = Login 'siyuan.li' $Password
$qeToken = $qe.accessToken
Check 'quality engineer logged in' ($null -ne $qeToken) 'login failed'
if (-not $qeToken) { $lines | ForEach-Object { [Console]::Out.WriteLine($_) }; exit 1 }

# --- dictionaries -----------------------------------------------------------
$prio = Get-Api '/api/master-data/dictionary/priority' $qeToken
Check 'priority dictionary has 3 entries' (@($prio).Count -eq 3) ('count=' + @($prio).Count)
Check 'priority carries English names' ((@($prio | Where-Object { $_.nameEn }).Count) -eq 3) 'missing nameEn'

$locations = Get-Api '/api/master-data/dictionary/failure_location' $qeToken
Check 'failure location has 6 entries' (@($locations).Count -eq 6) ('count=' + @($locations).Count)

$modes = Get-Api '/api/master-data/dictionary/failure_mode' $qeToken
Check 'failure mode has 8 entries' (@($modes).Count -eq 8) ('count=' + @($modes).Count)

$segments = Get-Api '/api/master-data/dictionary/sub_segment' $qeToken
Check 'sub segment has 5 entries' (@($segments).Count -eq 5) ('count=' + @($segments).Count)

# --- failure type cascade ---------------------------------------------------
$tree = Get-Api '/api/master-data/failure-types/tree' $qeToken
Check 'failure type tree has 4 top levels' (@($tree).Count -eq 4) ('count=' + @($tree).Count)

$l2Total = 0
$l3Total = 0
foreach ($l1 in @($tree)) {
    foreach ($l2 in @($l1.children)) {
        $l2Total++
        $l3Total += @($l2.children).Count
    }
}
Check 'level 2 nodes present' ($l2Total -eq 8) ('count=' + $l2Total)
Check 'level 3 nodes present' ($l3Total -eq 22) ('count=' + $l3Total)

$bondWire = $tree | Where-Object { $_.code -eq '2' } | ForEach-Object { $_.children } | Where-Object { $_.code -eq '2a' }
Check 'a cascade path resolves 2 -> 2a -> 2aa' (
    ($null -ne $bondWire) -and (@($bondWire.children | Where-Object { $_.code -eq '2aa' }).Count -eq 1)
) 'expected 2aa under 2a'

# --- customers / ship-to / contacts -----------------------------------------
$customers = Get-Api '/api/master-data/customers' $qeToken
Check 'customers list has 4 entries' (@($customers).Count -eq 4) ('count=' + @($customers).Count)

$filtered = Get-Api '/api/master-data/customers?q=%E5%8D%9A%E4%B8%96' $qeToken
Check 'customer search filters by name' (@($filtered).Count -eq 1) ('count=' + @($filtered).Count)

$shipTo = Get-Api '/api/master-data/customers/CUST-1001/ship-to' $qeToken
Check 'ship-to resolves for CUST-1001' (@($shipTo).Count -eq 2) ('count=' + @($shipTo).Count)

$contacts = Get-Api '/api/master-data/customers/CUST-1001/contacts' $qeToken
Check 'contacts resolve for CUST-1001' (@($contacts).Count -eq 1) ('count=' + @($contacts).Count)

# --- products / employees ---------------------------------------------------
$products = Get-Api '/api/master-data/products' $qeToken
Check 'products list has 3 entries' (@($products).Count -eq 3) ('count=' + @($products).Count)
Check 'product type name is resolved' (($products | Where-Object { -not $_.productTypeName }).Count -eq 0) 'a product had no type name'
Check 'packing type name is resolved' (($products | Where-Object { -not $_.packingTypeName }).Count -eq 0) 'a product had no packing name'

$employees = Get-Api '/api/master-data/employees' $qeToken
Check 'employees list has 9 entries' (@($employees).Count -eq 9) ('count=' + @($employees).Count)
Check 'employees carry Chinese and English names' (
    (@($employees | Where-Object { $_.name -and $_.nameEn }).Count) -eq 9
) 'missing a name'

# --- status codes -----------------------------------------------------------
$statuses = Get-Api '/api/master-data/status-codes?entity=Complaint' $qeToken
Check 'complaint status codes have 7 entries' (@($statuses).Count -eq 7) ('count=' + @($statuses).Count)
Check 'exactly one complaint status is final' (@($statuses | Where-Object { $_.isFinal }).Count -eq 1) 'final count wrong'

# --- permission boundary ----------------------------------------------------
$qeRoles = Get-ApiStatus '/api/master-data/roles' $qeToken
Check 'quality engineer is refused the role list (403)' ($qeRoles -eq 403) ('status=' + $qeRoles)

$admin = Login 'ying.zhou' $Password
$adminToken = $admin.accessToken
$roles = Get-Api '/api/master-data/roles' $adminToken
Check 'administrator sees 4 roles' (@($roles).Count -eq 4) ('count=' + @($roles).Count)

$perms = Get-Api '/api/master-data/permissions' $adminToken
Check 'administrator sees 26 permissions' (@($perms).Count -eq 26) ('count=' + @($perms).Count)

$anon = Get-ApiStatus '/api/master-data/customers' ''
Check 'master data requires a login' ($anon -eq 401) ('status=' + $anon)

$lines.Add('')
$lines.Add(('  RESULT : ' + $(if ($fail -eq 0) { 'PASS' } else { "FAIL ($fail)" }) + '   passed=' + $pass + ' failed=' + $fail))
$lines | Set-Content -Path (Join-Path $cfg.outDir 'verify_masterdata_report.txt') -Encoding UTF8
$lines | ForEach-Object { [Console]::Out.WriteLine($_) }
if ($fail -ne 0) { exit 1 }
