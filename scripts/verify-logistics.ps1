<#
  verify-logistics.ps1
  Acceptance for sample logistics (requirements 3.2.1 / 3.2.2): the shipment
  lifecycle, moving samples between the pool and a batch, the integrity rules no
  foreign key can express, the close-date rule, permissions and the audit trail.

  Pure ASCII.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\verify-logistics.ps1"
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
$expect = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '_verify_expectations.json')) | ConvertFrom-Json

$pass = 0; $fail = 0
$lines = New-Object System.Collections.Generic.List[string]
function Check([string] $name, [bool] $ok, [string] $detail) {
    if ($ok) { $script:pass++; $lines.Add(('  PASS  {0}' -f $name)) }
    else     { $script:fail++; $lines.Add(('  FAIL  {0}  -> {1}' -f $name, $detail)) }
}

function Get-ErrorStatus($err) { try { return [int]$err.Exception.Response.StatusCode } catch { return 0 } }
function Get-ErrorMessage($err) {
    try {
        $reader = New-Object System.IO.StreamReader($err.Exception.Response.GetResponseStream())
        $text = $reader.ReadToEnd(); $reader.Close()
        $parsed = $text | ConvertFrom-Json
        if ($parsed.message) { return $parsed.message }
    } catch { }
    return $err.Exception.Message
}
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
        # -InputObject, not the pipeline: piping a one-element array through
        # ConvertTo-Json unwraps it into a bare object, and the server then
        # rejects a body that should have been a list.
        $json = ConvertTo-Json -InputObject $payload -Depth 12
        $a['Body'] = [System.Text.Encoding]::UTF8.GetBytes($json)
    }
    try {
        # Invoke-WebRequest, not Invoke-RestMethod: the latter does not expose the
        # status code, so a helper built on it reports 200 for every success and
        # silently turns "expects 201" into a failure and "expects 200" into a
        # tautology.
        $response = Invoke-WebRequest @a
        $body = $null
        if ($response.Content) { $body = $response.Content | ConvertFrom-Json }
        return @{ status = [int]$response.StatusCode; body = $body }
    }
    catch { return @{ status = Get-ErrorStatus $_; body = $null; message = (Get-ErrorMessage $_) } }
}

function NewComplaintPayload([string] $sampleCustomerId) {
    return @{
        header = @{
            complaintTypeCode = 'COMPLAINT_TYPE_001'; priorityCode = 'PRIORITY_002'
            failureLocationCode = 'FAILURE_LOCATION_005'; complaintOwnerId = 'U02'
            coordinatorId = 'U01'; customerTargetDate = (Get-Date).Date.AddDays(20).ToString('yyyy-MM-dd')
        }
        qualityPartner = @{ qualityPartnerCode = 'CUST-1001'; application = 'Yes'; contactPersonId = 'CP-1001'; subSegmentCode = 'SUB_SEGMENT_001' }
        product = @{ productTypeCode = 'PRODUCT_TYPE_001'; packingTypeCode = 'PACKING_TYPE_001' }
        failureDescription = @{ customerFailureModeCode = 'FAILURE_MODE_001' }
        samples = @(
            @{ customerSampleId = $sampleCustomerId; sampleQuantity = 4; uom = 'PCS'; rejectConfirmed = $true
               failureTypeL1Code = '2'; failureTypeL2Code = '2c'; failureTypeL3Code = '2ca' }
        )
    }
}

$lines.Add('verify-logistics  ->  ' + $BaseUrl)
$lines.Add('')

$token = (Login 'xiaoran.ma' $Password).accessToken
Check 'logged in' ($null -ne $token) 'login failed'
if (-not $token) { $lines | ForEach-Object { [Console]::Out.WriteLine($_) }; exit 1 }

$today = (Get-Date).Date
$complaintIds = New-Object System.Collections.ArrayList

# --- 1. a complaint carrying two samples -----------------------------------
$a = (Api 'POST' '/api/complaints' $token (NewComplaintPayload 'CS-LOG-1')).body
[void]$complaintIds.Add($a.complaintId)
$secondSampleId = (Api 'POST' ("/api/complaints/" + $a.complaintId + '/samples') $token @{
    customerSampleId = 'CS-LOG-2'; sampleQuantity = 3; uom = 'PCS'; description = 'second sample'
    failureTypeL1Code = '2'; failureTypeL2Code = '2b'; failureTypeL3Code = '2ba'
}).body.sampleId
Check 'a second sample can be added after registration' ($secondSampleId -match '^S\d{9}$') ('id=' + $secondSampleId)

$detail = (Api 'GET' ('/api/complaints/' + $a.complaintId) $token $null).body
Check 'the complaint now carries two samples' (@($detail.samples).Count -eq 2) ('count=' + @($detail.samples).Count)
$firstSampleId = @($detail.samples)[0].sampleId

