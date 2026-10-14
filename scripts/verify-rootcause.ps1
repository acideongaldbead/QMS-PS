<#
  verify-rootcause.ps1
  Acceptance for D4 (requirement 3.5, PS-042/043/044/045/046/047): root-cause
  entries, the ownership decision and transfer, the append-only 3x5Why / fishbone
  content with its version history, permissions and the audit trail.

  Pure ASCII.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\verify-rootcause.ps1"
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

$lines.Add('verify-rootcause  ->  ' + $BaseUrl)
$lines.Add('')

$qe = Login 'siyuan.li' $Password
$token = $qe.accessToken
Check 'quality engineer logged in (holds rootcause:edit)' ($null -ne $token) 'login failed'
if (-not $token) { $lines | ForEach-Object { [Console]::Out.WriteLine($_) }; exit 1 }

$complaintIds = New-Object System.Collections.ArrayList

# --- 1. a complaint to analyse ----------------------------------------------
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
        @{ customerSampleId = 'CS-D4-1'; sampleQuantity = 3; uom = 'PCS'
           failureTypeL1Code = '2'; failureTypeL2Code = '2c'; failureTypeL3Code = '2ca' }
    )
}
$a = (Api 'POST' '/api/complaints' $token $payload).body
[void]$complaintIds.Add($a.complaintId)

$rootBody = @{
    rootCauseDesc = 'Mold temperature drifted after the tool change; the profile was not re-verified.'
    rootCauseSummary = 'Mold temperature drift after tool change'
    riskAssessment = 'Medium: affects one cavity only, containment already in place.'
    responsibleOrgType = 'INTERNAL'
    responsibleOrgCode = 'RESPONSIBLE_ORG_001'
}
$created = Api 'POST' ('/api/complaints/' + $a.complaintId + '/root-causes') $token $rootBody
Check 'a root cause can be created' ($created.status -eq 201) ('status=' + $created.status + ' ' + $created.message)
$rootCauseId = $created.body.rootCause.rootCauseId
Check 'the root cause id is generated' ($rootCauseId -match '^RC\d{9}$') ('id=' + $rootCauseId)
Check 'a new root cause starts as to-analyse' ($created.body.rootCause.statusCode -eq 'ROOTCAUSE_TODO') ('status=' + $created.body.rootCause.statusCode)
Check 'the organisation name is resolved' ($created.body.rootCause.responsibleOrgName -eq $expect.rootcause.orgInternal) ('name=' + $created.body.rootCause.responsibleOrgName)
Check 'no analyses exist yet' (($null -eq $created.body.whyAnalysis) -and ($null -eq $created.body.fishbone)) 'an analysis was returned unexpectedly'

$detail = (Api 'GET' ('/api/complaints/' + $a.complaintId) $token $null).body
Check 'creating a root cause advances the complaint to D4' ($detail.currentStage -eq 'D4') ('stage=' + $detail.currentStage)
Check 'the complaint moves to the analysing status' ($detail.statusCode -eq 'COMPLAINT_S04') ('status=' + $detail.statusCode)

# --- 2. validation ----------------------------------------------------------
Check 'an empty description is refused' ((Api 'POST' ('/api/complaints/' + $a.complaintId + '/root-causes') $token @{ rootCauseDesc = '' }).status -eq 400) 'expected 400'

$bad = $rootBody.Clone(); $bad['statusCode'] = 'NOT_A_STATUS'
$badStatus = Api 'POST' ('/api/complaints/' + $a.complaintId + '/root-causes') $token $bad
Check 'an unknown status is refused' ($badStatus.status -eq 400) ('status=' + $badStatus.status)
Check 'the unknown status is explained' ($badStatus.message -like ('*' + $expect.rootcause.invalidStatus + '*')) ('msg=' + $badStatus.message)

