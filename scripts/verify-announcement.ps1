<#
  verify-announcement.ps1
  Acceptance for the announcement management screen (requirement 3.0 / PS-003):

    - access control: reading is open to a logged-in user, managing is
      announcement:manage only (401 for anonymous, 403 for the quality engineer)
    - create / edit / publish / retire / delete and the status transitions
      (draft -> published -> retired -> published), with 409 on illegal ones
    - the home list stays published-only while a draft exists
    - the body is stored as sanitised HTML: scripts, event handlers and
      javascript: links are stripped, safe markup survives
    - an attribute-free body round-trips byte for byte
    - the F21 data migration left the seeded bodies as HTML
    - the administrator can set the publish time
    - the audit trail records create / update / status change / delete

  Pure ASCII: the Chinese fragments live in _verify_expectations.json.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\verify-announcement.ps1"
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

$lines.Add('verify-announcement  ->  ' + $BaseUrl)
$lines.Add('')

# --- sign in ----------------------------------------------------------------
$admin = Login 'ying.zhou' $Password
$adminToken = $admin.accessToken
$engineer = Login 'siyuan.li' $Password
$engToken = $engineer.accessToken
Check 'the administrator can sign in' ($null -ne $adminToken) 'no token'
Check 'the quality engineer can sign in' ($null -ne $engToken) 'no token'

$me = (Api 'GET' '/api/auth/me' $adminToken $null).body
Check 'the administrator holds announcement:manage' ($me.permissions -contains 'announcement:manage') ($me.permissions -join ',')
$engMe = (Api 'GET' '/api/auth/me' $engToken $null).body
Check 'the engineer lacks announcement:manage' (-not ($engMe.permissions -contains 'announcement:manage')) ($engMe.permissions -join ',')

# --- access control ---------------------------------------------------------
$stamp = Get-Date -Format 'HHmmss'
$title = 'VERIFYANN-' + $stamp
$new = @{ title = $title; content = '<p>draft body</p>' }

Check 'anonymous reading of the manager is refused (401)' ((Api 'GET' '/api/announcements/manage' '' $null).status -eq 401) 'expected 401'
Check 'anonymous creating is refused (401)' ((Api 'POST' '/api/announcements/manage' '' $new).status -eq 401) 'expected 401'
Check 'the engineer cannot list the manager (403)' ((Api 'GET' '/api/announcements/manage' $engToken $null).status -eq 403) 'expected 403'
Check 'the engineer cannot create (403)' ((Api 'POST' '/api/announcements/manage' $engToken $new).status -eq 403) 'expected 403'
Check 'the engineer cannot edit (403)' ((Api 'PUT' '/api/announcements/manage/1' $engToken $new).status -eq 403) 'expected 403'
Check 'the engineer cannot publish (403)' ((Api 'POST' '/api/announcements/manage/1/publish' $engToken $null).status -eq 403) 'expected 403'
Check 'the engineer cannot delete (403)' ((Api 'DELETE' '/api/announcements/manage/1' $engToken $null).status -eq 403) 'expected 403'

# --- validation -------------------------------------------------------------
$badTitle = @{ title = ''; content = '<p>x</p>' }
$r = Api 'POST' '/api/announcements/manage' $adminToken $badTitle
Check 'a blank title is refused (400)' ($r.status -eq 400) ('status=' + $r.status)
Check 'the blank-title message names the field' ($r.message -like ('*' + $expect.announcement.titleRequired + '*')) ('msg=' + $r.message)

$badContent = @{ title = 'VERIFYANN-' + $stamp + '-EMPTY'; content = '' }
$r = Api 'POST' '/api/announcements/manage' $adminToken $badContent
Check 'a blank body is refused (400)' ($r.status -eq 400) ('status=' + $r.status)
Check 'the blank-body message names the field' ($r.message -like ('*' + $expect.announcement.contentRequired + '*')) ('msg=' + $r.message)

