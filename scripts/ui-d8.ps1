<#
  ui-d8.ps1
  UI half of task 2.8 D8: seeds a report-ready complaint (through D7) via the API,
  then drives the D8 flow in a real browser as Sales Quality -- generate the
  report, open it, export Word, send it, and confirm the complaint closes.

  Pure ASCII.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\ui-d8.ps1"
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
$outDir = Join-Path $cfg.outDir 'ui'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

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

$login = Invoke-RestMethod -Uri ($BaseUrl + '/api/auth/login') -Method Post -TimeoutSec 20 `
    -ContentType 'application/json' `
    -Body (@{ username = 'siyuan.li'; password = $Password } | ConvertTo-Json)
$token = $login.accessToken
if (-not $token) { throw 'login failed' }
$headers = @{ Authorization = 'Bearer ' + $token }
$today = (Get-Date).Date

function Post([string] $path, $payload) {
    return Invoke-RestMethod -Uri ($BaseUrl + $path) -Method Post -TimeoutSec 30 `
        -Headers $headers -ContentType 'application/json; charset=utf-8' `
        -Body ([System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Depth 12)))
}

$payload = @{
    header = @{
        complaintTypeCode = 'COMPLAINT_TYPE_001'; priorityCode = 'PRIORITY_002'
        failureLocationCode = 'FAILURE_LOCATION_005'; complaintOwnerId = 'U02'
        coordinatorId = 'U01'; customerTargetDate = $today.AddDays(20).ToString('yyyy-MM-dd')
    }
    qualityPartner = @{ qualityPartnerCode = 'CUST-1001'; application = 'Yes'; contactPersonId = 'CP-1001'; subSegmentCode = 'SUB_SEGMENT_001' }
    product = @{ productTypeCode = 'PRODUCT_TYPE_001'; packingTypeCode = 'PACKING_TYPE_001' }
    failureDescription = @{ customerFailureModeCode = 'FAILURE_MODE_001'; quantityFailing = 8; quantityFailingUom = 'PCS' }
    samples = @(
        @{ customerSampleId = 'CS-D8UI-1'; sampleQuantity = 3; uom = 'PCS'; rejectConfirmed = $true
           failureTypeL1Code = '2'; failureTypeL2Code = '2c'; failureTypeL3Code = '2ca' }
    )
}
$complaint = Post '/api/complaints' $payload
$complaintId = $complaint.complaintId
[Console]::Out.WriteLine('created complaint ' + $complaintId)

# Seed it to a report-ready D7: verified action + completed prevention file.
Post ('/api/complaints/' + $complaintId + '/validity') @{ valid = $true; conclusion = 'Reproduced in the lab.' } | Out-Null
Post ('/api/complaints/' + $complaintId + '/containment/decision') @{ required = $true; note = 'Stock blocked.' } | Out-Null
Post ('/api/complaints/' + $complaintId + '/containment/actions') @{
    plannedAction = 'Block all suspect stock at the customer.'; ownerId = 'U06'
    plannedCompletionDate = $today.AddDays(3).ToString('yyyy-MM-dd')
    completedDate = $today.ToString('yyyy-MM-dd'); statusCode = 'CONTAIN_DONE'
    result = 'Stock blocked.'
} | Out-Null
$rc = (Post ('/api/complaints/' + $complaintId + '/root-causes') @{
    rootCauseDesc = 'Mold temperature drift after tool change.'; rootCauseSummary = 'Mold temperature drift'
    responsibleOrgType = 'INTERNAL'; responsibleOrgCode = 'RESPONSIBLE_ORG_001'
}).rootCause.rootCauseId
$ac = (Post ('/api/complaints/' + $complaintId + '/corrective-actions') @{
    rootCauseId = $rc; plannedActionDesc = 'Add a re-verification step to the changeover checklist.'
    ownerId = 'U06'; targetDate = $today.AddDays(7).ToString('yyyy-MM-dd')
}).action.correctiveActionId
Post ('/api/corrective-actions/' + $ac + '/verifications') @{
    actualCompletionDate = $today.ToString('yyyy-MM-dd'); verificationResult = 'Verified.'; isEffective = $true
} | Out-Null
Post ('/api/complaints/' + $complaintId + '/prevention-files') @{
    fileTypeCode = 'FILE_TYPE_001'; controlProgram = 'CTL-2026-114'
    referenceNumber = 'FMEA-8801'; statusCode = 'PREV_DONE'
} | Out-Null
[Console]::Out.WriteLine('seeded through D7 (action verified, prevention file done)')

$e2e = Join-Path $cfg.root 'e2e'
$edge = @(
    (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
    (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe')
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $edge) { throw 'msedge.exe not found' }

if (-not (Test-Path (Join-Path $e2e 'node_modules'))) {
    Push-Location $e2e
    try { & npm install --no-audit --no-fund | Out-Null } finally { Pop-Location }
}

$nodeArgs = @(
    (Join-Path $e2e 'd8.mjs'),
    ('--complaint=' + $complaintId),
    ('--base=' + $BaseUrl),
    ('--out=' + $outDir),
    ('--password=' + $Password),
    ('--edge=' + $edge)
)
Push-Location $e2e
try { $output = & node @nodeArgs 2>&1 } finally { Pop-Location }
$output | ForEach-Object { [Console]::Out.WriteLine($_) }
$nodeExit = $LASTEXITCODE

if (-not $KeepData) {
    & $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value -q `
        -c ("DELETE FROM qms.complaint WHERE complaint_id = '" + $complaintId + "';") | Out-Null
    [Console]::Out.WriteLine('  cleaned up ' + $complaintId)
}

if ($nodeExit -ne 0) { exit 1 }
