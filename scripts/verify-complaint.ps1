<#
  verify-complaint.ps1
  Acceptance for complaint registration (D0-D1): the success path, the date
  rules, the reference checks that foreign keys cannot express, the permission
  boundary, and the audit trail.

  Pure ASCII.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\verify-complaint.ps1"
  Optional:
    -BaseUrl http://localhost:8080   -Password Qms@2026
#>
[CmdletBinding()]
param(
    [string] $BaseUrl = 'http://localhost:8080',
    [string] $Password = 'Qms@2026',
    # By default the complaints this script creates are deleted afterwards, so a
    # verification run does not leave stray rows in the ledger. Pass -KeepData to
    # inspect them.
    [switch] $KeepData
)

$ErrorActionPreference = 'Continue'

$cfgPath = Join-Path $PSScriptRoot '_paths.json'
$cfg = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json
if (-not (Test-Path $cfg.outDir)) { New-Item -ItemType Directory -Path $cfg.outDir -Force | Out-Null }

# Chinese expected fragments live in a UTF-8 JSON file: a .ps1 without a BOM is
# decoded as GBK by PowerShell 5.1, so Chinese literals inside it never match.
$expect = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '_verify_expectations.json')) | ConvertFrom-Json

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
    $args = @{ Uri = $BaseUrl + $path; Method = $method; Headers = $headers; TimeoutSec = 30; UseBasicParsing = $true }
    if ($null -ne $payload) {
        $args['ContentType'] = 'application/json; charset=utf-8'
        $args['Body'] = [System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Depth 12))
    }
    try {
        # Invoke-WebRequest, not Invoke-RestMethod: the latter does not expose the
        # status code, so a helper built on it reports 200 for every success and
        # silently turns "expects 201" into a failure and "expects 200" into a
        # tautology.
        $response = Invoke-WebRequest @args
        $body = $null
        if ($response.Content) { $body = $response.Content | ConvertFrom-Json }
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

function Base-Payload {
    return @{
        header = @{
            complaintTypeCode     = 'COMPLAINT_TYPE_001'
            priorityCode          = 'PRIORITY_003'
            failureLocationCode   = 'FAILURE_LOCATION_005'
            complaintOwnerId      = 'U02'
            coordinatorId         = 'U01'
            verificationOwnerId   = 'U03'
            reportOwnerId         = 'U01'
            customerTargetDate    = (Get-Date).Date.AddDays(20).ToString('yyyy-MM-dd')
        }
        qualityPartner = @{
            qualityPartnerCode = 'CUST-1001'
            application        = 'Yes'
            contactPersonId    = 'CP-1001'
            subSegmentCode     = 'SUB_SEGMENT_001'
            shipToSoldToCode   = 'ST-1001-01'
            hsCode             = '8541.29.00'
            endCustomer        = 'General Motors'
            eccn               = 'EAR99'
        }
        product = @{
            materialCode    = '12NC-934068123456'
            productTypeCode = 'PRODUCT_TYPE_001'
            packingTypeCode = 'PACKING_TYPE_001'
            businessGroup   = 'Power Discretes'
            businessUnit    = 'Automotive Power'
            customerPartNo  = 'BOS-8812-A'
        }
        failureDescription = @{
            customerFailureDescription = 'Package chipping observed on returned units.'
            customerFailureModeCode    = 'FAILURE_MODE_001'
            quantityFailing            = 24
            quantityFailingUom         = 'PCS'
            qualityReturned            = 4
            qualityReturnedUom         = 'PCS'
        }
        samples = @(
            @{
                customerSampleId   = 'CS-8801'
                sampleQuantity     = 4
                uom                = 'PCS'
                description        = 'Chipped package sample'
                rejectConfirmed    = $true
                failureTypeL1Code  = '2'
                failureTypeL2Code  = '2c'
                failureTypeL3Code  = '2ca'
            }
        )
    }
}

# Deep clone that keeps nested hashtables mutable, so a test can add fields that
# Base-Payload never defined (startDate, targetDate). A JSON round-trip would turn
# them into PSCustomObjects, which reject new properties.
function DeepCopy($value) {
    if ($value -is [System.Collections.IDictionary]) {
        $copy = @{}
        foreach ($key in $value.Keys) { $copy[$key] = DeepCopy $value[$key] }
        return $copy
    }
    if ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
        $items = New-Object System.Collections.ArrayList
        foreach ($item in $value) { [void]$items.Add((DeepCopy $item)) }
        # The leading comma is required: PowerShell unwraps an array returned from
        # a function, which would turn a one-element list into a bare object and
        # make the server read an object where it expects an array.
        return , $items.ToArray()
    }
    return $value
}

