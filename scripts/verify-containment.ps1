<#
  verify-containment.ps1
  Acceptance for D3 (requirement 3.4, PS-039 to PS-041): the "is containment
  needed" decision, action registration and status tracking, the completion-date
  rule, the two states being kept consistent, permissions and the audit trail.

  Pure ASCII.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\verify-containment.ps1"
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

$lines.Add('verify-containment  ->  ' + $BaseUrl)
$lines.Add('')

$qe = Login 'siyuan.li' $Password
$token = $qe.accessToken
Check 'quality engineer logged in (holds containment:edit)' ($null -ne $token) 'login failed'
if (-not $token) { $lines | ForEach-Object { [Console]::Out.WriteLine($_) }; exit 1 }

$today = (Get-Date).Date
$complaintIds = New-Object System.Collections.ArrayList

# --- 1. a complaint brought up to D3 ----------------------------------------
$payload = @{
    header = @{
        complaintTypeCode = 'COMPLAINT_TYPE_001'; priorityCode = 'PRIORITY_002'
        failureLocationCode = 'FAILURE_LOCATION_005'; complaintOwnerId = 'U02'
        coordinatorId = 'U01'; customerTargetDate = $today.AddDays(20).ToString('yyyy-MM-dd')
    }
    qualityPartner = @{ qualityPartnerCode = 'CUST-1001'; application = 'Yes'; contactPersonId = 'CP-1001'; subSegmentCode = 'SUB_SEGMENT_001' }
    product = @{ productTypeCode = 'PRODUCT_TYPE_001'; packingTypeCode = 'PACKING_TYPE_001' }
    failureDescription = @{ customerFailureModeCode = 'FAILURE_MODE_001' }
    samples = @(
        @{ customerSampleId = 'CS-D3-1'; sampleQuantity = 3; uom = 'PCS'
           failureTypeL1Code = '2'; failureTypeL2Code = '2c'; failureTypeL3Code = '2ca' }
    )
}
$a = (Api 'POST' '/api/complaints' $token $payload).body
[void]$complaintIds.Add($a.complaintId)
$validity = Api 'POST' ('/api/complaints/' + $a.complaintId + '/validity') $token @{ valid = $true }
Check 'the complaint reached D3 by passing D2' ($validity.body.currentStage -eq 'D3') ('stage=' + $validity.body.currentStage)

# --- 2. the decision starts undecided ---------------------------------------
$summary = (Api 'GET' ('/api/complaints/' + $a.complaintId + '/containment') $token $null).body
Check 'containment starts undecided' ($null -eq $summary.required) ('required=' + $summary.required)
Check 'no actions are registered yet' (@($summary.actions).Count -eq 0) ('count=' + @($summary.actions).Count)
Check 'the complaint is reported as open' (-not $summary.complaintClosed) 'complaintClosed was true'

# --- 3. register a containment action ---------------------------------------
$actionBody = @{
    nexSampleNumber = 'NEX-8801'; customerSampleNumber = 'CS-D3-1'
    plannedAction = 'Contain all stock at the customer and quarantine the warehouse lot'
    ownerId = 'U06'
    plannedCompletionDate = $today.AddDays(5).ToString('yyyy-MM-dd')
}
$created = Api 'POST' ('/api/complaints/' + $a.complaintId + '/containment/actions') $token $actionBody
Check 'a containment action can be registered' ($created.status -eq 201) ('status=' + $created.status + ' ' + $created.message)
$actionId = @($created.body.actions)[0].actionId
Check 'the action id is generated' ($actionId -match '^CA\d{9}$') ('id=' + $actionId)
Check 'a new action starts as to-do' (@($created.body.actions)[0].statusCode -eq 'CONTAIN_TODO') ('status=' + @($created.body.actions)[0].statusCode)
Check 'the status name is resolved' (@($created.body.actions)[0].statusName -eq $expect.containment.statusTodo) ('name=' + @($created.body.actions)[0].statusName)
Check 'the owner name is resolved' (@($created.body.actions)[0].ownerName -eq $expect.containment.ownerName) ('name=' + @($created.body.actions)[0].ownerName)
Check 'the planned completion date is stored' (@($created.body.actions)[0].plannedCompletionDate -eq $today.AddDays(5).ToString('yyyy-MM-dd')) ('planned=' + @($created.body.actions)[0].plannedCompletionDate)
Check 'no warning while the action is still open' ($null -eq @($created.body.actions)[0].completionWarning) ('warning=' + @($created.body.actions)[0].completionWarning)
Check 'registering an action settles the decision as required' ($created.body.required -eq $true) ('required=' + $created.body.required)

