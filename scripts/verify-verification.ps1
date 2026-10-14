<#
  verify-verification.ps1
  Acceptance for D2 (requirement 3.3): task creation and scheduling, single and
  batch result entry, the failure type chain, the complaint stage/status advance,
  the validity conclusion and its two branches, permissions and the audit trail.

  Pure ASCII.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\verify-verification.ps1"
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
        # ConvertTo-Json unwraps it into a bare object.
        $a['Body'] = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $payload -Depth 12))
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

function NewComplaint([string] $token, [string] $sampleTag) {
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
            @{ customerSampleId = $sampleTag; sampleQuantity = 3; uom = 'PCS'
               failureTypeL1Code = '2'; failureTypeL2Code = '2c'; failureTypeL3Code = '2ca' }
        )
    }
    return (Api 'POST' '/api/complaints' $token $payload).body
}

$lines.Add('verify-verification  ->  ' + $BaseUrl)
$lines.Add('')

$qe = Login 'siyuan.li' $Password
$token = $qe.accessToken
Check 'quality engineer logged in (holds verify:edit)' ($null -ne $token) 'login failed'
if (-not $token) { $lines | ForEach-Object { [Console]::Out.WriteLine($_) }; exit 1 }

$today = (Get-Date).Date
$complaintIds = New-Object System.Collections.ArrayList

# --- 1. a complaint to verify ------------------------------------------------
$a = NewComplaint $token 'CS-D2-1'
[void]$complaintIds.Add($a.complaintId)
Check 'a complaint was registered at D1' ($a.currentStage -eq 'D1') ('stage=' + $a.currentStage)
$detail = (Api 'GET' ('/api/complaints/' + $a.complaintId) $token $null).body
$sampleId = $detail.samples[0].sampleId

# --- 2. create a D2 task ----------------------------------------------------
$taskBody = @{
    sampleId = $sampleId; taskOwnerId = 'U03'
    plannedStartDate = $today.ToString('yyyy-MM-dd')
    targetCompletionDate = $today.AddDays(3).ToString('yyyy-MM-dd')
}
$created = Api 'POST' ('/api/complaints/' + $a.complaintId + '/verification-tasks') $token $taskBody
Check 'a verification task can be created' ($created.status -eq 201 -or $created.status -eq 200) ('status=' + $created.status + ' ' + $created.message)
$taskId = $created.body.task.taskId
Check 'the task id is generated' ($taskId -match '^VT\d{9}$') ('id=' + $taskId)
Check 'a task with a planned start is scheduled' ($created.body.task.taskStatus -eq 'VERIF_SCHEDULED') ('status=' + $created.body.task.taskStatus)
Check 'the task status name is resolved' ($created.body.task.taskStatusName -eq $expect.verification.taskStatusScheduled) ('name=' + $created.body.task.taskStatusName)

$detail = (Api 'GET' ('/api/complaints/' + $a.complaintId) $token $null).body
Check 'the complaint moved to D2' ($detail.currentStage -eq 'D2') ('stage=' + $detail.currentStage)
Check 'the complaint status became verification-scheduled' ($detail.statusCode -eq 'COMPLAINT_S02') ('status=' + $detail.statusCode)

# --- 3. the target conflict warning -----------------------------------------
$lateBody = $taskBody.Clone()
$lateBody['targetCompletionDate'] = $today.AddDays(60).ToString('yyyy-MM-dd')
$lateTask = (Api 'POST' ('/api/complaints/' + $a.complaintId + '/verification-tasks') $token $lateBody).body
Check 'a task due after the complaint is flagged' ($lateTask.task.targetWarning -like ('*' + $expect.verification.scheduleWarning + '*')) ('warning=' + $lateTask.task.targetWarning)

# --- 4. task validation -----------------------------------------------------
$bad = $taskBody.Clone(); $bad['taskOwnerId'] = 'U99'
Check 'an unknown task owner is refused' ((Api 'POST' ('/api/complaints/' + $a.complaintId + '/verification-tasks') $token $bad).status -eq 400) 'expected 400'

$bad = $taskBody.Clone()
$bad['plannedStartDate'] = $today.AddDays(5).ToString('yyyy-MM-dd')
$bad['targetCompletionDate'] = $today.AddDays(1).ToString('yyyy-MM-dd')
Check 'a target before the planned start is refused' ((Api 'POST' ('/api/complaints/' + $a.complaintId + '/verification-tasks') $token $bad).status -eq 400) 'expected 400'