# --- 2. sample edit ---------------------------------------------------------
$edit = Api 'PUT' ('/api/complaints/' + $a.complaintId + '/samples/' + $secondSampleId) $token @{
    customerSampleId = 'CS-LOG-2'; sampleQuantity = 7; uom = 'PCS'; description = 'edited sample'
    failureTypeL1Code = '2'; failureTypeL2Code = '2b'; failureTypeL3Code = '2ba'
}
Check 'a sample can be edited' ($edit.status -eq 200) ('status=' + $edit.status + ' ' + $edit.message)
$detail = (Api 'GET' ('/api/complaints/' + $a.complaintId) $token $null).body
$edited = @($detail.samples) | Where-Object { $_.sampleId -eq $secondSampleId }
Check 'the edit was stored' ($edited.value.sampleQuantity -eq 7) ('qty=' + $edited.value.sampleQuantity)

$bad = Api 'PUT' ('/api/complaints/' + $a.complaintId + '/samples/' + $secondSampleId) $token @{
    customerFailureModeCode = 'x'; failureTypeL1Code = '2'; failureTypeL2Code = '3a'
}
Check 'a broken failure type chain is refused on edit' ($bad.status -eq 400) ('status=' + $bad.status)

# --- 3. a third sample, then delete it --------------------------------------
$thirdSampleId = (Api 'POST' ("/api/complaints/" + $a.complaintId + '/samples') $token @{
    customerSampleId = 'CS-LOG-3'; sampleQuantity = 1; uom = 'PCS'
}).body.sampleId
$del = Api 'DELETE' ('/api/complaints/' + $a.complaintId + '/samples/' + $thirdSampleId) $token $null
Check 'an unlinked sample can be deleted' ($del.status -eq 200) ('status=' + $del.status)

# --- 4. create a shipment ---------------------------------------------------
$shipBody = @{
    senderId = 'U02'; receiverId = 'U03'; shipmentNo = 'SF-1001'
    quantityPartsShipped = 6; application = 'Yes'
    startDate = $today.ToString('yyyy-MM-dd')
    carrierName = 'SF Express'; carrierTrackingNumber = 'SF1234567890'
    targetDate = $today.AddDays(5).ToString('yyyy-MM-dd')
    comments = 'first batch'
}
$created = Api 'POST' ('/api/complaints/' + $a.complaintId + '/shipments') $token $shipBody
$shipmentId = $created.body.shipment.shipmentId
Check 'a shipment can be created' ($shipmentId -match '^SH\d{9}$') ('id=' + $shipmentId)
Check 'a new shipment starts in the preparing state' ($created.body.shipment.shipmentStatus -eq 'SHIPMENT_PREPARING') ('status=' + $created.body.shipment.shipmentStatus)
Check 'the status name is resolved for display' ($created.body.shipment.shipmentStatusName -eq $expect.logistics.statusPreparing) ('name=' + $created.body.shipment.shipmentStatusName)
Check 'a new shipment carries no samples yet' (@($created.body.samples).Count -eq 0) ('count=' + @($created.body.samples).Count)
Check 'the sample pool offers both samples' (@($created.body.availableSamples).Count -eq 2) ('count=' + @($created.body.availableSamples).Count)
# @() around the pipeline: a single surviving object has no .Count of its own,
# so an unwrapped filter silently compares $null against the expected number.
$flaggedAtCreation = @(@($created.body.availableSamples) | Where-Object { $_.inThisShipment })
Check 'pool entries are not yet marked as in the shipment' ($flaggedAtCreation.Count -eq 0) ('flagged=' + $flaggedAtCreation.Count)

# --- 5. shipment validation -------------------------------------------------
$badBody = $shipBody.Clone(); $badBody['carrierName'] = ''
Check 'a missing carrier is refused' ((Api 'POST' ('/api/complaints/' + $a.complaintId + '/shipments') $token $badBody).status -eq 400) 'expected 400'

$badBody = $shipBody.Clone(); $badBody['senderId'] = 'U99'
Check 'an unknown sender is refused' ((Api 'POST' ('/api/complaints/' + $a.complaintId + '/shipments') $token $badBody).status -eq 400) 'expected 400'

$badBody = $shipBody.Clone()
$badBody['targetDate'] = $today.AddDays(-3).ToString('yyyy-MM-dd')
Check 'a target before the start is refused' ((Api 'POST' ('/api/complaints/' + $a.complaintId + '/shipments') $token $badBody).status -eq 400) 'expected 400'

