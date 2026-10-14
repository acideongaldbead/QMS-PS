<#
  seed-demo-ledger.ps1
  Seeds the complaint ledger / home dashboard with demo complaints.

  Why it drives the REST API instead of inserting SQL: only the application's own
  stage transitions keep current_stage and status_code consistent (the status set
  is coarser than the nine stages, and D2 has two branches). Hand-written INSERTs
  would sooner or later produce a state the UI cannot render.

  Deterministic: the variant picked for each complaint is a pure function of its
  index (no random numbers), so two runs produce the same shape. Each complaint
  is walked to a target 8D stage and left with the sub-records that stage has -
  including deliberately unfinished ones, so "my to-do" on the home page has real
  tasks to aggregate.

  Two logins are used because no single preset role can do the whole walk:
  xiaoran.ma (Sales Quality) registers and sends reports, siyuan.li (Quality
  Engineer) performs the D2-D7 technical steps.

  This script only adds; it never deletes. Run db-clear-complaints.ps1 -Force
  first if you want a clean slate. Re-running appends another batch.

  Pure ASCII; all Chinese copy lives in _seed_ledger_text.json.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\seed-demo-ledger.ps1"
  Optional:
    -Count 40 -BaseUrl http://localhost:8080 -Password Qms@2026
#>
[CmdletBinding()]
param(
    [string] $BaseUrl = 'http://localhost:8080',
    [string] $Password = 'Qms@2026',
    [int]    $Count = 40
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# ------------------------------------------------------------------ logins

function New-Session([string] $username) {
    $body = @{ username = $username; password = $Password } | ConvertTo-Json
    $res = Invoke-RestMethod -Uri ($BaseUrl + '/api/auth/login') -Method Post -TimeoutSec 20 `
        -ContentType 'application/json' -Body $body
    if (-not $res.accessToken) { throw ('login failed: ' + $username) }
    return @{ Authorization = 'Bearer ' + $res.accessToken }
}

function Post([string] $path, $payload, $headers) {
    $json = $payload | ConvertTo-Json -Depth 12
    return Invoke-RestMethod -Uri ($BaseUrl + $path) -Method Post -TimeoutSec 30 `
        -Headers $headers -ContentType 'application/json; charset=utf-8' `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($json))
}

$sales = New-Session 'xiaoran.ma'
$engineer = New-Session 'siyuan.li'
# A second quality engineer walks every other complaint. Without it the whole
# D2-D7 trail would be attributed to one person, and the "related to me" tab
# would collapse into "all data" - the prototype's data deliberately avoids that.
$engineer2 = New-Session 'zhenyu.wang'
# Sending a report needs its approval first, so the seeder also needs an approver.
$approver = New-Session 'hong.zhang'

# ------------------------------------------------------------------ psql (back-dating only)

# created_at is an audit column the application fills with now(), which would
# leave every seeded complaint with a processing time of 0 days - a column the
# ledger shows. The final step of this script back-dates it so the demo looks
# like real aged data. Everything else goes through the API.
$cfg = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '_paths.json')) | ConvertFrom-Json
$psql = Join-Path $cfg.pgBin 'psql.exe'
$dbHost = 'localhost'
$dbPort = '5432'
$dbName = 'qms'
$dbUser = 'postgres'
$envFile = Join-Path $cfg.root 'config\.env'
if (Test-Path $envFile) {
    $vars = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($envFile)) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        $i = $t.IndexOf('=')
        if ($i -lt 1) { continue }
        $vars[$t.Substring(0, $i).Trim()] = $t.Substring($i + 1).Trim()
    }
    $m = [regex]::Match($vars['QMS_DB_URL'], 'jdbc:postgresql://([^:/]+)(?::(\d+))?/([^?]+)')
    if ($m.Success) {
        $dbHost = $m.Groups[1].Value
        if ($m.Groups[2].Success) { $dbPort = $m.Groups[2].Value }
        $dbName = $m.Groups[3].Value
        $dbUser = $vars['QMS_DB_USER']
    }
    $env:PGPASSWORD = $vars['QMS_DB_PASSWORD']
}
$env:PGCLIENTENCODING = 'UTF8'
$canBackDate = (Test-Path $psql)
$createdIds = New-Object System.Collections.ArrayList

# ------------------------------------------------------------------ fixtures

$text = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '_seed_ledger_text.json')) | ConvertFrom-Json

$partners = @(
    @{ customer = 'CUST-1001'; contact = 'CP-1001'; shipTo = 'ST-1001-01' },
    @{ customer = 'CUST-1002'; contact = 'CP-1002'; shipTo = 'ST-1002-01' },
    @{ customer = 'CUST-1003'; contact = 'CP-1003'; shipTo = 'ST-1003-01' },
    @{ customer = 'CUST-1004'; contact = 'CP-1004'; shipTo = 'ST-1004-01' })

$products = @(
    @{ material = '12NC-934068123456'; type = 'PRODUCT_TYPE_001'; packing = 'PACKING_TYPE_001' },
    @{ material = '12NC-934068789012'; type = 'PRODUCT_TYPE_002'; packing = 'PACKING_TYPE_001' },
    @{ material = '12NC-934071234567'; type = 'PRODUCT_TYPE_003'; packing = 'PACKING_TYPE_002' })

$priorities = @('PRIORITY_001', 'PRIORITY_002', 'PRIORITY_003')
$priorityDays = @{ PRIORITY_001 = 14; PRIORITY_002 = 10; PRIORITY_003 = 7 }
$subSegments = @('SUB_SEGMENT_001', 'SUB_SEGMENT_002', 'SUB_SEGMENT_003')
$locations = @('FAILURE_LOCATION_001', 'FAILURE_LOCATION_002', 'FAILURE_LOCATION_005')
$complaintTypes = @('COMPLAINT_TYPE_001', 'COMPLAINT_TYPE_002', 'COMPLAINT_TYPE_006')

# Everyone except U04 (siyuan.li, the usual demo login) comes from these pools.
# U04 appears only on the complaints the loop marks as its own - one in three -
# which is what keeps "related to me" a real subset of "all data" while still
# giving the demo login a full to-do list.
$ownerPool = @('U06', 'U07', 'U03', 'U02', 'U01')
$coordinatorPool = @('U01', 'U06', 'U07', 'U02', 'U03')

$stages = @('D1', 'D2', 'D3', 'D4', 'D5', 'D6', 'D7', 'D8')
# D2 and D8 get extra weight: D2 carries the open verification tasks and D8 the
# generated reports, the two richest sources of home-page to-do entries.
$stagePattern = @('D1', 'D2', 'D2', 'D3', 'D4', 'D5', 'D6', 'D7', 'D8', 'D8')

$today = (Get-Date).Date
$iso = { param($d) $d.ToString('yyyy-MM-dd') }

$created = 0
$failed = 0
$byStage = @{}
$byStatusNote = @{ overdue = 0; invalid = 0; closed = 0; pendingApproval = 0 }

# ------------------------------------------------------------------ one complaint

for ($i = 0; $i -lt $Count; $i++) {
    try {
        $partner = $partners[$i % $partners.Count]
        $product = $products[$i % $products.Count]
        $priority = $priorities[$i % $priorities.Count]
        $fmIndex = 1 + ($i % 8)
        $fmCode = 'FAILURE_MODE_{0:d3}' -f $fmIndex
        $chain = $text.failureChains[$i % 5]
        # One complaint in three belongs to U04: it takes the owner and coordinator
        # slots, the verification slot, and the walk itself. Every other complaint
        # avoids U04 completely, so the two ledger tabs never show the same set.
        $mine = (($i % 3) -eq 0)

        $owner = $(if ($mine) { 'U04' } else { $ownerPool[$i % $ownerPool.Count] })
        $coordinator = $(if ($mine) { 'U04' } else { $coordinatorPool[($i + 2) % $coordinatorPool.Count] })
        $reportOwner = $(if ($mine) { 'U04' } else { $ownerPool[($i + 3) % $ownerPool.Count] })
        $verificationOwner = $(if ($mine) { 'U04' } else { 'U03' })
        $walkToken = $(if ($mine) { $engineer } else { $engineer2 })

        $stage = $stagePattern[$i % $stagePattern.Count]
        $target = $stages.IndexOf($stage)
        $isInvalid = (($i % 13) -eq 0)
        $isOverdue = (($i % 5) -eq 0)

        # Pin the target date rather than deriving it from an age formula: a
        # fifth of the complaints are pushed past their target and the rest land
        # in the near future, which is what keeps the overdue rate at the
        # prototype's deliberate ~20% instead of drifting up with the stage.
        # start_date stays consistent with it (target = start + priority days).
        if ($isOverdue) {
            $targetDate = $today.AddDays(-1 * (2 + ($i % 9)))
        }
        else {
            $targetDate = $today.AddDays(3 + ($i % 7))
        }
        $startDate = $targetDate.AddDays(-1 * $priorityDays[$priority])
        $customerTargetDate = $targetDate.AddDays(-3)

        $create = Post '/api/complaints' @{
            header = @{
                complaintTypeCode    = $complaintTypes[$i % $complaintTypes.Count]
                priorityCode         = $priority
                failureLocationCode  = $locations[$i % $locations.Count]
                complaintOwnerId     = $owner
                coordinatorId        = $coordinator
                verificationOwnerId  = $verificationOwner
                reportOwnerId        = $reportOwner
                startDate            = & $iso $startDate
                targetDate           = & $iso $targetDate
                customerTargetDate   = & $iso $customerTargetDate
                customerReferenceId  = 'REF-2026-{0:d4}' -f (1000 + $i)
            }
            qualityPartner = @{
                qualityPartnerCode = $partner.customer
                application        = 'Yes'
                contactPersonId    = $partner.contact
                subSegmentCode     = $subSegments[$i % $subSegments.Count]
                shipToSoldToCode   = $partner.shipTo
                endCustomer        = 'OEM'
                eccn               = 'EAR99'
            }
            product = @{
                materialCode    = $product.material
                productTypeCode = $product.type
                packingTypeCode = $product.packing
                businessGroup   = 'Power Discretes'
                businessUnit    = 'Automotive Power'
            }
            failureDescription = @{
                customerFailureDescription  = $text.symptoms[$fmIndex - 1]
                customerFailureModeCode     = $fmCode
                d0SymptomsDescription       = $text.symptoms[$fmIndex - 1]
                quantityFailing             = 8 + ($i % 6) * 4
                quantityFailingUom          = 'PCS'
                qualityReturned             = 2 + ($i % 4)
                qualityReturnedUom          = 'PCS'
                customerPo                  = 'PO-4500{0:d5}' -f (9000 + $i * 37)
                salesOrder                  = 'SO-2026{0:d3}' -f (100 + $i)
                comment                     = 'Registered by the demo seeder.'
            }
            samples = @(
                @{
                    customerSampleId   = 'CS-{0:d4}-1' -f (1000 + $i)
                    sampleQuantity     = 2 + ($i % 4)
                    uom                = 'PCS'
                    description        = 'Returned sample for analysis.'
                    applicationArea    = 'Customer incoming inspection'
                    rejectConfirmed    = $true
                    failureTypeL1Code  = $chain[0]
                    failureTypeL2Code  = $chain[1]
                    failureTypeL3Code  = $chain[2]
                }
            )
        } $sales

        $id = $create.complaintId
        $createdIds.Add($id) | Out-Null

        # ---- the invalid branch: D2 concludes the complaint does not hold -----
        if ($isInvalid) {
            Post ('/api/complaints/' + $id + '/validity') @{
                valid = $false; reasonCode = 'CLOSE_INVALID'
                conclusion = 'The returned samples could not reproduce the reported failure.'
            } $walkToken | Out-Null
            $byStatusNote.invalid = $byStatusNote.invalid + 1
        }
        else {
            # ---- D2: open verification tasks, left unfinished -----------------
            if ($target -eq 1) {
                $taskCount = 1 + ($i % 2)
                for ($t = 0; $t -lt $taskCount; $t++) {
                    $taskStart = $today.AddDays(-2)
                    $taskEnd = $today.AddDays(4 + $t)
                    if ($mine -and $t -gt 0) {
                        # The demo login's own second task has slipped, so the home
                        # page has an overdue entry to point at. Both dates move:
                        # the service refuses a target earlier than the planned start.
                        $taskStart = $today.AddDays(-10)
                        $taskEnd = $today.AddDays(-3)
                    }
                    Post ('/api/complaints/' + $id + '/verification-tasks') @{
                        taskOwnerId          = $(if ($t -eq 0) { 'U06' } else { $verificationOwner })
                        plannedStartDate     = & $iso $taskStart
                        targetCompletionDate = & $iso $taskEnd
                        creationMode         = 'MANUAL'
                    } $walkToken | Out-Null
                }
            }

            if ($target -ge 2) {
                # ---- D2 conclusion: valid -> complaint moves to D3 -------------
                Post ('/api/complaints/' + $id + '/validity') @{
                    valid = $true; conclusion = $text.conclusions[$fmIndex - 1]
                } $walkToken | Out-Null

                # ---- D3: containment decision plus one or two actions ----------
                Post ('/api/complaints/' + $id + '/containment/decision') @{
                    required = $true
                    note = 'Suspect stock must be contained before further shipment.'
                } $walkToken | Out-Null

                $actionCount = 1 + ($i % 2)
                for ($a = 0; $a -lt $actionCount; $a++) {
                    $done = ($target -ge 3) -or ($a -eq 0)
                    $action = @{
                        nexSampleNumber        = 'NEX-{0:d4}' -f (8000 + $i)
                        customerSampleNumber   = 'CS-{0:d4}-1' -f (1000 + $i)
                        plannedAction          = $text.containmentActions[($i + $a) % 6]
                        ownerId                = $(if ($a -eq 0) { $owner } else { $coordinator })
                        plannedCompletionDate  = & $iso $today.AddDays($a + 2)
                        statusCode             = $(if ($done) { 'CONTAIN_DONE' } else { 'CONTAIN_DOING' })
                    }
                    if ($done) {
                        $action.completedDate = & $iso $today
                        $action.result = 'Containment carried out at the customer site.'
                    }
                    Post ('/api/complaints/' + $id + '/containment/actions') $action $walkToken | Out-Null
                }
            }

            $rootCauseId = $null
            if ($target -ge 3) {
                # ---- D4: one root cause (left at its initial status) -----------
                $rc = Post ('/api/complaints/' + $id + '/root-causes') @{
                    rootCauseDesc       = $text.rootCauses[$i % 6]
                    rootCauseSummary    = 'Root cause ' + ($i + 1)
                    riskAssessment      = $text.risks[$i % 3]
                    responsibleOrgType  = 'INTERNAL'
                    responsibleOrgCode  = 'RESPONSIBLE_ORG_001'
                } $walkToken
                $rootCauseId = $rc.rootCause.rootCauseId
            }

            $actionId = $null
            if ($target -ge 4) {
                # ---- D5: the permanent corrective action -----------------------
                $ca = Post ('/api/complaints/' + $id + '/corrective-actions') @{
                    rootCauseId         = $rootCauseId
                    nexSampleNumber     = 'NEX-{0:d4}' -f (8000 + $i)
                    customerSampleId    = 'CS-{0:d4}-1' -f (1000 + $i)
                    plannedActionDesc   = $text.correctiveActions[$i % 6]
                    ownerId             = $owner
                    targetDate          = & $iso $today.AddDays(7 + ($i % 5))
                } $walkToken
                $actionId = $ca.action.correctiveActionId

                if ($target -ge 5) {
                    # ---- D6: implementation feedback, judged only from D7 on ---
                    $effective = ($target -ge 6)
                    $verification = @{
                        actualCompletionDate = & $iso $today.AddDays(-1)
                        verificationResult = $(if ($effective) {
                                'Change implemented and verified over two changeovers.'
                            } else {
                                'Implemented; effectiveness check still pending.'
                            })
                    }
                    if ($effective) { $verification.isEffective = $true }
                    Post ('/api/corrective-actions/' + $actionId + '/verifications') $verification $walkToken | Out-Null
                }
            }

            if ($target -ge 6) {
                # ---- D7: prevention files; one left open in the D7 bucket -----
                $fileCount = 2
                for ($f = 0; $f -lt $fileCount; $f++) {
                    $done = ($target -ge 7) -or ($f -eq 0)
                    Post ('/api/complaints/' + $id + '/prevention-files') @{
                        fileTypeCode    = $(if ($f -eq 0) { 'FILE_TYPE_001' } else { 'FILE_TYPE_002' })
                        controlProgram  = 'CTL-2026-{0:d4}' -f (100 + $i)
                        referenceNumber = 'REF-{0:d4}' -f (8000 + $i)
                        statusCode      = $(if ($done) { 'PREV_DONE' } else { 'PREV_DOING' })
                    } $walkToken | Out-Null
                }
            }

            if ($target -ge 7) {
                # ---- D8: generate the report; half of them are sent and closed -
                $report = Post ('/api/complaints/' + $id + '/reports') @{ reportType = 'INTERIM' } $walkToken
                if (($i % 2) -eq 0) {
                    # Sending is the last step and closes the complaint, and it now
                    # needs an approval first. Kept in its own try/catch so a mailer
                    # problem does not discard the whole complaint: the report itself
                    # is already a valid demo state.
                    try {
                        Post ('/api/reports/' + $report.reportId + '/submit') @{ approverId = 'U09' } $walkToken | Out-Null
                        Post ('/api/reports/' + $report.reportId + '/approve') @{ approved = $true; comment = 'Approved for the demo data set.' } $approver | Out-Null
                        Post ('/api/reports/' + $report.reportId + '/send') @{
                            recipient = 'customer.quality@example.com'
                            ccList    = 'sales.quality@example.com'
                            subject   = '8D Report ' + $id
                            body      = 'Please find the 8D report for the reported failure attached.'
                        } $sales | Out-Null
                        $byStatusNote.closed = $byStatusNote.closed + 1
                    }
                    catch {
                        [Console]::Out.WriteLine('  WARN  index ' + $i + ' : report ' + $report.reportId + ' left unsent - ' + $_.Exception.Message)
                    }
                }
                elseif (-not $mine) {
                    # Someone else's report, not sent: hand it to the approver and
                    # leave it waiting, so the approver's own home page has a real
                    # "waiting for me" entry to show. My own reports stay drafts, so
                    # the drafting entry stays on my list too.
                    try {
                        Post ('/api/reports/' + $report.reportId + '/submit') @{ approverId = 'U09' } $walkToken | Out-Null
                        $byStatusNote.pendingApproval = $byStatusNote.pendingApproval + 1
                    }
                    catch {
                        [Console]::Out.WriteLine('  WARN  index ' + $i + ' : report ' + $report.reportId + ' not submitted - ' + $_.Exception.Message)
                    }
                }
            }
        }

        $created = $created + 1
        if ($isOverdue) { $byStatusNote.overdue = $byStatusNote.overdue + 1 }
        if (-not $byStage.ContainsKey($stage)) { $byStage[$stage] = 0 }
        $byStage[$stage] = $byStage[$stage] + 1
    }
    catch {
        $failed = $failed + 1
        [Console]::Out.WriteLine('  FAIL  index ' + $i + ' : ' + $_.Exception.Message)
    }
}

# ------------------------------------------------------------------ back-date created_at

# created = start - 7 days, the same offset the registration rule uses, so the
# ledger's processing time grows with the complaint's age instead of being 0.
$backDated = 0
if ($canBackDate -and $createdIds.Count -gt 0) {
    $idList = ($createdIds | ForEach-Object { "'" + $_ + "'" }) -join ','
    $sql = "UPDATE qms.complaint SET created_at = (start_date - 7)::timestamptz WHERE complaint_id IN ($idList);"
    & $psql -h $dbHost -p $dbPort -U $dbUser -d $dbName -q -c $sql | Out-Null
    if ($LASTEXITCODE -eq 0) { $backDated = $createdIds.Count }
    else { [Console]::Out.WriteLine('  WARN  back-dating created_at failed (exit ' + $LASTEXITCODE + ')') }
}

# ------------------------------------------------------------------ summary

[Console]::Out.WriteLine('')
[Console]::Out.WriteLine('seed-demo-ledger  ->  ' + $BaseUrl)
[Console]::Out.WriteLine('  created          : ' + $created)
[Console]::Out.WriteLine('  failed           : ' + $failed)
foreach ($s in $stages) {
    if ($byStage.ContainsKey($s)) {
        [Console]::Out.WriteLine('  target stage ' + $s + '   : ' + $byStage[$s])
    }
}
[Console]::Out.WriteLine('  overdue          : ' + $byStatusNote.overdue)
[Console]::Out.WriteLine('  back-dated       : ' + $backDated)
[Console]::Out.WriteLine('  awaiting approval: ' + $byStatusNote.pendingApproval)
[Console]::Out.WriteLine('  closed (sent)    : ' + $byStatusNote.closed)
[Console]::Out.WriteLine('  closed (invalid) : ' + $byStatusNote.invalid)
[Console]::Out.WriteLine('')
[Console]::Out.WriteLine('open  : ' + $BaseUrl + '/#/complaints')
[Console]::Out.WriteLine('home  : ' + $BaseUrl + '/#/')