$bad = $taskBody.Clone(); $bad['taskStatus'] = 'NOT_A_STATUS'
$badStatus = Api 'POST' ('/api/complaints/' + $a.complaintId + '/verification-tasks') $token $bad
Check 'an unknown task status is refused' ($badStatus.status -eq 400) ('status=' + $badStatus.status)
Check 'the unknown task status is explained' ($badStatus.message -like ('*' + $expect.verification.invalidTaskStatus + '*')) ('msg=' + $badStatus.message)

$b = NewComplaint $token 'CS-D2-OTHER'
[void]$complaintIds.Add($b.complaintId)
$foreignSample = (Api 'GET' ('/api/complaints/' + $b.complaintId) $token $null).body.samples[0].sampleId
$bad = $taskBody.Clone(); $bad['sampleId'] = $foreignSample
Check 'a sample from another complaint is refused' ((Api 'POST' ('/api/complaints/' + $a.complaintId + '/verification-tasks') $token $bad).status -eq 400) 'expected 400'

Check 'a task for an unknown complaint returns 404' ((Api 'POST' '/api/complaints/C202699999/verification-tasks' $token $taskBody).status -eq 404) 'expected 404'

# --- 5. record one result ---------------------------------------------------
$result = @{ testItem = 'X-Ray'; failureTypeL1Code = '2'; failureTypeL2Code = '2c'; failureTypeL3Code = '2ca'; resultConclusion = 'Package chipping confirmed' }
$after = Api 'POST' ('/api/verification-tasks/' + $taskId + '/results') $token $result
Check 'one result line can be recorded' ($after.status -eq 200) ('status=' + $after.status + ' ' + $after.message)
Check 'the task now has one result' (@($after.body.results).Count -eq 1) ('count=' + @($after.body.results).Count)
Check 'the entry mode is recorded as single' (@($after.body.results)[0].entryMode -eq 'SINGLE') ('mode=' + @($after.body.results)[0].entryMode)
Check 'the failure type names are resolved' (@($after.body.results)[0].failureTypeL3Name -like '*Package chipping*') ('name=' + @($after.body.results)[0].failureTypeL3Name)
Check 'the recorder is stamped' (@($after.body.results)[0].recordedByName -eq $expect.verification.recorderName) ('by=' + @($after.body.results)[0].recordedByName)
Check 'the task result count is reported' ($after.body.task.resultCount -eq 1) ('count=' + $after.body.task.resultCount)

$detail = (Api 'GET' ('/api/complaints/' + $a.complaintId) $token $null).body
Check 'the complaint status became verifying' ($detail.statusCode -eq 'COMPLAINT_S03') ('status=' + $detail.statusCode)
Check 'the stage is still D2' ($detail.currentStage -eq 'D2') ('stage=' + $detail.currentStage)

# --- 6. the failure type chain is enforced here too -------------------------
$broken = @{ testItem = 'Broken'; failureTypeL1Code = '2'; failureTypeL2Code = '3a'; resultConclusion = 'x' }
$badChain = Api 'POST' ('/api/verification-tasks/' + $taskId + '/results') $token $broken
Check 'a broken failure type chain is refused' ($badChain.status -eq 400) ('status=' + $badChain.status)
Check 'the broken chain is explained' ($badChain.message -like ('*' + $expect.verification.brokenChain + '*')) ('msg=' + $badChain.message)

# --- 7. batch entry ---------------------------------------------------------
$batch = @(
    @{ testItem = 'Electrical test'; failureTypeL1Code = '2'; failureTypeL2Code = '2c'; failureTypeL3Code = '2cb'; resultConclusion = 'Mold flash found' },
    @{ testItem = 'Visual inspection'; failureTypeL1Code = '2'; failureTypeL2Code = '2c'; failureTypeL3Code = '2cc'; resultConclusion = 'Void in mold' }
)
$afterBatch = Api 'POST' ('/api/verification-tasks/' + $taskId + '/results/batch') $token $batch
Check 'a batch of results can be recorded' ($afterBatch.status -eq 200) ('status=' + $afterBatch.status + ' ' + $afterBatch.message)
Check 'all batch lines were stored' (@($afterBatch.body.results).Count -eq 3) ('count=' + @($afterBatch.body.results).Count)
$batchModes = @(@($afterBatch.body.results) | Where-Object { $_.entryMode -eq 'BATCH' })
Check 'the batch lines are marked as batch entry' ($batchModes.Count -eq 2) ('batch lines=' + $batchModes.Count)