$emptyPara = @{ title = 'VERIFYANN-' + $stamp + '-P'; content = '<p></p>' }
$r = Api 'POST' '/api/announcements/manage' $adminToken $emptyPara
Check 'a body of only empty paragraphs is refused (400)' ($r.status -eq 400) ('status=' + $r.status)

# --- create as draft --------------------------------------------------------
$created = Api 'POST' '/api/announcements/manage' $adminToken $new
Check 'the administrator creates a draft (201)' ($created.status -eq 201) ('status=' + $created.status)
$id = $created.body.announcementId
Check 'the created announcement gets an id' ($id -gt 0) ('id=' + $id)
Check 'a new announcement is a draft' ($created.body.publishStatus -eq $expect.announcement.statusDraft) ('status=' + $created.body.publishStatus)
Check 'a draft carries no publish time yet' ($null -eq $created.body.publishedAt) ('at=' + $created.body.publishedAt)
Check 'a draft names no publisher yet' ($null -eq $created.body.publishedByName) ('by=' + $created.body.publishedByName)

$manage = @((Api 'GET' '/api/announcements/manage' $adminToken $null).body)
Check 'the manager lists the new draft' ((@($manage | Where-Object { $_.announcementId -eq $id }).Count) -eq 1) 'row missing'
Check 'the manager lists drafts as well as published rows' ((@($manage | Where-Object { $_.publishStatus -eq $expect.announcement.statusDraft }).Count) -ge 1) 'no draft listed'

# $home is a reserved PowerShell variable (the user profile), so the list is named homeList.
$homeList = @((Api 'GET' '/api/announcements' $engToken $null).body)
Check 'a draft is absent from the home list' ((@($homeList | Where-Object { $_.announcementId -eq $id }).Count) -eq 0) 'draft leaked to home'
Check 'every published body is HTML (the migration ran)' ((@($homeList | Where-Object { $_.content -notlike '<*' }).Count) -eq 0) 'a plain-text body survived'

# --- edit -------------------------------------------------------------------
$edit = @{ title = $title + '-EDITED'; content = '<p>edited body</p>' }
Check 'the engineer cannot edit (403)' ((Api 'PUT' ('/api/announcements/manage/' + $id) $engToken $edit).status -eq 403) 'expected 403'

$edited = Api 'PUT' ('/api/announcements/manage/' + $id) $adminToken $edit
Check 'the administrator edits the draft (200)' ($edited.status -eq 200) ('status=' + $edited.status)
Check 'the new title is returned' ($edited.body.title -eq ($title + '-EDITED')) ('title=' + $edited.body.title)
Check 'an edit keeps the draft a draft' ($edited.body.publishStatus -eq $expect.announcement.statusDraft) ('status=' + $edited.body.publishStatus)

$missing = Api 'GET' '/api/announcements/manage/999999999' $adminToken $null
Check 'an unknown announcement id is a 404' ($missing.status -eq 404) ('status=' + $missing.status)
Check 'the not-found message names the resource' ($missing.message -like ('*' + $expect.announcement.notFound + '*')) ('msg=' + $missing.message)

# --- sanitising -------------------------------------------------------------
$dirty = @{
    title = 'VERIFYANN-' + $stamp + '-SAN'
    content = '<p onclick="x">hi</p><script>alert(1)</script><strong>ok</strong><img src=x onerror=alert(1)>'
}
$san = Api 'POST' '/api/announcements/manage' $adminToken $dirty
Check 'a row with hostile markup is created (201)' ($san.status -eq 201) ('status=' + $san.status)
$sanId = $san.body.announcementId
$sanBody = $san.body.content
Check 'safe markup survives sanitising' ($sanBody -like '*<strong>ok</strong>*') ('body=' + $sanBody)
Check 'a script element is stripped' ($sanBody -notlike '*<script*') ('body=' + $sanBody)
Check 'an onclick handler is stripped' ($sanBody -notlike '*onclick*') ('body=' + $sanBody)
Check 'an onerror handler is stripped' ($sanBody -notlike '*onerror*') ('body=' + $sanBody)
Check 'an image element is stripped' ($sanBody -notlike '*<img*') ('body=' + $sanBody)

