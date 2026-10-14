<#
  _probe-downloads.ps1
  Diagnostic (v2, curl-based). tests each candidate source with a real ranged GET
  and reports http code / bytes / seconds. The first version stalled at 0 bytes on
  GitHub release assets, so we now compare domestic mirrors too.

  Pure ASCII. Paths come from _paths.json.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\_probe-downloads.ps1"
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

$cfgPath = Join-Path $PSScriptRoot '_paths.json'
$cfg = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json
$outDir = $cfg.outDir
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

$curl = Join-Path $env:SystemRoot 'System32\curl.exe'
if (-not (Test-Path $curl)) { throw "curl.exe not found at $curl" }

function Emit([string] $m) { [Console]::Out.WriteLine($m) }

$targets = @(
    @{ name = 'npmjs (control)';   url = 'https://registry.npmjs.org/' },
    @{ name = 'apache archive';    url = 'https://archive.apache.org/dist/maven/maven-3/3.9.9/binaries/apache-maven-3.9.9-bin.zip' },
    @{ name = 'tuna apache';       url = 'https://mirrors.tuna.tsinghua.edu.cn/apache/maven/maven-3/3.9.9/binaries/apache-maven-3.9.9-bin.zip' },
    @{ name = 'adoptium api';      url = 'https://api.adoptium.net/v3/binary/latest/21/ga/windows/x64/jdk/hotspot/normal/eclipse' },
    @{ name = 'tuna adoptium dir'; url = 'https://mirrors.tuna.tsinghua.edu.cn/Adoptium/21/jdk/x64/windows/' },
    @{ name = 'tuna gh-release';   url = 'https://mirrors.tuna.tsinghua.edu.cn/github-release/git-for-windows/git/' },
    @{ name = 'hwcloud openjdk';   url = 'https://mirrors.huaweicloud.com/openjdk/' }
)

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('probe-downloads (curl, 1MB range where the server allows it)')

foreach ($t in $targets) {
    $fmt = '%{http_code} %{size_download} %{time_total} %{redirect_url}'
    $raw = & $curl -sSL --max-time 45 -r 0-1048575 -o NUL -w $fmt $t.url 2>&1
    $text = ($raw | Select-Object -Last 1)
    $parts = ($text -split '\s+')
    $code = $parts[0]
    $size = $parts[1]
    $time = $parts[2]
    $line = ('{0,-18} HTTP {1,-4} {2,9} bytes  {3,7}s' -f $t.name, $code, $size, $time)
    Emit $line
    $lines.Add($line)
}

# Which JDK archives does the TUNA mirror actually offer?
Emit ''
Emit '--- TUNA Adoptium 21 jdk x64 windows: available archives ---'
$listing = & $curl -sSL --max-time 45 'https://mirrors.tuna.tsinghua.edu.cn/Adoptium/21/jdk/x64/windows/' 2>&1
$zips = [regex]::Matches(($listing -join "`n"), 'href="([^"]*jdk_x64_windows_hotspot[^"]*\.zip)"')
if ($zips.Count -eq 0) {
    Emit '  (no matches -- mirror layout differs or unreachable)'
    $lines.Add('  TUNA adoptium: no zip matches')
} else {
    foreach ($m in ($zips | Select-Object -Last 4)) {
        $u = 'https://mirrors.tuna.tsinghua.edu.cn/Adoptium/21/jdk/x64/windows/' + $m.Groups[1].Value
        Emit ('  ' + $u)
        $lines.Add('  ' + $u)
    }
}

$lines | Set-Content -Path (Join-Path $outDir 'probe_downloads.txt') -Encoding UTF8
Emit ('report: ' + (Join-Path $outDir 'probe_downloads.txt'))