$badBody = $shipBody.Clone(); $badBody['shipmentStatus'] = 'NOT_A_STATUS'
$badStatus = Api 'POST' ('/api/complaints/' + $a.complaintId + '/shipments') $token $badBody
Check 'an unknown status is refused' ($badStatus.status -eq 400) ('status=' + $badStatus.status)
Check 'the unknown status is explained' ($badStatus.message -like ('*' + $expect.logistics.invalidStatus + '*')) ('msg=' + $badStatus.message)

Check 'a shipment for an unknown complaint is refused' ((Api 'POST' '/api/complaints/C202699999/shipments' $token $shipBody).status -eq 404) 'expected 404'

# --- 6. move samples into the batch ----------------------------------------
$add = Api 'POST' ('/api/shipments/' + $shipmentId + '/samples') $token @(
    @{ sampleId = $firstSampleId; dateCode = '2432'; dbId = 'DB-01'; qty = 4; uom = 'PCS'
       assemblyCenter = 'SZ'; testCenter = 'TC-1'; numOfDies = 2 }
)
Check 'a sample can be moved into the batch' ($add.status -eq 200) ('status=' + $add.status + ' ' + $add.message)
Check 'the batch now carries one sample' (@($add.body.samples).Count -eq 1) ('count=' + @($add.body.samples).Count)
Check 'the per-batch attributes were stored' ((@($add.body.samples)[0].dateCode) -eq '2432') ('dateCode=' + @($add.body.samples)[0].dateCode)
Check 'the failure type is resolved for the batch row' (@($add.body.samples)[0].failureTypeName -like '*Package chipping*') ('name=' + @($add.body.samples)[0].failureTypeName)
$poolDump = (@($add.body.availableSamples) | ForEach-Object { $_.sampleId + '=' + $_.inThisShipment }) -join ', '
$flaggedAfterAdd = @(@($add.body.availableSamples) | Where-Object { $_.inThisShipment })
Check 'the pool flags the linked sample' ($flaggedAfterAdd.Count -eq 1) ('pool: ' + $poolDump)

# --- 7. integrity rules -----------------------------------------------------
$dup = Api 'POST' ('/api/shipments/' + $shipmentId + '/samples') $token @(@{ sampleId = $firstSampleId })
Check 'adding an already-linked sample is refused' ($dup.status -eq 400) ('status=' + $dup.status)
Check 'the duplicate is explained' ($dup.message -like ('*' + $expect.logistics.alreadyInShipment + '*')) ('msg=' + $dup.message)

$twice = Api 'POST' ('/api/shipments/' + $shipmentId + '/samples') $token @(
    @{ sampleId = $secondSampleId }, @{ sampleId = $secondSampleId }
)
Check 'the same sample twice in one request is refused' ($twice.status -eq 400) ('status=' + $twice.status)
Check 'the repeat is explained' ($twice.message -like ('*' + $expect.logistics.duplicateSample + '*')) ('msg=' + $twice.message)

# a sample belonging to a different complaint
$b = (Api 'POST' '/api/complaints' $token (NewComplaintPayload 'CS-OTHER-1')).body
[void]$complaintIds.Add($b.complaintId)
$foreignSample = (Api 'GET' ('/api/complaints/' + $b.complaintId) $token $null).body.samples[0].sampleId
$cross = Api 'POST' ('/api/shipments/' + $shipmentId + '/samples') $token @(@{ sampleId = $foreignSample })
Check 'a sample from another complaint is refused' ($cross.status -eq 400) ('status=' + $cross.status)
Check 'the cross-complaint sample is explained' ($cross.message -like ('*' + $expect.logistics.sampleNotOfComplaint + '*')) ('msg=' + $cross.message)

# deleting a linked sample
$blocked = Api 'DELETE' ('/api/complaints/' + $a.complaintId + '/samples/' + $firstSampleId) $token $null
Check 'deleting a sample a batch carries is refused' ($blocked.status -eq 409) ('status=' + $blocked.status)
Check 'the deletion refusal explains why' ($blocked.message -like ('*' + $expect.logistics.sampleLinkedRefusal + '*')) ('msg=' + $blocked.message)

# --- 8. removing a sample from the batch -----------------------------------
$removed = Api 'DELETE' ('/api/shipments/' + $shipmentId + '/samples/' + $firstSampleId) $token $null
Check 'a sample can be removed from the batch' ($removed.status -eq 200) ('status=' + $removed.status)
Check 'the batch is empty again' (@($removed.body.samples).Count -eq 0) ('count=' + @($removed.body.samples).Count)

$missing = Api 'DELETE' ('/api/shipments/' + $shipmentId + '/samples/' + $secondSampleId) $token $null
Check 'removing a sample that is not in the batch returns 404' ($missing.status -eq 404) ('status=' + $missing.status)