$jsLink = @{ title = 'VERIFYANN-' + $stamp + '-JS'; content = '<a href="javascript:alert(1)">x</a>' }
$js = Api 'POST' '/api/announcements/manage' $adminToken $jsLink
Check 'a javascript: link is refused' ($js.body.content -notlike '*javascript:*') ('body=' + $js.body.content)
$jsId = $js.body.announcementId

$goodLink = @{ title = 'VERIFYANN-' + $stamp + '-LINK'; content = '<a href="https://example.com">x</a>' }
$gl = Api 'POST' '/api/announcements/manage' $adminToken $goodLink
Check 'an https link survives' ($gl.body.content -like '*href="https://example.com"*') ('body=' + $gl.body.content)
$glId = $gl.body.announcementId

# --- byte-for-byte round trip ----------------------------------------------
$roundTrip = '<p>Hello <strong>world</strong></p><ul><li>a</li><li>b</li></ul>'
$rt = Api 'POST' '/api/announcements/manage' $adminToken @{ title = 'VERIFYANN-' + $stamp + '-RT'; content = $roundTrip }
Check 'an attribute-free body is stored unchanged' ($rt.body.content -eq $roundTrip) ('body=' + $rt.body.content)
$rtId = $rt.body.announcementId

# --- publish / retire / republish ------------------------------------------
$published = Api 'POST' ('/api/announcements/manage/' + $id + '/publish') $adminToken $null
Check 'the draft publishes (200)' ($published.status -eq 200) ('status=' + $published.status)
Check 'the status becomes published' ($published.body.publishStatus -eq $expect.announcement.statusPublished) ('status=' + $published.body.publishStatus)
Check 'the publisher is recorded' ($published.body.publishedByName -eq $expect.announcement.publisherName) ('by=' + $published.body.publishedByName)
Check 'publishing stamps a time' ($null -ne $published.body.publishedAt) 'no time'

Check 'publishing an already published row is refused (409)' ((Api 'POST' ('/api/announcements/manage/' + $id + '/publish') $adminToken $null).status -eq 409) 'expected 409'
$r = Api 'POST' ('/api/announcements/manage/' + $id + '/publish') $adminToken $null
Check 'the publish refusal explains itself' ($r.message -like ('*' + $expect.announcement.publishRefused + '*')) ('msg=' + $r.message)

$home2 = @((Api 'GET' '/api/announcements' $engToken $null).body)
Check 'a published announcement reaches the home list' ((@($home2 | Where-Object { $_.announcementId -eq $id }).Count) -eq 1) 'missing from home'

$retired = Api 'POST' ('/api/announcements/manage/' + $id + '/retire') $adminToken $null
Check 'a published announcement retires (200)' ($retired.status -eq 200) ('status=' + $retired.status)
Check 'the status becomes retired' ($retired.body.publishStatus -eq $expect.announcement.statusRetired) ('status=' + $retired.body.publishStatus)

Check 'retiring a non-published row is refused (409)' ((Api 'POST' ('/api/announcements/manage/' + $id + '/retire') $adminToken $null).status -eq 409) 'expected 409'
$r = Api 'POST' ('/api/announcements/manage/' + $id + '/retire') $adminToken $null
Check 'the retire refusal explains itself' ($r.message -like ('*' + $expect.announcement.retireRefused + '*')) ('msg=' + $r.message)

$home3 = @((Api 'GET' '/api/announcements' $engToken $null).body)
Check 'a retired announcement leaves the home list' ((@($home3 | Where-Object { $_.announcementId -eq $id }).Count) -eq 0) 'retired row still on home'

