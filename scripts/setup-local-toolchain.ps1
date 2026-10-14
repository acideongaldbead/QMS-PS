<#
  setup-local-toolchain.ps1
  Downloads and unpacks a portable, admin-free toolchain into <root>\tools:
    - Temurin JDK 21     (zip)
    - Apache Maven 3.9.x (zip)
    - PortableGit        (7z self-extracting exe)

  Why mirrors: on this network GitHub release assets stall at 0 bytes and the
  Adoptium API only returns a 307 to them. TUNA (Tsinghua) mirrors answer in
  ~0.2s, so they are tried first and upstream is the fallback. All transfers go
  through curl.exe.

  Two PowerShell 5.1 traps this script deliberately avoids:
    * never pipe a native command's stderr with 2>&1 while $ErrorActionPreference
      is Stop -- it wraps stderr in an ErrorRecord and aborts the script;
    * always wrap Matches/ForEach-Object pipelines in @() before indexing, or a
      single result collapses to a string and [0] returns its first character.

  Idempotent: skips a component whose target folder already exists.
  A failure in one component does not stop the others.

  Pure ASCII on purpose (no BOM needed). Paths come from _paths.json.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\setup-local-toolchain.ps1"
  Optional:
    -Components jdk,maven,git
    -Force        re-download even if present
#>
[CmdletBinding()]
param(
    [string[]] $Components = @('jdk', 'maven', 'git'),
    [switch]   $Force
)

# 'Continue', not 'Stop': native tools write diagnostics to stderr (curl errors,
# `java -version`, `mvn -v`) and Stop turns any redirected stderr into a fatal
# ErrorRecord. Every step below checks its own outcome explicitly instead.
$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

$cfgPath = Join-Path $PSScriptRoot '_paths.json'
if (-not (Test-Path $cfgPath)) { throw "Missing config: $cfgPath" }
$cfg = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json

$toolsDir = $cfg.toolsDir
$outDir   = $cfg.outDir
foreach ($d in @($toolsDir, $outDir)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}
$cacheDir = Join-Path $toolsDir '_downloads'
if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }

$curl = Join-Path $env:SystemRoot 'System32\curl.exe'
if (-not (Test-Path $curl)) { throw "curl.exe not found at $curl" }

$script:log = New-Object System.Collections.Generic.List[string]
# Must write to the real console: Write-Output would become part of the
# enclosing function's return value and corrupt its result.
function Say([string] $m) { $script:log.Add($m); [Console]::Out.WriteLine($m) }

function Save-Report {
    $reportPath = Join-Path $outDir 'toolchain_report.txt'
    ($script:log -join [Environment]::NewLine) | Set-Content -Path $reportPath -Encoding UTF8
    [Console]::Out.WriteLine("report: " + $reportPath)
}

# Fetch a directory listing into a temp file and return its text.
function Get-Listing([string] $url) {
    $tmp = Join-Path $cacheDir '_listing.tmp'
    & $curl -sSL --max-time 60 -o $tmp $url
    if ((Test-Path $tmp) -and (Get-Item $tmp).Length -gt 0) {
        return [System.IO.File]::ReadAllText($tmp)
    }
    return ''
}

# Download $url to $outFile. Returns $true only on a plausible, complete file.
function Download-File([string] $url, [string] $outFile) {
    Say ("  GET " + $url)
    if (Test-Path $outFile) { Remove-Item -Force $outFile }
    # No 2>&1 here on purpose -- see the header comment.
    & $curl -sS --fail --max-time 3600 -o $outFile -w '%{http_code}' $url
    $code = $LASTEXITCODE
    if (-not (Test-Path $outFile)) { Say ("  FAILED: no file (curl exit " + $code + ")"); return $false }
    $len = (Get-Item $outFile).Length
    if ($len -lt 1000000) {
        Say ("  FAILED: only " + $len + " bytes (curl exit " + $code + ")")
        Remove-Item -Force $outFile
        return $false
    }
    Say ("  OK  " + [math]::Round($len / 1MB, 1) + " MB")
    return $true
}

