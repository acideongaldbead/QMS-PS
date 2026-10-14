<#
  ui-ledger.ps1
  UI half of task 2.9: seeds two complaints the ledger test can recognise, drives
  the ledger in a real browser (tabs, filters, sorting, column settings, row
  selection, the Excel export, opening a complaint) and cleans the data up.

  The two complaints are deliberately different on the axis the "与我相关" tab
  filters on: A belongs to the logged-in quality engineer, B does not - it is
  registered by a sales-quality user, owned by someone else and coordinated by
  someone else, so no field of the "related to me" predicate matches.
  They are found by a keyword marker so the demo data around them cannot make the
  run flaky.

  Pure ASCII.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\ui-ledger.ps1"
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

$marker = 'UILEDGER'

function Get-Token([string] $username) {
    $res = Invoke-RestMethod -Uri ($BaseUrl + '/api/auth/login') -Method Post `
        -ContentType 'application/json' -TimeoutSec 20 `
        -Body (@{ username = $username; password = $Password } | ConvertTo-Json)
    if (-not $res.accessToken) { throw ('login failed: ' + $username) }
    return $res.accessToken
}

function New-Complaint($token, $payload) {
    return Invoke-RestMethod -Uri ($BaseUrl + '/api/complaints') -Method Post -TimeoutSec 30 `
        -Headers @{ Authorization = 'Bearer ' + $token } `
        -ContentType 'application/json; charset=utf-8' `
        -Body ([System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Depth 12)))
}

# --- clean anything a previous interrupted run left behind -------------------
& $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value -q `
    -c ("DELETE FROM qms.complaint WHERE customer_reference_id LIKE '" + $marker + "%';") | Out-Null

$today = (Get-Date).Date
$iso = { param($d) $d.ToString('yyyy-MM-dd') }

function New-Sample([string] $ref) {
    # The leading comma stops PowerShell from unwrapping the single-element array
    # on return, which would turn the JSON array into an object.
    return ,@(
        @{ customerSampleId = $ref; sampleQuantity = 3; uom = 'PCS'; rejectConfirmed = $true
           failureTypeL1Code = '2'; failureTypeL2Code = '2c'; failureTypeL3Code = '2ca' }
    )
}

# A: the quality engineer's own complaint, ten days past its target date.
$engineerToken = Get-Token 'siyuan.li'
$createdA = New-Complaint $engineerToken @{
    header = @{
        complaintTypeCode = 'COMPLAINT_TYPE_001'; priorityCode = 'PRIORITY_003'
        failureLocationCode = 'FAILURE_LOCATION_005'; complaintOwnerId = 'U04'
        coordinatorId = 'U01'; verificationOwnerId = 'U03'; reportOwnerId = 'U04'
        startDate = (& $iso $today.AddDays(-20)); targetDate = (& $iso $today.AddDays(-10))
        customerTargetDate = (& $iso $today.AddDays(-5))
        customerReferenceId = ($marker + '-A')
    }
    qualityPartner = @{ qualityPartnerCode = 'CUST-1001'; application = 'Yes'; contactPersonId = 'CP-1001'; subSegmentCode = 'SUB_SEGMENT_001' }
    product = @{ productTypeCode = 'PRODUCT_TYPE_001'; packingTypeCode = 'PACKING_TYPE_001' }
    failureDescription = @{ customerFailureModeCode = 'FAILURE_MODE_001'; quantityFailing = 12; quantityFailingUom = 'PCS' }
    samples = (New-Sample 'CS-LEDGER-A')
}
$idA = $createdA.complaintId

# B: nobody on this complaint is the quality engineer - registered by sales
# quality, owned by U02, coordinated by U01 - so "与我相关" must not match it.
$salesToken = Get-Token 'xiaoran.ma'
$createdB = New-Complaint $salesToken @{
    header = @{
        complaintTypeCode = 'COMPLAINT_TYPE_002'; priorityCode = 'PRIORITY_001'
        failureLocationCode = 'FAILURE_LOCATION_001'; complaintOwnerId = 'U02'
        coordinatorId = 'U01'; verificationOwnerId = 'U03'; reportOwnerId = 'U01'
        startDate = (& $iso $today.AddDays(7)); targetDate = (& $iso $today.AddDays(14))
        customerTargetDate = (& $iso $today.AddDays(20))
        customerReferenceId = ($marker + '-B')
    }
    qualityPartner = @{ qualityPartnerCode = 'CUST-1002'; application = 'Yes'; contactPersonId = 'CP-1002'; subSegmentCode = 'SUB_SEGMENT_002' }
    product = @{ productTypeCode = 'PRODUCT_TYPE_002'; packingTypeCode = 'PACKING_TYPE_001' }
    failureDescription = @{ customerFailureModeCode = 'FAILURE_MODE_005'; quantityFailing = 6; quantityFailingUom = 'PCS' }
    samples = (New-Sample 'CS-LEDGER-B')
}
$idB = $createdB.complaintId
[Console]::Out.WriteLine('seeded ' + $idA + ' (mine, overdue) and ' + $idB + ' (not mine)')

# --- drive the browser ------------------------------------------------------
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
    (Join-Path $e2e 'ledger.mjs'),
    ('--marker=' + $marker),
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
        -c ("DELETE FROM qms.complaint WHERE complaint_id IN ('" + $idA + "','" + $idB + "');") | Out-Null
    [Console]::Out.WriteLine('  cleaned up ' + $idA + ' and ' + $idB)
}

if ($nodeExit -ne 0) { exit 1 }