# --- 4. validation ----------------------------------------------------------
$bad = $actionBody.Clone(); $bad['ownerId'] = 'U99'
Check 'an unknown owner is refused' ((Api 'POST' ('/api/complaints/' + $a.complaintId + '/containment/actions') $token $bad).status -eq 400) 'expected 400'

$bad = $actionBody.Clone(); $bad['plannedAction'] = ''
Check 'a missing planned action is refused' ((Api 'POST' ('/api/complaints/' + $a.complaintId + '/containment/actions') $token $bad).status -eq 400) 'expected 400'

$bad = $actionBody.Clone(); $bad['statusCode'] = 'NOT_A_STATUS'
$badStatus = Api 'POST' ('/api/complaints/' + $a.complaintId + '/containment/actions') $token $bad
Check 'an unknown status is refused' ($badStatus.status -eq 400) ('status=' + $badStatus.status)
Check 'the unknown status is explained' ($badStatus.message -like ('*' + $expect.containment.invalidStatus + '*')) ('msg=' + $badStatus.message)

Check 'an action for an unknown complaint returns 404' ((Api 'POST' '/api/complaints/C202699999/containment/actions' $token $actionBody).status -eq 404) 'expected 404'

# --- 5. status tracking and the completion date -----------------------------
$doing = $actionBody.Clone(); $doing['statusCode'] = 'CONTAIN_DOING'; $doing['result'] = 'Stock blocked at both sites'
$updated = Api 'PUT' ('/api/containment-actions/' + $actionId) $token $doing
Check 'an action can move to in-progress' ($updated.status -eq 200) ('status=' + $updated.status)
Check 'in-progress has no completion date yet' ($null -eq @($updated.body.actions)[0].completedDate) ('completedDate=' + @($updated.body.actions)[0].completedDate)

$done = $actionBody.Clone(); $done['statusCode'] = 'CONTAIN_DONE'; $done['result'] = 'All suspect stock contained'
$completed = Api 'PUT' ('/api/containment-actions/' + $actionId) $token $done
Check 'an action can be completed' ($completed.status -eq 200) ('status=' + $completed.status)
Check 'completing stamps the completion date' (@($completed.body.actions)[0].completedDate -eq $today.ToString('yyyy-MM-dd')) ('completedDate=' + @($completed.body.actions)[0].completedDate)
Check 'the result is stored' (@($completed.body.actions)[0].result -like '*suspect stock*') ('result=' + @($completed.body.actions)[0].result)

# Completing today against a plan five days out is the anomaly the schema comment
# asks to flag.
$warning = @($completed.body.actions)[0].completionWarning
Check 'finishing earlier than planned raises a warning' ($null -ne $warning) 'no warning was raised'
Check 'the warning names both dates' ($warning -like ('*' + $today.ToString('yyyy-MM-dd') + '*') -and $warning -like ('*' + $today.AddDays(5).ToString('yyyy-MM-dd') + '*')) ('warning=' + $warning)

# A plan date in the past is not an anomaly, so the warning must clear.
$backdated = $done.Clone()
$backdated['plannedCompletionDate'] = $today.AddDays(-1).ToString('yyyy-MM-dd')
$noWarning = Api 'PUT' ('/api/containment-actions/' + $actionId) $token $backdated
Check 'a later plan date clears the warning' ($null -eq @($noWarning.body.actions)[0].completionWarning) ('warning=' + @($noWarning.body.actions)[0].completionWarning)
Check 'the plan date can be corrected' (@($noWarning.body.actions)[0].plannedCompletionDate -eq $today.AddDays(-1).ToString('yyyy-MM-dd')) ('planned=' + @($noWarning.body.actions)[0].plannedCompletionDate)