function Expand-Portable {
    param([string] $Archive, [string] $TargetDir, [string] $InnerPattern)
    if (Test-Path $TargetDir) { Remove-Item -Recurse -Force $TargetDir }
    $stage = Join-Path $toolsDir ('_stage_' + (Split-Path $TargetDir -Leaf))
    if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
    New-Item -ItemType Directory -Path $stage -Force | Out-Null

    if ($Archive -like '*.7z.exe') {
        $p = Start-Process -FilePath $Archive -ArgumentList @('-y', ('-o' + $stage)) -Wait -PassThru -NoNewWindow
        Say ("  sfx exit code: " + $p.ExitCode)
    } else {
        Expand-Archive -Path $Archive -DestinationPath $stage -Force
    }

    if ($InnerPattern -eq '*') {
        # PortableGit's SFX lays its payload out directly (bin/, cmd/, mingw64/, ...)
        # with no wrapper folder, so the whole stage is the target.
        Move-Item -Path $stage -Destination $TargetDir
        return
    }

    $inner = Get-ChildItem -Path $stage -Directory | Where-Object { $_.Name -like $InnerPattern } | Select-Object -First 1
    if (-not $inner) { $inner = Get-ChildItem -Path $stage -Directory | Select-Object -First 1 }
    if (-not $inner) { throw ("Nothing extracted from " + $Archive) }
    Move-Item -Path $inner.FullName -Destination $TargetDir
    Remove-Item -Recurse -Force $stage
}

# Try each candidate URL until one downloads successfully.
function Download-First([string[]] $urls, [string] $outFile) {
    foreach ($u in $urls) {
        if ($u -and (Download-File $u $outFile)) { return $true }
    }
    return $false
}

# Read the first line a native tool prints. java writes its version to stderr, so
# capture every stream into a file rather than piping (see header comment).
function Native-FirstLine([string] $exe, [string[]] $exeArgs) {
    $tmp = Join-Path $cacheDir '_native.tmp'
    if (Test-Path $tmp) { Remove-Item -Force $tmp }
    & $exe @exeArgs *> $tmp
    if ((Test-Path $tmp) -and (Get-Item $tmp).Length -gt 0) {
        return (Get-Content $tmp -TotalCount 1)
    }
    return '(no output)'
}