$bad = $rootBody.Clone(); $bad['responsibleOrgCode'] = 'NO_SUCH_ORG'
$badOrg = Api 'POST' ('/api/complaints/' + $a.complaintId + '/root-causes') $token $bad
Check 'an unknown organisation is refused' ($badOrg.status -eq 400) ('status=' + $badOrg.status)
Check 'the unknown organisation is explained' ($badOrg.message -like ('*' + $expect.rootcause.invalidOrg + '*')) ('msg=' + $badOrg.message)

$bad = $rootBody.Clone(); $bad['responsibleOrgType'] = 'SOMEWHERE'
Check 'an invalid ownership value is refused' ((Api 'POST' ('/api/complaints/' + $a.complaintId + '/root-causes') $token $bad).status -eq 400) 'expected 400'

Check 'a root cause for an unknown complaint returns 404' ((Api 'POST' '/api/complaints/C202699999/root-causes' $token $rootBody).status -eq 404) 'expected 404'

# --- 3. update --------------------------------------------------------------
$edit = $rootBody.Clone()
$edit['rootCauseSummary'] = 'Edited summary'
$edit['statusCode'] = 'ROOTCAUSE_DONE'
$updated = Api 'PUT' ('/api/root-causes/' + $rootCauseId) $token $edit
Check 'a root cause can be edited' ($updated.status -eq 200) ('status=' + $updated.status)
Check 'the edit and the status change are stored' ($updated.body.rootCause.rootCauseSummary -eq 'Edited summary' -and $updated.body.rootCause.statusCode -eq 'ROOTCAUSE_DONE') ('summary=' + $updated.body.rootCause.rootCauseSummary + ' status=' + $updated.body.rootCause.statusCode)

# --- 4. the append-only analysis content -----------------------------------
$whyV1 = @{
    analysisType = '3x5WHY'
    contentJson = '{"nodeData":{"id":"root","topic":"Package chipping","children":[{"id":"a1","topic":"Mold temperature drift","children":[{"id":"b1","topic":"Tool change without re-verification","children":[]}]}]}}'
}
$saved1 = Api 'POST' ('/api/root-causes/' + $rootCauseId + '/analysis') $token $whyV1
Check '3x5Why content can be saved' ($saved1.status -eq 200) ('status=' + $saved1.status + ' ' + $saved1.message)
Check 'the first save is version 1' ($saved1.body.whyAnalysis.versionNo -eq 1) ('version=' + $saved1.body.whyAnalysis.versionNo)
Check 'the saved content comes back' ($saved1.body.whyAnalysis.contentJson -like '*Mold temperature drift*') 'content missing'
Check 'content is attributed to its author' ($saved1.body.whyAnalysis.createdByName -eq $expect.verification.recorderName) ('by=' + $saved1.body.whyAnalysis.createdByName)

$whyV2 = $whyV1.Clone()
$whyV2['contentJson'] = '{"nodeData":{"id":"root","topic":"Package chipping","children":[{"id":"a1","topic":"Mold temperature drift (revised)","children":[]}]}}'
$saved2 = Api 'POST' ('/api/root-causes/' + $rootCauseId + '/analysis') $token $whyV2
Check 'saving again creates a new version' ($saved2.body.whyAnalysis.versionNo -eq 2) ('version=' + $saved2.body.whyAnalysis.versionNo)
Check 'the newest content is returned' ($saved2.body.whyAnalysis.contentJson -like '*revised*') 'the newest content was not returned'

$versions = (Api 'GET' ('/api/root-causes/' + $rootCauseId + '/analysis/3x5WHY/versions') $token $null).body
Check 'the version history is kept' (@($versions).Count -eq 2) ('count=' + @($versions).Count)
Check 'the history is newest first' (@($versions)[0].versionNo -eq 2) ('first=' + @($versions)[0].versionNo)
Check 'the older version is still intact' (@($versions)[1].contentJson -like '*Mold temperature drift*' -and @($versions)[1].contentJson -notlike '*revised*') 'the old version was overwritten'

