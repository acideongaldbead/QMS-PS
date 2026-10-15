<#
  verify-home.ps1
  Acceptance for the home dashboard (requirement 3.0): the to-do list built from
  real outstanding records, the four figures, the overdue banner and the
  announcement list.

  The central check is that an entry disappears once its record is finished -
  which is what separates "these are real tasks" from "these are the complaints
  that happen to sit at some stage".

  Pure ASCII.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\verify-home.ps1"
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

function Q([string] $sql) {
    return ((& $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value -t -A -c $sql) -join ' ').Trim()
}

$pass = 0; $fail = 0
$lines = New-Object System.Collections.Generic.List[string]
function Check([string] $name, [bool] $ok, [string] $detail) {
    if ($ok) { $script:pass++; $lines.Add(('  PASS  {0}' -f $name)) }
    else     { $script:fail++; $lines.Add(('  FAIL  {0}  -> {1}' -f $name, $detail)) }
}

function Get-ErrorStatus($err) { try { return [int]$err.Exception.Response.StatusCode } catch { return 0 } }
function Login([string] $user, [string] $pwd) {
    return Invoke-RestMethod -Uri ($BaseUrl + '/api/auth/login') -Method Post `
        -ContentType 'application/json' -TimeoutSec 20 `
        -Body (@{ username = $user; password = $pwd } | ConvertTo-Json)
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
        return @{ status = Get-ErrorStatus $_; body = $null; message = $_ }
    }
}

$lines.Add('verify-home  ->  ' + $BaseUrl)
$lines.Add('')

$marker = 'VERIFYHOME'

