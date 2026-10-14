<#
  verify-actions.ps1
  Acceptance for D5 / D6 / D7 (requirements 3.6-3.8, PS-050 to PS-056): corrective
  actions tied to a root cause, the implementation feedback and effectiveness check
  that drives their status, the rework branch, the prevention file list and the
  "all files complete" precondition, permissions and the audit trail.

  Pure ASCII.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\verify-actions.ps1"
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

$lines.Add('verify-actions  ->  ' + $BaseUrl)
$lines.Add('')

$qe = Login 'siyuan.li' $Password
$token = $qe.accessToken
Check 'quality engineer logged in' ($null -ne $token) 'login failed'
if (-not $token) { $lines | ForEach-Object { [Console]::Out.WriteLine($_) }; exit 1 }

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

# --- setup: a complaint with a root cause -----------------------------------
$a = NewComplaint $token 'CS-D5-1'
[void]$complaintIds.Add($a.complaintId)
$rootCauseId = (Api 'POST' ('/api/complaints/' + $a.complaintId + '/root-causes') $token @{
    rootCauseDesc = 'Mold temperature drift after the tool change.'
    rootCauseSummary = 'Mold temperature drift'
    responsibleOrgType = 'INTERNAL'
}).body.rootCause.rootCauseId
Check 'a root cause exists to base the action on' ($rootCauseId -match '^RC\d{9}$') ('id=' + $rootCauseId)

# --- D5: the corrective action ---------------------------------------------
$actionBody = @{
    rootCauseId = $rootCauseId
    plannedActionDesc = 'Add a mould-temperature re-verification step to the changeover checklist.'
    ownerId = 'U06'
    targetDate = $today.AddDays(7).ToString('yyyy-MM-dd')
}
$created = Api 'POST' ('/api/complaints/' + $a.complaintId + '/corrective-actions') $token $actionBody
Check 'a corrective action can be created' ($created.status -eq 201) ('status=' + $created.status + ' ' + $created.message)
$actionId = $created.body.action.correctiveActionId
Check 'the action id is generated' ($actionId -match '^PCA\d{9}$') ('id=' + $actionId)
Check 'a new action starts as to-do' ($created.body.action.statusCode -eq 'CORR_TODO') ('status=' + $created.body.action.statusCode)
Check 'the root cause summary is resolved' ($created.body.action.rootCauseSummary -eq 'Mold temperature drift') ('summary=' + $created.body.action.rootCauseSummary)
Check 'the owner name is resolved' ($created.body.action.ownerName -eq $expect.actions.ownerName) ('name=' + $created.body.action.ownerName)

$detail = (Api 'GET' ('/api/complaints/' + $a.complaintId) $token $null).body
Check 'creating a corrective action advances the complaint to D5' ($detail.currentStage -eq 'D5') ('stage=' + $detail.currentStage)
Check 'the complaint moves to the actions status' ($detail.statusCode -eq 'COMPLAINT_S05') ('status=' + $detail.statusCode)

# --- D5 validation, including the rule no foreign key can express ----------
$bad = $actionBody.Clone(); $bad['rootCauseId'] = 'RC999999999'
$badRoot = Api 'POST' ('/api/complaints/' + $a.complaintId + '/corrective-actions') $token $bad
Check 'an unknown root cause is refused' ($badRoot.status -eq 400) ('status=' + $badRoot.status)
Check 'the unknown root cause is explained' ($badRoot.message -like ('*' + $expect.actions.rootCauseMissing + '*')) ('msg=' + $badRoot.message)