$empty = Api 'POST' ('/api/verification-tasks/' + $taskId + '/results/batch') $token @()
Check 'an empty batch is refused' ($empty.status -eq 400) ('status=' + $empty.status)

$badBatch = @(
    @{ testItem = 'Good'; failureTypeL1Code = '2'; failureTypeL2Code = '2c'; resultConclusion = 'ok' },
    @{ testItem = 'Bad'; failureTypeL1Code = '2'; failureTypeL2Code = '4a'; resultConclusion = 'x' }
)
$mixed = Api 'POST' ('/api/verification-tasks/' + $taskId + '/results/batch') $token $badBatch
Check 'a batch with one bad row is refused entirely' ($mixed.status -eq 400) ('status=' + $mixed.status)
$afterMixed = (Api 'GET' ('/api/verification-tasks/' + $taskId) $token $null).body
Check 'nothing from the rejected batch was stored' (@($afterMixed.results).Count -eq 3) ('count=' + @($afterMixed.results).Count)

# --- 8. removing a result line ---------------------------------------------
$firstResultId = @($afterMixed.results)[0].resultId
$removed = Api 'DELETE' ('/api/verification-tasks/' + $taskId + '/results/' + $firstResultId) $token $null
Check 'a result line can be removed' ($removed.status -eq 200) ('status=' + $removed.status)
Check 'the removal is reflected' (@($removed.body.results).Count -eq 2) ('count=' + @($removed.body.results).Count)

# --- 9. completing a task blocks further entry -----------------------------
$doneBody = $taskBody.Clone(); $doneBody['taskStatus'] = 'VERIF_DONE'
$done = Api 'PUT' ('/api/verification-tasks/' + $taskId) $token $doneBody
Check 'a task can be marked complete' ($done.status -eq 200) ('status=' + $done.status)
Check 'completion stamps the completion time' ($null -ne $done.body.task.completedAt) 'completedAt missing'

$blocked = Api 'POST' ('/api/verification-tasks/' + $taskId + '/results') $token $result
Check 'a completed task refuses further results' ($blocked.status -eq 409) ('status=' + $blocked.status)
Check 'the refusal explains why' ($blocked.message -like ('*' + $expect.verification.taskClosedForEntry + '*')) ('msg=' + $blocked.message)

# --- 10. the validity conclusion: valid branch -----------------------------
$valid = Api 'POST' ('/api/complaints/' + $a.complaintId + '/validity') $token @{
    valid = $true; conclusion = 'Failure reproduced; complaint valid.'
}
Check 'a valid conclusion is accepted' ($valid.status -eq 200) ('status=' + $valid.status + ' ' + $valid.message)
Check 'a valid complaint advances to D3' ($valid.body.currentStage -eq 'D3') ('stage=' + $valid.body.currentStage)
Check 'a valid complaint moves to the analysing status' ($valid.body.statusCode -eq 'COMPLAINT_S04') ('status=' + $valid.body.statusCode)
Check 'a valid complaint is not closed' ($null -eq $valid.body.closeDate) ('closeDate=' + $valid.body.closeDate)

$detail = (Api 'GET' ('/api/complaints/' + $a.complaintId) $token $null).body
Check 'the conclusion was written to the failure description' ($detail.failureDescription.analysisConclusion -like '*reproduced*') ('conclusion=' + $detail.failureDescription.analysisConclusion)

$again = Api 'POST' ('/api/complaints/' + $a.complaintId + '/validity') $token @{ valid = $false }
Check 'a non-administrator cannot change a decided verdict' ($again.status -eq 403) ('status=' + $again.status)
Check 'the refusal points at the administrator' ($again.message -like ('*' + $expect.verification.alreadyDecided + '*')) ('msg=' + $again.message)

