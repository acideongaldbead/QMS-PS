<#
  verify-knowledge.ps1
  Acceptance for the knowledge centre (requirement 3.11): the category dictionary,
  document listing with category and keyword filters, create / update / soft delete,
  document-number uniqueness, the document file going through the shared attachment
  table under biz_type=KnowledgeArticle, the permission split between reading and
  maintaining, and the audit trail.

  PowerShell 5.1 has no -Form parameter, so the multipart body is built by hand.

  Pure ASCII.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\verify-knowledge.ps1"
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
$tmp = Join-Path $cfg.outDir '_kb_download.png'

$work = Join-Path $cfg.outDir '_kb_tmp'
if (Test-Path $work) { Remove-Item -Recurse -Force $work }
New-Item -ItemType Directory -Path $work -Force | Out-Null

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
function ApiBytes([string] $path, [string] $token, [string] $outFile) {
    $headers = @{}
    if ($token) { $headers['Authorization'] = 'Bearer ' + $token }
    try {
        Invoke-WebRequest -Uri ($BaseUrl + $path) -Method Get -Headers $headers -TimeoutSec 60 `
            -OutFile $outFile -UseBasicParsing
        return @{ status = 200; file = $outFile }
    } catch {
        return @{ status = Get-ErrorStatus $_; file = $null }
    }
}

# Builds a multipart/form-data upload: two text fields plus one file.
function Invoke-Upload {
    param(
        [string] $Url, [string] $Token, [string] $FilePath,
        [string] $FileName, [string] $BizType, [string] $BizId
    )
    $boundary = [Guid]::NewGuid().ToString('N')
    $ms = New-Object System.IO.MemoryStream
    $enc = [System.Text.Encoding]::UTF8

    $fields = @(
        @{ name = 'bizType'; value = $BizType },
        @{ name = 'bizId';   value = $BizId }
    )
    foreach ($f in $fields) {
        $part = "--$boundary`r`nContent-Disposition: form-data; name=`"$($f.name)`"`r`n`r`n$($f.value)`r`n"
        $bytes = $enc.GetBytes($part)
        $ms.Write($bytes, 0, $bytes.Length)
    }

    $fileHeader = "--$boundary`r`nContent-Disposition: form-data; name=`"file`"; filename=`"$FileName`"`r`nContent-Type: application/octet-stream`r`n`r`n"
    $hb = $enc.GetBytes($fileHeader)
    $ms.Write($hb, 0, $hb.Length)

    $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
    $ms.Write($fileBytes, 0, $fileBytes.Length)

    $closing = $enc.GetBytes("`r`n--$boundary--`r`n")
    $ms.Write($closing, 0, $closing.Length)

    $payload = $ms.ToArray()
    $ms.Dispose()

    try {
        $r = Invoke-WebRequest -Uri $Url -Method Post -TimeoutSec 120 `
            -Headers @{ Authorization = 'Bearer ' + $Token } `
            -ContentType ("multipart/form-data; boundary=" + $boundary) `
            -Body $payload -UseBasicParsing
        return @{ status = [int]$r.StatusCode; body = ($r.Content | ConvertFrom-Json) }
    } catch {
        return @{ status = Get-ErrorStatus $_; body = $null; message = (Get-ErrorMessage $_) }
    }
}

$lines.Add('verify-knowledge  ->  ' + $BaseUrl)
$lines.Add('')

# --- sign in ----------------------------------------------------------------
$admin = Login 'ying.zhou' $Password
$adminToken = $admin.accessToken
$engineer = Login 'siyuan.li' $Password
$engToken = $engineer.accessToken
Check 'the administrator can sign in' ($null -ne $adminToken) 'no token'
Check 'the quality engineer can sign in' ($null -ne $engToken) 'no token'

$me = (Api 'GET' '/api/auth/me' $adminToken $null).body
Check 'the administrator holds knowledge:manage' ($me.permissions -contains 'knowledge:manage') ($me.permissions -join ',')
$engMe = (Api 'GET' '/api/auth/me' $engToken $null).body
Check 'the engineer lacks knowledge:manage' (-not ($engMe.permissions -contains 'knowledge:manage')) ($engMe.permissions -join ',')
Check 'the engineer keeps knowledge:view' ($engMe.permissions -contains 'knowledge:view') ($engMe.permissions -join ',')

# --- category dictionary ----------------------------------------------------
$cats = @((Api 'GET' '/api/master-data/dictionary/knowledge_category' $engToken $null).body)
Check 'the knowledge_category dictionary has four entries' ($cats.Count -eq 4) ('count=' + $cats.Count)
Check 'each category carries an English name' (@($cats | Where-Object { $_.nameEn }).Count -eq 4) 'a category had no nameEn'
$catProcess = (@($cats | Where-Object { $_.nameCn -eq $expect.knowledge.categoryProcess })[0]).code
$catTraining = (@($cats | Where-Object { $_.nameCn -eq $expect.knowledge.categoryTraining })[0]).code
Check 'the process-file category resolves' ($null -ne $catProcess) 'not found'
Check 'the training category resolves' ($null -ne $catTraining) 'not found'

# --- baseline summary -------------------------------------------------------
$summary = (Api 'GET' '/api/knowledge/summary' $engToken $null).body
Check 'the engineer can read the summary' ($null -ne $summary) 'no body'
$baseTotal = [int]$summary.total

# --- create -----------------------------------------------------------------
$stamp = Get-Date -Format 'HHmmss'
$codeA = 'ACC-' + $stamp + '-A'
$codeB = 'ACC-' + $stamp + '-B'
$bodyA = @{
    title = $expect.knowledge.docTitle; titleEn = $expect.knowledge.docTitleEn
    category = $catProcess; docCode = $codeA; version = 'V1.0'
    summary = $expect.knowledge.docSummary; content = 'acceptance body'
}

Check 'creating without a token is refused (401)' ((Api 'POST' '/api/knowledge/articles' '' $bodyA).status -eq 401) 'expected 401'
Check 'the engineer cannot create a document (403)' ((Api 'POST' '/api/knowledge/articles' $engToken $bodyA).status -eq 403) 'expected 403'

$badTitle = $bodyA.Clone(); $badTitle['title'] = ''
$r = Api 'POST' '/api/knowledge/articles' $adminToken $badTitle
Check 'a blank title is refused (400)' ($r.status -eq 400) ('status=' + $r.status)
Check 'the blank-title message names the field' ($r.message -like ('*' + $expect.knowledge.titleRequired + '*')) ('msg=' + $r.message)

$badCat = $bodyA.Clone(); $badCat['category'] = 'NO_SUCH_CATEGORY'
$r = Api 'POST' '/api/knowledge/articles' $adminToken $badCat
Check 'an unknown category is refused (400)' ($r.status -eq 400) ('status=' + $r.status)
Check 'the unknown-category message names it' ($r.message -like ('*' + $expect.knowledge.unknownCategory + '*')) ('msg=' + $r.message)

$createdA = Api 'POST' '/api/knowledge/articles' $adminToken $bodyA
Check 'the administrator creates a document (201)' ($createdA.status -eq 201) ('status=' + $createdA.status)
$idA = $createdA.body.articleId
Check 'the created document gets an id' ($idA -gt 0) ('id=' + $idA)
Check 'the document number is echoed back' ($createdA.body.docCode -eq $codeA) ('code=' + $createdA.body.docCode)
Check 'the category name is resolved for the list' ($createdA.body.categoryName -eq $expect.knowledge.categoryProcess) ('name=' + $createdA.body.categoryName)
Check 'the maintainer is recorded' ($createdA.body.maintainerName -eq $expect.knowledge.maintainerName) ('name=' + $createdA.body.maintainerName)
Check 'a new document has no file yet' ($null -eq $createdA.body.latestFileName) 'unexpected file'

$dupA = $bodyA.Clone(); $dupA['title'] = 'another title'
$r = Api 'POST' '/api/knowledge/articles' $adminToken $dupA
Check 'a duplicate document number is refused (409)' ($r.status -eq 409) ('status=' + $r.status)
Check 'the duplicate message names the number' ($r.message -like ('*' + $expect.knowledge.duplicateDocCode + '*')) ('msg=' + $r.message)

$bodyB = @{
    title = $expect.knowledge.docTitle2; titleEn = $expect.knowledge.docTitle2En
    category = $catTraining; docCode = $codeB; version = 'V2.0'
    summary = $expect.knowledge.docSummary2; content = ''
}
$createdB = Api 'POST' '/api/knowledge/articles' $adminToken $bodyB
Check 'a second document in another category is created' ($createdB.status -eq 201) ('status=' + $createdB.status)
$idB = $createdB.body.articleId

# --- list and filters -------------------------------------------------------
$all = @((Api 'GET' '/api/knowledge/articles' $engToken $null).body)
Check 'the engineer sees both documents' ((@($all | Where-Object { $_.articleId -eq $idA -or $_.articleId -eq $idB }).Count) -eq 2) 'missing a row'

$byCat = @((Api 'GET' ('/api/knowledge/articles?category=' + $catProcess) $engToken $null).body)
Check 'filtering by category keeps the right document' ((@($byCat | Where-Object { $_.articleId -eq $idA }).Count) -eq 1) 'row missing'
Check 'filtering by category drops the other one' ((@($byCat | Where-Object { $_.articleId -eq $idB }).Count) -eq 0) 'row leaked in'

$byCode = @((Api 'GET' ('/api/knowledge/articles?keyword=' + $codeA) $engToken $null).body)
Check 'the document number is searchable' ((@($byCode | Where-Object { $_.articleId -eq $idA }).Count) -eq 1) 'not found by number'
Check 'a document-number search excludes the others' ((@($byCode | Where-Object { $_.articleId -eq $idB }).Count) -eq 0) 'row leaked in'

$byCn = @((Api 'GET' ('/api/knowledge/articles?keyword=' + [uri]::EscapeDataString($expect.knowledge.docTitle)) $engToken $null).body)
Check 'the Chinese title is searchable' ((@($byCn | Where-Object { $_.articleId -eq $idA }).Count) -ge 1) 'not found by title'

$bySummary = @((Api 'GET' ('/api/knowledge/articles?keyword=' + [uri]::EscapeDataString($expect.knowledge.docSummary2)) $engToken $null).body)
Check 'the description is searchable' ((@($bySummary | Where-Object { $_.articleId -eq $idB }).Count) -eq 1) 'not found by summary'

$byNone = @((Api 'GET' '/api/knowledge/articles?keyword=ZZZ_NO_SUCH_DOCUMENT' $engToken $null).body)
Check 'a keyword that matches nothing returns an empty list' ($byNone.Count -eq 0) ('count=' + $byNone.Count)

# --- single document --------------------------------------------------------
$one = Api 'GET' ('/api/knowledge/articles/' + $idA) $engToken $null
Check 'a single document is readable by the engineer' ($one.status -eq 200) ('status=' + $one.status)
Check 'the single document carries its title' ($one.body.title -eq $expect.knowledge.docTitle) ('title=' + $one.body.title)

$missing = Api 'GET' '/api/knowledge/articles/999999999' $engToken $null
Check 'an unknown document id is a 404' ($missing.status -eq 404) ('status=' + $missing.status)
Check 'the not-found message names the resource' ($missing.message -like ('*' + $expect.knowledge.notFound + '*')) ('msg=' + $missing.message)

# --- update -----------------------------------------------------------------
$edit = $bodyA.Clone(); $edit['title'] = $expect.knowledge.docTitleEdited; $edit['version'] = 'V1.1'
Check 'the engineer cannot edit a document (403)' ((Api 'PUT' ('/api/knowledge/articles/' + $idA) $engToken $edit).status -eq 403) 'expected 403'

$edited = Api 'PUT' ('/api/knowledge/articles/' + $idA) $adminToken $edit
Check 'the administrator edits the document (200)' ($edited.status -eq 200) ('status=' + $edited.status)
Check 'the new title is returned' ($edited.body.title -eq $expect.knowledge.docTitleEdited) ('title=' + $edited.body.title)
Check 'the new version is returned' ($edited.body.version -eq 'V1.1') ('version=' + $edited.body.version)

$clash = $edit.Clone(); $clash['docCode'] = $codeB
$r = Api 'PUT' ('/api/knowledge/articles/' + $idA) $adminToken $clash
Check 'an edit cannot steal another document number (409)' ($r.status -eq 409) ('status=' + $r.status)

$keepOwn = $edit.Clone(); $keepOwn['docCode'] = $codeA
Check 'a document may keep its own number on edit (200)' ((Api 'PUT' ('/api/knowledge/articles/' + $idA) $adminToken $keepOwn).status -eq 200) 'expected 200'

# --- summary moves ----------------------------------------------------------
$summary2 = (Api 'GET' '/api/knowledge/summary' $engToken $null).body
Check 'the summary total grew by two' ([int]$summary2.total -eq ($baseTotal + 2)) ('before=' + $baseTotal + ' after=' + $summary2.total)
$catCount = (@($summary2.categories | Where-Object { $_.category -eq $catProcess })[0]).total
Check 'the process-file category counts the new document' ($catCount -ge 1) ('count=' + $catCount)

# --- document file through the shared attachment table ----------------------
$pngPath = Join-Path $work 'manual.png'
[System.IO.File]::WriteAllBytes($pngPath, [Convert]::FromBase64String(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg=='))
$exePath = Join-Path $work 'installer.exe'
[System.IO.File]::WriteAllBytes($exePath, [byte[]](0x4D, 0x5A, 0x90, 0x00, 0x03, 0x00, 0x00, 0x00) + (New-Object byte[] 4096))

$uploadUrl = $BaseUrl + '/api/attachments'
Check 'the engineer cannot attach a document file (403)' `
    ((Invoke-Upload -Url $uploadUrl -Token $engToken -FilePath $pngPath -FileName 'manual.png' -BizType 'KnowledgeArticle' -BizId ([string]$idA)).status -eq 403) 'expected 403'

$up = Invoke-Upload -Url $uploadUrl -Token $adminToken -FilePath $pngPath -FileName 'manual.png' -BizType 'KnowledgeArticle' -BizId ([string]$idA)
Check 'the administrator attaches a document file (2xx)' ($up.status -eq 200 -or $up.status -eq 201) ('status=' + $up.status + ' ' + $up.message)
$attachmentId = $up.body.attachment.attachmentId

$files = @((Api 'GET' ('/api/attachments?bizType=KnowledgeArticle&bizId=' + $idA) $engToken $null).body)
Check 'the document file is listed under the article' ($files.Count -eq 1) ('count=' + $files.Count)

$oneAgain = (Api 'GET' ('/api/knowledge/articles/' + $idA) $engToken $null).body
Check 'the list row now shows the newest file name' ($oneAgain.latestFileName -eq 'manual.png') ('name=' + $oneAgain.latestFileName)
Check 'the list row now shows the file size' ($oneAgain.latestFileSize -gt 0) ('size=' + $oneAgain.latestFileSize)

$dl = ApiBytes ('/api/attachments/' + $attachmentId + '/download') $engToken $tmp
Check 'the document file downloads (200)' ($dl.status -eq 200) ('status=' + $dl.status)
$sameBytes = $false
if ($dl.status -eq 200) {
    $sameBytes = ((Get-FileHash $tmp).Hash -eq (Get-FileHash $pngPath).Hash)
}
Check 'the downloaded bytes match what was uploaded' $sameBytes 'hash mismatch'

$orphan = Invoke-Upload -Url $uploadUrl -Token $adminToken -FilePath $pngPath -FileName 'manual.png' -BizType 'KnowledgeArticle' -BizId '999999999'
Check 'attaching to a missing document is a 404' ($orphan.status -eq 404) ('status=' + $orphan.status)
$wrongParent = Invoke-Upload -Url $uploadUrl -Token $adminToken -FilePath $pngPath -FileName 'manual.png' -BizType 'Complaint' -BizId '999999999'
Check 'a bigint document id does not leak into another parent type' ($wrongParent.status -eq 404) ('status=' + $wrongParent.status)
$badType = Invoke-Upload -Url $uploadUrl -Token $adminToken -FilePath $exePath -FileName 'installer.exe' -BizType 'KnowledgeArticle' -BizId ([string]$idA)
Check 'an unsupported file type is refused (400)' ($badType.status -eq 400) ('status=' + $badType.status)
Check 'the refusal names the reason' ($badType.message -like ('*' + $expect.knowledge.unsupportedType + '*')) ('msg=' + $badType.message)

Check 'the administrator removes the document file (200)' ((Api 'DELETE' ('/api/attachments/' + $attachmentId) $adminToken $null).status -eq 200) 'expected 200'
$filesAfter = @((Api 'GET' ('/api/attachments?bizType=KnowledgeArticle&bizId=' + $idA) $engToken $null).body)
Check 'the removed file is gone from the article' ($filesAfter.Count -eq 0) ('count=' + $filesAfter.Count)

# --- delete -----------------------------------------------------------------
Check 'the engineer cannot delete a document (403)' ((Api 'DELETE' ('/api/knowledge/articles/' + $idB) $engToken $null).status -eq 403) 'expected 403'
Check 'the administrator deletes a document (204)' ((Api 'DELETE' ('/api/knowledge/articles/' + $idB) $adminToken $null).status -eq 204) 'expected 204'
Check 'the deleted document is a 404 afterwards' ((Api 'GET' ('/api/knowledge/articles/' + $idB) $engToken $null).status -eq 404) 'expected 404'
$afterDelete = @((Api 'GET' '/api/knowledge/articles' $engToken $null).body)
Check 'the deleted document is gone from the list' ((@($afterDelete | Where-Object { $_.articleId -eq $idB }).Count) -eq 0) 'row still listed'

$reuse = Api 'POST' '/api/knowledge/articles' $adminToken $bodyB
Check 'a deleted document number can be reused (201)' ($reuse.status -eq 201) ('status=' + $reuse.status)
$idC = $reuse.body.articleId

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
Check 'the creation was audited' ((Q "select count(*) from qms.audit_log where action_type='CREATE' and biz_type='KnowledgeArticle' and biz_id='$idA'") -ge '1') 'expected at least 1'
Check 'the edit was audited with both values' ((Q "select count(*) from qms.audit_log where action_type='UPDATE' and biz_type='KnowledgeArticle' and biz_id='$idA' and before_value is not null and after_value is not null") -ge '1') 'expected a before/after pair'
Check 'the deletion was audited' ((Q "select count(*) from qms.audit_log where action_type='DELETE' and biz_type='KnowledgeArticle' and biz_id='$idB'") -ge '1') 'expected at least 1'
Check 'the refused attachment upload was still audited' ((Q "select count(*) from qms.audit_log where action_type='UPLOAD_REJECTED' and biz_type='Attachment' and biz_id='$idA'") -ge '1') 'expected at least 1'
Check 'the deleted document is only soft deleted' ((Q "select count(*) from qms.knowledge_article where article_id=$idB and is_deleted = true") -eq '1') 'row not soft deleted'

# --- cleanup ----------------------------------------------------------------
if (-not $KeepData) {
    $ids = @($idA, $idB, $idC) -join ','
    & $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value -q `
        -c ("DELETE FROM qms.attachment WHERE biz_type='KnowledgeArticle' AND biz_id IN ('$idA','$idB','$idC');") | Out-Null
    & $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value -q `
        -c ("DELETE FROM qms.knowledge_article WHERE article_id IN ($ids);") | Out-Null
    Remove-Item -Recurse -Force $work
    if (Test-Path $tmp) { Remove-Item -Force $tmp }
    $lines.Add('')
    $lines.Add('  cleaned up 3 test document(s) and their files')
}

$lines.Add('')
$lines.Add(('  RESULT : ' + $(if ($fail -eq 0) { 'PASS' } else { "FAIL ($fail)" }) + '   passed=' + $pass + ' failed=' + $fail))
$lines | Set-Content -Path (Join-Path $cfg.outDir 'verify_knowledge_report.txt') -Encoding UTF8
$lines | ForEach-Object { [Console]::Out.WriteLine($_) }
if ($fail -ne 0) { exit 1 }