# --- 6. the two states must not contradict each other ----------------------
$skipWithActions = Api 'POST' ('/api/complaints/' + $a.complaintId + '/containment/decision') $token @{
    required = $false; note = 'No containment needed after all'
}
Check 'skipping is refused while actions exist' ($skipWithActions.status -eq 409) ('status=' + $skipWithActions.status)
Check 'the refusal explains the conflict' ($skipWithActions.message -like ('*' + $expect.containment.actionsExist + '*')) ('msg=' + $skipWithActions.message)

$noNote = Api 'POST' ('/api/complaints/' + $a.complaintId + '/containment/decision') $token @{ required = $true }
Check 'deciding without a note is allowed when required' ($noNote.status -eq 200) ('status=' + $noNote.status)

# --- 7. a second action, then delete both and skip --------------------------
$second = Api 'POST' ('/api/complaints/' + $a.complaintId + '/containment/actions') $token $actionBody
Check 'a complaint can carry several actions' (@($second.body.actions).Count -eq 2) ('count=' + @($second.body.actions).Count)
$secondId = @($second.body.actions)[1].actionId

Api 'DELETE' ('/api/containment-actions/' + $actionId) $token $null | Out-Null
$afterDelete = Api 'DELETE' ('/api/containment-actions/' + $secondId) $token $null
Check 'an action can be deleted' ($afterDelete.status -eq 200) ('status=' + $afterDelete.status)
Check 'the list is empty afterwards' (@($afterDelete.body.actions).Count -eq 0) ('count=' + @($afterDelete.body.actions).Count)

$skip = Api 'POST' ('/api/complaints/' + $a.complaintId + '/containment/decision') $token @{
    required = $false; note = 'Failure is benign; stock check found no other affected parts'
}
Check 'skipping is allowed once no actions remain' ($skip.status -eq 200) ('status=' + $skip.status + ' ' + $skip.message)
Check 'the decision is recorded as not required' ($skip.body.required -eq $false) ('required=' + $skip.body.required)
Check 'the reason is kept' ($skip.body.decisionNote -like '*benign*') ('note=' + $skip.body.decisionNote)

$detail = (Api 'GET' ('/api/complaints/' + $a.complaintId) $token $null).body
Check 'skipping advances the complaint to D4' ($detail.currentStage -eq 'D4') ('stage=' + $detail.currentStage)

$blockedCreate = Api 'POST' ('/api/complaints/' + $a.complaintId + '/containment/actions') $token $actionBody
Check 'adding an action after skipping is refused' ($blockedCreate.status -eq 409) ('status=' + $blockedCreate.status)
Check 'the refusal explains why' ($blockedCreate.message -like ('*' + $expect.containment.alreadySkipped + '*')) ('msg=' + $blockedCreate.message)

# --- 8. reversing the decision ---------------------------------------------
$reRequired = Api 'POST' ('/api/complaints/' + $a.complaintId + '/containment/decision') $token @{
    required = $true; note = 'Customer asked for containment after all'
}
Check 'the decision can be reversed to required' ($reRequired.status -eq 200) ('status=' + $reRequired.status)
Check 'reversing does not rewind the stage bar' ((Api 'GET' ('/api/complaints/' + $a.complaintId) $token $null).body.currentStage -eq 'D4') 'expected the stage to stay at D4'
$resumed = Api 'POST' ('/api/complaints/' + $a.complaintId + '/containment/actions') $token $actionBody
Check 'actions can be registered again after reversing' ($resumed.status -eq 201) ('status=' + $resumed.status + ' ' + $resumed.message)