$fish = @{
    analysisType = 'FISHBONE'
    contentJson = '{"effect":"Package chipping","categories":[{"name":"Machine","causes":[{"text":"Mold temperature drift","subCauses":["Tool change without re-verification"]}]}]}'
}
$savedFish = Api 'POST' ('/api/root-causes/' + $rootCauseId + '/analysis') $token $fish
Check 'fishbone content can be saved' ($savedFish.status -eq 200) ('status=' + $savedFish.status + ' ' + $savedFish.message)
Check 'the fishbone has its own version series' ($savedFish.body.fishbone.versionNo -eq 1) ('version=' + $savedFish.body.fishbone.versionNo)
Check 'both tools are returned together' (($null -ne $savedFish.body.whyAnalysis) -and ($null -ne $savedFish.body.fishbone)) 'one of the tools is missing'

$badType = @{ analysisType = 'PARETO'; contentJson = '{}' }
$badTypeResult = Api 'POST' ('/api/root-causes/' + $rootCauseId + '/analysis') $token $badType
Check 'an unknown analysis type is refused' ($badTypeResult.status -eq 400) ('status=' + $badTypeResult.status)

# --- 5. the ownership decision and transfer (PS-047) -----------------------
$transfer = Api 'POST' ('/api/root-causes/' + $rootCauseId + '/transfer') $token @{
    transferredToId = 'U03'; responsibleOrgType = 'EXTERNAL'; responsibleOrgCode = 'RESPONSIBLE_ORG_002'
    note = 'Handed to the assembly partner for investigation.'
}
Check 'a root cause can be transferred' ($transfer.status -eq 200) ('status=' + $transfer.status + ' ' + $transfer.message)
Check 'the transfer target is stored' ($transfer.body.rootCause.transferredToId -eq 'U03') ('target=' + $transfer.body.rootCause.transferredToId)
Check 'the transfer target name is resolved' ($transfer.body.rootCause.transferredToName -eq $expect.rootcause.transferTarget) ('name=' + $transfer.body.rootCause.transferredToName)
Check 'the transfer is timestamped' ($null -ne $transfer.body.rootCause.transferredAt) 'no timestamp'
Check 'the ownership decision is stored' ($transfer.body.rootCause.responsibleOrgType -eq 'EXTERNAL') ('type=' + $transfer.body.rootCause.responsibleOrgType)

$badTransfer = Api 'POST' ('/api/root-causes/' + $rootCauseId + '/transfer') $token @{ transferredToId = 'U99' }
Check 'an unknown transfer target is refused' ($badTransfer.status -eq 400) ('status=' + $badTransfer.status)

# --- 6. several root causes per complaint ----------------------------------
$second = Api 'POST' ('/api/complaints/' + $a.complaintId + '/root-causes') $token $rootBody
Check 'a complaint can carry several root causes' ($second.status -eq 201) ('status=' + $second.status)
$secondId = $second.body.rootCause.rootCauseId
$list = (Api 'GET' ('/api/complaints/' + $a.complaintId + '/root-causes') $token $null).body
Check 'both root causes are listed' (@($list).Count -eq 2) ('count=' + @($list).Count)
# @() around the pipeline: a single surviving object has no .Count of its own.
$withTwoVersions = @(@($list) | Where-Object { $_.whyVersionCount -eq 2 })
Check 'the list reports how many versions exist' ($withTwoVersions.Count -eq 1) ('matched=' + $withTwoVersions.Count)

$removed = Api 'DELETE' ('/api/root-causes/' + $secondId) $token $null
Check 'a root cause can be deleted' ($removed.status -eq 200) ('status=' + $removed.status)
$afterDelete = (Api 'GET' ('/api/complaints/' + $a.complaintId + '/root-causes') $token $null).body
Check 'the deleted root cause is gone' (@($afterDelete).Count -eq 1) ('count=' + @($afterDelete).Count)

