<#
  verify-ledger.ps1
  Acceptance for the complaint ledger query (requirement 3.1.1): paging, the
  filters, the sort whitelist, the two tabs' counters, the soft-delete boundary,
  permissions, the Excel export and its audit trail.

  Objects: two complaints registered by the quality engineer (one of them
  overdue) and one registered by a sales-quality user that nobody on it is the
  engineer - which is what makes the "与我相关" tab observable.

  Data is found through a marker on the customer reference and removed afterwards.

  Pure ASCII (no Chinese is asserted; the checks are on codes, counts and dates).

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\verify-ledger.ps1"
  Optional:
    -BaseUrl http://localhost:8080   -Password Qms@2026   -KeepData
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
$psql = Join-Path $cfg.pgBin 'psql.exe'
$env:PGCLIENTENCODING = 'UTF8'
$env:PGPASSWORD = $vars['QMS_DB_PASSWORD']

function Q([string] $sql) {
    return ((& $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value -t -A -c $sql) -join ' ').Trim()
}

$pass = 0; $fail = 0
$lines = New-Object System.Collections.Generic.List[string]
function Check([string] $name, [bool] $ok, [string] $detail) {
    if ($ok) { $script:pass++; $lines.Add(('  PASS  {0}' -f $name)) }
    else     { $script:fail++; $lines.Add(('  FAIL  {0}  -> {1}' -f $name, $detail)) }
}

