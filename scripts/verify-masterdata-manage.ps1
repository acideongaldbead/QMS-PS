<#
  verify-masterdata-manage.ps1
  Acceptance for master data maintenance (PS-109 dictionary entries, PS-036 the
  three-level failure type tree).

  Covers: the permission boundary; the dictionary type list; create / rename /
  re-sort / deactivate / reactivate / delete, code uniqueness across the whole
  table, the read-only priority list, and the guard that an entry business data
  still references cannot be deleted. For the failure type tree: the code follows
  its parent, a fourth level is refused, a branch switches its children off with
  it, a child cannot come back before its parent, and only a leaf can be deleted.

  Everything it creates is removed again, because verify-masterdata.ps1 asserts
  exact counts (tree 4/8/22, dictionary sizes). Test codes:
    dictionary  VERIFYMD-<stamp>
    failure type  Z / Za / Zaa

  Pure ASCII.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\verify-masterdata-manage.ps1"
  Optional:
    -BaseUrl http://localhost:8080  -Password Qms@2026  -KeepData
#>
[CmdletBinding()]
param(
    [string] $BaseUrl = 'http://localhost:8080',
    [string] $Password = 'Qms@2026',
    [switch] $KeepData
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
    return Invoke-RestMethod -Uri ($BaseUrl + '/api/auth/login') -Method Post `
        -ContentType 'application/json' -Body $body -TimeoutSec 20
}

function Invoke-Api([string] $method, [string] $path, [string] $token, $payload) {
    $headers = @{}
    if ($token) { $headers['Authorization'] = 'Bearer ' + $token }
    $reqArgs = @{ Uri = $BaseUrl + $path; Method = $method; Headers = $headers; TimeoutSec = 30; UseBasicParsing = $true }
    if ($null -ne $payload) {
        $reqArgs['ContentType'] = 'application/json; charset=utf-8'
        $reqArgs['Body'] = [System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Depth 12))
    }
    try {
        # Invoke-WebRequest, not Invoke-RestMethod: the latter hides the status code.
        $response = Invoke-WebRequest @reqArgs
        $body = $null
        if ($response.Content) { try { $body = $response.Content | ConvertFrom-Json } catch { $body = $response.Content } }
        return @{ status = [int]$response.StatusCode; body = $body }
    } catch {
        $status = 0
        $message = $_.Exception.Message
        try {
            $status = [int]$_.Exception.Response.StatusCode
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $text = $reader.ReadToEnd()
            $reader.Close()
            $parsed = $text | ConvertFrom-Json
            if ($parsed.message) { $message = $parsed.message }
        } catch { }
        return @{ status = $status; body = $null; message = $message }
    }
}

# --- database access, for the fixture lookup and the cleanup -----------------
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
$env:PGCLIENTENCODING = 'UTF8'
$env:PGPASSWORD = $vars['QMS_DB_PASSWORD']
$psql = Join-Path $cfg.pgBin 'psql.exe'

function Q([string] $sql) {
    return ((& $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value -t -A -c $sql) -join '').Trim()
}

# --- tree helpers ------------------------------------------------------------
function Count-Nodes($nodes) {
    $total = 0
    foreach ($node in @($nodes)) {
        if ($null -eq $node) { continue }
        $total = $total + 1 + (Count-Nodes $node.children)
    }
    return $total
}

function Find-Node($nodes, [string] $code) {
    foreach ($node in @($nodes)) {
        if ($null -eq $node) { continue }
        if ($node.code -eq $code) { return $node }
        $hit = Find-Node $node.children $code
        if ($null -ne $hit) { return $hit }
    }
    return $null
}

function Type-Row($types, [string] $mdType) {
    return @($types | Where-Object { $_.mdType -eq $mdType })[0]
}

function Item-ByCode($items, [string] $code) {
    return @($items | Where-Object { $_.code -eq $code })[0]
}

$lines.Add('verify-masterdata-manage  ->  ' + $BaseUrl)
$lines.Add('')

$stamp = Get-Date -Format 'HHmmss'
$dictType = 'responsible_org'
$dictCode = 'VERIFYMD-' + $stamp
$l1 = 'Z'
$l2 = 'Za'
$l3 = 'Zaa'

function Cleanup {
    # Leaf first: the self-reference is ON DELETE SET NULL, so order is not
    # enforced, but deleting children before parents keeps the intent obvious.
    Q "DELETE FROM qms.failure_type WHERE code IN ('Zaa','Za','Z');" | Out-Null
    Q ("DELETE FROM qms.master_data_item WHERE code LIKE 'VERIFYMD-%';") | Out-Null
}
Cleanup

$admin = Login 'ying.zhou' $Password
Check 'administrator logged in' ($null -ne $admin.accessToken) 'login failed'
$adminToken = $admin.accessToken
$qe = Login 'siyuan.li' $Password
Check 'quality engineer logged in' ($null -ne $qe.accessToken) 'login failed'
$qeToken = $qe.accessToken

$manage = '/api/master-data/manage'

# --- 1. permission boundary --------------------------------------------------
$anon = Invoke-Api 'POST' ($manage + '/dictionary/' + $dictType) '' @{ code = 'VERIFYMD-ANON'; nameCn = 'x' }
Check 'maintaining master data requires a login (401)' ($anon.status -eq 401) ('status=' + $anon.status)

$qeWrite = Invoke-Api 'POST' ($manage + '/dictionary/' + $dictType) $qeToken @{ code = 'VERIFYMD-QE'; nameCn = 'x' }
Check 'a quality engineer cannot maintain master data (403)' ($qeWrite.status -eq 403) ('status=' + $qeWrite.status)

$qeRead = Invoke-Api 'GET' ($manage + '/dictionary-types') $qeToken $null
Check 'a quality engineer cannot read the maintenance list (403)' ($qeRead.status -eq 403) ('status=' + $qeRead.status)

# --- 2. the type list --------------------------------------------------------
$types = @((Invoke-Api 'GET' ($manage + '/dictionary-types') $adminToken $null).body)
Check 'the maintainable type list loads' ($types.Count -ge 11) ('types=' + $types.Count)
Check 'the priority list is read-only' ((Type-Row $types 'priority').editable -eq $false) 'priority was editable'
Check 'other types are editable' ((Type-Row $types 'complaint_type').editable -eq $true) 'complaint_type was read-only'
Check 'the type list reports how many entries each holds' ((Type-Row $types $dictType).total -ge 1) 'no total'

# --- 3. dictionary entry lifecycle -------------------------------------------
$create = Invoke-Api 'POST' ($manage + '/dictionary/' + $dictType) $adminToken @{ code = $dictCode; nameCn = 'VERIFYMD entry'; nameEn = 'Verify master data' }
Check 'a dictionary entry is created' ($create.status -eq 200) ('status=' + $create.status + ' msg=' + $create.message)

$items = @((Invoke-Api 'GET' ($manage + '/dictionary/' + $dictType) $adminToken $null).body)
$created = Item-ByCode $items $dictCode
Check 'the new entry appears in the list' ($null -ne $created) ('code=' + $dictCode)
Check 'the new entry gets a sort order of its own' ($null -ne $created.sortOrder) ('sort=' + $created.sortOrder)
Check 'the new entry is active' ($created.active -eq $true) 'not active'

$duplicate = Invoke-Api 'POST' ($manage + '/dictionary/' + $dictType) $adminToken @{ code = $dictCode; nameCn = 'dup' }
Check 'a duplicate code is refused (409)' ($duplicate.status -eq 409) ('status=' + $duplicate.status)

# The unique constraint is on the whole table, not on (md_type, code).
$priorityCode = @((Invoke-Api 'GET' ('/api/master-data/dictionary/priority') $adminToken $null).body)[0].code
$crossType = Invoke-Api 'POST' ($manage + '/dictionary/' + $dictType) $adminToken @{ code = $priorityCode; nameCn = 'dup' }
Check 'a code already used by another type is refused (409)' ($crossType.status -eq 409) ('status=' + $crossType.status)

$blank = Invoke-Api 'POST' ($manage + '/dictionary/' + $dictType) $adminToken @{ code = 'VERIFYMD-BLANK'; nameCn = '  ' }
Check 'a blank name is refused (400)' ($blank.status -eq 400) ('status=' + $blank.status)

$unknownType = Invoke-Api 'GET' ($manage + '/dictionary/no_such_type') $adminToken $null
Check 'an unknown type is refused (404)' ($unknownType.status -eq 404) ('status=' + $unknownType.status)

$priorityWrite = Invoke-Api 'POST' ($manage + '/dictionary/priority') $adminToken @{ code = 'VERIFYMD-P1'; nameCn = 'x' }
Check 'the priority list cannot be maintained (409)' ($priorityWrite.status -eq 409) ('status=' + $priorityWrite.status)

$rename = Invoke-Api 'PUT' ($manage + '/dictionary/' + $dictType + '/' + $dictCode) $adminToken @{ nameCn = 'VERIFYMD renamed'; nameEn = 'Renamed'; sortOrder = 99 }
Check 'a dictionary entry can be renamed and re-sorted' ($rename.status -eq 200) ('status=' + $rename.status)

$items = @((Invoke-Api 'GET' ($manage + '/dictionary/' + $dictType) $adminToken $null).body)
$renamed = Item-ByCode $items $dictCode
Check 'the rename is visible in the list' ($renamed.nameCn -eq 'VERIFYMD renamed' -and $renamed.sortOrder -eq 99) ('name=' + $renamed.nameCn + ' sort=' + $renamed.sortOrder)

# Deactivating is what a picker sees: the public read only returns active entries.
$off = Invoke-Api 'POST' ($manage + '/dictionary/' + $dictType + '/' + $dictCode + '/deactivate') $adminToken $null
Check 'a dictionary entry can be deactivated' ($off.status -eq 200) ('status=' + $off.status)
$publicAfterOff = @((Invoke-Api 'GET' ('/api/master-data/dictionary/' + $dictType) $adminToken $null).body)
Check 'a deactivated entry leaves the picker' (@($publicAfterOff | Where-Object { $_.code -eq $dictCode }).Count -eq 0) 'still offered'

$on = Invoke-Api 'POST' ($manage + '/dictionary/' + $dictType + '/' + $dictCode + '/activate') $adminToken $null
Check 'a dictionary entry can be reactivated' ($on.status -eq 200) ('status=' + $on.status)
$publicAfterOn = @((Invoke-Api 'GET' ('/api/master-data/dictionary/' + $dictType) $adminToken $null).body)
Check 'a reactivated entry returns to the picker' (@($publicAfterOn | Where-Object { $_.code -eq $dictCode }).Count -eq 1) 'not offered'

$remove = Invoke-Api 'DELETE' ($manage + '/dictionary/' + $dictType + '/' + $dictCode) $adminToken $null
Check 'a dictionary entry can be deleted' ($remove.status -eq 200) ('status=' + $remove.status)
$items = @((Invoke-Api 'GET' ($manage + '/dictionary/' + $dictType) $adminToken $null).body)
Check 'the deleted entry is gone from the list' ($null -eq (Item-ByCode $items $dictCode)) 'still listed'

$reuse = Invoke-Api 'POST' ($manage + '/dictionary/' + $dictType) $adminToken @{ code = $dictCode; nameCn = 'reuse' }
Check 'the code can be reused after the delete' ($reuse.status -eq 200) ('status=' + $reuse.status)
Invoke-Api 'DELETE' ($manage + '/dictionary/' + $dictType + '/' + $dictCode) $adminToken $null | Out-Null

# An entry business data still points at must not disappear.
$usedTypeCode = Q "SELECT complaint_type_code FROM qms.complaint WHERE complaint_type_code IS NOT NULL AND is_deleted = false LIMIT 1;"
Check 'found a dictionary code business data references' ($usedTypeCode -ne '') ('code=' + $usedTypeCode)
if ($usedTypeCode -ne '') {
    $blocked = Invoke-Api 'DELETE' ($manage + '/dictionary/complaint_type/' + $usedTypeCode) $adminToken $null
    Check 'a referenced dictionary entry cannot be deleted (409)' ($blocked.status -eq 409) ('status=' + $blocked.status)
    $stillThere = @((Invoke-Api 'GET' ($manage + '/dictionary/complaint_type') $adminToken $null).body | Where-Object { $_.code -eq $usedTypeCode }).Count
    Check 'the referenced entry is still there' ($stillThere -eq 1) ('count=' + $stillThere)
}

# --- 4. failure type tree ----------------------------------------------------
$tree = @((Invoke-Api 'GET' ($manage + '/failure-types/tree') $adminToken $null).body)
Check 'the failure type tree loads' ($tree.Count -eq 4) ('level1=' + $tree.Count)
Check 'the tree holds all 34 nodes' ((Count-Nodes $tree) -eq 34) ('nodes=' + (Count-Nodes $tree))

$mkL1 = Invoke-Api 'POST' ($manage + '/failure-types') $adminToken @{ code = $l1; name = 'Z - Verify related' }
Check 'a level-1 failure type is created' ($mkL1.status -eq 200) ('status=' + $mkL1.status + ' msg=' + $mkL1.message)
$mkL2 = Invoke-Api 'POST' ($manage + '/failure-types') $adminToken @{ parentCode = $l1; code = $l2; name = 'Za - Verify child' }
Check 'a level-2 failure type is created under it' ($mkL2.status -eq 200) ('status=' + $mkL2.status + ' msg=' + $mkL2.message)
$mkL3 = Invoke-Api 'POST' ($manage + '/failure-types') $adminToken @{ parentCode = $l2; code = $l3; name = 'Zaa - Verify leaf' }
Check 'a level-3 failure type is created under that' ($mkL3.status -eq 200) ('status=' + $mkL3.status + ' msg=' + $mkL3.message)

$tree = @((Invoke-Api 'GET' ($manage + '/failure-types/tree') $adminToken $null).body)
Check 'the new branch appears in the tree' ($null -ne (Find-Node $tree $l3)) ('code=' + $l3)
Check 'the tree now holds 37 nodes' ((Count-Nodes $tree) -eq 37) ('nodes=' + (Count-Nodes $tree))

$badPrefix = Invoke-Api 'POST' ($manage + '/failure-types') $adminToken @{ parentCode = $l1; code = 'Yx'; name = 'wrong prefix' }
Check 'a code that ignores its parent is refused (400)' ($badPrefix.status -eq 400) ('status=' + $badPrefix.status)

$tooLong = Invoke-Api 'POST' ($manage + '/failure-types') $adminToken @{ parentCode = $l1; code = 'Zab'; name = 'too long' }
Check 'a code more than one character deeper is refused (400)' ($tooLong.status -eq 400) ('status=' + $tooLong.status)

$fourth = Invoke-Api 'POST' ($manage + '/failure-types') $adminToken @{ parentCode = $l3; code = 'Zaaa'; name = 'fourth level' }
Check 'a fourth level is refused (400)' ($fourth.status -eq 400) ('status=' + $fourth.status)

$dupFt = Invoke-Api 'POST' ($manage + '/failure-types') $adminToken @{ parentCode = $l1; code = $l2; name = 'dup' }
Check 'a duplicate failure type code is refused (409)' ($dupFt.status -eq 409) ('status=' + $dupFt.status)

$badParent = Invoke-Api 'POST' ($manage + '/failure-types') $adminToken @{ parentCode = 'NO_SUCH'; code = 'NO_SUCHa'; name = 'x' }
Check 'an unknown parent is refused (404)' ($badParent.status -eq 404) ('status=' + $badParent.status)

$renamedFt = Invoke-Api 'PUT' ($manage + '/failure-types/' + $l3) $adminToken @{ name = 'Zaa - Renamed leaf' }
Check 'a failure type can be renamed' ($renamedFt.status -eq 200) ('status=' + $renamedFt.status)
$tree = @((Invoke-Api 'GET' ($manage + '/failure-types/tree') $adminToken $null).body)
Check 'the rename is visible in the tree' ((Find-Node $tree $l3).name -eq 'Zaa - Renamed leaf') ((Find-Node $tree $l3).name)

# Switching a branch off takes the subtree with it.
$offBranch = Invoke-Api 'POST' ($manage + '/failure-types/' + $l2 + '/deactivate') $adminToken $null
Check 'a branch can be deactivated' ($offBranch.status -eq 200) ('status=' + $offBranch.status)
$tree = @((Invoke-Api 'GET' ($manage + '/failure-types/tree') $adminToken $null).body)
Check 'deactivating a branch switches its child off too' ((Find-Node $tree $l3).active -eq $false) 'child still active'
$publicTree = @((Invoke-Api 'GET' '/api/master-data/failure-types/tree' $adminToken $null).body)
Check 'the disabled branch leaves the picker' ($null -eq (Find-Node $publicTree $l2)) 'still offered'

# An active child under a disabled parent is unreachable in every picker, so it
# cannot be created in the first place.
$childUnderOff = Invoke-Api 'POST' ($manage + '/failure-types') $adminToken @{ parentCode = $l2; code = 'Zab'; name = 'under a disabled parent' }
Check 'a child cannot be added under a disabled parent (409)' ($childUnderOff.status -eq 409) ('status=' + $childUnderOff.status)

$childFirst = Invoke-Api 'POST' ($manage + '/failure-types/' + $l3 + '/activate') $adminToken $null
Check 'a child cannot return before its parent (409)' ($childFirst.status -eq 409) ('status=' + $childFirst.status)

$onBranch = Invoke-Api 'POST' ($manage + '/failure-types/' + $l2 + '/activate') $adminToken $null
Check 'the branch can be reactivated' ($onBranch.status -eq 200) ('status=' + $onBranch.status)
$onLeaf = Invoke-Api 'POST' ($manage + '/failure-types/' + $l3 + '/activate') $adminToken $null
Check 'the child can then be reactivated' ($onLeaf.status -eq 200) ('status=' + $onLeaf.status)

$delParent = Invoke-Api 'DELETE' ($manage + '/failure-types/' + $l2) $adminToken $null
Check 'a node with children cannot be deleted (409)' ($delParent.status -eq 409) ('status=' + $delParent.status)

$usedFtCode = Q "SELECT failure_type_l3_code FROM qms.sample WHERE failure_type_l3_code IS NOT NULL AND is_deleted = false LIMIT 1;"
Check 'found a failure type business data references' ($usedFtCode -ne '') ('code=' + $usedFtCode)
if ($usedFtCode -ne '') {
    $blockedFt = Invoke-Api 'DELETE' ($manage + '/failure-types/' + $usedFtCode) $adminToken $null
    Check 'a referenced failure type cannot be deleted (409)' ($blockedFt.status -eq 409) ('status=' + $blockedFt.status)
}

$delLeaf = Invoke-Api 'DELETE' ($manage + '/failure-types/' + $l3) $adminToken $null
Check 'a leaf can be deleted' ($delLeaf.status -eq 200) ('status=' + $delLeaf.status)
$delMid = Invoke-Api 'DELETE' ($manage + '/failure-types/' + $l2) $adminToken $null
Check 'the middle node can then be deleted' ($delMid.status -eq 200) ('status=' + $delMid.status)
$delRoot = Invoke-Api 'DELETE' ($manage + '/failure-types/' + $l1) $adminToken $null
Check 'the level-1 node can then be deleted' ($delRoot.status -eq 200) ('status=' + $delRoot.status)

$tree = @((Invoke-Api 'GET' ($manage + '/failure-types/tree') $adminToken $null).body)
Check 'the tree is back to 34 nodes' ((Count-Nodes $tree) -eq 34) ('nodes=' + (Count-Nodes $tree))

$reuseFt = Invoke-Api 'POST' ($manage + '/failure-types') $adminToken @{ code = $l1; name = 'Z again' }
Check 'the failure type code can be reused after the delete' ($reuseFt.status -eq 200) ('status=' + $reuseFt.status)

# --- 5. audit ----------------------------------------------------------------
$dictAudit = [int](Q ("SELECT count(*) FROM qms.audit_log WHERE biz_type='MasterDataItem' AND action_type='CREATE';"))
$ftAudit = [int](Q ("SELECT count(*) FROM qms.audit_log WHERE biz_type='FailureType' AND action_type='CREATE';"))
$ftStatusAudit = [int](Q ("SELECT count(*) FROM qms.audit_log WHERE biz_type='FailureType' AND action_type='STATUS_CHANGE';"))
$ftDeleteAudit = [int](Q ("SELECT count(*) FROM qms.audit_log WHERE biz_type='FailureType' AND action_type='DELETE';"))
Check 'creating a dictionary entry is audited' ($dictAudit -ge 1) ('rows=' + $dictAudit)
Check 'creating a failure type is audited' ($ftAudit -ge 1) ('rows=' + $ftAudit)
Check 'switching a failure type off is audited' ($ftStatusAudit -ge 1) ('rows=' + $ftStatusAudit)
Check 'deleting a failure type is audited' ($ftDeleteAudit -ge 1) ('rows=' + $ftDeleteAudit)

# --- 6. cleanup --------------------------------------------------------------
if ($KeepData) {
    $lines.Add('')
    $lines.Add('  kept: ' + $dictCode + ' / ' + $l1 + ' ' + $l2 + ' ' + $l3)
} else {
    Cleanup
    $leftDict = Q ("SELECT count(*) FROM qms.master_data_item WHERE code LIKE 'VERIFYMD-%';")
    $leftFt = Q "SELECT count(*) FROM qms.failure_type WHERE code IN ('Zaa','Za','Z');"
    $lines.Add('')
    $lines.Add('  cleaned up; leftover dictionary=' + $leftDict + ' failure-type=' + $leftFt)
}

$lines.Add('')
$lines.Add(('  RESULT : ' + $(if ($fail -eq 0) { 'PASS' } else { "FAIL ($fail)" }) + '   passed=' + $pass + ' failed=' + $fail))
$lines | Set-Content -Path (Join-Path $cfg.outDir 'verify_masterdata_manage_report.txt') -Encoding UTF8
$lines | ForEach-Object { [Console]::Out.WriteLine($_) }
if ($fail -ne 0) { exit 1 }
