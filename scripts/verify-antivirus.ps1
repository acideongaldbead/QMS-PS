<#
  verify-antivirus.ps1
  Verifies the ClamAV adapter against a stand-in clamd that speaks the real
  INSTREAM protocol (e2e\fake-clamd.mjs). Three paths are covered:

    1. daemon says OK      -> the upload is stored
    2. daemon says FOUND   -> the upload is refused and nothing reaches storage
    3. daemon unreachable  -> the upload is refused rather than accepted unscanned

  It also asserts the byte count the daemon received, which is what proves the
  adapter's length-prefixed framing is correct rather than accidentally working.

  The application is started with the clamav provider for the duration and
  restored to the default provider afterwards.

  Pure ASCII.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\verify-antivirus.ps1"
  Optional:
    -Port 3310   -BaseUrl http://localhost:8080   -Password Qms@2026   -KeepData
#>
[CmdletBinding()]
param(
    [int] $Port = 3310,
    [string] $BaseUrl = 'http://localhost:8080',
    [string] $Password = 'Qms@2026',
    [switch] $KeepData
)

$ErrorActionPreference = 'Continue'

$cfgPath = Join-Path $PSScriptRoot '_paths.json'
$cfg = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json
if (-not (Test-Path $cfg.outDir)) { New-Item -ItemType Directory -Path $cfg.outDir -Force | Out-Null }
$expect = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '_verify_expectations.json')) | ConvertFrom-Json

$serverScript = Join-Path $PSScriptRoot 'qms-server.ps1'
$fakeScript = Join-Path $cfg.root 'e2e\fake-clamd.mjs'
$work = Join-Path $cfg.outDir '_av_tmp'
if (Test-Path $work) { Remove-Item -Recurse -Force $work }
New-Item -ItemType Directory -Path $work -Force | Out-Null

$pass = 0; $fail = 0
$lines = New-Object System.Collections.Generic.List[string]
function Check([string] $name, [bool] $ok, [string] $detail) {
    if ($ok) { $script:pass++; $lines.Add(('  PASS  {0}' -f $name)) }
    else     { $script:fail++; $lines.Add(('  FAIL  {0}  -> {1}' -f $name, $detail)) }
}

# --- database access, for the "nothing reached storage" assertions ----------
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

# --- fake clamd lifecycle ---------------------------------------------------
$script:fakeHandle = $null
function Start-FakeClamd([string] $Verdict) {
    $log = Join-Path $cfg.outDir ('fake_clamd_' + $Verdict + '.log')
    if (Test-Path $log) { Remove-Item -Force $log }
    $node = (Get-Command node).Source
    $p = Start-Process -FilePath $node `
        -ArgumentList @($fakeScript, ("--port=" + $Port), ("--verdict=" + $Verdict)) `
        -PassThru -WindowStyle Hidden -RedirectStandardOutput $log -RedirectStandardError ($log + '.err')
    $deadline = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 300
        if ((Test-Path $log) -and ((Get-Content $log -Raw) -match 'listening')) { break }
    }
    $script:fakeHandle = @{ pid = $p.Id; log = $log; verdict = $Verdict }
    return $script:fakeHandle
}
function Stop-FakeClamd {
    if ($script:fakeHandle) {
        & taskkill /PID $script:fakeHandle.pid /T /F | Out-Null
        Start-Sleep -Milliseconds 700
        $script:fakeHandle = $null
    }
}