# a root cause belonging to a different complaint
$b = NewComplaint $token 'CS-D5-OTHER'
[void]$complaintIds.Add($b.complaintId)
$foreignRoot = (Api 'POST' ('/api/complaints/' + $b.complaintId + '/root-causes') $token @{
    rootCauseDesc = 'A cause on another complaint.'; responsibleOrgType = 'INTERNAL'
}).body.rootCause.rootCauseId
$bad = $actionBody.Clone(); $bad['rootCauseId'] = $foreignRoot
$crossRoot = Api 'POST' ('/api/complaints/' + $a.complaintId + '/corrective-actions') $token $bad
Check 'a root cause from another complaint is refused' ($crossRoot.status -eq 400) ('status=' + $crossRoot.status)
Check 'the cross-complaint root cause is explained' ($crossRoot.message -like ('*' + $expect.actions.rootCauseOtherComplaint + '*')) ('msg=' + $crossRoot.message)

$bad = $actionBody.Clone(); $bad['ownerId'] = 'U99'
Check 'an unknown owner is refused' ((Api 'POST' ('/api/complaints/' + $a.complaintId + '/corrective-actions') $token $bad).status -eq 400) 'expected 400'

$bad = $actionBody.Clone(); $bad['targetDate'] = $null
Check 'a missing target date is refused' ((Api 'POST' ('/api/complaints/' + $a.complaintId + '/corrective-actions') $token $bad).status -eq 400) 'expected 400'

$bad = $actionBody.Clone(); $bad['statusCode'] = 'NOT_A_STATUS'
$badStatus = Api 'POST' ('/api/complaints/' + $a.complaintId + '/corrective-actions') $token $bad
Check 'an unknown action status is refused' ($badStatus.status -eq 400) ('status=' + $badStatus.status)
Check 'the unknown action status is explained' ($badStatus.message -like ('*' + $expect.actions.invalidActionStatus + '*')) ('msg=' + $badStatus.message)

# --- D6: implementation feedback drives the action status ------------------
$feedback = Api 'POST' ('/api/corrective-actions/' + $actionId + '/verifications') $token @{
    actualCompletionDate = $today.ToString('yyyy-MM-dd')
    verificationResult = 'Checklist updated and released.'
}
Check 'implementation feedback can be recorded' ($feedback.status -eq 200) ('status=' + $feedback.status + ' ' + $feedback.message)
Check 'an actual completion date marks the action implemented' ($feedback.body.action.statusCode -eq 'CORR_DONE') ('status=' + $feedback.body.action.statusCode)
Check 'the status name is resolved' ($feedback.body.action.statusName -eq $expect.actions.statusDone) ('name=' + $feedback.body.action.statusName)
Check 'no effectiveness verdict is claimed yet' ($null -eq $feedback.body.action.isEffective) ('isEffective=' + $feedback.body.action.isEffective)

$detail = (Api 'GET' ('/api/complaints/' + $a.complaintId) $token $null).body
Check 'recording a verification advances the complaint to D6' ($detail.currentStage -eq 'D6') ('stage=' + $detail.currentStage)

# an ineffective verdict sends it back for rework (PS-054)
$ineffective = Api 'POST' ('/api/corrective-actions/' + $actionId + '/verifications') $token @{
    verificationResult = 'The drift recurred on the next changeover.'
    isEffective = $false
}
Check 'an ineffective verdict is accepted' ($ineffective.status -eq 200) ('status=' + $ineffective.status)
Check 'an ineffective action goes back for rework' ($ineffective.body.action.statusCode -eq 'CORR_FAILED') ('status=' + $ineffective.body.action.statusCode)
Check 'the rework status name is resolved' ($ineffective.body.action.statusName -eq $expect.actions.statusFailed) ('name=' + $ineffective.body.action.statusName)

# an effective verdict after rework settles it as verified
$effective = Api 'POST' ('/api/corrective-actions/' + $actionId + '/verifications') $token @{
    verificationResult = 'Checklist revised again; two changeovers verified.'
    isEffective = $true
}
Check 'an effective verdict is accepted' ($effective.status -eq 200) ('status=' + $effective.status)
Check 'an effective action is marked verified' ($effective.body.action.statusCode -eq 'CORR_VERIFIED') ('status=' + $effective.body.action.statusCode)
Check 'the verified status name is resolved' ($effective.body.action.statusName -eq $expect.actions.statusVerified) ('name=' + $effective.body.action.statusName)
Check 'the verifier is stamped' ($effective.body.action.verifiedByName -eq $expect.verification.recorderName) ('by=' + $effective.body.action.verifiedByName)
Check 'every verification is kept as history' (@($effective.body.verifications).Count -eq 3) ('count=' + @($effective.body.verifications).Count)

