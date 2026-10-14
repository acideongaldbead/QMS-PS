<#
  ui-knowledge.ps1
  UI half of task 2.12: drives the knowledge centre in a real browser - the
  document list grouped by category, the category filter and its counts, the
  keyword search, the administrator's create / upload / delete flow, and the fact
  that a reader sees no maintenance controls.

  It seeds two documents through the API (one with a file, one without), hands
  their ids and the API's own totals to the browser script, and removes them
  afterwards. Seeding through the API rather than the UI keeps the browser half
  about the screen, and means the assertions compare the page against the data
  rather than against constants.

  Pure ASCII; the browser half carries the Chinese it has to look for.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\ui-knowledge.ps1"
  Optional:
    -BaseUrl http://localhost:8080   -Password Qms@2026   -KeepData
#>
[CmdletBinding()]
param(
    [string] $BaseUrl = 'http://localhost:8080',
    [string] $Password = 'Qms@2026',
    [string] $Admin = 'ying.zhou',
    [string] $Engineer = 'siyuan.li',
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

function Api([string] $method, [string] $path, [string] $token, $payload) {
    $headers = @{}
    if ($token) { $headers['Authorization'] = 'Bearer ' + $token }
    $a = @{ Uri = $BaseUrl + $path; Method = $method; Headers = $headers; TimeoutSec = 30; UseBasicParsing = $true }
    if ($null -ne $payload) {
        $a['ContentType'] = 'application/json; charset=utf-8'
        $a['Body'] = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $payload -Depth 12))
    }
    $response = Invoke-WebRequest @a
    $body = $null
    if ($response.Content) { $body = $response.Content | ConvertFrom-Json }
    return @{ status = [int]$response.StatusCode; body = $body }
}

function Invoke-Upload {
    param([string] $Url, [string] $Token, [string] $FilePath, [string] $FileName, [string] $BizType, [string] $BizId)
    $boundary = [Guid]::NewGuid().ToString('N')
    $ms = New-Object System.IO.MemoryStream
    $enc = [System.Text.Encoding]::UTF8
    foreach ($f in @(@{ n = 'bizType'; v = $BizType }, @{ n = 'bizId'; v = $BizId })) {
        $bytes = $enc.GetBytes("--$boundary`r`nContent-Disposition: form-data; name=`"$($f.n)`"`r`n`r`n$($f.v)`r`n")
        $ms.Write($bytes, 0, $bytes.Length)
    }
    $head = $enc.GetBytes("--$boundary`r`nContent-Disposition: form-data; name=`"file`"; filename=`"$FileName`"`r`nContent-Type: application/octet-stream`r`n`r`n")
    $ms.Write($head, 0, $head.Length)
    $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
    $ms.Write($fileBytes, 0, $fileBytes.Length)
    $tail = $enc.GetBytes("`r`n--$boundary--`r`n")
    $ms.Write($tail, 0, $tail.Length)
    $payload = $ms.ToArray()
    $ms.Dispose()
    $r = Invoke-WebRequest -Uri $Url -Method Post -TimeoutSec 120 `
        -Headers @{ Authorization = 'Bearer ' + $Token } `
        -ContentType ("multipart/form-data; boundary=" + $boundary) -Body $payload -UseBasicParsing
    return ($r.Content | ConvertFrom-Json)
}

$login = Invoke-RestMethod -Uri ($BaseUrl + '/api/auth/login') -Method Post `
    -ContentType 'application/json' -TimeoutSec 20 `
    -Body (@{ username = $Admin; password = $Password } | ConvertTo-Json)
$token = $login.accessToken
if (-not $token) { throw 'admin login failed' }

# The dictionary order is the prototype's tab order, so the first entry is the
# process files and the third is the training material. Nothing here assumes a
# Chinese literal: the labels travel to the browser script as API values.
$cats = @((Api 'GET' '/api/master-data/dictionary/knowledge_category' $token $null).body |
    Sort-Object { [int]$_.sortOrder })
if ($cats.Count -lt 3) { throw 'the knowledge_category dictionary is not seeded' }
$catA = $cats[0].code
$catAForBrowser = $cats[0].nameCn
$catB = $cats[2].code

$stamp = Get-Date -Format 'HHmmss'
$codeA = 'UIKB-A-' + $stamp
$codeB = 'UIKB-B-' + $stamp

$docA = (Api 'POST' '/api/knowledge/articles' $token @{
    title = 'Acceptance document A ' + $stamp
    titleEn = 'Acceptance document A'
    category = $catA
    docCode = $codeA
    version = 'V1.0'
    summary = 'Seeded by ui-knowledge.ps1'
}).body
$docB = (Api 'POST' '/api/knowledge/articles' $token @{
    title = 'Acceptance document B ' + $stamp
    titleEn = 'Acceptance document B'
    category = $catB
    docCode = $codeB
    summary = 'Seeded without a file'
}).body
if (-not $docA.articleId -or -not $docB.articleId) { throw 'seeding the documents failed' }

$pngPath = Join-Path $outDir 'kb-upload.png'
[System.IO.File]::WriteAllBytes($pngPath, [Convert]::FromBase64String(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg=='))
$up = Invoke-Upload -Url ($BaseUrl + '/api/attachments') -Token $token -FilePath $pngPath `
    -FileName 'manual.png' -BizType 'KnowledgeArticle' -BizId ([string]$docA.articleId)
if (-not $up.attachment.attachmentId) { throw 'seeding the document file failed' }

$summary = (Api 'GET' '/api/knowledge/summary' $token $null).body
[Console]::Out.WriteLine('kb data: total=' + $summary.total + ' docA=' + $docA.articleId + ' docB=' + $docB.articleId)

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
    (Join-Path $e2e 'knowledge.mjs'),
    ('--docA=' + $docA.articleId),
    ('--codeA=' + $codeA),
    ('--catA=' + $catA),
    ('--docB=' + $docB.articleId),
    ('--catProcess=' + $catAForBrowser),
    ('--keyword=' + $codeA),
    ('--total=' + $summary.total),
    ('--png=' + $pngPath),
    ('--user=' + $Admin),
    ('--engineer=' + $Engineer),
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
    # Both the seeded documents and any document the browser script created use
    # the UIKB- prefix, so one sweep clears the run.
    & $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value -q `
        -c ("DELETE FROM qms.attachment WHERE biz_type='KnowledgeArticle' AND biz_id IN (SELECT article_id::text FROM qms.knowledge_article WHERE doc_code LIKE 'UIKB-%');") | Out-Null
    & $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value -q `
        -c ("DELETE FROM qms.knowledge_article WHERE doc_code LIKE 'UIKB-%';") | Out-Null
    [Console]::Out.WriteLine('  cleaned up the seeded knowledge documents')
}

if ($nodeExit -ne 0) { exit 1 }
