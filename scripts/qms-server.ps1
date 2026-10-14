<#
  qms-server.ps1
  Start / stop / check the QMS backend jar on this machine.

  Configuration comes from config\.env (never from arguments), so moving the
  system to the company Windows server is a matter of editing that one file.

  Pure ASCII. Paths come from _paths.json.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\qms-server.ps1" -Action Start
    & "...\qms-server.ps1" -Action Status
    & "...\qms-server.ps1" -Action Stop
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Start', 'Stop', 'Status', 'Restart')]
    [string] $Action,
    [int] $HealthTimeoutSec = 90,
    # Spring Boot overrides, e.g. --qms.antivirus.provider=clamav. Lets a test
    # start the application with a different configuration without editing files.
    [string[]] $ExtraArgs = @()
)

$ErrorActionPreference = 'Continue'

$cfgPath = Join-Path $PSScriptRoot '_paths.json'
$cfg = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json

$root    = $cfg.root
$jar     = Join-Path $root 'backend\target\qms-api.jar'
$java    = Join-Path $cfg.toolsDir 'jdk-21\bin\java.exe'
$logsDir = Join-Path $root 'logs'
$runDir  = Join-Path $root 'run'
foreach ($d in @($logsDir, $runDir)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}
$pidFile  = Join-Path $runDir 'qms-api.pid'
$outLog   = Join-Path $logsDir 'qms-api.out.log'
$errLog   = Join-Path $logsDir 'qms-api.err.log'

$envFile = Join-Path $root 'config\.env'
if (-not (Test-Path $envFile)) { throw "Missing config\.env (copy config\.env.example)" }

function Import-DotEnv {
    foreach ($line in [System.IO.File]::ReadAllLines($envFile)) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        $i = $t.IndexOf('=')
        if ($i -lt 1) { continue }
        [Environment]::SetEnvironmentVariable($t.Substring(0, $i).Trim(), $t.Substring($i + 1).Trim(), 'Process')
    }
}

function Get-ServerPid {
    if (-not (Test-Path $pidFile)) { return $null }
    $raw = (Get-Content $pidFile -Raw).Trim()
    if (-not $raw) { return $null }
    $procId = 0
    if (-not [int]::TryParse($raw, [ref] $procId)) { return $null }
    $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
    if ($p -and $p.ProcessName -like 'java*') { return $procId }
    return $null
}

function Get-Health {
    try {
        $r = Invoke-RestMethod -Uri 'http://localhost:8080/actuator/health' -TimeoutSec 5
        return $r.status
    } catch {
        return 'DOWN'
    }
}

function Stop-Server {
    $procId = Get-ServerPid
    if (-not $procId) {
        [Console]::Out.WriteLine('not running')
        if (Test-Path $pidFile) { Remove-Item -Force $pidFile }
        return
    }
    & taskkill /PID $procId /T /F | Out-Null
    Start-Sleep -Seconds 2
    Remove-Item -Force $pidFile -ErrorAction SilentlyContinue
    [Console]::Out.WriteLine("stopped pid $procId")
}

function Start-Server {
    if (-not (Test-Path $jar))    { throw "Jar not built: $jar  (run backend-build.ps1)" }
    if (-not (Test-Path $java))   { throw "JDK missing: $java  (run setup-local-toolchain.ps1)" }

    $existing = Get-ServerPid
    if ($existing) {
        [Console]::Out.WriteLine("already running (pid $existing); use -Action Restart")
        return
    }

    Import-DotEnv
    # Absolute storage path so it does not depend on the process working directory.
    [Environment]::SetEnvironmentVariable('QMS_STORAGE_ROOT', (Join-Path $root 'data\attachments'), 'Process')

    $javaArgs = @('-jar', $jar, '--spring.profiles.active=local') + $ExtraArgs
    $p = Start-Process -FilePath $java -ArgumentList $javaArgs -WorkingDirectory $root `
                       -PassThru -WindowStyle Hidden `
                       -RedirectStandardOutput $outLog -RedirectStandardError $errLog
    $p.Id | Set-Content -Path $pidFile -Encoding ASCII
    [Console]::Out.WriteLine("starting pid " + $p.Id + " ... (log: " + $outLog + ")")
}

function Show-Status {
    $procId = Get-ServerPid
    $health = Get-Health
    [Console]::Out.WriteLine(('pid    : ' + $(if ($procId) { $procId } else { '(none)' })))
    [Console]::Out.WriteLine(('health : ' + $health))
    if ($health -eq 'DOWN' -and (Test-Path $errLog)) {
        [Console]::Out.WriteLine('--- last 15 lines of stderr ---')
        foreach ($l in (Get-Content $errLog -Tail 15)) { [Console]::Out.WriteLine('  ' + $l) }
    }
}

switch ($Action) {
    'Stop'    { Stop-Server }
    'Start'   {
        Start-Server
        $deadline = (Get-Date).AddSeconds($HealthTimeoutSec)
        $status = 'DOWN'
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 3
            $status = Get-Health
            if ($status -eq 'UP') { break }
            if (-not (Get-ServerPid)) { break }
        }
        [Console]::Out.WriteLine('health : ' + $status)
        if ($status -ne 'UP') {
            [Console]::Out.WriteLine('--- last 30 lines of stderr ---')
            if (Test-Path $errLog) { foreach ($l in (Get-Content $errLog -Tail 30)) { [Console]::Out.WriteLine('  ' + $l) } }
            exit 1
        }
    }
    'Restart' { Stop-Server; Start-Server
        $deadline = (Get-Date).AddSeconds($HealthTimeoutSec)
        while ((Get-Date) -lt $deadline) { Start-Sleep -Seconds 3; if ((Get-Health) -eq 'UP') { break } }
        [Console]::Out.WriteLine('health : ' + (Get-Health)) }
    'Status'  { Show-Status }
}