function Get-ErrorStatus($err) { try { return [int]$err.Exception.Response.StatusCode } catch { return 0 } }
function Login([string] $user, [string] $pwd) {
    $body = @{ username = $user; password = $pwd } | ConvertTo-Json
    return Invoke-RestMethod -Uri ($BaseUrl + '/api/auth/login') -Method Post `
        -ContentType 'application/json' -Body $body -TimeoutSec 20
}
function Api([string] $method, [string] $path, [string] $token, $payload) {
    $headers = @{}
    if ($token) { $headers['Authorization'] = 'Bearer ' + $token }
    $a = @{ Uri = $BaseUrl + $path; Method = $method; Headers = $headers; TimeoutSec = 30; UseBasicParsing = $true }
    if ($null -ne $payload) {
        $a['ContentType'] = 'application/json; charset=utf-8'
        $a['Body'] = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $payload -Depth 12))
    }
    try {
        $response = Invoke-WebRequest @a
        $body = $null
        if ($response.Content) { $body = $response.Content | ConvertFrom-Json }
        return @{ status = [int]$response.StatusCode; body = $body }
    } catch {
        return @{ status = Get-ErrorStatus $_; body = $null; message = $_ }
    }
}

$lines.Add('verify-ledger  ->  ' + $BaseUrl)
$lines.Add('')

$marker = 'VERIFYLEDGER'

# --- clean anything a previous interrupted run left behind -------------------
& $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value -q `
    -c ("DELETE FROM qms.complaint WHERE customer_reference_id LIKE '" + $marker + "%';") | Out-Null

$qe = Login 'siyuan.li' $Password
$engineerToken = $qe.accessToken
Check 'quality engineer logged in (holds complaint:view)' ($null -ne $engineerToken) 'login failed'
if (-not $engineerToken) { $lines | ForEach-Object { [Console]::Out.WriteLine($_) }; exit 1 }

$salesToken = (Login 'xiaoran.ma' $Password).accessToken
Check 'sales quality logged in' ($null -ne $salesToken) 'login failed'

# --- 1. access control -------------------------------------------------------
$anon = Api 'GET' '/api/complaints' $null $null
Check 'an anonymous request is rejected with 401' ($anon.status -eq 401) ('status=' + $anon.status)

# --- 2. seed the objects -----------------------------------------------------
$today = (Get-Date).Date
$iso = { param($d) $d.ToString('yyyy-MM-dd') }

function New-Sample([string] $ref) {
    return ,@(
        @{ customerSampleId = $ref; sampleQuantity = 3; uom = 'PCS'
           failureTypeL1Code = '2'; failureTypeL2Code = '2c'; failureTypeL3Code = '2ca' }
    )
}

# The engineer's own, ten days past its target date.
$minePast = (Api 'POST' '/api/complaints' $engineerToken @{
    header = @{
        complaintTypeCode = 'COMPLAINT_TYPE_001'; priorityCode = 'PRIORITY_003'
        failureLocationCode = 'FAILURE_LOCATION_005'; complaintOwnerId = 'U04'
        coordinatorId = 'U01'; startDate = (& $iso $today.AddDays(-20)); targetDate = (& $iso $today.AddDays(-10))
        customerTargetDate = (& $iso $today.AddDays(-5)); customerReferenceId = ($marker + '-MINE-PAST')
    }
    qualityPartner = @{ qualityPartnerCode = 'CUST-1001'; application = 'Yes'; contactPersonId = 'CP-1001'; subSegmentCode = 'SUB_SEGMENT_001' }
    product = @{ productTypeCode = 'PRODUCT_TYPE_001'; packingTypeCode = 'PACKING_TYPE_001' }
    failureDescription = @{ customerFailureModeCode = 'FAILURE_MODE_001' }
    samples = (New-Sample 'CS-VL-1')
}).body

# The engineer's own, comfortably in the future.
$mineFuture = (Api 'POST' '/api/complaints' $engineerToken @{
    header = @{
        complaintTypeCode = 'COMPLAINT_TYPE_001'; priorityCode = 'PRIORITY_001'
        failureLocationCode = 'FAILURE_LOCATION_001'; complaintOwnerId = 'U04'
        coordinatorId = 'U01'; startDate = (& $iso $today.AddDays(7)); targetDate = (& $iso $today.AddDays(21))
        customerTargetDate = (& $iso $today.AddDays(25)); customerReferenceId = ($marker + '-MINE-FUTURE')
    }
    qualityPartner = @{ qualityPartnerCode = 'CUST-1001'; application = 'Yes'; contactPersonId = 'CP-1001'; subSegmentCode = 'SUB_SEGMENT_001' }
    product = @{ productTypeCode = 'PRODUCT_TYPE_001'; packingTypeCode = 'PACKING_TYPE_001' }
    failureDescription = @{ customerFailureModeCode = 'FAILURE_MODE_001' }
    samples = (New-Sample 'CS-VL-2')
}).body

# Registered by sales quality, owned and coordinated by others: nothing here
# matches the engineer, which is the point of the object.
$theirs = (Api 'POST' '/api/complaints' $salesToken @{
    header = @{
        complaintTypeCode = 'COMPLAINT_TYPE_002'; priorityCode = 'PRIORITY_002'
        failureLocationCode = 'FAILURE_LOCATION_001'; complaintOwnerId = 'U02'
        coordinatorId = 'U01'; startDate = (& $iso $today.AddDays(7)); targetDate = (& $iso $today.AddDays(17))
        customerTargetDate = (& $iso $today.AddDays(20)); customerReferenceId = ($marker + '-THEIRS')
    }
    qualityPartner = @{ qualityPartnerCode = 'CUST-1002'; application = 'Yes'; contactPersonId = 'CP-1002'; subSegmentCode = 'SUB_SEGMENT_002' }
    product = @{ productTypeCode = 'PRODUCT_TYPE_002'; packingTypeCode = 'PACKING_TYPE_001' }
    failureDescription = @{ customerFailureModeCode = 'FAILURE_MODE_005' }
    samples = (New-Sample 'CS-VL-3')
}).body

$idMinePast = $minePast.complaintId
$idMineFuture = $mineFuture.complaintId
$idTheirs = $theirs.complaintId
$allCreated = (-not [string]::IsNullOrWhiteSpace($idMinePast)) -and
              (-not [string]::IsNullOrWhiteSpace($idMineFuture)) -and
              (-not [string]::IsNullOrWhiteSpace($idTheirs))
Check 'three complaints were registered for the ledger checks' $allCreated `
    ('ids=' + $idMinePast + ',' + $idMineFuture + ',' + $idTheirs)

# --- 3. the keyword filter ----------------------------------------------------
$byMarker = (Api 'GET' ('/api/complaints?scope=all&q=' + $marker) $engineerToken $null).body
Check 'the keyword finds exactly the three seeded complaints' ($byMarker.total -eq 3) ('total=' + $byMarker.total)
Check 'the keyword search returns a page of rows' (@($byMarker.items).Count -eq 3) ('items=' + @($byMarker.items).Count)

$ids = @($byMarker.items | ForEach-Object { $_.complaintId })
Check 'all three seeded ids are returned' `
    (($ids -contains $idMinePast) -and ($ids -contains $idMineFuture) -and ($ids -contains $idTheirs)) ($ids -join ',')

$first = $byMarker.items | Where-Object { $_.complaintId -eq $idMinePast } | Select-Object -First 1
Check 'the row carries the status display name' (-not [string]::IsNullOrWhiteSpace($first.statusName)) ('statusName=' + $first.statusName)
Check 'the row carries the priority display name' (-not [string]::IsNullOrWhiteSpace($first.priorityName)) ('priorityName=' + $first.priorityName)
Check 'the row carries the owner name' (-not [string]::IsNullOrWhiteSpace($first.ownerName)) ('ownerName=' + $first.ownerName)
Check 'the row carries the customer name' (-not [string]::IsNullOrWhiteSpace($first.customerName)) ('customerName=' + $first.customerName)
Check 'the row carries the product type name' (-not [string]::IsNullOrWhiteSpace($first.productTypeName)) ('productTypeName=' + $first.productTypeName)
Check 'the row reports the complaint as open' ($null -eq $first.closeDate) ('closeDate=' + $first.closeDate)
Check 'the overdue complaint reports its overdue days' ($first.overdueDays -gt 0) ('overdueDays=' + $first.overdueDays)
Check 'the row marks the engineer as related' ($first.mine -eq $true) ('mine=' + $first.mine)
# Counted from the registration date, so a complaint registered seconds ago has
# none yet. The demo seeder back-dates created_at to make the column vary.
Check 'a complaint registered today has no processing time yet' ($first.processingDays -eq 0) ('processingDays=' + $first.processingDays)

$futureRow = $byMarker.items | Where-Object { $_.complaintId -eq $idMineFuture } | Select-Object -First 1
Check 'a complaint inside its target date is not overdue' ($futureRow.overdueDays -eq 0) ('overdueDays=' + $futureRow.overdueDays)

# --- 4. the two tab counters --------------------------------------------------
Check 'the all tab counts every complaint' ($byMarker.allTotal -ge 3) ('allTotal=' + $byMarker.allTotal)
Check 'the mine tab counts fewer than all' ($byMarker.mineTotal -lt $byMarker.allTotal) `
    ('mine=' + $byMarker.mineTotal + ' all=' + $byMarker.allTotal)

$mineScoped = (Api 'GET' ('/api/complaints?scope=mine&q=' + $marker) $engineerToken $null).body
Check 'the mine tab keeps the engineer''s two complaints' ($mineScoped.total -eq 2) ('total=' + $mineScoped.total)
$mineIds = @($mineScoped.items | ForEach-Object { $_.complaintId })
Check 'the other owner''s complaint is not on the mine tab' (-not ($mineIds -contains $idTheirs)) ($mineIds -join ',')

$theirsSeen = (Api 'GET' ('/api/complaints?scope=all&q=' + $marker) $salesToken $null).body
$theirsIds = @($theirsSeen.items | ForEach-Object { $_.complaintId })
Check 'the other owner''s complaint is mine for its own registrant' ($theirsIds -contains $idTheirs) ($theirsIds -join ',')

# --- 5. the filters ----------------------------------------------------------
$byStatus = (Api 'GET' ('/api/complaints?scope=all&q=' + $marker + '&status=COMPLAINT_S01') $engineerToken $null).body
Check 'filtering by the registration status keeps all three' ($byStatus.total -eq 3) ('total=' + $byStatus.total)

$byPriority = (Api 'GET' ('/api/complaints?scope=all&q=' + $marker + '&priority=PRIORITY_003') $engineerToken $null).body
Check 'filtering by priority narrows to one' ($byPriority.total -eq 1) ('total=' + $byPriority.total)

$byCustomer = (Api 'GET' ('/api/complaints?scope=all&q=' + $marker + '&customer=CUST-1002') $engineerToken $null).body
Check 'filtering by customer narrows to one' ($byCustomer.total -eq 1) ('total=' + $byCustomer.total)

$byOwner = (Api 'GET' ('/api/complaints?scope=all&q=' + $marker + '&owner=U02') $engineerToken $null).body
Check 'filtering by owner narrows to one' ($byOwner.total -eq 1) ('total=' + $byOwner.total)

$byType = (Api 'GET' ('/api/complaints?scope=all&q=' + $marker + '&complaintType=COMPLAINT_TYPE_002') $engineerToken $null).body
Check 'filtering by complaint type narrows to one' ($byType.total -eq 1) ('total=' + $byType.total)

$overdue = (Api 'GET' ('/api/complaints?scope=all&q=' + $marker + '&overdue=true') $engineerToken $null).body
Check 'the overdue filter keeps only the late complaint' ($overdue.total -eq 1) ('total=' + $overdue.total)
$overdueId = @($overdue.items)[0].complaintId
Check 'the overdue filter kept the right complaint' ($overdueId -eq $idMinePast) ('id=' + $overdueId)

$open = (Api 'GET' ('/api/complaints?scope=all&q=' + $marker + '&open=true') $engineerToken $null).body
Check 'the open filter keeps all three (none is closed)' ($open.total -eq 3) ('total=' + $open.total)

$valid = (Api 'GET' ('/api/complaints?scope=all&q=' + $marker + '&valid=true') $engineerToken $null).body
Check 'the valid filter excludes the un-validated complaints' ($valid.total -eq 0) ('total=' + $valid.total)

$windowed = (Api 'GET' ('/api/complaints?scope=all&q=' + $marker + '&startFrom=' + (& $iso $today.AddDays(6)) + '&startTo=' + (& $iso $today.AddDays(8))) $engineerToken $null).body
Check 'a start-date window narrows to the two future complaints' ($windowed.total -eq 2) ('total=' + $windowed.total)

# --- 6. the sort whitelist ---------------------------------------------------
$asc = (Api 'GET' ('/api/complaints?scope=all&q=' + $marker + '&sort=id&order=asc') $engineerToken $null).body
$ascIds = @($asc.items | ForEach-Object { $_.complaintId })
Check 'sorting by id ascending orders the ids' (($ascIds[0] -le $ascIds[-1])) ($ascIds -join ',')

$desc = (Api 'GET' ('/api/complaints?scope=all&q=' + $marker + '&sort=id&order=desc') $engineerToken $null).body
$descIds = @($desc.items | ForEach-Object { $_.complaintId })
Check 'sorting by id descending reverses the order' (($descIds[0] -ge $descIds[-1])) ($descIds -join ',')

$byTarget = (Api 'GET' ('/api/complaints?scope=all&q=' + $marker + '&sort=targetDate&order=asc') $engineerToken $null).body
$targetDates = @($byTarget.items | ForEach-Object { $_.targetDate })
Check 'sorting by target date orders the dates' (($targetDates[0] -le $targetDates[-1])) ($targetDates -join ',')

$badSort = Api 'GET' ('/api/complaints?scope=all&q=' + $marker + '&sort=complaint_id%3Bdrop%20table%20complaint') $engineerToken $null
Check 'an unknown sort key is ignored rather than failing' ($badSort.status -eq 200) ('status=' + $badSort.status)
Check 'an unknown sort key still returns rows' ($badSort.body.total -eq 3) ('total=' + $badSort.body.total)

$badDate = Api 'GET' '/api/complaints?startFrom=not-a-date' $engineerToken $null
Check 'a malformed date is rejected with 400' ($badDate.status -eq 400) ('status=' + $badDate.status)

# --- 7. paging ---------------------------------------------------------------
$page1 = (Api 'GET' '/api/complaints?scope=all&page=1&size=20' $engineerToken $null).body
Check 'size=20 returns a full page when there is enough data' (@($page1.items).Count -eq 20) ('items=' + @($page1.items).Count)
Check 'the page reports the total' ($page1.total -ge 20) ('total=' + $page1.total)
Check 'the page echoes the size it used' ($page1.size -eq 20) ('size=' + $page1.size)

$page2 = (Api 'GET' '/api/complaints?scope=all&page=2&size=20' $engineerToken $null).body
$page1First = @($page1.items)[0].complaintId
$page2First = @($page2.items)[0].complaintId
Check 'page two starts where page one stopped' ($page1First -ne $page2First) ($page1First + ' vs ' + $page2First)

$offList = (Api 'GET' '/api/complaints?scope=all&page=1&size=7' $engineerToken $null).body
Check 'a size outside the offered set falls back to the default' ($offList.size -eq 20) ('size=' + $offList.size)

$clamped = (Api 'GET' '/api/complaints?scope=all&page=0&size=50' $engineerToken $null).body
Check 'page 0 is clamped to the first page' ($clamped.page -eq 1) ('page=' + $clamped.page)

# --- 8. the soft-delete boundary ---------------------------------------------
& $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value -q `
    -c ("UPDATE qms.complaint SET is_deleted = true WHERE complaint_id = '" + $idMineFuture + "';") | Out-Null
$afterDelete = (Api 'GET' ('/api/complaints?scope=all&q=' + $marker) $engineerToken $null).body
Check 'a soft-deleted complaint drops out of the ledger' ($afterDelete.total -eq 2) ('total=' + $afterDelete.total)
$afterIds = @($afterDelete.items | ForEach-Object { $_.complaintId })
Check 'the soft-deleted complaint is the one missing' (-not ($afterIds -contains $idMineFuture)) ($afterIds -join ',')
& $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value -q `
    -c ("UPDATE qms.complaint SET is_deleted = false WHERE complaint_id = '" + $idMineFuture + "';") | Out-Null

# --- 9. the Excel export -----------------------------------------------------
# PowerShell 5.1 gives either the headers or the bytes for a binary body, not
# both in one call, so the request is made twice: once to read the content type
# and once to land the file.
$exportPath = Join-Path $cfg.outDir 'verify_ledger_export.xlsx'
$onePath = Join-Path $cfg.outDir 'verify_ledger_export_one.xlsx'

$exportHeaders = Invoke-WebRequest -Uri ($BaseUrl + '/api/complaints/export?scope=all&q=' + $marker) `
    -Headers @{ Authorization = 'Bearer ' + $engineerToken } -TimeoutSec 60 -UseBasicParsing
$exportType = $exportHeaders.Headers['Content-Type']
Check 'the export declares the spreadsheet content type' ($exportType -like '*spreadsheetml.sheet*') ('content-type=' + $exportType)

Invoke-WebRequest -Uri ($BaseUrl + '/api/complaints/export?scope=all&q=' + $marker) `
    -Headers @{ Authorization = 'Bearer ' + $engineerToken } -TimeoutSec 60 -UseBasicParsing `
    -OutFile $exportPath | Out-Null
$exportBytes = [System.IO.File]::ReadAllBytes($exportPath)
$magic = [System.Text.Encoding]::ASCII.GetString($exportBytes[0..1])
Check 'the export returns an xlsx workbook' ($magic -eq 'PK') ('magic=' + $magic)
Check 'the export is not empty' ($exportBytes.Length -gt 1000) ('bytes=' + $exportBytes.Length)

Invoke-WebRequest -Uri ($BaseUrl + '/api/complaints/export?ids=' + $idMinePast) `
    -Headers @{ Authorization = 'Bearer ' + $engineerToken } -TimeoutSec 60 -UseBasicParsing `
    -OutFile $onePath | Out-Null
$oneBytes = [System.IO.File]::ReadAllBytes($onePath)
Check 'exporting a selection produces a smaller workbook' ($oneBytes.Length -lt $exportBytes.Length) `
    ('one=' + $oneBytes.Length + ' all=' + $exportBytes.Length)
$oneMagic = [System.Text.Encoding]::ASCII.GetString($oneBytes[0..1])
Check 'a selection export is a workbook too' ($oneMagic -eq 'PK') ('magic=' + $oneMagic)

# Scoped by the marker: another script's exports would otherwise be counted too.
$audited = Q "SELECT count(*) FROM qms.audit_log WHERE action_type = 'EXPORT' AND biz_type = 'Complaint' AND after_value LIKE '%$marker%' AND created_at > now() - interval '5 minutes';"
Check 'the export is written to the audit trail' ([int]$audited -ge 2) ('audit rows=' + $audited)

$auditDetail = Q "SELECT coalesce(max(after_value),'') FROM qms.audit_log WHERE action_type = 'EXPORT' AND biz_type = 'Complaint' AND after_value LIKE '%$marker%' AND created_at > now() - interval '5 minutes';"
Check 'the audit entry records how big the export was' ($auditDetail -like '*3*') ('detail=' + $auditDetail)

# --- 10. the detail endpoint still works -------------------------------------
$detail = Api 'GET' ('/api/complaints/' + $idMinePast) $engineerToken $null
Check 'the existing detail endpoint is unaffected' ($detail.status -eq 200) ('status=' + $detail.status)

# --- cleanup -----------------------------------------------------------------
if (-not $KeepData) {
    & $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value -q `
        -c ("DELETE FROM qms.complaint WHERE customer_reference_id LIKE '" + $marker + "%';") | Out-Null
    $lines.Add('')
    $lines.Add('  cleaned up the seeded complaints')
}

$lines.Add('')
$lines.Add(('  RESULT : {0}   pass={1} fail={2}' -f $(if ($fail -eq 0) { 'PASS' } else { 'FAIL' }), $pass, $fail))
$lines | ForEach-Object { [Console]::Out.WriteLine($_) }
$lines | Out-File -FilePath (Join-Path $cfg.outDir 'verify_ledger_report.txt') -Encoding utf8

if ($fail -ne 0) { exit 1 }
