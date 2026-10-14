<#
  verify-report.ps1
  Acceptance for D8 (requirement 3.9): report generation from D1-D7, the D6/D7
  precondition, Word export, the send-and-close flow with the date rules, the
  three distinct capabilities, and the audit trail.

  Pure ASCII.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\verify-report.ps1"
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
$tmp = Join-Path $cfg.outDir '_d8_export.docx'
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
        $a['Body'] = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $payload -Depth 12))
    }
    try {
        $response = Invoke-WebRequest @a
        $body = $null
        if ($response.Content) { $body = $response.Content | ConvertFrom-Json }
        return @{ status = [int]$response.StatusCode; body = $body }
    } catch {
        return @{ status = Get-ErrorStatus $_; body = $null; message = (Get-ErrorMessage $_) }
    }
}
function ApiBytes([string] $path, [string] $token, [string] $outFile) {
    $headers = @{}
    if ($token) { $headers['Authorization'] = 'Bearer ' + $token }
    try {
        Invoke-WebRequest -Uri ($BaseUrl + $path) -Method Get -Headers $headers -TimeoutSec 60 `
            -OutFile $outFile -UseBasicParsing
        return @{ status = 200; file = $outFile }
    } catch {
        return @{ status = Get-ErrorStatus $_; file = $null }
    }
}

$lines.Add('verify-report  ->  ' + $BaseUrl)
$lines.Add('')

$qe = Login 'siyuan.li' $Password
$token = $qe.accessToken
Check 'quality engineer logged in (holds report:generate)' ($null -ne $token) 'login failed'
if (-not $token) { $lines | ForEach-Object { [Console]::Out.WriteLine($_) }; exit 1 }

$sales = Login 'xiaoran.ma' $Password
$salesToken = $sales.accessToken
Check 'sales quality logged in (holds report:send)' ($null -ne $salesToken) 'login failed'

$today = (Get-Date).Date
$complaintIds = New-Object System.Collections.ArrayList

function NewComplaint([string] $token, [string] $tag) {
    $payload = @{
        header = @{
            complaintTypeCode = 'COMPLAINT_TYPE_001'; priorityCode = 'PRIORITY_002'
            failureLocationCode = 'FAILURE_LOCATION_005'; complaintOwnerId = 'U02'
            coordinatorId = 'U01'; customerTargetDate = (Get-Date).Date.AddDays(20).ToString('yyyy-MM-dd')
        }
        qualityPartner = @{ qualityPartnerCode = 'CUST-1001'; application = 'Yes'; contactPersonId = 'CP-1001'; subSegmentCode = 'SUB_SEGMENT_001' }
        product = @{ productTypeCode = 'PRODUCT_TYPE_001'; packingTypeCode = 'PACKING_TYPE_001' }
        failureDescription = @{ customerFailureModeCode = 'FAILURE_MODE_001' }
        samples = @(
            @{ customerSampleId = $tag; sampleQuantity = 3; uom = 'PCS'
               failureTypeL1Code = '2'; failureTypeL2Code = '2c'; failureTypeL3Code = '2ca' }
        )
    }
    return (Api 'POST' '/api/complaints' $token $payload).body
}

# Advance a complaint to a report-ready D7 (action verified + prevention file done).
function CompleteToD7([string] $token, $complaint, [bool] $preventionDone) {
    $id = $complaint.complaintId
    Api 'POST' ('/api/complaints/' + $id + '/validity') $token @{ valid = $true; conclusion = 'Reproduced.' } | Out-Null
    Api 'POST' ('/api/complaints/' + $id + '/containment/decision') $token @{ required = $true; note = 'Stock blocked.' } | Out-Null
    Api 'POST' ('/api/complaints/' + $id + '/containment/actions') $token @{
        plannedAction = 'Block suspect stock.'; ownerId = 'U06'
        plannedCompletionDate = $today.AddDays(3).ToString('yyyy-MM-dd')
        completedDate = $today.ToString('yyyy-MM-dd'); statusCode = 'CONTAIN_DONE'
    } | Out-Null
    $rc = (Api 'POST' ('/api/complaints/' + $id + '/root-causes') $token @{
        rootCauseDesc = 'Mold temperature drift.'; rootCauseSummary = 'Mold temperature drift'
        responsibleOrgType = 'INTERNAL'
    }).body.rootCause.rootCauseId
    $ac = (Api 'POST' ('/api/complaints/' + $id + '/corrective-actions') $token @{
        rootCauseId = $rc; plannedActionDesc = 'Add re-verification step.'; ownerId = 'U06'
        targetDate = $today.AddDays(7).ToString('yyyy-MM-dd')
    }).body.action.correctiveActionId
    Api 'POST' ('/api/corrective-actions/' + $ac + '/verifications') $token @{
        actualCompletionDate = $today.ToString('yyyy-MM-dd'); verificationResult = 'Verified.'
        isEffective = $true
    } | Out-Null
    $prevStatus = if ($preventionDone) { 'PREV_DONE' } else { 'PREV_TODO' }
    Api 'POST' ('/api/complaints/' + $id + '/prevention-files') $token @{
        fileTypeCode = 'FILE_TYPE_001'; controlProgram = 'CTL-2026-114'
        referenceNumber = 'FMEA-8801'; statusCode = $prevStatus
    } | Out-Null
}

# --- precondition: an open prevention file blocks generation ----------------
$open = NewComplaint $token 'CS-D8-OPEN'
[void]$complaintIds.Add($open.complaintId)
CompleteToD7 $token $open $false
$blocked = Api 'POST' ('/api/complaints/' + $open.complaintId + '/reports') $token @{ reportType = 'INTERIM' }
Check 'an unfinished D7 blocks report generation' ($blocked.status -eq 409) ('status=' + $blocked.status)
Check 'the block is explained' ($blocked.message -like ('*' + $expect.report.preconditionPrevention + '*')) ('msg=' + $blocked.message)

# --- generation -------------------------------------------------------------
$a = NewComplaint $token 'CS-D8-1'
[void]$complaintIds.Add($a.complaintId)
CompleteToD7 $token $a $true

$created = Api 'POST' ('/api/complaints/' + $a.complaintId + '/reports') $token @{ reportType = 'INTERIM' }
Check 'a report can be generated' ($created.status -eq 201) ('status=' + $created.status + ' ' + $created.message)
$reportId = $created.body.reportId
Check 'the report id is generated' ($reportId -match '^R\d{9}$') ('id=' + $reportId)
Check 'a new report is a draft' ($created.body.approvalStatus -eq 'DRAFT') ('status=' + $created.body.approvalStatus)
Check 'the report type is labelled' ($created.body.reportTypeName -eq $expect.report.typeInterim) ('name=' + $created.body.reportTypeName)
Check 'the template is XTE-0071' ($created.body.templateCode -eq 'XTE-0071') ('tpl=' + $created.body.templateCode)
Check 'the dates stay empty until it is sent' (($null -eq $created.body.reportStartDate) -and ($null -eq $created.body.reportCloseDate)) 'dates were filled early'

$detail = (Api 'GET' ('/api/complaints/' + $a.complaintId) $token $null).body
Check 'generating advances the complaint to D8' ($detail.currentStage -eq 'D8') ('stage=' + $detail.currentStage)
Check 'the complaint moves to report drafting' ($detail.statusCode -eq 'COMPLAINT_S06') ('status=' + $detail.statusCode)

$badType = Api 'POST' ('/api/complaints/' + $a.complaintId + '/reports') $token @{ reportType = 'NOPE' }
Check 'an unknown report type is refused' ($badType.status -eq 400) ('status=' + $badType.status)

# --- the assembled content --------------------------------------------------
$content = (Api 'GET' ('/api/reports/' + $reportId) $token $null).body
Check 'the report content is returned' ($content.report.reportId -eq $reportId) 'report missing'
Check 'the D1 team is snapshotted' (@($content.team).Count -ge 1) ('team=' + @($content.team).Count)
Check 'the D5/D6 actions are included' (@($content.correctiveActions).Count -eq 1) ('actions=' + @($content.correctiveActions).Count)
Check 'the D7 files are included' (@($content.preventionFiles).Count -eq 1) ('files=' + @($content.preventionFiles).Count)
Check 'the complaint block is included' ($content.complaint.complaintId -eq $a.complaintId) 'complaint missing'

# --- Word export ------------------------------------------------------------
$export = ApiBytes ('/api/reports/' + $reportId + '/export.docx') $token $tmp
Check 'the report exports as Word' ($export.status -eq 200) ('status=' + $export.status)
$bytes = if (Test-Path $tmp) { [System.IO.File]::ReadAllBytes($tmp) } else { @() }
Check 'the export is a real .docx (ZIP magic)' (($bytes.Length -gt 2) -and ($bytes[0] -eq 0x50) -and ($bytes[1] -eq 0x4B)) ('firstBytes=' + ($bytes[0..1] -join ','))

# --- PDF export -------------------------------------------------------------
# Only the font subset actually used is embedded, so a healthy report is tens of
# kilobytes rather than megabytes; the floor only has to catch an empty file.
$pdfTmp = Join-Path $cfg.outDir 'verify_report_export.pdf'
$pdfProbe = Invoke-WebRequest -Uri ($BaseUrl + '/api/reports/' + $reportId + '/export.pdf') `
    -Headers @{ Authorization = 'Bearer ' + $token } -TimeoutSec 60 -UseBasicParsing
Check 'the PDF export declares the pdf content type' `
    ($pdfProbe.Headers['Content-Type'] -like '*application/pdf*') ('content-type=' + $pdfProbe.Headers['Content-Type'])
$pdfExport = ApiBytes ('/api/reports/' + $reportId + '/export.pdf') $token $pdfTmp
Check 'the report exports as PDF' ($pdfExport.status -eq 200) ('status=' + $pdfExport.status)
$pdfBytes = if (Test-Path $pdfTmp) { [System.IO.File]::ReadAllBytes($pdfTmp) } else { @() }
$pdfMagic = if ($pdfBytes.Length -ge 4) { [System.Text.Encoding]::ASCII.GetString($pdfBytes[0..3]) } else { '' }
Check 'the export is a real PDF (magic)' ($pdfMagic -eq '%PDF') ('magic=' + $pdfMagic)
Check 'the PDF carries a font subset, not just a header' ($pdfBytes.Length -gt 5000) ('bytes=' + $pdfBytes.Length)

# --- permissions ------------------------------------------------------------
Check 'sales quality can read reports' ((Api 'GET' ('/api/reports/' + $reportId) $salesToken $null).status -eq 200) 'expected 200'
Check 'the quality engineer cannot send' ((Api 'POST' ('/api/reports/' + $reportId + '/send') $token @{ recipient = 'a@b.com'; subject = 's'; body = 'b' }).status -eq 403) 'expected 403'
$auditor = Login 'zhiyuan.chen' $Password
Check 'an auditor cannot generate a report' ((Api 'POST' ('/api/complaints/' + $a.complaintId + '/reports') $auditor.accessToken @{ reportType = 'INTERIM' }).status -eq 403) 'expected 403'
Check 'report endpoints require a login' ((Api 'GET' '/api/reports/R999999999' '' $null).status -eq 401) 'expected 401'
Check 'an unknown report returns 404' ((Api 'GET' '/api/reports/R999999999' $token $null).status -eq 404) 'expected 404'

# --- approval gates the send -------------------------------------------------
# The report goes out to the customer and closes the complaint, so it needs an
# approval first; the send stays refused until that step has been walked.
$sendBody = @{ recipient = 'customer@example.com'; ccList = 'internal@example.com'; subject = '8D Report'; body = 'Please find attached.' }

$gate = Api 'POST' ('/api/reports/' + $reportId + '/send') $salesToken $sendBody
Check 'an unapproved report cannot be sent' ($gate.status -eq 409) ('status=' + $gate.status)
Check 'the refusal says an approval is missing' `
    ($gate.message -like ('*' + $expect.report.approvalRequired + '*')) ('msg=' + $gate.message)

$approverList = Api 'GET' '/api/reports/approvers' $salesToken $null
Check 'the approver list is exposed for the dialog' `
    ($approverList.status -eq 200 -and @($approverList.body).Count -gt 0) `
    ('status=' + $approverList.status + ' count=' + @($approverList.body).Count)

$badApprover = Api 'POST' ('/api/reports/' + $reportId + '/submit') $salesToken @{ approverId = 'U02' }
Check 'someone without approval rights cannot be named approver' ($badApprover.status -eq 400) ('status=' + $badApprover.status)

Check 'an auditor cannot submit a report for approval' `
    ((Api 'POST' ('/api/reports/' + $reportId + '/submit') $auditor.accessToken @{ approverId = 'U09' }).status -eq 403) 'expected 403'

$submit = Api 'POST' ('/api/reports/' + $reportId + '/submit') $salesToken @{ approverId = 'U09' }
Check 'a report can be submitted for approval' ($submit.status -eq 200) ('status=' + $submit.status + ' ' + $submit.message)
Check 'the submitted report is pending' ($submit.body.approvalStatus -eq 'PENDING') ('status=' + $submit.body.approvalStatus)
Check 'the pending approval names the approver' `
    ($submit.body.approval.approverName -eq $expect.report.approverName) ('approver=' + $submit.body.approval.approverName)
Check 'submitting the same report twice is refused' `
    ((Api 'POST' ('/api/reports/' + $reportId + '/submit') $salesToken @{ approverId = 'U09' }).status -eq 409) 'expected 409'

# U05 also holds report:approve, which is what makes the next check meaningful.
$otherApproverToken = (Login 'zhiyuan.chen' $Password).accessToken
$otherApprover = Api 'POST' ('/api/reports/' + $reportId + '/approve') $otherApproverToken @{ approved = $true }
Check 'an approver who was not named cannot decide it' ($otherApprover.status -eq 403) ('status=' + $otherApprover.status)
Check 'the refusal names the approver who owes the decision' `
    ($otherApprover.message -like ('*' + $expect.report.approverName + '*')) ('msg=' + $otherApprover.message)

$approverToken = (Login 'hong.zhang' $Password).accessToken
$noComment = Api 'POST' ('/api/reports/' + $reportId + '/approve') $approverToken @{ approved = $false }
Check 'rejecting without a comment is refused' ($noComment.status -eq 400) ('status=' + $noComment.status)
Check 'rejecting without a comment says why' `
    ($noComment.message -like ('*' + $expect.report.rejectionNeedsComment + '*')) ('msg=' + $noComment.message)

$approve = Api 'POST' ('/api/reports/' + $reportId + '/approve') $approverToken `
    @{ approved = $true; comment = 'Checked against the customer template.' }
Check 'the named approver can approve' ($approve.status -eq 200) ('status=' + $approve.status + ' ' + $approve.message)
Check 'the report is approved' ($approve.body.approvalStatus -eq 'APPROVED') ('status=' + $approve.body.approvalStatus)

# --- send and close (Sales Quality only) ------------------------------------
$sent = Api 'POST' ('/api/reports/' + $reportId + '/send') $salesToken $sendBody
Check 'sales quality can send the report' ($sent.status -eq 200) ('status=' + $sent.status + ' ' + $sent.message)

$expectedStart = $today.ToString('yyyy-MM-dd')
$expectedTarget = $today.AddDays(14).ToString('yyyy-MM-dd')
Check 'the start date is the send day' ($sent.body.report.reportStartDate -eq $expectedStart) ('start=' + $sent.body.report.reportStartDate)
Check 'the close date is the send day' ($sent.body.report.reportCloseDate -eq $expectedStart) ('close=' + $sent.body.report.reportCloseDate)
Check 'the target date defaults to start + 14' ($sent.body.report.reportTargetDate -eq $expectedTarget) ('target=' + $sent.body.report.reportTargetDate)
Check 'a communication log entry is returned' ($null -ne $sent.body.distribution) 'no log'

$closed = (Api 'GET' ('/api/complaints/' + $a.complaintId) $token $null).body
Check 'sending closes the complaint' ($closed.closeDate -eq $expectedStart) ('closeDate=' + $closed.closeDate)
Check 'the close reason is the normal one' ($closed.closeReasonCode -eq 'CLOSE_NORMAL') ('reason=' + $closed.closeReasonCode)
Check 'the complaint is in the closed status' ($closed.statusCode -eq 'COMPLAINT_S07') ('status=' + $closed.statusCode)

Check 'a closed complaint refuses a new report' ((Api 'POST' ('/api/complaints/' + $a.complaintId + '/reports') $token @{ reportType = 'FINAL' }).status -eq 409) 'expected 409'
Check 'a closed complaint refuses another send' ((Api 'POST' ('/api/reports/' + $reportId + '/send') $salesToken $sendBody).status -eq 409) 'expected 409'

# --- audit and persistence --------------------------------------------------
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
Check 'the report generation was audited' ((Q "select count(*) from qms.audit_log where action_type='CREATE' and biz_type='Report8D' and biz_id='$($a.complaintId)'") -ge '1') 'expected at least 1'
Check 'the export was audited' ((Q "select count(*) from qms.audit_log where action_type='EXPORT' and biz_type='Report8D' and biz_id='$($a.complaintId)'") -ge '1') 'expected at least 1'
Check 'the send was audited' ((Q "select count(*) from qms.audit_log where action_type='SEND' and biz_type='Report8D' and biz_id='$($a.complaintId)'") -ge '1') 'expected at least 1'
Check 'the closure was audited' ((Q "select count(*) from qms.audit_log where action_type='STATUS_CHANGE' and biz_type='Complaint' and biz_id='$($a.complaintId)' and after_value like '%COMPLAINT_S07%'") -ge '1') 'expected at least 1'
Check 'the communication log is persisted' ((Q "select count(*) from qms.report_distribution where report_id='$reportId' and is_deleted = false") -eq '1') 'expected 1'
Check 'the report row carries the send dates' ((Q "select count(*) from qms.report_8d where report_id='$reportId' and report_start_date = report_close_date and report_target_date = report_start_date + 14") -eq '1') 'date rule not stored'

# --- cleanup ----------------------------------------------------------------
if (-not $KeepData) {
    $quoted = ($complaintIds | ForEach-Object { "'" + $_ + "'" }) -join ','
    & $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value -q `
        -c ("DELETE FROM qms.complaint WHERE complaint_id IN (" + $quoted + ");") | Out-Null
    if (Test-Path $tmp) { Remove-Item -Force $tmp }
    $lines.Add('')
    $lines.Add('  cleaned up ' + $complaintIds.Count + ' test complaint(s)')
}

$lines.Add('')
$lines.Add(('  RESULT : ' + $(if ($fail -eq 0) { 'PASS' } else { "FAIL ($fail)" }) + '   passed=' + $pass + ' failed=' + $fail))
$lines | Set-Content -Path (Join-Path $cfg.outDir 'verify_report_report.txt') -Encoding UTF8
$lines | ForEach-Object { [Console]::Out.WriteLine($_) }
if ($fail -ne 0) { exit 1 }