$lines.Add('verify-complaint  ->  ' + $BaseUrl)
$lines.Add('')

$sales = Login 'xiaoran.ma' $Password
$salesToken = $sales.accessToken
Check 'sales quality logged in' ($null -ne $salesToken) 'login failed'
if (-not $salesToken) { $lines | ForEach-Object { [Console]::Out.WriteLine($_) }; exit 1 }

$today = (Get-Date).Date
$createdIds = New-Object System.Collections.ArrayList

# --- 1. success path --------------------------------------------------------
$r = Invoke-Api 'POST' '/api/complaints' $salesToken (Base-Payload)
Check 'registration returns 201' ($r.status -eq 201 -or $r.status -eq 200) ('status=' + $r.status + ' ' + $r.message)
$created = $r.body
Check 'complaint id matches C + 9 digits' ($created.complaintId -match '^C\d{9}$') ('id=' + $created.complaintId)
Check 'registration lands on D1 (the team-forming stage)' ($created.currentStage -eq 'D1') ('stage=' + $created.currentStage)
Check 'new complaint status is the registered state' ($created.statusCode -eq 'COMPLAINT_S01') ('status=' + $created.statusCode)
Check 'one sample id was returned' (@($created.sampleIds).Count -eq 1) ('count=' + @($created.sampleIds).Count)
Check 'sample id was generated' (@($created.sampleIds)[0] -match '^S\d{9}$') ('id=' + @($created.sampleIds)[0])

# --- 2. date rules ----------------------------------------------------------
$expectedStart = $today.AddDays(7).ToString('yyyy-MM-dd')
Check 'start date defaults to creation + 7 days' ($created.startDate -eq $expectedStart) `
    ('got ' + $created.startDate + ' expected ' + $expectedStart)
$expectedTargetP3 = $today.AddDays(7 + 7).ToString('yyyy-MM-dd')
Check 'very urgent target is start + 7 days' ($created.targetDate -eq $expectedTargetP3) `
    ('got ' + $created.targetDate + ' expected ' + $expectedTargetP3)

$complaintId = $created.complaintId
[void]$createdIds.Add($complaintId)

# --- 2b. the priority rule the wizard previews with -------------------------
$rules = (Invoke-Api 'GET' '/api/complaints/priority-rules' $salesToken $null).body
Check 'priority rules are exposed for live date preview' (@($rules).Count -eq 3) ('count=' + @($rules).Count)
$urgentRule = @($rules) | Where-Object { $_.code -eq 'PRIORITY_003' }
Check 'PRIORITY_003 (very urgent) maps to 7 days' ($urgentRule.days -eq 7) ('days=' + $urgentRule.days)
$standardRule = @($rules) | Where-Object { $_.code -eq 'PRIORITY_001' }
Check 'PRIORITY_001 (standard) maps to 14 days' ($standardRule.days -eq 14) ('days=' + $standardRule.days)