# --- 7. a closed complaint is read-only ------------------------------------
$c = (Api 'POST' '/api/complaints' $token $payload).body
[void]$complaintIds.Add($c.complaintId)
Api 'POST' ('/api/complaints/' + $c.complaintId + '/validity') $token @{ valid = $false } | Out-Null
$closedCreate = Api 'POST' ('/api/complaints/' + $c.complaintId + '/root-causes') $token $rootBody
Check 'a closed complaint refuses new root causes' ($closedCreate.status -eq 409) ('status=' + $closedCreate.status)
Check 'the closed refusal is explained' ($closedCreate.message -like ('*' + $expect.rootcause.complaintClosed + '*')) ('msg=' + $closedCreate.message)

# --- 8. permissions ---------------------------------------------------------
$sales = Login 'xiaoran.ma' $Password
Check 'sales quality can read root causes' ((Api 'GET' ('/api/complaints/' + $a.complaintId + '/root-causes') $sales.accessToken $null).status -eq 200) 'expected 200'
Check 'sales quality cannot create a root cause' ((Api 'POST' ('/api/complaints/' + $a.complaintId + '/root-causes') $sales.accessToken $rootBody).status -eq 403) 'expected 403'
Check 'sales quality cannot save analysis content' ((Api 'POST' ('/api/root-causes/' + $rootCauseId + '/analysis') $sales.accessToken $fish).status -eq 403) 'expected 403'

$auditor = Login 'zhiyuan.chen' $Password
Check 'an auditor cannot transfer a root cause' ((Api 'POST' ('/api/root-causes/' + $rootCauseId + '/transfer') $auditor.accessToken @{ transferredToId = 'U03' }).status -eq 403) 'expected 403'
Check 'D4 endpoints require a login' ((Api 'GET' ('/api/complaints/' + $a.complaintId + '/root-causes') '' $null).status -eq 401) 'expected 401'
Check 'an unknown root cause returns 404' ((Api 'GET' '/api/root-causes/RC999999999' $token $null).status -eq 404) 'expected 404'

# --- 9. audit trail ---------------------------------------------------------
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
Check 'the root cause creation was audited' ((Q "select count(*) from qms.audit_log where action_type='CREATE' and biz_type='RootCause' and biz_id='$($a.complaintId)'") -ge '1') 'expected at least 1'
Check 'the status change was audited' ((Q "select count(*) from qms.audit_log where action_type='STATUS_CHANGE' and biz_type='RootCause' and biz_id='$($a.complaintId)'") -ge '1') 'expected at least 1'
Check 'the stage advance was audited' ((Q "select count(*) from qms.audit_log where action_type='STATUS_CHANGE' and biz_type='Complaint' and biz_id='$($a.complaintId)'") -ge '1') 'expected at least 1'
Check 'content is stored as jsonb, not text' ((Q "select count(*) from information_schema.columns where table_schema='qms' and table_name='why_analysis' and column_name='content_json' and data_type='jsonb'") -eq '1') 'content_json is not jsonb'
Check 'the analysis rows were persisted' ((Q "select count(*) from qms.why_analysis where root_cause_id='$rootCauseId' and is_deleted = false") -eq '3') 'expected 3 rows (two 3x5Why versions plus one fishbone)'

# --- cleanup ----------------------------------------------------------------
if (-not $KeepData) {
    $quoted = ($complaintIds | ForEach-Object { "'" + $_ + "'" }) -join ','
    & $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value -q `
        -c ("DELETE FROM qms.complaint WHERE complaint_id IN (" + $quoted + ");") | Out-Null
    $lines.Add('')
    $lines.Add('  cleaned up ' + $complaintIds.Count + ' test complaint(s), their root causes and analyses')
}

$lines.Add('')
$lines.Add(('  RESULT : ' + $(if ($fail -eq 0) { 'PASS' } else { "FAIL ($fail)" }) + '   passed=' + $pass + ' failed=' + $fail))
$lines | Set-Content -Path (Join-Path $cfg.outDir 'verify_rootcause_report.txt') -Encoding UTF8
$lines | ForEach-Object { [Console]::Out.WriteLine($_) }
if ($fail -ne 0) { exit 1 }
