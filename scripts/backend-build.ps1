<#
  backend-build.ps1
  Builds the Spring Boot backend with the portable Maven, using this machine's
  Maven settings (Aliyun mirror). Writes a short report under tools\_out.

  Pure ASCII. Paths come from _paths.json.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\backend-build.ps1"
  Optional:
    -SkipTests     pass -DskipTests
    -Goals<goals>  override the default 'clean package'
#>
[CmdletBinding()]
param(
    [switch] $SkipTests,
    [switch] $KeepServer,
    [string] $Goals = 'clean package'
)

$ErrorActionPreference = 'Continue'

$cfgPath = Join-Path $PSScriptRoot '_paths.json'
$cfg = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json
$outDir = $cfg.outDir
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$reportPath = Join-Path $outDir 'backend_build_report.txt'

$jdk = Join-Path $cfg.toolsDir 'jdk-21'
$mvn = Join-Path $cfg.toolsDir 'maven\bin\mvn.cmd'
$settings = Join-Path $cfg.root 'config\maven-settings.xml'
$backend = Join-Path $cfg.root 'backend'

if (-not (Test-Path (Join-Path $jdk 'bin\java.exe'))) { throw "JDK not installed; run setup-local-toolchain.ps1" }
if (-not (Test-Path $mvn)) { throw "Maven not installed; run setup-local-toolchain.ps1" }
if (-not (Test-Path (Join-Path $backend 'pom.xml'))) { throw "No pom.xml in $backend" }

$env:JAVA_HOME = $jdk
$env:PATH = (Join-Path $jdk 'bin') + ';' + $env:PATH

$mvnArgs = @('-B')
if (Test-Path $settings) { $mvnArgs += @('-s', $settings) }
if ($SkipTests) { $mvnArgs += '-DskipTests' }
$mvnArgs += ($Goals -split ' ')

$log = Join-Path $outDir 'backend_build.log'
$lines = New-Object System.Collections.Generic.List[string]

# On Windows a running jar is file-locked, so `clean` fails with a confusing
# message. Stop the server first unless the caller says otherwise.
if (-not $KeepServer) {
    $pidFile = Join-Path $cfg.root 'run\qms-api.pid'
    if (Test-Path $pidFile) {
        $raw = (Get-Content $pidFile -Raw).Trim()
        $serverPid = 0
        if ([int]::TryParse($raw, [ref] $serverPid)) {
            $p = Get-Process -Id $serverPid -ErrorAction SilentlyContinue
            if ($p -and $p.ProcessName -like 'java*') {
                & taskkill /PID $serverPid /T /F | Out-Null
                Start-Sleep -Seconds 2
                $lines.Add('  note   : stopped running server (pid ' + $serverPid + ') to release the jar lock')
            }
        }
        Remove-Item -Force $pidFile -ErrorAction SilentlyContinue
    }
}

Push-Location $backend
try {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    & $mvn @mvnArgs *> $log
    $code = $LASTEXITCODE
    $sw.Stop()
} finally {
    Pop-Location
}

$lines.Add('backend-build')
$lines.Add('  goals    : ' + $Goals + $(if ($SkipTests) { ' (skip tests)' } else { '' }))
$lines.Add('  settings : ' + $settings)
$lines.Add('  exit     : ' + $code + '  in ' + [int]$sw.Elapsed.TotalSeconds + 's')
$lines.Add('  log      : ' + $log)

if ($code -eq 0) {
    $jar = Join-Path $backend 'target\qms-api.jar'
    if (Test-Path $jar) {
        $lines.Add('  jar      : ' + $jar + '  (' + [math]::Round((Get-Item $jar).Length / 1MB, 1) + ' MB)')
    } else {
        $lines.Add('  jar      : (not produced by these goals)')
    }
    $lines.Add('  RESULT   : PASS')
} else {
    $lines.Add('')
    $lines.Add('  --- last 25 log lines ---')
    if (Test-Path $log) {
        foreach ($l in (Get-Content $log -Tail 25)) { $lines.Add('  | ' + $l) }
    }
    $lines.Add('  RESULT   : FAIL')
}

$lines | Set-Content -Path $reportPath -Encoding UTF8
$lines | ForEach-Object { [Console]::Out.WriteLine($_) }
if ($code -ne 0) { exit 1 }