# --- HTTP helpers -----------------------------------------------------------
function Login([string] $user, [string] $pwd) {
    $body = @{ username = $user; password = $pwd } | ConvertTo-Json
    return Invoke-RestMethod -Uri ($BaseUrl + '/api/auth/login') -Method Post `
        -ContentType 'application/json' -Body $body -TimeoutSec 20
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
function Invoke-Json([string] $method, [string] $path, [string] $token, $payload) {
    $headers = @{}
    if ($token) { $headers['Authorization'] = 'Bearer ' + $token }
    $a = @{ Uri = $BaseUrl + $path; Method = $method; Headers = $headers; TimeoutSec = 30 }
    if ($null -ne $payload) {
        $a['ContentType'] = 'application/json; charset=utf-8'
        $a['Body'] = [System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Depth 12))
    }
    try { return @{ status = 200; body = (Invoke-RestMethod @a) } }
    catch { return @{ status = Get-ErrorStatus $_; body = $null; message = (Get-ErrorMessage $_) } }
}
function Invoke-Upload([string] $Token, [string] $FilePath, [string] $FileName, [string] $BizId) {
    $boundary = [Guid]::NewGuid().ToString('N')
    $ms = New-Object System.IO.MemoryStream
    $enc = [System.Text.Encoding]::UTF8
    foreach ($f in @(@{ n = 'bizType'; v = 'Complaint' }, @{ n = 'bizId'; v = $BizId })) {
        $bytes = $enc.GetBytes("--$boundary`r`nContent-Disposition: form-data; name=`"$($f.n)`"`r`n`r`n$($f.v)`r`n")
        $ms.Write($bytes, 0, $bytes.Length)
    }
    $head = $enc.GetBytes("--$boundary`r`nContent-Disposition: form-data; name=`"file`"; filename=`"$FileName`"`r`nContent-Type: application/octet-stream`r`n`r`n")
    $ms.Write($head, 0, $head.Length)
    $fb = [System.IO.File]::ReadAllBytes($FilePath)
    $ms.Write($fb, 0, $fb.Length)
    $tail = $enc.GetBytes("`r`n--$boundary--`r`n")
    $ms.Write($tail, 0, $tail.Length)
    $payload = $ms.ToArray(); $ms.Dispose()
    try {
        $r = Invoke-WebRequest -Uri ($BaseUrl + '/api/attachments') -Method Post -TimeoutSec 120 `
            -Headers @{ Authorization = 'Bearer ' + $Token } `
            -ContentType ("multipart/form-data; boundary=" + $boundary) `
            -Body $payload -UseBasicParsing
        return @{ status = [int]$r.StatusCode; body = ($r.Content | ConvertFrom-Json) }
    } catch {
        return @{ status = Get-ErrorStatus $_; body = $null; message = (Get-ErrorMessage $_) }
    }
}

# --- the file under test ----------------------------------------------------
$pngPath = Join-Path $work 'scan.png'
[System.IO.File]::WriteAllBytes($pngPath, [Convert]::FromBase64String(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg=='))
$pngSize = (Get-Item $pngPath).Length

$lines.Add('verify-antivirus  ->  ' + $BaseUrl + '   (fake clamd on port ' + $Port + ')')
$lines.Add('')

$complaintId = $null
try {
    # ---- start the daemon in OK mode and the app in clamav mode -------------
    Start-FakeClamd 'ok' | Out-Null
    & $serverScript -Action Stop | Out-Null
    & $serverScript -Action Start -ExtraArgs "--qms.antivirus.provider=clamav", ("--qms.antivirus.clamav.port=" + $Port) | Out-Null

    $health = (Invoke-RestMethod -Uri ($BaseUrl + '/actuator/health') -TimeoutSec 10).status
    Check 'the application starts with the clamav provider' ($health -eq 'UP') ('health=' + $health)

    $token = (Login 'xiaoran.ma' $Password).accessToken
    Check 'logged in' ($null -ne $token) 'login failed'

    $payload = @{
        header = @{
            complaintTypeCode = 'COMPLAINT_TYPE_001'; priorityCode = 'PRIORITY_003'
            failureLocationCode = 'FAILURE_LOCATION_005'; complaintOwnerId = 'U02'
            coordinatorId = 'U01'; customerTargetDate = (Get-Date).Date.AddDays(20).ToString('yyyy-MM-dd')
        }
        qualityPartner = @{ qualityPartnerCode = 'CUST-1001'; application = 'Yes'; contactPersonId = 'CP-1001'; subSegmentCode = 'SUB_SEGMENT_001' }
        product = @{ productTypeCode = 'PRODUCT_TYPE_001'; packingTypeCode = 'PACKING_TYPE_001' }
        failureDescription = @{ customerFailureModeCode = 'FAILURE_MODE_001' }
        samples = @()
    }
    $complaintId = (Invoke-Json 'POST' '/api/complaints' $token $payload).body.complaintId
    Check 'a parent complaint was created' ($complaintId -match '^C\d{9}$') ('id=' + $complaintId)

    # ---- 1. clean verdict ---------------------------------------------------
    $r = Invoke-Upload $token $pngPath 'scan.png' $complaintId
    Check 'a clean file is stored when the daemon reports OK' ($r.status -eq 200 -or $r.status -eq 201) ('status=' + $r.status + ' ' + $r.message)
    Check 'the OK verdict is carried back to the client' ($r.body.scanResult -like '*stream: OK*') ('scanResult=' + $r.body.scanResult)
    Check 'an attachment row was created' ((Q "select count(*) from qms.attachment where biz_id='$complaintId' and is_deleted = false") -eq '1') 'expected 1'

    # The framing proof: the daemon counted exactly the bytes we uploaded.
    $fakeLog = Get-Content $script:fakeHandle.log -Raw
    $scanLine = [regex]::Match($fakeLog, '\{"event":"scan","received":(\d+)')
    $received = if ($scanLine.Success) { [int]$scanLine.Groups[1].Value } else { -1 }
    Check 'the daemon received exactly the uploaded bytes' ($received -eq $pngSize) `
        ('received=' + $received + ' expected=' + $pngSize)

    # ---- 2. the daemon reports a detection ----------------------------------
    Stop-FakeClamd
    Start-FakeClamd 'found' | Out-Null
    Start-Sleep -Milliseconds 400

    $r = Invoke-Upload $token $pngPath 'scan.png' $complaintId
    Check 'a detected file is refused' ($r.status -eq 400) ('status=' + $r.status)
    Check 'the refusal mentions the scan' ($r.message -like ('*' + $expect.antivirus.scanFailed + '*')) ('msg=' + $r.message)
    Check 'the refusal carries the signature name' ($r.message -like '*FOUND*') ('msg=' + $r.message)
    Check 'nothing was stored for the detected file' ((Q "select count(*) from qms.attachment where biz_id='$complaintId' and is_deleted = false") -eq '1') 'expected the count to stay at 1'
    Check 'the rejection was audited' ((Q "select count(*) from qms.audit_log where action_type='UPLOAD_REJECTED' and biz_id='$complaintId'") -ge '1') 'expected at least 1'

    # ---- 3. the daemon is gone ---------------------------------------------
    Stop-FakeClamd
    Start-Sleep -Milliseconds 500

    $r = Invoke-Upload $token $pngPath 'scan.png' $complaintId
    Check 'an unreachable daemon causes a refusal, not a silent accept' ($r.status -eq 400) ('status=' + $r.status)
    Check 'the unreachable daemon is named in the refusal' ($r.message -like ('*' + $expect.antivirus.unavailable + '*')) ('msg=' + $r.message)
    Check 'still nothing extra was stored' ((Q "select count(*) from qms.attachment where biz_id='$complaintId' and is_deleted = false") -eq '1') 'expected the count to stay at 1'

    # ---- 4. the file that was stored is intact -----------------------------
    $stored = Q "select storage_path from qms.attachment where biz_id='$complaintId' and is_deleted = false limit 1"
    $storedPath = Join-Path (Join-Path $cfg.root 'data\attachments') ($stored -replace '/', '\')
    Check 'the accepted file is on disk' (Test-Path $storedPath) ('path=' + $storedPath)
    if (Test-Path $storedPath) {
        $sameHash = (Get-FileHash -Algorithm SHA256 $pngPath).Hash -eq (Get-FileHash -Algorithm SHA256 $storedPath).Hash
        Check 'the stored bytes match the upload' $sameHash 'hash mismatch'
    }
} catch {
    Check 'antivirus verification run' $false $_.Exception.Message
} finally {
    # Restore the application to its normal configuration.
    Stop-FakeClamd
    & $serverScript -Action Stop | Out-Null
    & $serverScript -Action Start | Out-Null

    if ($complaintId -and -not $KeepData) {
        & $psql -h $m.Groups[1].Value -p $m.Groups[2].Value -U $vars['QMS_DB_USER'] -d $m.Groups[3].Value -q `
            -c ("DELETE FROM qms.attachment WHERE biz_id = '" + $complaintId + "'; DELETE FROM qms.complaint WHERE complaint_id = '" + $complaintId + "';") | Out-Null
        $lines.Add('')
        $lines.Add('  cleaned up complaint ' + $complaintId)
    }
    $lines.Add('')
    $lines.Add('  application restarted with the default antivirus provider')
}

$lines.Add('')
$lines.Add(('  RESULT : ' + $(if ($fail -eq 0) { 'PASS' } else { "FAIL ($fail)" }) + '   passed=' + $pass + ' failed=' + $fail))
$lines | Set-Content -Path (Join-Path $cfg.outDir 'verify_antivirus_report.txt') -Encoding UTF8
$lines | ForEach-Object { [Console]::Out.WriteLine($_) }
if ($fail -ne 0) { exit 1 }