# --- 3. round-trip fidelity -------------------------------------------------
$detail = (Invoke-Api 'GET' ('/api/complaints/' + $complaintId) $salesToken $null).body
Check 'detail can be read back' ($null -ne $detail) 'no detail returned'
Check 'header round-trips' ($detail.header.complaintTypeCode -eq 'COMPLAINT_TYPE_001') ('got ' + $detail.header.complaintTypeCode)
Check 'quality partner round-trips' ($detail.qualityPartner.contactPersonId -eq 'CP-1001') ('got ' + $detail.qualityPartner.contactPersonId)
Check 'product round-trips' ($detail.product.materialCode -eq '12NC-934068123456') ('got ' + $detail.product.materialCode)
Check 'failure description round-trips' ($detail.failureDescription.quantityFailing -eq 24) ('got ' + $detail.failureDescription.quantityFailing)
Check 'sample round-trips including the failure type chain' (
    (@($detail.samples).Count -eq 1) -and ($detail.samples[0].value.failureTypeL3Code -eq '2ca')
) 'sample chain lost'
Check 'initiator is the logged-in user' ($detail.createdBy -eq 'U01') ('got ' + $detail.createdBy)
Check 'display names were resolved' (
    $detail.labels.customerName -and $detail.labels.contactName -and $detail.labels.ownerName
) 'labels missing'
Check 'a fresh complaint is not overdue' ($detail.overdueDays -eq 0) ('overdueDays=' + $detail.overdueDays)