try {
    # ------------------------------------------------------------ JDK 21
    if ($Components -contains 'jdk') {
        $jdkDir = Join-Path $toolsDir 'jdk-21'
        if ((Test-Path $jdkDir) -and -not $Force) {
            Say ("[jdk]   already present: " + $jdkDir)
        } else {
            Say '[jdk]   installing'
            $zip = Join-Path $cacheDir 'jdk21.zip'
            $urls = New-Object System.Collections.Generic.List[string]

            $mirrorDir = 'https://mirrors.tuna.tsinghua.edu.cn/Adoptium/21/jdk/x64/windows/'
            $listing = Get-Listing $mirrorDir
            $hits = @([regex]::Matches($listing, 'href="([^"]*jdk_x64_windows_hotspot[^"]*\.zip)"'))
            if ($hits.Count -gt 0) {
                $urls.Add($mirrorDir + $hits[$hits.Count - 1].Groups[1].Value)
                Say ("  mirror offers " + $hits.Count + " archives")
            } else {
                Say '  mirror listing unusable, falling back upstream'
            }
            $urls.Add($cfg.downloads.jdkUrl)

            if (Download-First $urls $zip) {
                Expand-Portable -Archive $zip -TargetDir $jdkDir -InnerPattern 'jdk-*'
                Say ("[jdk]   -> " + $jdkDir)
            } else { Say '[jdk]   FAILED' }
        }
    }

    # ------------------------------------------------------------ Maven
    if ($Components -contains 'maven') {
        $mvnDir = Join-Path $toolsDir 'maven'
        if ((Test-Path $mvnDir) -and -not $Force) {
            Say ("[maven] already present: " + $mvnDir)
        } else {
            Say '[maven] installing'
            $zip = Join-Path $cacheDir 'maven.zip'
            $urls = New-Object System.Collections.Generic.List[string]

            $mirrorRoot = 'https://mirrors.tuna.tsinghua.edu.cn/apache/maven/maven-3/'
            $listing = Get-Listing $mirrorRoot
            # @() is essential: a single match would otherwise collapse to a string.
            $vers = @([regex]::Matches($listing, 'href="(3\.9\.\d+)/"') |
                      ForEach-Object { $_.Groups[1].Value } |
                      Sort-Object { [version]$_ })
            if ($vers.Count -gt 0) {
                $v = $vers[$vers.Count - 1]
                $urls.Add($mirrorRoot + $v + '/binaries/apache-maven-' + $v + '-bin.zip')
                Say ("  mirror newest 3.9.x = " + $v)
            } else {
                Say '  mirror listing unusable, falling back upstream'
            }
            $urls.Add($cfg.downloads.mavenUrl)

            if (Download-First $urls $zip) {
                Expand-Portable -Archive $zip -TargetDir $mvnDir -InnerPattern 'apache-maven-*'
                Say ("[maven] -> " + $mvnDir)
            } else { Say '[maven] FAILED' }
        }
    }

    # ------------------------------------------------------------ PortableGit
    if ($Components -contains 'git') {
        $gitDir = Join-Path $toolsDir 'git'
        if ((Test-Path $gitDir) -and -not $Force) {
            Say ("[git]   already present: " + $gitDir)
        } else {
            Say '[git]   installing'
            $exe = Join-Path $cacheDir 'PortableGit.7z.exe'
            $urls = New-Object System.Collections.Generic.List[string]

            $mirrorRoot = 'https://mirrors.tuna.tsinghua.edu.cn/github-release/git-for-windows/git/'
            # The mirror exposes a LatestRelease alias; fall back to scraping the
            # newest version directory if the alias is not served.
            foreach ($dir in @(($mirrorRoot + 'LatestRelease/'), $mirrorRoot)) {
                $listing = Get-Listing $dir
                $hits = @([regex]::Matches($listing, 'href="([^"]*PortableGit[^"]*64-bit\.7z\.exe)"'))
                if ($hits.Count -gt 0) {
                    $urls.Add($dir + $hits[0].Groups[1].Value)
                    Say ("  mirror hit at " + $dir)
                    break
                }
                if ($dir -eq $mirrorRoot) {
                    $subs = @([regex]::Matches($listing, 'href="([^"]+/)"') |
                              ForEach-Object { $_.Groups[1].Value } |
                              Where-Object { $_ -like 'Git*Windows*' })
                    if ($subs.Count -gt 0) {
                        $sub = $subs[$subs.Count - 1]
                        $l2 = Get-Listing ($mirrorRoot + $sub)
                        $h2 = @([regex]::Matches($l2, 'href="([^"]*PortableGit[^"]*64-bit\.7z\.exe)"'))
                        if ($h2.Count -gt 0) {
                            $urls.Add($mirrorRoot + $sub + $h2[0].Groups[1].Value)
                            Say ("  mirror hit at " + $sub)
                        }
                    }
                }
            }
            if ($urls.Count -eq 0) { Say '  mirror listing unusable, falling back upstream' }
            foreach ($u in $cfg.downloads.gitUrls) { $urls.Add($u) }

            if (Download-First $urls $exe) {
                Expand-Portable -Archive $exe -TargetDir $gitDir -InnerPattern '*'
                Say ("[git]   -> " + $gitDir)
            } else { Say '[git]   FAILED' }
        }
    }

    # ------------------------------------------------------------ verify
    Say ''
    Say '--- verify ---'

    $javaExe = Join-Path $toolsDir 'jdk-21\bin\java.exe'
    if (Test-Path $javaExe) {
        Say ("java : " + (Native-FirstLine $javaExe @('-version')))
    } else { Say 'java : MISSING' }

    $mvnCmd = Join-Path $toolsDir 'maven\bin\mvn.cmd'
    if (Test-Path $mvnCmd) {
        $env:JAVA_HOME = Join-Path $toolsDir 'jdk-21'
        Say ("mvn  : " + (Native-FirstLine $mvnCmd @('-v')))
    } else { Say 'mvn  : MISSING' }

    $gitExe = Join-Path $toolsDir 'git\cmd\git.exe'
    if (Test-Path $gitExe) {
        Say ("git  : " + (Native-FirstLine $gitExe @('--version')))
    } else { Say 'git  : MISSING' }
}
catch {
    Say ("FATAL: " + $_.Exception.Message)
    if ($_.Exception.InnerException) { Say ("       " + $_.Exception.InnerException.Message) }
}
finally {
    Save-Report
}