$history = (Api 'GET' ('/api/corrective-actions/' + $actionId) $token $null).body
Check 'the verification history is newest first' (@($history.verifications)[0].isEffective -eq $true) 'order wrong'

$removed = Api 'DELETE' ('/api/corrective-actions/' + $actionId + '/verifications/' + @($history.verifications)[0].verificationId) $token $null
Check 'a verification can be removed' ($removed.status -eq 200) ('status=' + $removed.status)
Check 'the removal is reflected' (@($removed.body.verifications).Count -eq 2) ('count=' + @($removed.body.verifications).Count)

# --- D7: prevention files ---------------------------------------------------
$fileBody = @{
    fileTypeCode = 'FILE_TYPE_001'
    controlProgram = 'CTL-2026-114'
    referenceNumber = 'FMEA-8801'
}
$files = Api 'POST' ('/api/complaints/' + $a.complaintId + '/prevention-files') $token $fileBody
Check 'a prevention file can be registered' ($files.status -eq 201) ('status=' + $files.status + ' ' + $files.message)
Check 'the file type name is resolved' (@($files.body)[0].fileTypeName -eq $expect.actions.fileTypeFmea) ('name=' + @($files.body)[0].fileTypeName)
Check 'a new file starts as to-update' (@($files.body)[0].statusCode -eq 'PREV_TODO') ('status=' + @($files.body)[0].statusCode)
$updateId = @($files.body)[0].updateId

$detail = (Api 'GET' ('/api/complaints/' + $a.complaintId) $token $null).body
Check 'registering a prevention file advances the complaint to D7' ($detail.currentStage -eq 'D7') ('stage=' + $detail.currentStage)
Check 'the complaint moves to the reporting status' ($detail.statusCode -eq 'COMPLAINT_S06') ('status=' + $detail.statusCode)

$bad = $fileBody.Clone(); $bad['fileTypeCode'] = 'NO_SUCH_TYPE'
$badType = Api 'POST' ('/api/complaints/' + $a.complaintId + '/prevention-files') $token $bad
Check 'an unknown file type is refused' ($badType.status -eq 400) ('status=' + $badType.status)
Check 'the unknown file type is explained' ($badType.message -like ('*' + $expect.actions.invalidFileType + '*')) ('msg=' + $badType.message)

$bad = $fileBody.Clone(); $bad['statusCode'] = 'NOT_A_STATUS'
$badPrevStatus = Api 'POST' ('/api/complaints/' + $a.complaintId + '/prevention-files') $token $bad
Check 'an unknown prevention status is refused' ($badPrevStatus.status -eq 400) ('status=' + $badPrevStatus.status)

$second = $fileBody.Clone(); $second['fileTypeCode'] = 'FILE_TYPE_002'; $second['referenceNumber'] = 'CP-8801'
$twoFiles = Api 'POST' ('/api/complaints/' + $a.complaintId + '/prevention-files') $token $second
Check 'a complaint can carry several prevention files' (@($twoFiles.body).Count -eq 2) ('count=' + @($twoFiles.body).Count)