$repub = Api 'POST' ('/api/announcements/manage/' + $id + '/publish') $adminToken $null
Check 'a retired announcement can be re-published' ($repub.body.publishStatus -eq $expect.announcement.statusPublished) ('status=' + $repub.body.publishStatus)
$home4 = @((Api 'GET' '/api/announcements' $engToken $null).body)
Check 'the re-published announcement is back on the home list' ((@($home4 | Where-Object { $_.announcementId -eq $id }).Count) -eq 1) 'missing from home'

# --- administrator-set publish time ----------------------------------------
$timed = @{ title = 'VERIFYANN-' + $stamp + '-TIME'; content = '<p>back dated</p>'; publishedAt = '2020-01-02T03:04:05' }
$tm = Api 'POST' '/api/announcements/manage' $adminToken $timed
Check 'a publish time can be supplied at creation' ($tm.body.publishedAt -like '2020-01-02*') ('at=' + $tm.body.publishedAt)
$tmId = $tm.body.announcementId
$tmPub = Api 'POST' ('/api/announcements/manage/' + $tmId + '/publish') $adminToken $null
Check 'publishing keeps the supplied time' ($tmPub.body.publishedAt -like '2020-01-02*') ('at=' + $tmPub.body.publishedAt)

# --- delete -----------------------------------------------------------------
$del = @{ title = 'VERIFYANN-' + $stamp + '-DEL'; content = '<p>to delete</p>' }
$delId = (Api 'POST' '/api/announcements/manage' $adminToken $del).body.announcementId
Check 'the administrator deletes an announcement (204)' ((Api 'DELETE' ('/api/announcements/manage/' + $delId) $adminToken $null).status -eq 204) 'expected 204'
Check 'the deleted announcement is a 404 afterwards' ((Api 'GET' ('/api/announcements/manage/' + $delId) $adminToken $null).status -eq 404) 'expected 404'
$manage2 = @((Api 'GET' '/api/announcements/manage' $adminToken $null).body)
Check 'the deleted announcement is gone from the manager list' ((@($manage2 | Where-Object { $_.announcementId -eq $delId }).Count) -eq 0) 'row still listed'

# --- audit trail ------------------------------------------------------------
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
Check 'the creation was audited' ((Q "select count(*) from qms.audit_log where action_type='CREATE' and biz_type='Announcement' and biz_id='$id'") -ge '1') 'expected at least 1'
Check 'the edit was audited with both values' ((Q "select count(*) from qms.audit_log where action_type='UPDATE' and biz_type='Announcement' and biz_id='$id' and before_value is not null and after_value is not null") -ge '1') 'expected a before/after pair'
Check 'the publish was audited as a status change' ((Q "select count(*) from qms.audit_log where action_type='STATUS_CHANGE' and biz_type='Announcement' and biz_id='$id'") -ge '1') 'expected at least 1'
Check 'the deletion was audited' ((Q "select count(*) from qms.audit_log where action_type='DELETE' and biz_type='Announcement' and biz_id='$delId'") -ge '1') 'expected at least 1'
Check 'the deleted announcement is only soft deleted' ((Q "select count(*) from qms.system_announcement where announcement_id=$delId and is_deleted = true") -eq '1') 'row not soft deleted'

# --- cleanup ----------------------------------------------------------------
if (-not $KeepData) {
    & $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value -q `
        -c "DELETE FROM qms.system_announcement WHERE title LIKE 'VERIFYANN-%';" | Out-Null
    $lines.Add('')
    $lines.Add('  cleaned up the VERIFYANN test announcements')
}

$lines.Add('')
$lines.Add(('  RESULT : ' + $(if ($fail -eq 0) { 'PASS' } else { "FAIL ($fail)" }) + '   passed=' + $pass + ' failed=' + $fail))
$lines | Set-Content -Path (Join-Path $cfg.outDir 'verify_announcement_report.txt') -Encoding UTF8
$lines | ForEach-Object { [Console]::Out.WriteLine($_) }
if ($fail -ne 0) { exit 1 }