# --- 4. priority drives the target date ------------------------------------
foreach ($case in @(@{ code = 'PRIORITY_002'; days = 10 }, @{ code = 'PRIORITY_001'; days = 14 })) {
    $p = DeepCopy (Base-Payload)
    $p.header.priorityCode = $case.code
    $res = Invoke-Api 'POST' '/api/complaints' $salesToken $p
    if ($res.body.complaintId) { [void]$createdIds.Add($res.body.complaintId) }
    $expected = $today.AddDays(7 + $case.days).ToString('yyyy-MM-dd')
    Check ('priority ' + $case.code + ' gives start + ' + $case.days + ' days') `
        ($res.body.targetDate -eq $expected) ('got ' + $res.body.targetDate + ' expected ' + $expected)
}

# --- 5. explicit dates are honoured ----------------------------------------
$p = DeepCopy (Base-Payload)
$p.header.startDate = $today.AddDays(2).ToString('yyyy-MM-dd')
$p.header.targetDate = $today.AddDays(9).ToString('yyyy-MM-dd')
$res = Invoke-Api 'POST' '/api/complaints' $salesToken $p
if ($res.body.complaintId) { [void]$createdIds.Add($res.body.complaintId) }
Check 'explicit start and target dates are honoured' (
    ($res.body.startDate -eq $p.header.startDate) -and ($res.body.targetDate -eq $p.header.targetDate)
) ('got ' + $res.body.startDate + ' / ' + $res.body.targetDate)

# --- 6. a complaint with no samples is allowed -----------------------------
$p = DeepCopy (Base-Payload)
$p.samples = @()
$res = Invoke-Api 'POST' '/api/complaints' $salesToken $p
if ($res.body.complaintId) { [void]$createdIds.Add($res.body.complaintId) }
Check 'registration without samples succeeds' ($res.status -eq 201 -or $res.status -eq 200) ('status=' + $res.status + ' ' + $res.message)

# --- 7. reference checks ----------------------------------------------------
$p = DeepCopy (Base-Payload)
$p.header.priorityCode = 'NOT_A_PRIORITY'
$res = Invoke-Api 'POST' '/api/complaints' $salesToken $p
Check 'unknown dictionary code is rejected' ($res.status -eq 400) ('status=' + $res.status)
Check 'unknown dictionary code explains itself' ($res.message -like '*NOT_A_PRIORITY*') ('msg=' + $res.message)

$p = DeepCopy (Base-Payload)
$p.qualityPartner.contactPersonId = 'CP-1002'   # belongs to CUST-1002, not CUST-1001
$res = Invoke-Api 'POST' '/api/complaints' $salesToken $p
Check 'a contact from another customer is rejected' ($res.status -eq 400) ('status=' + $res.status)
Check 'cross-customer contact explains itself' ($res.message -like ('*' + $expect.complaint.contactNotOfCustomer + '*')) ('msg=' + $res.message)

$p = DeepCopy (Base-Payload)
$p.qualityPartner.shipToSoldToCode = 'ST-1004-01'   # belongs to CUST-1004
$res = Invoke-Api 'POST' '/api/complaints' $salesToken $p
Check 'a ship-to from another customer is rejected' ($res.status -eq 400) ('status=' + $res.status)

$p = DeepCopy (Base-Payload)
$p.samples[0].failureTypeL2Code = '3a'   # 3a sits under 3, not under 2
$res = Invoke-Api 'POST' '/api/complaints' $salesToken $p
Check 'a broken failure type chain is rejected' ($res.status -eq 400) ('status=' + $res.status)
Check 'broken chain explains itself' ($res.message -like ('*' + $expect.complaint.brokenChain + '*')) ('msg=' + $res.message)

$p = DeepCopy (Base-Payload)
$p.samples[0].failureTypeL1Code = $null
$res = Invoke-Api 'POST' '/api/complaints' $salesToken $p
Check 'choosing L2 without L1 is rejected' ($res.status -eq 400) ('status=' + $res.status)

$p = DeepCopy (Base-Payload)
$p.header.targetDate = $today.AddDays(1).ToString('yyyy-MM-dd')
$p.header.startDate = $today.AddDays(5).ToString('yyyy-MM-dd')
$res = Invoke-Api 'POST' '/api/complaints' $salesToken $p
Check 'target earlier than start is rejected' ($res.status -eq 400) ('status=' + $res.status)

$p = DeepCopy (Base-Payload)
$p.header.complaintOwnerId = 'U99'
$res = Invoke-Api 'POST' '/api/complaints' $salesToken $p
Check 'an unknown owner is rejected' ($res.status -eq 400) ('status=' + $res.status)

$p = DeepCopy (Base-Payload)
$p.qualityPartner.application = 'Maybe'
$res = Invoke-Api 'POST' '/api/complaints' $salesToken $p
Check 'an invalid Yes/No value is rejected' ($res.status -eq 400) ('status=' + $res.status)

$p = DeepCopy (Base-Payload)
$p.header.complaintTypeCode = ''
$res = Invoke-Api 'POST' '/api/complaints' $salesToken $p
Check 'a missing required field is rejected' ($res.status -eq 400) ('status=' + $res.status)

# --- 8. validation reports every problem at once ---------------------------
$p = DeepCopy (Base-Payload)
$p.header.priorityCode = 'BAD_PRIORITY'
$p.qualityPartner.contactPersonId = 'CP-1002'
$res = Invoke-Api 'POST' '/api/complaints' $salesToken $p
Check 'all problems are reported together' (
    ($res.message -like ('*' + $expect.complaint.unknownDictionary + '*')) -and
    ($res.message -like ('*' + $expect.complaint.contactNotOfCustomer + '*'))
) ('msg=' + $res.message)

# --- 9. permission boundary -------------------------------------------------
$auditor = Login 'zhiyuan.chen' $Password
$res = Invoke-Api 'POST' '/api/complaints' $auditor.accessToken (Base-Payload)
Check 'an auditor cannot register a complaint (403)' ($res.status -eq 403) ('status=' + $res.status)

$res = Invoke-Api 'POST' '/api/complaints' '' (Base-Payload)
Check 'registration requires a login (401)' ($res.status -eq 401) ('status=' + $res.status)

$res = Invoke-Api 'GET' '/api/complaints/C202699999' $salesToken $null
Check 'an unknown complaint returns 404' ($res.status -eq 404) ('status=' + $res.status)

# --- 9b. the process and communication log tab ------------------------------
# Everything the stage services write is recorded with the complaint id as
# biz_id, so one lookup by complaint returns the whole trail.
$logs = @((Invoke-Api 'GET' ('/api/complaints/' + $complaintId + '/logs') $salesToken $null).body)
Check 'the complaint has a process log' ($logs.Count -gt 0) ('entries=' + $logs.Count)

$registration = @($logs | Where-Object { $_.actionLabel -eq $expect.log.registrationLabel })
Check 'registering the complaint is in its log' ($registration.Count -ge 1) `
    (($logs | ForEach-Object { $_.actionLabel }) -join ' | ')
Check 'the registration entry names the person who did it' `
    (@($registration)[0].actorName -eq $expect.log.actorName) ('actor=' + @($registration)[0].actorName)
Check 'the log entry carries a detail line' `
    (-not [string]::IsNullOrWhiteSpace(@($registration)[0].detail)) ('detail=' + @($registration)[0].detail)
Check 'the entry is marked as a process action' (@($logs)[0].kind -eq 'AUDIT') ('kind=' + @($logs)[0].kind)
Check 'the log gives every entry a time' `
    (@($logs | Where-Object { [string]::IsNullOrWhiteSpace($_.at) }).Count -eq 0) 'an entry had no timestamp'

$logTimes = @($logs | ForEach-Object { $_.at })
$logOrdered = $true
for ($i = 1; $i -lt $logTimes.Count; $i++) {
    if ([string]$logTimes[$i] -gt [string]$logTimes[$i - 1]) { $logOrdered = $false }
}
Check 'the log is newest first' $logOrdered ($logTimes -join ',')

$otherLog = @((Invoke-Api 'GET' ('/api/complaints/' + $createdIds[1] + '/logs') $salesToken $null).body)
Check 'another complaint has its own log' `
    (@($otherLog | Where-Object { $_.detail -like ('*' + $complaintId + '*') }).Count -eq 0) `
    'the second complaint log mentions the first complaint'

$unknownLog = Invoke-Api 'GET' '/api/complaints/C202699999/logs' $salesToken $null
Check 'an unknown complaint has no process log (404)' ($unknownLog.status -eq 404) ('status=' + $unknownLog.status)

$anonLog = Invoke-Api 'GET' ('/api/complaints/' + $complaintId + '/logs') '' $null
Check 'the process log requires a login (401)' ($anonLog.status -eq 401) ('status=' + $anonLog.status)

# --- 10. audit trail --------------------------------------------------------
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
$auditSql = "select count(*) from qms.audit_log where action_type='CREATE' and biz_type='Complaint' and biz_id='" + $complaintId + "';"
$auditCount = (& $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value -t -A -c $auditSql) -join ''
Check 'an audit row was written for the registration' (($auditCount.Trim()) -eq '1') ('audit rows=' + $auditCount)
$retainSql = "select retain_until >= current_date + interval '2 years 11 months' from qms.audit_log where biz_id='" + $complaintId + "' limit 1;"
$retain = (& $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value -t -A -c $retainSql) -join ''
Check 'audit retention is at least three years' (($retain.Trim()) -eq 't') ('retain_until ok=' + $retain)

# --- cleanup ----------------------------------------------------------------
if ($createdIds.Count -gt 0) {
    if ($KeepData) {
        $lines.Add('')
        $lines.Add('  created (kept): ' + ($createdIds -join ', '))
    } else {
        # Sub-tables cascade from complaint, so one delete removes the whole set.
        # audit_log has no foreign key to complaint and is intentionally left behind.
        $quoted = ($createdIds | ForEach-Object { "'" + $_ + "'" }) -join ','
        & $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value `
            -c ("DELETE FROM qms.complaint WHERE complaint_id IN (" + $quoted + ");") | Out-Null
        $left = (& $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value `
            -t -A -c ("SELECT count(*) FROM qms.complaint WHERE complaint_id IN (" + $quoted + ");")) -join ''
        $lines.Add('')
        $lines.Add('  cleaned up ' + $createdIds.Count + ' test complaint(s); remaining=' + ($left.Trim()))
    }
}

$lines.Add('')
$lines.Add(('  RESULT : ' + $(if ($fail -eq 0) { 'PASS' } else { "FAIL ($fail)" }) + '   passed=' + $pass + ' failed=' + $fail))
$lines | Set-Content -Path (Join-Path $cfg.outDir 'verify_complaint_report.txt') -Encoding UTF8
$lines | ForEach-Object { [Console]::Out.WriteLine($_) }
if ($fail -ne 0) { exit 1 }