# --- 10b. only an administrator may change a determined verdict -------------
$admin = Login 'ying.zhou' $Password
$adminChange = Api 'POST' ('/api/complaints/' + $a.complaintId + '/validity') $admin.accessToken @{
    valid = $false; conclusion = 'Administrator override: not valid after all.'
}
Check 'an administrator can change a determined verdict' ($adminChange.status -eq 200) ('status=' + $adminChange.status + ' ' + $adminChange.message)
Check 'changing to invalid closes the complaint' ($adminChange.body.closeDate -eq $today.ToString('yyyy-MM-dd')) ('closeDate=' + $adminChange.body.closeDate)
Check 'changing to invalid records the close reason' ($adminChange.body.closeReasonCode -eq 'CLOSE_INVALID') ('reason=' + $adminChange.body.closeReasonCode)
Check 'changing to invalid reaches the final status' ($adminChange.body.statusCode -eq 'COMPLAINT_S07') ('status=' + $adminChange.body.statusCode)

$reopen = Api 'POST' ('/api/complaints/' + $a.complaintId + '/validity') $admin.accessToken @{
    valid = $true; conclusion = 'Administrator reopened the complaint.'
}
Check 'an administrator can reverse the verdict back to valid' ($reopen.status -eq 200) ('status=' + $reopen.status + ' ' + $reopen.message)
Check 'reversing clears the close date' ($null -eq $reopen.body.closeDate) ('closeDate=' + $reopen.body.closeDate)
Check 'reversing clears the close reason' ($null -eq $reopen.body.closeReasonCode) ('reason=' + $reopen.body.closeReasonCode)
Check 'reversing returns the complaint to the analysing stage' ($reopen.body.currentStage -eq 'D3') ('stage=' + $reopen.body.currentStage)
Check 'reversing restores the analysing status' ($reopen.body.statusCode -eq 'COMPLAINT_S04') ('status=' + $reopen.body.statusCode)