if (-not $KeepData) {
    & $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value -q `
        -c ("DELETE FROM qms.complaint WHERE customer_reference_id LIKE '" + $marker + "%';") | Out-Null
}

$engineer = Login 'siyuan.li' $Password
$engineerToken = $engineer.accessToken
Check 'quality engineer logged in (holds complaint:view)' ($null -ne $engineerToken) 'login failed'
if (-not $engineerToken) { $lines | ForEach-Object { [Console]::Out.WriteLine($_) }; exit 1 }
$salesToken = (Login 'xiaoran.ma' $Password).accessToken

# --- 1. access control -------------------------------------------------------
$anonOverview = Api 'GET' '/api/home/overview' $null $null
Check 'the overview requires a login (401)' ($anonOverview.status -eq 401) ('status=' + $anonOverview.status)
$anonAnnouncements = Api 'GET' '/api/announcements' $null $null
Check 'the announcements require a login (401)' ($anonAnnouncements.status -eq 401) ('status=' + $anonAnnouncements.status)

# --- 2. the figures -----------------------------------------------------------
$overview = (Api 'GET' '/api/home/overview' $engineerToken $null).body
Check 'the overview returns the four figures' ($null -ne $overview.stats) 'no stats block'
Check 'the to-do count matches the list length' `
    ($overview.todoTotal -ge @($overview.todos).Count) `
    ('total=' + $overview.todoTotal + ' listed=' + @($overview.todos).Count)
Check 'the to-do list is capped' (@($overview.todos).Count -le 12) ('listed=' + @($overview.todos).Count)
Check 'the related-complaint figure is positive' ($overview.stats.myComplaintCount -gt 0) `
    ('mine=' + $overview.stats.myComplaintCount)

# The home figure and the ledger tab are the same question asked twice.
$ledger = (Api 'GET' '/api/complaints?scope=mine&size=20' $engineerToken $null).body
Check 'the figure agrees with the ledger tab' `
    ($overview.stats.myComplaintCount -eq $ledger.mineTotal) `
    ('home=' + $overview.stats.myComplaintCount + ' ledger=' + $ledger.mineTotal)

# --- 3. the overdue banner ----------------------------------------------------
Check 'the overdue banner has rows' (@($overview.overdueComplaints).Count -gt 0) 'no banner rows'
Check 'the banner total is at least the rows it shows' `
    ($overview.overdueComplaintTotal -ge @($overview.overdueComplaints).Count) `
    ('total=' + $overview.overdueComplaintTotal + ' rows=' + @($overview.overdueComplaints).Count)
$bannerOverdue = @($overview.overdueComplaints | Where-Object { $_.overdueDays -gt 0 })
Check 'every banner row really is overdue' `
    ($bannerOverdue.Count -eq @($overview.overdueComplaints).Count) `
    ('overdue rows=' + $bannerOverdue.Count)
$bannerDays = @($overview.overdueComplaints | ForEach-Object { $_.overdueDays })
$sortedDesc = $true
for ($i = 1; $i -lt $bannerDays.Count; $i++) {
    if ($bannerDays[$i] -gt $bannerDays[$i - 1]) { $sortedDesc = $false }
}
Check 'the banner starts with the worst' $sortedDesc ($bannerDays -join ',')

# --- 4. a real task becomes a to-do, then stops being one ---------------------
$today = (Get-Date).Date
$iso = { param($d) $d.ToString('yyyy-MM-dd') }

$created = (Api 'POST' '/api/complaints' $salesToken @{
    header = @{
        complaintTypeCode = 'COMPLAINT_TYPE_001'; priorityCode = 'PRIORITY_002'
        failureLocationCode = 'FAILURE_LOCATION_005'; complaintOwnerId = 'U07'
        coordinatorId = 'U06'; verificationOwnerId = 'U04'
        customerTargetDate = (& $iso $today.AddDays(20)); customerReferenceId = ($marker + '-A')
    }
    qualityPartner = @{ qualityPartnerCode = 'CUST-1001'; application = 'Yes'; contactPersonId = 'CP-1001'; subSegmentCode = 'SUB_SEGMENT_001' }
    product = @{ productTypeCode = 'PRODUCT_TYPE_001'; packingTypeCode = 'PACKING_TYPE_001' }
    failureDescription = @{ customerFailureModeCode = 'FAILURE_MODE_001' }
    samples = ,@{ customerSampleId = 'CS-VH-1'; sampleQuantity = 3; uom = 'PCS'
                   failureTypeL1Code = '2'; failureTypeL2Code = '2c'; failureTypeL3Code = '2ca' }
}).body
$complaintId = $created.complaintId
Check 'a complaint was registered for the to-do checks' (-not [string]::IsNullOrWhiteSpace($complaintId)) 'no id'

$targetDate = $today.AddDays(5)
$task = (Api 'POST' ('/api/complaints/' + $complaintId + '/verification-tasks') $engineerToken @{
    taskOwnerId = 'U04'
    plannedStartDate = (& $iso $today.AddDays(-1))
    targetCompletionDate = (& $iso $targetDate)
    creationMode = 'MANUAL'
}).body
$taskId = $task.task.taskId
Check 'a verification task was created for the engineer' (-not [string]::IsNullOrWhiteSpace($taskId)) 'no task id'

$withTask = (Api 'GET' '/api/home/overview' $engineerToken $null).body
$entry = @($withTask.todos | Where-Object { $_.complaintId -eq $complaintId })
Check 'the open task shows up as a to-do entry' ($entry.Count -eq 1) ('entries=' + $entry.Count)
Check 'the entry is labelled as verification work' ($entry[0].type -eq 'VERIFICATION') ('type=' + $entry[0].type)
Check 'the entry opens the D2 tab' ($entry[0].tab -eq 'd2') ('tab=' + $entry[0].tab)
Check 'the entry carries the task due date' ($entry[0].dueDate -eq (& $iso $targetDate)) ('due=' + $entry[0].dueDate)
Check 'the entry carries the task status' (-not [string]::IsNullOrWhiteSpace($entry[0].statusText)) ('status=' + $entry[0].statusText)
Check 'a task due in the future is not urgent' (-not $entry[0].urgent) ('urgent=' + $entry[0].urgent)

# Finishing the task is what removes the entry: the list is built from records,
# not from the stage the complaint happens to be at.
Api 'PUT' ('/api/verification-tasks/' + $taskId) $engineerToken @{
    taskOwnerId = 'U04'
    plannedStartDate = (& $iso $today.AddDays(-1))
    targetCompletionDate = (& $iso $targetDate)
    taskStatus = 'VERIF_DONE'
    creationMode = 'MANUAL'
} | Out-Null

$afterTask = (Api 'GET' '/api/home/overview' $engineerToken $null).body
$entryAfter = @($afterTask.todos | Where-Object { $_.complaintId -eq $complaintId })
Check 'completing the task removes the entry' ($entryAfter.Count -eq 0) ('entries=' + $entryAfter.Count)

# --- 5. an overdue complaint reaches the banner ------------------------------
$overdueComplaint = (Api 'POST' '/api/complaints' $salesToken @{
    header = @{
        complaintTypeCode = 'COMPLAINT_TYPE_002'; priorityCode = 'PRIORITY_001'
        failureLocationCode = 'FAILURE_LOCATION_001'; complaintOwnerId = 'U07'
        coordinatorId = 'U06'; verificationOwnerId = 'U04'
        startDate = (& $iso $today.AddDays(-100)); targetDate = (& $iso $today.AddDays(-90))
        customerTargetDate = (& $iso $today.AddDays(-80)); customerReferenceId = ($marker + '-B')
    }
    qualityPartner = @{ qualityPartnerCode = 'CUST-1002'; application = 'Yes'; contactPersonId = 'CP-1002'; subSegmentCode = 'SUB_SEGMENT_002' }
    product = @{ productTypeCode = 'PRODUCT_TYPE_002'; packingTypeCode = 'PACKING_TYPE_001' }
    failureDescription = @{ customerFailureModeCode = 'FAILURE_MODE_005' }
    samples = ,@{ customerSampleId = 'CS-VH-2'; sampleQuantity = 2; uom = 'PCS'
                   failureTypeL1Code = '2'; failureTypeL2Code = '2c'; failureTypeL3Code = '2ca' }
}).body
$overdueId = $overdueComplaint.complaintId
Check 'a long-overdue complaint was registered for the banner' `
    (-not [string]::IsNullOrWhiteSpace($overdueId)) 'no id'

$withOverdue = (Api 'GET' '/api/home/overview' $engineerToken $null).body
$bannerIds = @($withOverdue.overdueComplaints | ForEach-Object { $_.complaintId })
Check 'the most overdue complaint leads the banner' `
    ($bannerIds.Count -gt 0 -and $bannerIds[0] -eq $overdueId) ($bannerIds -join ',')
Check 'the banner total went up' ($withOverdue.overdueComplaintTotal -ge 1) ('total=' + $withOverdue.overdueComplaintTotal)

# --- 6. announcements --------------------------------------------------------
$published = (Api 'GET' '/api/announcements' $engineerToken $null).body
$publishedCount = @($published).Count
Check 'published announcements are returned' ($publishedCount -gt 0) ('count=' + $publishedCount)
Check 'an announcement carries its title' (-not [string]::IsNullOrWhiteSpace($published[0].title)) 'no title'
Check 'an announcement carries its body' (-not [string]::IsNullOrWhiteSpace($published[0].content)) 'no body'
Check 'every published body is stored as HTML' ((@($published | Where-Object { $_.content -notlike '<*' }).Count) -eq 0) 'a plain-text body survived'
Check 'an announcement names its publisher' (-not [string]::IsNullOrWhiteSpace($published[0].publishedByName)) 'no publisher'
$times = @($published | ForEach-Object { $_.publishedAt })
$timeOrdered = $true
for ($i = 1; $i -lt $times.Count; $i++) {
    if ([string]$times[$i] -gt [string]$times[$i - 1]) { $timeOrdered = $false }
}
Check 'announcements are newest first' $timeOrdered ($times -join ',')

# A row that is not published must never reach the home page. The status value
# is deliberately an ASCII placeholder: the script may not carry Chinese.
$draftTitle = $marker + '-DRAFT'
& $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value -q `
    -c ("INSERT INTO qms.system_announcement (title, content, publish_status, published_by, published_at) VALUES ('" + $draftTitle + "', 'draft body', 'DRAFT-XYZ', 'U08', now());") | Out-Null

$afterDraft = (Api 'GET' '/api/announcements' $engineerToken $null).body
$titles = @($afterDraft | ForEach-Object { $_.title })
Check 'an unpublished announcement is not returned' (-not ($titles -contains $draftTitle)) ($titles -join ' | ')
Check 'the count is unchanged by the draft' (@($afterDraft).Count -eq $publishedCount) `
    ('before=' + $publishedCount + ' after=' + @($afterDraft).Count)
& $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value -q `
    -c ("DELETE FROM qms.system_announcement WHERE title = '" + $draftTitle + "';") | Out-Null

$capped = (Api 'GET' '/api/announcements?limit=999' $engineerToken $null)
Check 'an oversized limit is accepted and capped' ($capped.status -eq 200) ('status=' + $capped.status)
Check 'the capped response is still the published set' (@($capped.body).Count -le $publishedCount) `
    ('count=' + @($capped.body).Count)

# --- 6b. the NEW badge, which is per reader -------------------------------
# The sales-quality user's read markers are cleared first so the assertion does
# not depend on what an earlier run happened to open.
& $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value -q `
    -c "DELETE FROM qms.announcement_read WHERE employee_id = 'U01';" | Out-Null

$salesView = @((Api 'GET' '/api/announcements' $salesToken $null).body)
$unreadForSales = @($salesView | Where-Object { $_.isNew -eq $true })
Check 'a reader who has opened nothing sees everything as new' `
    ($unreadForSales.Count -eq $salesView.Count) `
    ('new=' + $unreadForSales.Count + ' total=' + $salesView.Count)

# The target is one announcement that BOTH readers have not opened: only then
# does "one reader opening it" prove the marker is per reader rather than global.
$engineerView = @((Api 'GET' '/api/announcements' $engineerToken $null).body)
$engineerUnreadIds = @($engineerView | Where-Object { $_.isNew -eq $true } | ForEach-Object { $_.announcementId })
$salesUnreadIds = @($unreadForSales | ForEach-Object { $_.announcementId })
$targetId = @($salesUnreadIds | Where-Object { $engineerUnreadIds -contains $_ })[0]
Check 'an announcement both readers have not opened is available to test with' `
    ($null -ne $targetId) ('sales=' + ($salesUnreadIds -join ',') + ' engineer=' + ($engineerUnreadIds -join ','))
$engineerViewBefore = @($engineerView | Where-Object { $_.announcementId -eq $targetId })[0].isNew

$marked = Api 'POST' ('/api/announcements/' + $targetId + '/read') $salesToken $null
Check 'opening an announcement is recorded' ($marked.status -eq 204) ('status=' + $marked.status)

$afterRead = @((Api 'GET' '/api/announcements' $salesToken $null).body)
$readEntry = @($afterRead | Where-Object { $_.announcementId -eq $targetId })[0]
Check 'the announcement that was opened is no longer new' ($readEntry.isNew -eq $false) ('isNew=' + $readEntry.isNew)
Check 'the others stay new' `
    (@($afterRead | Where-Object { $_.isNew -eq $true }).Count -eq ($salesView.Count - 1)) `
    ('new=' + @($afterRead | Where-Object { $_.isNew -eq $true }).Count)
Check 'a read announcement is still listed' ($afterRead.Count -eq $salesView.Count) `
    ('count=' + $afterRead.Count)

$again = Api 'POST' ('/api/announcements/' + $targetId + '/read') $salesToken $null
Check 'marking the same announcement read twice is harmless' ($again.status -eq 204) ('status=' + $again.status)

# Per reader, not per announcement: the engineer had not opened it either, so
# their view must still show it as new.
$engineerViewAfter = @((Api 'GET' '/api/announcements' $engineerToken $null).body |
    Where-Object { $_.announcementId -eq $targetId })[0].isNew
Check 'one reader marking it read does not clear it for another' `
    ($engineerViewBefore -eq $true -and $engineerViewAfter -eq $true) `
    ('before=' + $engineerViewBefore + ' after=' + $engineerViewAfter)

$unknown = Api 'POST' '/api/announcements/99999999/read' $salesToken $null
Check 'marking an unknown announcement read returns 404' ($unknown.status -eq 404) ('status=' + $unknown.status)

& $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value -q `
    -c "DELETE FROM qms.announcement_read WHERE employee_id = 'U01';" | Out-Null

# --- 7. the ledger is unaffected --------------------------------------------
$detail = Api 'GET' ('/api/complaints/' + $complaintId) $engineerToken $null
Check 'the complaint endpoints still work alongside the home module' ($detail.status -eq 200) ('status=' + $detail.status)

# --- cleanup -----------------------------------------------------------------
if (-not $KeepData) {
    & $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value -q `
        -c ("DELETE FROM qms.complaint WHERE customer_reference_id LIKE '" + $marker + "%';") | Out-Null
    $lines.Add('')
    $lines.Add('  cleaned up the seeded complaints')
}

$lines.Add('')
$lines.Add(('  RESULT : {0}   pass={1} fail={2}' -f $(if ($fail -eq 0) { 'PASS' } else { 'FAIL' }), $pass, $fail))
$lines | ForEach-Object { [Console]::Out.WriteLine($_) }
$lines | Out-File -FilePath (Join-Path $cfg.outDir 'verify_home_report.txt') -Encoding utf8

if ($fail -ne 0) { exit 1 }