# --- permissions: three distinct capabilities ------------------------------
$sales = Login 'xiaoran.ma' $Password
Check 'sales quality can read corrective actions' ((Api 'GET' ('/api/complaints/' + $a.complaintId + '/corrective-actions') $sales.accessToken $null).status -eq 200) 'expected 200'
Check 'sales quality cannot create a corrective action' ((Api 'POST' ('/api/complaints/' + $a.complaintId + '/corrective-actions') $sales.accessToken $actionBody).status -eq 403) 'expected 403'
Check 'sales quality cannot verify effectiveness' ((Api 'POST' ('/api/corrective-actions/' + $actionId + '/verifications') $sales.accessToken @{ isEffective = $true }).status -eq 403) 'expected 403'
Check 'sales quality cannot edit prevention files' ((Api 'POST' ('/api/complaints/' + $a.complaintId + '/prevention-files') $sales.accessToken $fileBody).status -eq 403) 'expected 403'

$auditor = Login 'zhiyuan.chen' $Password
Check 'an auditor cannot create a corrective action' ((Api 'POST' ('/api/complaints/' + $a.complaintId + '/corrective-actions') $auditor.accessToken $actionBody).status -eq 403) 'expected 403'
Check 'D5 endpoints require a login' ((Api 'GET' ('/api/complaints/' + $a.complaintId + '/corrective-actions') '' $null).status -eq 401) 'expected 401'
Check 'an unknown corrective action returns 404' ((Api 'PUT' '/api/corrective-actions/PCA999999999' $token $actionBody).status -eq 404) 'expected 404'
Check 'an unknown prevention file returns 404' ((Api 'PUT' '/api/prevention-files/99999999' $token $fileBody).status -eq 404) 'expected 404'

# --- a closed complaint is read-only ---------------------------------------
$c = NewComplaint $token 'CS-D5-CLOSED'
[void]$complaintIds.Add($c.complaintId)
Api 'POST' ('/api/complaints/' + $c.complaintId + '/validity') $token @{ valid = $false } | Out-Null
$closed = Api 'POST' ('/api/complaints/' + $c.complaintId + '/corrective-actions') $token $actionBody
Check 'a closed complaint refuses new corrective actions' ($closed.status -eq 409) ('status=' + $closed.status)
Check 'the closed refusal is explained' ($closed.message -like ('*' + $expect.actions.complaintClosed + '*')) ('msg=' + $closed.message)

# --- audit trail and the D7 precondition ----------------------------------
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
Check 'the action creation was audited' ((Q "select count(*) from qms.audit_log where action_type='CREATE' and biz_type='CorrectiveAction' and biz_id='$($a.complaintId)'") -ge '1') 'expected at least 1'
Check 'the status changes were audited' ((Q "select count(*) from qms.audit_log where action_type='STATUS_CHANGE' and biz_type='CorrectiveAction' and biz_id='$($a.complaintId)'") -ge '1') 'expected at least 1'
Check 'the prevention file creation was audited' ((Q "select count(*) from qms.audit_log where action_type='CREATE' and biz_type='PreventionFileUpdate' and biz_id='$($a.complaintId)'") -ge '1') 'expected at least 1'
Check 'two prevention files are still open' ((Q "select count(*) from qms.prevention_file_update where complaint_id='$($a.complaintId)' and is_deleted = false") -eq '2') 'expected 2'

# Mark them complete and confirm the precondition for D8 clears.
Api 'PUT' ('/api/prevention-files/' + $updateId) $token @{
    fileTypeCode = 'FILE_TYPE_001'; controlProgram = 'CTL-2026-114'
    referenceNumber = 'FMEA-8801'; statusCode = 'PREV_DONE'
} | Out-Null
$allFiles = (Api 'GET' ('/api/complaints/' + $a.complaintId + '/prevention-files') $token $null).body
$doneCount = @(@($allFiles) | Where-Object { $_.statusCode -eq 'PREV_DONE' }).Count
Check 'a prevention file can be marked complete' ($doneCount -eq 1) ('done=' + $doneCount)

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
$lines | Set-Content -Path (Join-Path $cfg.outDir 'verify_actions_report.txt') -Encoding UTF8
$lines | ForEach-Object { [Console]::Out.WriteLine($_) }
if ($fail -ne 0) { exit 1 }
