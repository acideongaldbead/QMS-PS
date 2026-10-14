<#
  verify-attachment.ps1
  Acceptance for attachments: the whitelist, the 50 MB ceiling, the content
  sniffing that catches a renamed executable, the polymorphic parent check,
  permission, the upload/download round trip, deletion, and the audit trail.

  PowerShell 5.1 has no -Form parameter, so the multipart body is built by hand.

  Pure ASCII.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\verify-attachment.ps1"
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

$work = Join-Path $cfg.outDir '_attach_tmp'
if (Test-Path $work) { Remove-Item -Recurse -Force $work }
New-Item -ItemType Directory -Path $work -Force | Out-Null

$pass = 0; $fail = 0
$lines = New-Object System.Collections.Generic.List[string]
function Check([string] $name, [bool] $ok, [string] $detail) {
    if ($ok) { $script:pass++; $lines.Add(('  PASS  {0}' -f $name)) }
    else     { $script:fail++; $lines.Add(('  FAIL  {0}  -> {1}' -f $name, $detail)) }
}

function Login([string] $user, [string] $pwd) {
    $body = @{ username = $user; password = $pwd } | ConvertTo-Json
    return Invoke-RestMethod -Uri ($BaseUrl + '/api/auth/login') -Method Post `
        -ContentType 'application/json' -Body $body -TimeoutSec 20
}

function Invoke-Json([string] $method, [string] $path, [string] $token, $payload) {
    $headers = @{}
    if ($token) { $headers['Authorization'] = 'Bearer ' + $token }
    $args = @{ Uri = $BaseUrl + $path; Method = $method; Headers = $headers; TimeoutSec = 30; UseBasicParsing = $true }
    if ($null -ne $payload) {
        $args['ContentType'] = 'application/json; charset=utf-8'
        $args['Body'] = [System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Depth 12))
    }
    try {
        # Invoke-WebRequest, not Invoke-RestMethod: the latter does not expose the
        # status code, so a helper built on it reports 200 for every success and
        # silently turns "expects 201" into a failure and "expects 200" into a
        # tautology.
        $response = Invoke-WebRequest @args
        $body = $null
        if ($response.Content) { $body = $response.Content | ConvertFrom-Json }
        return @{ status = [int]$response.StatusCode; body = $body }
    }
    catch {
        return @{ status = Get-ErrorStatus $_; body = $null; message = (Get-ErrorMessage $_) }
    }
}

function Get-ErrorStatus($err) {
    try { return [int]$err.Exception.Response.StatusCode } catch { return 0 }
}
function Get-ErrorMessage($err) {
    try {
        $reader = New-Object System.IO.StreamReader($err.Exception.Response.GetResponseStream())
        $text = $reader.ReadToEnd(); $reader.Close()
        $parsed = $text | ConvertFrom-Json
        if ($parsed.message) { return $parsed.message }
    } catch { }
    return $err.Exception.Message
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

# --- test files -------------------------------------------------------------
$pngPath = Join-Path $work 'sample.png'
[System.IO.File]::WriteAllBytes($pngPath, [Convert]::FromBase64String(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg=='))

$exePath = Join-Path $work 'installer.exe'
[System.IO.File]::WriteAllBytes($exePath, [byte[]](0x4D, 0x5A, 0x90, 0x00, 0x03, 0x00, 0x00, 0x00) + (New-Object byte[] 4096))

# A Windows executable renamed to .pdf: the extension passes, the content must not.
$disguisedPath = Join-Path $work 'report.pdf'
[System.IO.File]::WriteAllBytes($disguisedPath, [byte[]](0x4D, 0x5A, 0x90, 0x00, 0x03, 0x00, 0x00, 0x00) + (New-Object byte[] 4096))

$oversizePath = Join-Path $work 'huge.png'
$fs = [System.IO.File]::Create($oversizePath)
$fs.SetLength(52MB)
$fs.Close()

# A minimal but structurally valid .pptx. OOXML documents are ZIP containers and
# Tika tells them apart from the other OOXML kinds by the content type they
# declare for their main part, so a synthetic package exercises the presentation
# branch without shipping a real (and possibly confidential) deck in the repo.
Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null
$pptxPath = Join-Path $work 'training-deck.pptx'
$macroDeckPath = Join-Path $work 'macro-deck.pptx'

function New-OoxmlPackage {
    param([string] $Path, [string] $PresentationContentType, [switch] $WithMacro)
    if (Test-Path $Path) { Remove-Item $Path -Force }
    $contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
        '<Default Extension="xml" ContentType="application/xml"/>' +
        '<Override PartName="/ppt/presentation.xml" ContentType="' + $PresentationContentType + '"/>' +
        '</Types>'
    $rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>' +
        '</Relationships>'
    $presentation = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
        '<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"/>'

    $parts = @(
        @{ name = '[Content_Types].xml';  text = $contentTypes },
        @{ name = '_rels/.rels';          text = $rels },
        @{ name = 'ppt/presentation.xml'; text = $presentation }
    )
    if ($WithMacro) {
        # A real macro-enabled Office package carries its VBA project as this part,
        # and that entry is the only reliable signal (Tika names the package after
        # its main part, so it cannot tell a renamed macro deck apart).
        $parts += @{ name = 'ppt/vbaProject.bin'; text = "MZ" + ('0' * 64) }
    }

    $zip = [System.IO.Compression.ZipFile]::Open($Path, 'Create')
    try {
        foreach ($part in $parts) {
            $entry = $zip.CreateEntry($part.name)
            $stream = $entry.Open()
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($part.text)
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Dispose()
        }
    } finally {
        $zip.Dispose()
    }
}

New-OoxmlPackage $pptxPath 'application/vnd.openxmlformats-officedocument.presentationml.presentation'
# The same package, but carrying VBA and declaring a macro-enabled content type:
# its extension is one we accept and the content type is one Tika will not report,
# so only the package-level macro check can refuse it.
New-OoxmlPackage $macroDeckPath 'application/vnd.ms-powerpoint.presentation.macroEnabled.12' -WithMacro

$lines.Add('verify-attachment  ->  ' + $BaseUrl)
$lines.Add('')

$sales = Login 'xiaoran.ma' $Password
$token = $sales.accessToken
Check 'sales quality logged in' ($null -ne $token) 'login failed'
if (-not $token) { $lines | ForEach-Object { [Console]::Out.WriteLine($_) }; exit 1 }

# --- a parent complaint to attach to ---------------------------------------
$payload = @{
    header = @{
        complaintTypeCode = 'COMPLAINT_TYPE_001'; priorityCode = 'PRIORITY_003'
        failureLocationCode = 'FAILURE_LOCATION_005'; complaintOwnerId = 'U02'
        coordinatorId = 'U01'; customerTargetDate = (Get-Date).Date.AddDays(20).ToString('yyyy-MM-dd')
    }
    qualityPartner = @{
        qualityPartnerCode = 'CUST-1001'; application = 'Yes'; contactPersonId = 'CP-1001'
        subSegmentCode = 'SUB_SEGMENT_001'
    }
    product = @{ productTypeCode = 'PRODUCT_TYPE_001'; packingTypeCode = 'PACKING_TYPE_001' }
    failureDescription = @{ customerFailureModeCode = 'FAILURE_MODE_001' }
    samples = @()
}
$created = (Invoke-Json 'POST' '/api/complaints' $token $payload).body
$complaintId = $created.complaintId
Check 'a parent complaint was created for the test' ($complaintId -match '^C\d{9}$') ('id=' + $complaintId)

$api = $BaseUrl + '/api/attachments'
$okUrl = $api

# --- 1. accepted upload -----------------------------------------------------
$r = Invoke-Upload -Url $okUrl -Token $token -FilePath $pngPath -FileName 'sample.png' -BizType 'Complaint' -BizId $complaintId
Check 'a whitelisted PNG uploads' ($r.status -eq 200 -or $r.status -eq 201) ('status=' + $r.status + ' ' + $r.message)
$attachmentId = $r.body.attachment.attachmentId
Check 'the upload returns an attachment id' ($attachmentId -gt 0) ('id=' + $attachmentId)
Check 'the detected content type is reported' ($r.body.attachment.fileType -eq 'image/png') ('type=' + $r.body.attachment.fileType)
Check 'the scan result is reported' ($null -ne $r.body.scanResult) 'no scan result'

# --- 2. the bytes come back unchanged --------------------------------------
$dl = Invoke-WebRequest -Uri ($api + '/' + $attachmentId + '/download') -Method Get `
    -Headers @{ Authorization = 'Bearer ' + $token } -UseBasicParsing -TimeoutSec 60
$origHash = (Get-FileHash -Algorithm SHA256 $pngPath).Hash
$dlHash = [BitConverter]::ToString(
    [System.Security.Cryptography.SHA256]::Create().ComputeHash($dl.Content)).Replace('-', '')
Check 'download returns the identical bytes' ($origHash -eq $dlHash) ('orig=' + $origHash + ' got=' + $dlHash)
Check 'download sets the content type' ($dl.Headers['Content-Type'] -like 'image/png*') ('ct=' + $dl.Headers['Content-Type'])
Check 'download offers the original filename' ($dl.Headers['Content-Disposition'] -like '*sample.png*') ('cd=' + $dl.Headers['Content-Disposition'])

# --- 3. listing -------------------------------------------------------------
$list = (Invoke-Json 'GET' ('/api/attachments?bizType=Complaint&bizId=' + $complaintId) $token $null).body
Check 'the attachment appears in the list' (@($list).Count -eq 1) ('count=' + @($list).Count)
Check 'the uploader name is resolved' (@($list)[0].uploadedByName -eq $expect.attachment.uploaderName) ('name=' + @($list)[0].uploadedByName)

# --- 4. refusals ------------------------------------------------------------
$r = Invoke-Upload -Url $okUrl -Token $token -FilePath $exePath -FileName 'installer.exe' -BizType 'Complaint' -BizId $complaintId
Check 'a non-whitelisted extension is refused' ($r.status -eq 400) ('status=' + $r.status)
Check 'the extension refusal names the problem' ($r.message -like ('*' + $expect.attachment.unsupportedType + '*')) ('msg=' + $r.message)

$r = Invoke-Upload -Url $okUrl -Token $token -FilePath $oversizePath -FileName 'huge.png' -BizType 'Complaint' -BizId $complaintId
Check 'a file over the 50MB ceiling is refused' ($r.status -eq 400 -or $r.status -eq 413) ('status=' + $r.status)
Check 'the size refusal is explained' ($r.message -like ('*' + $expect.attachment.overSize + '*')) ('msg=' + $r.message)

$r = Invoke-Upload -Url $okUrl -Token $token -FilePath $disguisedPath -FileName 'report.pdf' -BizType 'Complaint' -BizId $complaintId
Check 'an executable renamed to .pdf is refused' ($r.status -eq 400) ('status=' + $r.status)
Check 'the content refusal names the real type' ($r.message -like ('*' + $expect.attachment.executable + '*')) ('msg=' + $r.message)

$r = Invoke-Upload -Url $okUrl -Token $token -FilePath $pngPath -FileName 'decoy.docx' -BizType 'Complaint' -BizId $complaintId
Check 'a PNG renamed to .docx is refused' ($r.status -eq 400) ('status=' + $r.status)
Check 'the mismatch refusal says so' ($r.message -like ('*' + $expect.attachment.contentMismatch + '*')) ('msg=' + $r.message)

$r = Invoke-Upload -Url $okUrl -Token $token -FilePath $pngPath -FileName 'sample.png' -BizType 'Complaint' -BizId 'C202699999'
Check 'attaching to a non-existent complaint is refused' ($r.status -eq 404) ('status=' + $r.status)

$r = Invoke-Upload -Url $okUrl -Token $token -FilePath $pngPath -FileName 'sample.png' -BizType 'NotATable' -BizId $complaintId
Check 'an unknown business type is refused' ($r.status -eq 400) ('status=' + $r.status)

# --- 5. permission ----------------------------------------------------------
$auditor = Login 'zhiyuan.chen' $Password
$r = Invoke-Upload -Url $okUrl -Token $auditor.accessToken -FilePath $pngPath -FileName 'sample.png' -BizType 'Complaint' -BizId $complaintId
Check 'an auditor cannot upload (403)' ($r.status -eq 403) ('status=' + $r.status)

$r = Invoke-Upload -Url $okUrl -Token '' -FilePath $pngPath -FileName 'sample.png' -BizType 'Complaint' -BizId $complaintId
Check 'upload requires a login (401)' ($r.status -eq 401) ('status=' + $r.status)

# --- 6. download guards -----------------------------------------------------
try {
    Invoke-WebRequest -Uri ($api + '/99999999/download') -Method Get `
        -Headers @{ Authorization = 'Bearer ' + $token } -UseBasicParsing -TimeoutSec 30 | Out-Null
    Check 'downloading a missing attachment returns 404' $false 'it succeeded'
} catch {
    Check 'downloading a missing attachment returns 404' ((Get-ErrorStatus $_) -eq 404) ('status=' + (Get-ErrorStatus $_))
}

# --- 7. deletion ------------------------------------------------------------
$r = Invoke-Json 'DELETE' ('/api/attachments/' + $attachmentId) $token $null
Check 'an attachment can be deleted' ($r.status -eq 200) ('status=' + $r.status)
$list = (Invoke-Json 'GET' ('/api/attachments?bizType=Complaint&bizId=' + $complaintId) $token $null).body
Check 'a deleted attachment leaves the list' (@($list).Count -eq 0) ('count=' + @($list).Count)

# --- 8. audit trail ---------------------------------------------------------
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
Check 'an upload audit row was written' ((Q "select count(*) from qms.audit_log where action_type='CREATE' and biz_type='Attachment' and biz_id='$complaintId'") -eq '1') 'expected 1'
Check 'the disguised executable was recorded as a rejection' ((Q "select count(*) from qms.audit_log where action_type='UPLOAD_REJECTED' and biz_id='$complaintId' and after_value like '%report.pdf%'") -eq '1') 'expected exactly 1'
Check 'every refusal inside validation is audited' ((Q "select count(*) from qms.audit_log where action_type='UPLOAD_REJECTED' and biz_id='$complaintId'") -ge '3') 'expected at least 3 (extension, size, disguised content)'
Check 'a delete audit row was written' ((Q "select count(*) from qms.audit_log where action_type='DELETE' and biz_type='Attachment' and biz_id='$complaintId'") -eq '1') 'expected 1'
Check 'no attachment row is left active' ((Q "select count(*) from qms.attachment where biz_id='$complaintId' and is_deleted = false") -eq '0') 'expected 0'
Check 'the stored file was kept for review' ((Q "select count(*) from qms.attachment where biz_id='$complaintId'") -eq '1') 'expected the soft-deleted row to remain'

# --- 9. the Office formats the knowledge centre will need -------------------
# On its own complaint, so the exact-count assertions above keep their meaning.
$ruleSet = (Invoke-Json 'GET' '/api/attachments/rules' $token $null).body
$allowed = @($ruleSet.allowedExtensions)
Check 'the upload rules advertise Word, Excel and PowerPoint' `
    (($allowed -contains 'docx') -and ($allowed -contains 'xlsx') -and ($allowed -contains 'pptx')) `
    ('allowed=' + ($allowed -join ','))

$deck = (Invoke-Json 'POST' '/api/complaints' $token $payload).body
$deckComplaintId = $deck.complaintId
Check 'a second complaint was created for the Office-format checks' `
    ($deckComplaintId -match '^C\d{9}$') ('id=' + $deckComplaintId)

$r = Invoke-Upload -Url $okUrl -Token $token -FilePath $pptxPath -FileName 'training-deck.pptx' -BizType 'Complaint' -BizId $deckComplaintId
Check 'a PowerPoint deck is accepted' ($r.status -eq 200 -or $r.status -eq 201) ('status=' + $r.status + ' ' + $r.message)
Check 'the deck is recognised as a presentation' `
    ($r.body.attachment.fileType -eq 'application/vnd.openxmlformats-officedocument.presentationml.presentation') `
    ('type=' + $r.body.attachment.fileType)
$deckAttachmentId = $r.body.attachment.attachmentId

$deckDl = Invoke-WebRequest -Uri ($api + '/' + $deckAttachmentId + '/download') -Method Get `
    -Headers @{ Authorization = 'Bearer ' + $token } -UseBasicParsing -TimeoutSec 60
$deckHash = (Get-FileHash -Algorithm SHA256 $pptxPath).Hash
$deckGot = [BitConverter]::ToString(
    [System.Security.Cryptography.SHA256]::Create().ComputeHash($deckDl.Content)).Replace('-', '')
Check 'the deck downloads byte for byte' ($deckHash -eq $deckGot) ('orig=' + $deckHash + ' got=' + $deckGot)

$r = Invoke-Upload -Url $okUrl -Token $token -FilePath $macroDeckPath -FileName 'macro-deck.pptx' -BizType 'Complaint' -BizId $deckComplaintId
Check 'a macro-enabled deck renamed .pptx is refused' ($r.status -eq 400) ('status=' + $r.status)
Check 'the refusal names the macro' `
    ($r.message -like ('*' + $expect.attachment.macroRefused + '*')) ('msg=' + $r.message)
$deckList = @((Invoke-Json 'GET' ('/api/attachments?bizType=Complaint&bizId=' + $deckComplaintId) $token $null).body)
$macroStored = @($deckList | Where-Object { $_.fileName -eq 'macro-deck.pptx' }).Count
Check 'the refused macro deck is not stored' ($macroStored -eq 0) `
    ('stored=' + $macroStored + ' names=' + (($deckList | ForEach-Object { $_.fileName }) -join ','))

if (-not $KeepData) {
    & $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value -q `
        -c ("DELETE FROM qms.attachment WHERE biz_id = '" + $deckComplaintId + "'; DELETE FROM qms.complaint WHERE complaint_id = '" + $deckComplaintId + "';") | Out-Null
    $lines.Add('')
    $lines.Add('  cleaned up the Office-format complaint ' + $deckComplaintId)
}

# --- cleanup ----------------------------------------------------------------
if (-not $KeepData) {
    & $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value -q `
        -c ("DELETE FROM qms.attachment WHERE biz_id = '" + $complaintId + "'; DELETE FROM qms.complaint WHERE complaint_id = '" + $complaintId + "';") | Out-Null
    $lines.Add('')
    $lines.Add('  cleaned up complaint ' + $complaintId + ' and its attachment rows')
}

$lines.Add('')
$lines.Add(('  RESULT : ' + $(if ($fail -eq 0) { 'PASS' } else { "FAIL ($fail)" }) + '   passed=' + $pass + ' failed=' + $fail))
$lines | Set-Content -Path (Join-Path $cfg.outDir 'verify_attachment_report.txt') -Encoding UTF8
$lines | ForEach-Object { [Console]::Out.WriteLine($_) }
if ($fail -ne 0) { exit 1 }