# --- 9. a closed complaint is read-only -------------------------------------
$c = (Api 'POST' '/api/complaints' $token $payload).body
[void]$complaintIds.Add($c.complaintId)
Api 'POST' ('/api/complaints/' + $c.complaintId + '/validity') $token @{ valid = $false } | Out-Null
$closedCreate = Api 'POST' ('/api/complaints/' + $c.complaintId + '/containment/actions') $token $actionBody
Check 'a closed complaint refuses new actions' ($closedCreate.status -eq 409) ('status=' + $closedCreate.status)
Check 'the closed refusal is explained' ($closedCreate.message -like ('*' + $expect.containment.complaintClosed + '*')) ('msg=' + $closedCreate.message)
$closedSummary = (Api 'GET' ('/api/complaints/' + $c.complaintId + '/containment') $token $null).body
Check 'a closed complaint is still readable' ($closedSummary.complaintClosed -eq $true) 'complaintClosed was false'

# --- 10. permissions --------------------------------------------------------
$sales = Login 'xiaoran.ma' $Password
Check 'sales quality can read the containment summary' ((Api 'GET' ('/api/complaints/' + $a.complaintId + '/containment') $sales.accessToken $null).status -eq 200) 'expected 200'
Check 'sales quality cannot register an action' ((Api 'POST' ('/api/complaints/' + $a.complaintId + '/containment/actions') $sales.accessToken $actionBody).status -eq 403) 'expected 403'
Check 'sales quality cannot make the decision' ((Api 'POST' ('/api/complaints/' + $a.complaintId + '/containment/decision') $sales.accessToken @{ required = $true }).status -eq 403) 'expected 403'

$auditor = Login 'zhiyuan.chen' $Password
Check 'an auditor cannot register an action' ((Api 'POST' ('/api/complaints/' + $a.complaintId + '/containment/actions') $auditor.accessToken $actionBody).status -eq 403) 'expected 403'
Check 'D3 endpoints require a login' ((Api 'GET' ('/api/complaints/' + $a.complaintId + '/containment') '' $null).status -eq 401) 'expected 401'
Check 'an unknown action returns 404' ((Api 'PUT' '/api/containment-actions/CA999999999' $token $actionBody).status -eq 404) 'expected 404'

# --- 11. audit trail --------------------------------------------------------
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
Check 'the action creation was audited' ((Q "select count(*) from qms.audit_log where action_type='CREATE' and biz_type='ContainmentAction' and biz_id='$($a.complaintId)'") -ge '1') 'expected at least 1'
Check 'the status change was audited' ((Q "select count(*) from qms.audit_log where action_type='STATUS_CHANGE' and biz_type='ContainmentAction' and biz_id='$($a.complaintId)'") -ge '1') 'expected at least 1'
Check 'the stage advance was audited' ((Q "select count(*) from qms.audit_log where action_type='STATUS_CHANGE' and biz_type='Complaint' and biz_id='$($a.complaintId)'") -ge '1') 'expected at least 1'
Check 'the decision is stored on the complaint' ((Q "select count(*) from qms.complaint where complaint_id='$($a.complaintId)' and containment_required = true") -eq '1') 'expected containment_required = true'

# --- cleanup ----------------------------------------------------------------
if (-not $KeepData) {
    $quoted = ($complaintIds | ForEach-Object { "'" + $_ + "'" }) -join ','
    & $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value -q `
        -c ("DELETE FROM qms.complaint WHERE complaint_id IN (" + $quoted + ");") | Out-Null
    $lines.Add('')
    $lines.Add('  cleaned up ' + $complaintIds.Count + ' test complaint(s) and their actions')
}

$lines.Add('')
$lines.Add(('  RESULT : ' + $(if ($fail -eq 0) { 'PASS' } else { "FAIL ($fail)" }) + '   passed=' + $pass + ' failed=' + $fail))
$lines | Set-Content -Path (Join-Path $cfg.outDir 'verify_containment_report.txt') -Encoding UTF8
$lines | ForEach-Object { [Console]::Out.WriteLine($_) }
if ($fail -ne 0) { exit 1 }
