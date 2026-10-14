<#
  ui-logistics.ps1
  UI half of task 2.3: creates a complaint through the API, then drives the detail
  page in a real browser (stage bar, sample tab, creating a shipment, moving a
  sample into it) and cleans the data up afterwards.

  Pure ASCII.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\ui-logistics.ps1"
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

# --- database access, for setup and cleanup ---------------------------------
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

# --- create the complaint the browser will open -----------------------------
$login = Invoke-RestMethod -Uri ($BaseUrl + '/api/auth/login') -Method Post `
    -ContentType 'application/json' -TimeoutSec 20 `
    -Body (@{ username = 'xiaoran.ma'; password = $Password } | ConvertTo-Json)
$token = $login.accessToken
if (-not $token) { throw 'login failed' }

$payload = @{
    header = @{
        complaintTypeCode = 'COMPLAINT_TYPE_001'; priorityCode = 'PRIORITY_003'
        failureLocationCode = 'FAILURE_LOCATION_005'; complaintOwnerId = 'U02'
        coordinatorId = 'U01'; customerTargetDate = (Get-Date).Date.AddDays(20).ToString('yyyy-MM-dd')
    }
    qualityPartner = @{ qualityPartnerCode = 'CUST-1001'; application = 'Yes'; contactPersonId = 'CP-1001'; subSegmentCode = 'SUB_SEGMENT_001' }
    product = @{ materialTypeCode = 'PRODUCT_TYPE_001'; productTypeCode = 'PRODUCT_TYPE_001'; packingTypeCode = 'PACKING_TYPE_001' }
    failureDescription = @{ customerFailureModeCode = 'FAILURE_MODE_001'; quantityFailing = 12; quantityFailingUom = 'PCS' }
    samples = @(
        @{ customerSampleId = 'CS-UI-1'; sampleQuantity = 4; uom = 'PCS'; rejectConfirmed = $true
           failureTypeL1Code = '2'; failureTypeL2Code = '2c'; failureTypeL3Code = '2ca' }
    )
}
$created = Invoke-RestMethod -Uri ($BaseUrl + '/api/complaints') -Method Post -TimeoutSec 30 `
    -Headers @{ Authorization = 'Bearer ' + $token } `
    -ContentType 'application/json; charset=utf-8' `
    -Body ([System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Depth 12)))
$complaintId = $created.complaintId
[Console]::Out.WriteLine('created complaint ' + $complaintId)

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
    (Join-Path $e2e 'detail.mjs'),
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

# --- cleanup ----------------------------------------------------------------
if (-not $KeepData) {
    & $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value -q `
        -c ("DELETE FROM qms.complaint WHERE complaint_id = '" + $complaintId + "';") | Out-Null
    [Console]::Out.WriteLine('  cleaned up ' + $complaintId)
}

if ($nodeExit -ne 0) { exit 1 }
