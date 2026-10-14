<#
  seed-demo-showcase.ps1
  Creates one fully populated complaint for demos: walks it through D2 (valid),
  D3 (containment decision + action), D4 (root cause), D5 (corrective action),
  D6 (effective verification) and D7 (FMEA file update), and leaves the data in
  place. Prints the detail URL to open.

  Unlike the verify-*/ui-* scripts this one does NOT clean up: its whole point is
  to leave a complaint you can click through. Re-running adds another complaint.

  Pure ASCII.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\seed-demo-showcase.ps1"
  Optional:
    -BaseUrl http://localhost:8080   -Password Qms@2026
#>
[CmdletBinding()]
param(
    [string] $BaseUrl = 'http://localhost:8080',
    [string] $Password = 'Qms@2026'
)

$ErrorActionPreference = 'Stop'
$env:PGCLIENTENCODING = 'UTF8'

$login = Invoke-RestMethod -Uri ($BaseUrl + '/api/auth/login') -Method Post -TimeoutSec 20 `
    -ContentType 'application/json' `
    -Body (@{ username = 'siyuan.li'; password = $Password } | ConvertTo-Json)
$token = $login.accessToken
if (-not $token) { throw 'login failed' }
$headers = @{ Authorization = 'Bearer ' + $token }

function Post([string] $path, $payload) {
    return Invoke-RestMethod -Uri ($BaseUrl + $path) -Method Post -TimeoutSec 30 `
        -Headers $headers -ContentType 'application/json; charset=utf-8' `
        -Body ([System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Depth 12)))
}

$today = (Get-Date).Date

# --- D0/D1: register the complaint ------------------------------------------
$complaint = Post '/api/complaints' @{
    header = @{
        complaintTypeCode = 'COMPLAINT_TYPE_001'; priorityCode = 'PRIORITY_002'
        failureLocationCode = 'FAILURE_LOCATION_005'; complaintOwnerId = 'U01'
        coordinatorId = 'U04'; verificationOwnerId = 'U06'; reportOwnerId = 'U01'
        customerTargetDate = $today.AddDays(20).ToString('yyyy-MM-dd')
    }
    qualityPartner = @{ qualityPartnerCode = 'CUST-1001'; application = 'Yes'; contactPersonId = 'CP-1001'; subSegmentCode = 'SUB_SEGMENT_001' }
    product = @{ productTypeCode = 'PRODUCT_TYPE_001'; packingTypeCode = 'PACKING_TYPE_001' }
    failureDescription = @{ customerFailureModeCode = 'FAILURE_MODE_001'; quantityFailing = 8; quantityFailingUom = 'PCS' }
    samples = @(
        @{ customerSampleId = 'CS-DEMO-1'; sampleQuantity = 3; uom = 'PCS'; rejectConfirmed = $true
           failureTypeL1Code = '2'; failureTypeL2Code = '2c'; failureTypeL3Code = '2ca' }
    )
}
$id = $complaint.complaintId
[Console]::Out.WriteLine('complaint      : ' + $id)

# --- D2: conclude the complaint is valid ------------------------------------
Post ('/api/complaints/' + $id + '/validity') @{ valid = $true; conclusion = 'Failure reproduced in the lab.' } | Out-Null
[Console]::Out.WriteLine('D2             : valid')

# --- D3: containment decision and one completed action ----------------------
Post ('/api/complaints/' + $id + '/containment/decision') @{ required = $true; note = 'Suspect stock must be blocked at the customer.' } | Out-Null
Post ('/api/complaints/' + $id + '/containment/actions') @{
    nexSampleNumber = 'NEX-8801'; customerSampleNumber = 'CS-DEMO-1'
    plannedAction = 'Block all suspect stock at the customer site.'
    ownerId = 'U06'
    plannedCompletionDate = $today.AddDays(3).ToString('yyyy-MM-dd')
    completedDate = $today.ToString('yyyy-MM-dd')
    statusCode = 'CONTAIN_DONE'
    result = 'Stock blocked; 1200 units quarantined.'
} | Out-Null
[Console]::Out.WriteLine('D3             : containment required + 1 action')

# --- D4: the root cause ------------------------------------------------------
$root = Post ('/api/complaints/' + $id + '/root-causes') @{
    rootCauseDesc = 'Mold temperature drifted after the tool change; the changeover profile was not re-verified.'
    rootCauseSummary = 'Mold temperature drift after tool change'
    riskAssessment = 'Medium: affects one cavity only, containment already in place.'
    responsibleOrgType = 'INTERNAL'; responsibleOrgCode = 'RESPONSIBLE_ORG_001'
}
$rootCauseId = $root.rootCause.rootCauseId
[Console]::Out.WriteLine('D4             : root cause ' + $rootCauseId)

# --- D5: the permanent corrective action ------------------------------------
$action = Post ('/api/complaints/' + $id + '/corrective-actions') @{
    rootCauseId = $rootCauseId
    nexSampleNumber = 'NEX-8801'; customerSampleId = 'CS-DEMO-1'
    plannedActionDesc = 'Add a mould-temperature re-verification step to the changeover checklist.'
    ownerId = 'U06'
    targetDate = $today.AddDays(7).ToString('yyyy-MM-dd')
}
$actionId = $action.action.correctiveActionId
[Console]::Out.WriteLine('D5             : corrective action ' + $actionId)

# --- D6: an effective verification ------------------------------------------
Post ('/api/corrective-actions/' + $actionId + '/verifications') @{
    actualCompletionDate = $today.ToString('yyyy-MM-dd')
    verificationResult = 'Checklist revised and released; two changeovers verified.'
    isEffective = $true
} | Out-Null
[Console]::Out.WriteLine('D6             : verified (effective)')

# --- D7: the prevention file update -----------------------------------------
Post ('/api/complaints/' + $id + '/prevention-files') @{
    fileTypeCode = 'FILE_TYPE_001'
    controlProgram = 'CTL-2026-114'
    referenceNumber = 'FMEA-8801'
    statusCode = 'PREV_DONE'
} | Out-Null
[Console]::Out.WriteLine('D7             : prevention file registered (done)')

# --- D8: generate the 8D report, then submit and approve it ------------------
# Approval gates the send, so the showcase leaves a report that is ready to go:
# approved and waiting for Sales Quality to send it.
$report = Post ('/api/complaints/' + $id + '/reports') @{ reportType = 'INTERIM' }
[Console]::Out.WriteLine('D8             : report generated ' + $report.reportId + ' (draft)')

Post ('/api/reports/' + $report.reportId + '/submit') @{ approverId = 'U09' } | Out-Null
[Console]::Out.WriteLine('D8             : submitted for approval (approver U09)')

# The approve call is made as the approver, not as the engineer.
$approver = Invoke-RestMethod -Uri ($BaseUrl + '/api/auth/login') -Method Post -TimeoutSec 20 `
    -ContentType 'application/json' `
    -Body (@{ username = 'hong.zhang'; password = $Password } | ConvertTo-Json)
$headers = @{ Authorization = 'Bearer ' + $approver.accessToken }
Post ('/api/reports/' + $report.reportId + '/approve') @{ approved = $true; comment = 'Checked against the customer template.' } | Out-Null
[Console]::Out.WriteLine('D8             : approved (ready for Sales Quality to send)')

[Console]::Out.WriteLine('')
[Console]::Out.WriteLine('open  : ' + $BaseUrl + '/#/complaints/' + $id)
[Console]::Out.WriteLine('report: ' + $BaseUrl + '/#/complaints/' + $id + '/report/' + $report.reportId)