$detail = (Api 'GET' ('/api/complaints/' + $a.complaintId) $token $null).body
Check 'the reopened complaint is no longer closed' ($null -eq $detail.closeDate) ('closeDate=' + $detail.closeDate)
$reopenedTask = Api 'POST' ('/api/complaints/' + $a.complaintId + '/verification-tasks') $token $lateBody
Check 'the reopened complaint is usable again' ($reopenedTask.status -eq 201) `
    ('status=' + $reopenedTask.status + ' ' + $reopenedTask.message)

# --- 11. the validity conclusion: invalid branch closes the complaint -------
$c = NewComplaint $token 'CS-D2-INVALID'
[void]$complaintIds.Add($c.complaintId)
# The task must use this complaint's own sample: a task carrying another
# complaint's sample is refused, which would leave $invalidTask empty and make
# every later assertion in this block meaningless.
$cDetail = (Api 'GET' ('/api/complaints/' + $c.complaintId) $token $null).body
$cTaskBody = $taskBody.Clone()
$cTaskBody['sampleId'] = $cDetail.samples[0].sampleId
$invalidTask = (Api 'POST' ('/api/complaints/' + $c.complaintId + '/verification-tasks') $token $cTaskBody).body.task.taskId
Check 'a task exists on the complaint that will be voided' ($invalidTask -match '^VT\d{9}$') ('id=' + $invalidTask)
$invalid = Api 'POST' ('/api/complaints/' + $c.complaintId + '/validity') $token @{
    valid = $false; conclusion = 'No failure found on returned units.'
}
Check 'an invalid conclusion is accepted' ($invalid.status -eq 200) ('status=' + $invalid.status + ' ' + $invalid.message)
Check 'an invalid complaint is closed' ($invalid.body.closeDate -eq $today.ToString('yyyy-MM-dd')) ('closeDate=' + $invalid.body.closeDate)
Check 'an invalid complaint records the close reason' ($invalid.body.closeReasonCode -eq 'CLOSE_INVALID') ('reason=' + $invalid.body.closeReasonCode)
Check 'an invalid complaint lands on the closing stage' ($invalid.body.currentStage -eq 'D8') ('stage=' + $invalid.body.currentStage)
Check 'an invalid complaint reaches the final status' ($invalid.body.statusCode -eq 'COMPLAINT_S07') ('status=' + $invalid.body.statusCode)

$closedTask = Api 'POST' ('/api/complaints/' + $c.complaintId + '/verification-tasks') $token $taskBody
Check 'a closed complaint refuses new verification work' ($closedTask.status -eq 409) ('status=' + $closedTask.status)
Check 'the closed refusal is explained' ($closedTask.message -like ('*' + $expect.verification.complaintClosed + '*')) ('msg=' + $closedTask.message)

$closedEntry = Api 'POST' ('/api/verification-tasks/' + $invalidTask + '/results') $token $result
Check 'a closed complaint refuses new results' ($closedEntry.status -eq 409) ('status=' + $closedEntry.status)

$invalidAgain = Api 'POST' ('/api/complaints/' + $c.complaintId + '/validity') $token @{ valid = $true }
Check 'a decided invalid complaint cannot be re-decided by a non-admin' ($invalidAgain.status -eq 403) ('status=' + $invalidAgain.status)

# --- 12. permissions --------------------------------------------------------
$sales = Login 'xiaoran.ma' $Password
Check 'sales quality can read D2 tasks' ((Api 'GET' ('/api/complaints/' + $a.complaintId + '/verification-tasks') $sales.accessToken $null).status -eq 200) 'expected 200'
Check 'sales quality cannot create a D2 task' ((Api 'POST' ('/api/complaints/' + $a.complaintId + '/verification-tasks') $sales.accessToken $taskBody).status -eq 403) 'expected 403'
Check 'sales quality cannot decide validity' ((Api 'POST' ('/api/complaints/' + $a.complaintId + '/validity') $sales.accessToken @{ valid = $true }).status -eq 403) 'expected 403'

$auditor = Login 'zhiyuan.chen' $Password
Check 'an auditor cannot record results' ((Api 'POST' ('/api/verification-tasks/' + $taskId + '/results') $auditor.accessToken $result).status -eq 403) 'expected 403'
Check 'D2 endpoints require a login' ((Api 'GET' ('/api/complaints/' + $a.complaintId + '/verification-tasks') '' $null).status -eq 401) 'expected 401'
Check 'an unknown task returns 404' ((Api 'GET' '/api/verification-tasks/VT999999999' $token $null).status -eq 404) 'expected 404'

# --- 13. audit trail --------------------------------------------------------
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
Check 'the task creation was audited' ((Q "select count(*) from qms.audit_log where action_type='CREATE' and biz_type='VerificationTask' and biz_id='$($a.complaintId)'") -ge '1') 'expected at least 1'
Check 'the stage advance was audited' ((Q "select count(*) from qms.audit_log where action_type='STATUS_CHANGE' and biz_type='Complaint' and biz_id='$($a.complaintId)'") -ge '1') 'expected at least 1'
Check 'the validity decision was audited' ((Q "select count(*) from qms.audit_log where biz_id='$($a.complaintId)' and after_value like '%D2%'") -ge '1') 'expected at least 1'
# A changed verdict keeps both sides of the change. Matched on columns, not on
# Chinese text: psql cannot take Chinese in a -c argument on Windows.
Check 'an override keeps the before and after values' ((Q "select count(*) from qms.audit_log where action_type='UPDATE' and biz_type='Complaint' and biz_id='$($a.complaintId)' and before_value is not null and after_value is not null") -ge '1') 'expected at least 1'
Check 'the invalid closure was audited' ((Q "select count(*) from qms.audit_log where biz_id='$($c.complaintId)' and after_value like '%CLOSE_INVALID%'") -ge '1') 'expected at least 1'

# --- cleanup ----------------------------------------------------------------
if (-not $KeepData) {
    $quoted = ($complaintIds | ForEach-Object { "'" + $_ + "'" }) -join ','
    & $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value -q `
        -c ("DELETE FROM qms.complaint WHERE complaint_id IN (" + $quoted + ");") | Out-Null
    $lines.Add('')
    $lines.Add('  cleaned up ' + $complaintIds.Count + ' test complaint(s), their tasks and results')
}

$lines.Add('')
$lines.Add(('  RESULT : ' + $(if ($fail -eq 0) { 'PASS' } else { "FAIL ($fail)" }) + '   passed=' + $pass + ' failed=' + $fail))
$lines | Set-Content -Path (Join-Path $cfg.outDir 'verify_verification_report.txt') -Encoding UTF8
$lines | ForEach-Object { [Console]::Out.WriteLine($_) }
if ($fail -ne 0) { exit 1 }