# --- 9. one sample in two batches -----------------------------------------
$again = Api 'POST' ('/api/shipments/' + $shipmentId + '/samples') $token @(@{ sampleId = $firstSampleId; qty = 4 })
Check 'a sample can be added back to the batch' ($again.status -eq 200) ('status=' + $again.status)

$second = Api 'POST' ('/api/complaints/' + $a.complaintId + '/shipments') $token $shipBody
$secondShipmentId = $second.body.shipment.shipmentId
$inSecond = Api 'POST' ('/api/shipments/' + $secondShipmentId + '/samples') $token @(@{ sampleId = $firstSampleId; qty = 4 })
Check 'the same sample may travel in a second batch' ($inSecond.status -eq 200) ('status=' + $inSecond.status + ' ' + $inSecond.message)

$list = (Api 'GET' ('/api/complaints/' + $a.complaintId + '/shipments') $token $null).body
Check 'the complaint lists both batches' (@($list).Count -eq 2) ('count=' + @($list).Count)
$batchesWithOne = @(@($list) | Where-Object { $_.sampleCount -eq 1 })
Check 'each batch reports its sample count' ($batchesWithOne.Count -eq 2) ('batches at 1=' + $batchesWithOne.Count)

# --- 10. status transition and the close date rule -------------------------
$shipBody['shipmentStatus'] = 'SHIPMENT_RECEIVED'
$updated = Api 'PUT' ('/api/shipments/' + $shipmentId) $token $shipBody
Check 'a batch can be moved to received' ($updated.status -eq 200) ('status=' + $updated.status)
Check 'reaching a terminal status stamps the close date' ($updated.body.shipment.closeDate -eq $today.ToString('yyyy-MM-dd')) ('closeDate=' + $updated.body.shipment.closeDate)
Check 'a closed batch is no longer overdue' ($updated.body.shipment.overdueDays -eq 0) ('overdueDays=' + $updated.body.shipment.overdueDays)

# --- 11. permissions and 404 ------------------------------------------------
$auditor = Login 'zhiyuan.chen' $Password
Check 'an auditor can view shipments' ((Api 'GET' ('/api/complaints/' + $a.complaintId + '/shipments') $auditor.accessToken $null).status -eq 200) 'expected 200'
Check 'an auditor cannot create a shipment' ((Api 'POST' ('/api/complaints/' + $a.complaintId + '/shipments') $auditor.accessToken $shipBody).status -eq 403) 'expected 403'
Check 'creating a shipment requires a login' ((Api 'POST' ('/api/complaints/' + $a.complaintId + '/shipments') '' $shipBody).status -eq 401) 'expected 401'
Check 'an unknown shipment returns 404' ((Api 'GET' '/api/shipments/SH999999999' $token $null).status -eq 404) 'expected 404'

# --- 12. audit trail --------------------------------------------------------
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
    return ((& $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value -t -A -c $sql) -join ' ').Trim()
}
Check 'the shipment creation was audited' ((Q "select count(*) from qms.audit_log where action_type='CREATE' and biz_type='Shipment' and biz_id='$($a.complaintId)'") -ge '1') 'expected at least 1'
Check 'the status change was audited' ((Q "select count(*) from qms.audit_log where action_type='STATUS_CHANGE' and biz_type='Shipment' and biz_id='$($a.complaintId)'") -ge '1') 'expected at least 1'
Check 'the sample creation was audited' ((Q "select count(*) from qms.audit_log where action_type='CREATE' and biz_type='Sample' and biz_id='$($a.complaintId)'") -ge '1') 'expected at least 1'
Check 'the blocked sample deletion left nothing behind' ((Q "select count(*) from qms.sample where sample_id='$firstSampleId' and is_deleted = false") -eq '1') 'the sample should still be live'

# --- cleanup ----------------------------------------------------------------
if (-not $KeepData) {
    $quoted = ($complaintIds | ForEach-Object { "'" + $_ + "'" }) -join ','
    & $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value -q `
        -c ("DELETE FROM qms.complaint WHERE complaint_id IN (" + $quoted + ");") | Out-Null
    $lines.Add('')
    $lines.Add('  cleaned up ' + $complaintIds.Count + ' test complaint(s) and their shipments')
}

$lines.Add('')
$lines.Add(('  RESULT : ' + $(if ($fail -eq 0) { 'PASS' } else { "FAIL ($fail)" }) + '   passed=' + $pass + ' failed=' + $fail))
$lines | Set-Content -Path (Join-Path $cfg.outDir 'verify_logistics_report.txt') -Encoding UTF8
$lines | ForEach-Object { [Console]::Out.WriteLine($_) }
if ($fail -ne 0) { exit 1 }
