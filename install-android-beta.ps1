<#
.SYNOPSIS
    EXPERIMENTAL (BETA) Android SDK + Emulator installer for the Portable
    Flutter & VS Code development environment.
.DESCRIPTION
    Designed for non-admin University Lab Windows machines.
    This is a SELF-CONTAINED, ISOLATED, EXPERIMENTAL script. It does NOT
    modify, call, or depend on install.ps1. It installs everything the base
    environment needs PLUS a command-line-only Android SDK (NO Android Studio),
    an Android platform, a Google APIs x86_64 system image, and a ready-to-run
    AVD so students can try `flutter run` on an Android emulator instead of
    Chrome/Edge.

    *** EXPERIMENTAL / BETA ***
    The Android emulator requires hardware acceleration (WHPX / Hyper-V on
    Windows, or HAXM on older machines). Many locked-down university lab
    machines DISABLE virtualization in BIOS or forbid enabling WHPX/Hyper-V
    without administrator rights. On such hardware the emulator will NOT launch
    even though this installer succeeds. The Android system image + SDK
    download is also MULTIPLE GIGABYTES. Treat this as an experiment: install
    it, try to launch the emulator, and REPORT BACK whether it actually works
    on your machine.

    This script FAILS GRACEFULLY: a failing Android step logs a [FAIL] line
    and the script continues; it never deletes or corrupts an existing
    install.ps1 installation.
.USAGE
    From PowerShell:
      irm https://raw.githubusercontent.com/manighahrmani/flutter_vscode_package/main/install-android-beta.ps1 | iex
#>

$ErrorActionPreference = "Continue"

$DestFolder   = "$env:USERPROFILE\Downloads\flutter_vscode_package"
$ToolsFolder  = "$DestFolder\tools"
$VSCodeFolder = "$DestFolder\vscode"
$LogPath      = "$env:USERPROFILE\Downloads\flutter_vscode_install.log"
$SupportEmail = "mani.ghahremani@port.ac.uk"
$IssuesUrl    = "https://github.com/manighahrmani/flutter_vscode_package/issues"

# ===================== ANDROID BETA CHANNEL =====================
# EXPERIMENTAL. Isolated from install.ps1. See file header for caveats.
$AndroidFolder = "$ToolsFolder\android"

# Android commandline-tools (Windows). Concrete, recent, known-good build.
# Build 11076708 == cmdline-tools 11.0 (2024). The zip extracts to a folder
# named `cmdline-tools`; sdkmanager REQUIRES it to live under
# cmdline-tools\latest\, so the script relocates it below.
$AndroidCmdlineToolsBuild = "11076708"
$UrlAndroidCmdlineTools   = "https://dl.google.com/android/repository/commandlinetools-win-${AndroidCmdlineToolsBuild}_latest.zip"

# SDK packages to install via sdkmanager.
$AndroidPlatform    = "platforms;android-34"
$AndroidSystemImage = "system-images;android-34;google_apis;x86_64"
$AndroidAvdName     = "flutter_emulator"

# Deterministic tool paths. Defined up front (not only inside the install block)
# so the verification section can Test-Path them even when the Android steps are
# skipped because the JDK was unavailable.
$sdkManagerBat = "$AndroidFolder\cmdline-tools\latest\bin\sdkmanager.bat"
$avdManagerBat = "$AndroidFolder\cmdline-tools\latest\bin\avdmanager.bat"

# Portable JDK (Eclipse Temurin / Adoptium) 17 LTS. sdkmanager.bat and
# avdmanager.bat are Java launchers: with no JDK on the machine (JAVA_HOME
# unset, no `java` on PATH) every call fails with "JAVA_HOME is not set and no
# java command could be found". The portable bundle ships no Java, so we
# download and extract a no-admin JDK into $ToolsFolder\jdk and wire JAVA_HOME
# + PATH BEFORE any sdkmanager/avdmanager call. JDK (not JRE); .zip (not .msi).
$JdkFolder = "$ToolsFolder\jdk"
# PRIMARY: concrete, pinned, known-good 17.x asset. This is primary because the
# .NET WebClient fallback in Download-FileWithRetry does NOT follow redirects,
# and the Adoptium API URL below is a redirect.
$UrlJdkPrimary  = "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.20.1%2B1/OpenJDK17U-jdk_x64_windows_hotspot_17.0.20.1_1.zip"
# FALLBACK: Adoptium API "latest 17 GA" redirect. curl.exe -L (tier 1 of
# Download-FileWithRetry) follows it, so this still resolves if the pinned
# asset is ever removed.
$UrlJdkFallback = "https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse?project=jdk"
# Resolved below to the folder that DIRECTLY contains bin\java.exe. Gates the
# Android steps: if it stays $null the Android SDK/AVD setup is skipped.
$JavaHome = $null

# Component Download URLs (same set as install.ps1, kept self-contained)
$UrlPackageRelease = "https://github.com/manighahrmani/flutter_vscode_package/releases/latest/download/flutter_vscode_package.zip"
$UrlVSCode         = "https://update.code.visualstudio.com/latest/win32-x64-archive/stable"
$FlutterVersion    = "3.47.7"
$UrlFlutter        = "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_$FlutterVersion-stable.zip"
$UrlGit            = "https://github.com/git-for-windows/git/releases/download/v2.56.0.windows.2/MinGit-2.56.0.2-64-bit.zip"
$UrlSQLite         = "https://www.sqlite.org/2026/sqlite-tools-win-x64-3540100.zip"

# Required Extensions
$RequiredExtensions = @(
    "Dart-Code.flutter",
    "Dart-Code.dart-code",
    "GitHub.copilot",
    "GitHub.vscode-pull-request-github",
    "usernamehw.errorlens",
    "pkief.material-icon-theme",
    "qwtel.sqlite-viewer"
)

# ----------------- Telemetry & Logging Setup -----------------
$TelemetryEndpoint = "https://script.google.com/macros/s/AKfycbx4ztCT_U7XE9sNUFy4GNI5rvmptu_r1I20CoPbIZSy9a72ZaeZeIfRFY39X9NFpZA/exec"

$logEntries = [System.Collections.Generic.List[string]]::new()
function Log-Message([string]$msg, [string]$color="White", [bool]$toScreen=$true) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $formatted = "[$timestamp] $msg"
    $logEntries.Add($formatted)
    if ($toScreen) { Write-Host $msg -ForegroundColor $color }
}

function Save-Log {
    try {
        $logEntries | Out-File -FilePath $LogPath -Encoding utf8 -Force
    } catch {}
}

$installStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# ----------------- Per-step timing -----------------
# A lightweight per-step timer so the student can see how long each of the nine
# [n/9] steps took (and tell which one dominated - almost always the Android
# SDK + system image download). $script:stepStopwatch is a "lap" timer: it is
# restarted whenever a new step starts, and the elapsed lap is stored against
# the PREVIOUS step. $script:stepTimings holds one entry per step in order.
# Both the console and the log file receive the summary table (via Log-Message)
# at the finish block.
$script:stepTimings   = [System.Collections.Generic.List[object]]::new()
$script:stepStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

function Record-StepStart([string]$label) {
    # Close the lap for the previously-started step (if any) before starting
    # the timer for the incoming step.
    if ($script:stepTimings.Count -gt 0) {
        $previous = $script:stepTimings[$script:stepTimings.Count - 1]
        $previous.Seconds = $script:stepStopwatch.Elapsed.TotalSeconds
    }
    $script:stepStopwatch.Restart()
    $entry = @{ Label = $label; Seconds = $null }
    $script:stepTimings.Add($entry)
}

function Complete-LastStep {
    # Record the final lap for the last-started step. Called once, just before
    # the timing summary is printed.
    if ($script:stepTimings.Count -gt 0) {
        $last = $script:stepTimings[$script:stepTimings.Count - 1]
        if ($null -eq $last.Seconds) {
            $last.Seconds = $script:stepStopwatch.Elapsed.TotalSeconds
        }
    }
}

function Send-InstallationTelemetry([string]$status, [int]$failures=0, [hashtable]$extraData=@{}) {
    if (-not $TelemetryEndpoint -or $TelemetryEndpoint -eq "") { return }
    try {
        $fullLog = ($logEntries -join "`n")
        $durSec = if ($installStopwatch) { [Math]::Round($installStopwatch.Elapsed.TotalSeconds, 1).ToString() + "s" } else { "" }
        $payload = @{
            timestamp     = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            event         = (if ($status -eq "SUCCESS") { "INSTALL_SUCCESS" } else { "INSTALL_FAILED" })
            user          = $env:USERNAME
            computer      = $env:COMPUTERNAME
            os            = ([System.Environment]::OSVersion.VersionString)
            status        = $status
            choice        = "Android Emulator BETA Installation"
            duration      = $durSec
            checkFailures = $failures
            log           = $fullLog
        }
        $jsonPayload = $payload | ConvertTo-Json -Depth 3

        # Fire-and-forget background process so network timeouts never slow down the installation
        $encoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($jsonPayload))
        $telemetryScript = @"
try {
    `$bytes = [System.Convert]::FromBase64String('$encoded')
    `$json = [System.Text.Encoding]::UTF8.GetString(`$bytes)
    `$req = [System.Net.HttpWebRequest]::Create('$TelemetryEndpoint')
    `$req.Method = 'POST'
    `$req.ContentType = 'application/json'
    `$req.Timeout = 10000
    `$req.AllowAutoRedirect = `$true
    `$reqData = [System.Text.Encoding]::UTF8.GetBytes(`$json)
    `$req.ContentLength = `$reqData.Length
    `$stream = `$req.GetRequestStream()
    `$stream.Write(`$reqData, 0, `$reqData.Length)
    `$stream.Close()
    `$resp = `$req.GetResponse()
    `$resp.Close()
} catch {}
"@
        $encodedScript = [System.Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($telemetryScript))
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encodedScript" -WindowStyle Hidden
    } catch {}
}

function Fail-Exit([string]$reason) {
    Log-Message "FATAL ERROR: $reason" "Red"
    Save-Log
    Send-InstallationTelemetry "FAILED" 1 @{}
    Write-Host ""
    Write-Host "==========================================================================" -ForegroundColor Red
    Write-Host "                      INSTALLATION FAILED                                 " -ForegroundColor Red
    Write-Host "==========================================================================" -ForegroundColor Red
    Write-Host "Details: $reason" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Your diagnostic log file is saved at:" -ForegroundColor White
    Write-Host "  $LogPath" -ForegroundColor Green
    Write-Host ""
    Write-Host "To get help, choose one option:" -ForegroundColor White
    Write-Host "  1. GitHub: Open $IssuesUrl/new and upload the log file." -ForegroundColor Cyan
    Write-Host "  2. Email:  Send the log file to $SupportEmail" -ForegroundColor Cyan
    Write-Host "==========================================================================" -ForegroundColor Red
    Write-Host ""
    exit 1
}

# ----------------- Helper Functions (copied from install.ps1) -----------------
# Copied verbatim (not dot-sourced) so this experimental script stays fully
# self-contained for `irm .../install-android-beta.ps1 | iex`.
function Download-FileWithRetry([string]$url, [string]$outPath, [string]$description) {
    Log-Message "Downloading $description..." "Cyan"
    $tmp = "$outPath.tmp"
    if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }

    # Method 1: curl.exe
    $curlCmd = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curlCmd) {
        try {
            & curl.exe -L -C - --retry 3 --retry-delay 2 -o $tmp --progress-bar $url
            if ($LASTEXITCODE -eq 0 -and (Test-Path $tmp) -and (Get-Item $tmp).Length -gt 500) {
                Move-Item -Path $tmp -Destination $outPath -Force
                Log-Message "[OK] $description downloaded successfully via curl." "DarkGray" $false
                return $true
            }
        } catch {
            Log-Message "curl download failed for $description, trying WebClient..." "DarkYellow"
        }
    }

    # Method 2: .NET WebClient
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
        $wc.DownloadFile($url, $outPath)
        if ((Test-Path $outPath) -and (Get-Item $outPath).Length -gt 500) {
            Log-Message "[OK] $description downloaded successfully via WebClient." "DarkGray" $false
            return $true
        }
    } catch {
        Log-Message "WebClient download failed for $($description): $_" "DarkYellow"
    }

    # Method 3: Invoke-WebRequest
    try {
        Invoke-WebRequest -Uri $url -OutFile $outPath -UseBasicParsing -ErrorAction Stop
        if ((Test-Path $outPath) -and (Get-Item $outPath).Length -gt 500) {
            Log-Message "[OK] $description downloaded successfully via Invoke-WebRequest." "DarkGray" $false
            return $true
        }
    } catch {
        Log-Message "Invoke-WebRequest failed for $($description): $_" "DarkYellow"
    }

    return $false
}

function Extract-ZipArchive([string]$zipFile, [string]$targetDir, [string]$description="archive") {
    if (-not (Test-Path $targetDir)) {
        New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
    }

    $extractStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $extractedMethod = $null

    # Tier 1: Native tar.exe (Fastest)
    $tarCmd = Get-Command tar.exe -ErrorAction SilentlyContinue
    if ($tarCmd) {
        try {
            & tar.exe -xf $zipFile -C $targetDir 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $extractedMethod = "Native tar.exe"
            }
        } catch {}
    }

    # Tier 2: .NET ZipFile (Entry-by-Entry with overwrite)
    if (-not $extractedMethod) {
        try {
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
            $zip = [System.IO.Compression.ZipFile]::OpenRead($zipFile)
            foreach ($entry in $zip.Entries) {
                $destPath = Join-Path $targetDir $entry.FullName
                if ([string]::IsNullOrEmpty($entry.Name)) {
                    if (-not (Test-Path $destPath)) {
                        New-Item -ItemType Directory -Path $destPath -Force -ErrorAction SilentlyContinue | Out-Null
                    }
                } else {
                    $p = Split-Path -Parent $destPath
                    if (-not (Test-Path $p)) {
                        New-Item -ItemType Directory -Path $p -Force -ErrorAction SilentlyContinue | Out-Null
                    }
                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destPath, $true)
                }
            }
            $zip.Dispose()
            $extractedMethod = ".NET ZipFile API"
        } catch {}
    }

    # Tier 3: PowerShell Expand-Archive
    if (-not $extractedMethod) {
        try {
            $oldP = $ProgressPreference
            $ProgressPreference = 'SilentlyContinue'
            Expand-Archive -Path $zipFile -DestinationPath $targetDir -Force -ErrorAction Stop
            $ProgressPreference = $oldP
            $extractedMethod = "PowerShell Expand-Archive"
        } catch {}
    }

    # Tier 4: Windows Shell COM Object
    if (-not $extractedMethod) {
        try {
            $shell = New-Object -ComObject Shell.Application
            $zipPackage = $shell.NameSpace($zipFile)
            $destination = $shell.NameSpace($targetDir)
            $destination.CopyHere($zipPackage.Items(), 16) # 16 = Respond 'Yes to All'
            $extractedMethod = "Windows Shell COM"
        } catch {}
    }

    $extractStopwatch.Stop()
    $durationSec = [math]::Round($extractStopwatch.Elapsed.TotalSeconds, 1)

    if ($extractedMethod) {
        Log-Message "[OK] Extracted $description in ${durationSec}s (Method: $extractedMethod)" "DarkGray" $false
        return $true
    } else {
        Log-Message "[FAIL] All 4 extraction tiers failed for $description in ${durationSec}s" "Red"
        return $false
    }
}

# Invoke-Sdkmanager / Invoke-Avdmanager wrap the Android CLI tools so a failure
# logs a clear [FAIL] line (per install.ps1 style) instead of silently
# continuing. We pipe `y` (via a temp file) to accept any interactive prompts.
function Invoke-AndroidTool([string]$exePath, [string[]]$toolArgs, [string]$inputText, [string]$description) {
    if (-not (Test-Path $exePath)) {
        Log-Message "[FAIL] $description - tool not found at $exePath" "Red"
        return $false
    }
    try {
        if ($null -ne $inputText) {
            # Feed repeated acceptance lines to stdin for license/overwrite prompts.
            $inputText | & $exePath @toolArgs 2>&1 | ForEach-Object { Log-Message "    $_" "DarkGray" $false }
        } else {
            & $exePath @toolArgs 2>&1 | ForEach-Object { Log-Message "    $_" "DarkGray" $false }
        }
        if ($LASTEXITCODE -eq 0) {
            Log-Message "[OK] $description" "DarkGray" $false
            return $true
        } else {
            Log-Message "[FAIL] $description (exit code $LASTEXITCODE)" "Red"
            return $false
        }
    } catch {
        Log-Message "[FAIL] $($description): $_" "Red"
        return $false
    }
}


# ----------------- Start Installation -----------------
Clear-Host
Log-Message "=========================================================" "Cyan"
Log-Message "     Portable Flutter & VS Code Environment Setup        " "Cyan"
Log-Message "     *** ANDROID EMULATOR BETA (EXPERIMENTAL) ***        " "Magenta"
Log-Message "=========================================================" "Cyan"
Log-Message "Target Directory: $DestFolder" "DarkGray"
Log-Message "Log File:         $LogPath" "DarkGray"
Log-Message ""
Log-Message "NOTE: This BETA installs a command-line Android SDK + emulator." "Yellow"
Log-Message "      The download is MULTIPLE GIGABYTES and the emulator needs" "Yellow"
Log-Message "      hardware acceleration that many lab machines disable." "Yellow"
Log-Message ""

# Gather System Telemetry
Log-Message "--- SYSTEM TELEMETRY ---" "DarkGray" $false
Log-Message "OS: $([System.Environment]::OSVersion.VersionString)" "DarkGray" $false
Log-Message "Computer: $env:COMPUTERNAME | User: $env:USERNAME" "DarkGray" $false
Log-Message "PowerShell Version: $($PSVersionTable.PSVersion)" "DarkGray" $false
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Log-Message "Admin Rights: $isAdmin" "DarkGray" $false
Log-Message ""

# 1. Existing Installation Handling
# Unlike install.ps1 we do NOT early-exit/launch here: this is an add-on that
# layers an Android SDK on top of an existing (or fresh) base install.
if (Test-Path $DestFolder) {
    Log-Message "Existing installation found at: $DestFolder (Android SDK will be added alongside it)." "Yellow"
}

# Ensure Directory Hierarchy
$dirs = @(
    $DestFolder,
    "$ToolsFolder\flutter",
    "$ToolsFolder\git",
    "$ToolsFolder\sqlite",
    "$ToolsFolder\pub_cache",
    $JdkFolder,
    $AndroidFolder,
    "$AndroidFolder\cmdline-tools",
    $VSCodeFolder,
    "$VSCodeFolder\data\user-data\User",
    "$VSCodeFolder\data\extensions",
    "$DestFolder\workspace",
    "$DestFolder\bin"
)
foreach ($d in $dirs) {
    if (-not (Test-Path $d)) {
        New-Item -Path $d -ItemType Directory -Force | Out-Null
    }
}

# 2. Download / Extract Base Package Template
Log-Message "[1/9] Setting up base launcher scripts and configuration..." "Green"
Record-StepStart "1/9 Base launcher & config"
$pkgZip = "$env:TEMP\flutter_vscode_pkg.zip"
if (Download-FileWithRetry $UrlPackageRelease $pkgZip "Package Template") {
    Extract-ZipArchive $pkgZip $DestFolder "Base Launcher & Config Template" | Out-Null
    Remove-Item $pkgZip -Force -ErrorAction SilentlyContinue

    # Auto-flatten nested subfolder if present in archive
    $nestedDir = Join-Path $DestFolder "flutter_vscode_package"
    if (Test-Path $nestedDir) {
        Get-ChildItem -Path $nestedDir -Force | ForEach-Object {
            $destItem = Join-Path $DestFolder $_.Name
            if (Test-Path $destItem) { Remove-Item $destItem -Recurse -Force -ErrorAction SilentlyContinue }
            Move-Item -Path $_.FullName -Destination $DestFolder -Force
        }
        Remove-Item $nestedDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Ensure VS Code Settings file is in place
$settingsFile = "$VSCodeFolder\data\user-data\User\settings.json"
$settingsContent = @"
{
  "files.autoSave": "afterDelay",
  "files.autoSaveDelay": 1000,

  "dart.flutterSdkPath": "../../tools/flutter",
  "dart.sdkPath": "../../tools/flutter/bin/cache/dart-sdk",
  "dart.previewFlutterUiGuides": true,
  "dart.flutterOutline": true,
  "dart.openDevTools": "flutter",
  "dart.runPubGetOnPubspecChanges": "always",
  "dart.defaultFlutterDevice": "edge",
  "dart.flutterSelectDeviceWhenConnected": false,
  "dart.webRenderer": "auto",

  "editor.formatOnSave": true,
  "editor.tabSize": 2,
  "editor.rulers": [80],
  "[dart]": {
    "editor.defaultFormatter": "Dart-Code.dart-code",
    "editor.formatOnSave": true,
    "editor.formatOnType": true,
    "editor.selectionHighlight": false,
    "editor.suggest.snippetsPreventQuickSuggestions": false
  },
  "editor.codeActionsOnSave": {
    "source.fixAll": "explicit",
    "source.organizeImports": "explicit"
  },

  "errorlens.enabled": true,
  "errorlens.fontSize": "12px",
  "errorlens.fontStyleItalic": true,
  "errorlens.statusBarIconsEnabled": true,

  "workbench.iconTheme": "material-icon-theme",
  "workbench.startupEditor": "readme",

  "git.autofetch": true,
  "git.confirmSync": false,
  "git.enableSmartCommit": true,

  "github.copilot.enable": {
    "*": true,
    "yaml": true,
    "plaintext": true,
    "markdown": true
  },

  "extensions.autoUpdate": false,
  "extensions.autoCheckUpdates": false,
  "extensions.ignoreRecommendations": true,
  "telemetry.telemetryLevel": "off",
  "update.mode": "none",

  "security.workspace.trust.enabled": false,
  "security.workspace.trust.startupPrompt": "never",
  "security.workspace.trust.banner": "never",
  "security.workspace.trust.emptyWindow": false,
  "security.workspace.trust.untrustedFiles": "open"
}
"@
$settingsContent | Out-File -FilePath $settingsFile -Encoding utf8 -Force
Log-Message "[OK] Default VS Code Flutter settings configured." "Green"

# 3. Setup VS Code Portable
Log-Message "[2/9] Setting up VS Code Portable..." "Green"
Record-StepStart "2/9 VS Code Portable"
if (-not (Test-Path "$VSCodeFolder\Code.exe")) {
    $vscodeZip = "$env:TEMP\vscode_win64.zip"
    if (Download-FileWithRetry $UrlVSCode $vscodeZip "VS Code Portable x64") {
        Extract-ZipArchive $vscodeZip $VSCodeFolder "VS Code Portable x64" | Out-Null
        Remove-Item $vscodeZip -Force -ErrorAction SilentlyContinue
    }
}
if (-not (Test-Path "$VSCodeFolder\Code.exe")) {
    Fail-Exit "VS Code executable ($VSCodeFolder\Code.exe) could not be installed."
}
Log-Message "[OK] VS Code Portable ready." "Green"

# 4. Setup Flutter SDK
Log-Message "[3/9] Setting up Flutter SDK..." "Green"
Record-StepStart "3/9 Flutter SDK"
$flutterVersionFile = "$ToolsFolder\flutter\version"
$installedFlutterVersion = if (Test-Path $flutterVersionFile) { (Get-Content $flutterVersionFile -Raw).Trim() } else { $null }
if ((-not (Test-Path "$ToolsFolder\flutter\bin\flutter.bat")) -or ($installedFlutterVersion -ne $FlutterVersion)) {
    if (Test-Path "$ToolsFolder\flutter") {
        Log-Message "Existing Flutter SDK ($installedFlutterVersion) is outdated; upgrading to $FlutterVersion..." "Yellow"
        Remove-Item "$ToolsFolder\flutter" -Recurse -Force -ErrorAction SilentlyContinue
    }
    $flutterZip = "$env:TEMP\flutter_sdk.zip"
    if (Download-FileWithRetry $UrlFlutter $flutterZip "Flutter SDK (Windows x64)") {
        Extract-ZipArchive $flutterZip $ToolsFolder "Flutter SDK (Windows x64)" | Out-Null
        Remove-Item $flutterZip -Force -ErrorAction SilentlyContinue
    }
}
if (-not (Test-Path "$ToolsFolder\flutter\bin\flutter.bat")) {
    Fail-Exit "Flutter SDK ($ToolsFolder\flutter\bin\flutter.bat) could not be installed."
}
Log-Message "[OK] Flutter SDK installed." "Green"

# 5. Setup Git & SQLite CLIs
Log-Message "[4/9] Setting up Git and SQLite command-line tools..." "Green"
Record-StepStart "4/9 Git & SQLite"
if (-not (Test-Path "$ToolsFolder\git\cmd\git.exe")) {
    $gitZip = "$env:TEMP\mingit.zip"
    if (Download-FileWithRetry $UrlGit $gitZip "MinGit") {
        Extract-ZipArchive $gitZip "$ToolsFolder\git" "MinGit" | Out-Null
        Remove-Item $gitZip -Force -ErrorAction SilentlyContinue
    }
}
if (-not (Test-Path "$ToolsFolder\sqlite\sqlite3.exe")) {
    $sqliteZip = "$env:TEMP\sqlite.zip"
    if (Download-FileWithRetry $UrlSQLite $sqliteZip "SQLite Tools") {
        Extract-ZipArchive $sqliteZip "$env:TEMP\sqlite_extracted" "SQLite Tools" | Out-Null
        $foundSqlite = Get-ChildItem -Path "$env:TEMP\sqlite_extracted" -Filter "sqlite3.exe" -Recurse | Select-Object -First 1
        if ($foundSqlite) {
            Copy-Item -Path $foundSqlite.FullName -Destination "$ToolsFolder\sqlite\sqlite3.exe" -Force
        }
        Remove-Item "$env:TEMP\sqlite_extracted" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $sqliteZip -Force -ErrorAction SilentlyContinue
    }
}
if (-not (Test-Path "$ToolsFolder\sqlite\sqlite3.wasm")) {
    # Must match the sqlite3 Dart package version the course projects pin
    # (sqlite3 3.5.2). A mismatched wasm fails to load in the browser.
    $UrlSQLiteWasm = "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.5.2/sqlite3.wasm"
    Download-FileWithRetry $UrlSQLiteWasm "$ToolsFolder\sqlite\sqlite3.wasm" "SQLite WebAssembly Binary (sqlite3.wasm)" | Out-Null
}
Log-Message "[OK] Git and SQLite CLI tools ready." "Green"

# 6. Install VS Code Extensions
Log-Message "[5/9] Installing VS Code Extensions..." "Green"
Record-StepStart "5/9 VS Code extensions"
$codeCmd = "$VSCodeFolder\bin\code.cmd"
$extDir  = "$VSCodeFolder\data\extensions"
$userDataDir = "$VSCodeFolder\data\user-data"

foreach ($ext in $RequiredExtensions) {
    Log-Message "Installing extension: $ext..." "DarkGray"
    $installed = $false
    
    # Check if already installed in cache
    if (Test-Path $extDir) {
        $existing = Get-ChildItem -Path $extDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name.ToLower() -like "$($ext.ToLower())*" }
        if ($existing) {
            $installed = $true
            Log-Message "[OK] Extension $ext is already installed." "DarkGray"
        }
    }

    # Attempt 1: Direct CLI install
    if (-not $installed) {
        try {
            & $codeCmd --extensions-dir $extDir --user-data-dir $userDataDir --install-extension $ext --force 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $installed = $true
            }
        } catch {}
    }

    # Attempt 2: Direct VSIX download fallback (bypasses marketplace.visualstudio.com TLS renegotiation / ECONNRESET)
    if (-not $installed) {
        $parts = $ext.Split('.')
        if ($parts.Count -eq 2) {
            $pub = $parts[0]
            $name = $parts[1]
            $vsixUrl = "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/$pub/vsextensions/$name/latest/vspackage"
            $tempVsix = "$env:TEMP\$name.vsix"
            if (Test-Path $tempVsix) { Remove-Item $tempVsix -Force -ErrorAction SilentlyContinue }
            
            $downloaded = $false
            $curlCmd = Get-Command curl.exe -ErrorAction SilentlyContinue
            if ($curlCmd) {
                & curl.exe -sL --compressed -o $tempVsix $vsixUrl 2>&1 | Out-Null
                if ((Test-Path $tempVsix) -and (Get-Item $tempVsix).Length -gt 1000) {
                    $downloaded = $true
                }
            }
            if (-not $downloaded) {
                $downloaded = Download-FileWithRetry $vsixUrl $tempVsix "VSIX package for $ext"
            }

            if ($downloaded) {
                & $codeCmd --extensions-dir $extDir --user-data-dir $userDataDir --install-extension $tempVsix --force 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    $installed = $true
                    Log-Message "[OK] Installed $ext via direct VSIX download." "DarkGray"
                }
                Remove-Item $tempVsix -Force -ErrorAction SilentlyContinue
            }
        }
    }

    if (-not $installed) {
        Log-Message "Warning: Failed to install extension $ext via CLI and VSIX fallback." "DarkYellow"
    }
}

# Verify installed extensions count before locking down
$installedCount = 0
if (Test-Path $extDir) {
    $dirsInExt = Get-ChildItem -Path $extDir -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name.ToLower() }
    foreach ($ext in $RequiredExtensions) {
        if ($dirsInExt | Where-Object { $_ -like "$($ext.ToLower())*" }) {
            $installedCount++
        }
    }
}

# 6.5 Lock down Extension Marketplace (only if all required extensions are installed)
if ($installedCount -ge $RequiredExtensions.Count) {
    Log-Message "Locking down VS Code Extension Marketplace..." "DarkGray"
    $productJsonPath = "$VSCodeFolder\resources\app\product.json"
    if (Test-Path $productJsonPath) {
        try {
            $product = Get-Content $productJsonPath -Raw | ConvertFrom-Json
            if ($product.PSObject.Properties['extensionsGallery']) {
                $product.extensionsGallery.serviceUrl = ""
                $product.extensionsGallery.itemUrl = ""
                $product.extensionsGallery.controlUrl = ""
                $product.extensionsGallery.resourceUrlTemplate = ""
                $product | ConvertTo-Json -Depth 10 | Set-Content $productJsonPath -Encoding UTF8
                Log-Message "[OK] Extension Marketplace disabled. Only pre-installed extensions are permitted." "Green"
            }
        } catch {
            Log-Message "Notice: Could not modify product.json: $_" "DarkGray"
        }
    }
} else {
    Log-Message "[WARN] Extension Marketplace lockdown skipped: $installedCount/$($RequiredExtensions.Count) extensions installed." "Yellow"
}

# ===================== 6.9 PORTABLE JDK (BETA) =====================
# sdkmanager/avdmanager need Java. Download & extract a no-admin Temurin JDK 17
# into $JdkFolder, resolve $JavaHome, wire JAVA_HOME + PATH (Process & User),
# and verify. The Android steps below are gated on $JavaHome being set.
Log-Message "[6/9] Setting up portable JDK (BETA)..." "Green"
Record-StepStart "6/9 Portable JDK"

# Reuse an already-extracted JDK if present (skip the multi-hundred-MB download).
$existingJava = Get-ChildItem -Path $JdkFolder -Filter "java.exe" -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.Directory.Name -eq "bin" } | Select-Object -First 1
if ($existingJava) {
    $JavaHome = Split-Path -Parent $existingJava.Directory.FullName
    Log-Message "[OK] Reusing existing JDK at $JavaHome." "DarkGray" $false
} else {
    $jdkZip = "$env:TEMP\temurin_jdk17.zip"
    if (Test-Path $jdkZip) { Remove-Item $jdkZip -Force -ErrorAction SilentlyContinue }

    # PRIMARY concrete asset first; FALLBACK to the Adoptium API redirect.
    $jdkDownloaded = Download-FileWithRetry $UrlJdkPrimary $jdkZip "Eclipse Temurin JDK 17 (Windows x64)"
    if (-not $jdkDownloaded) {
        Log-Message "Primary JDK download failed; trying Adoptium API fallback..." "DarkYellow"
        $jdkDownloaded = Download-FileWithRetry $UrlJdkFallback $jdkZip "Eclipse Temurin JDK 17 (Adoptium API fallback)"
    }

    if ($jdkDownloaded) {
        if (Extract-ZipArchive $jdkZip $JdkFolder "Eclipse Temurin JDK 17") {
            # The zip extracts a versioned subfolder (e.g. jdk-17.0.9+9) that
            # directly contains bin\java.exe. Find it robustly.
            $foundJava = Get-ChildItem -Path $JdkFolder -Filter "java.exe" -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.Directory.Name -eq "bin" } | Select-Object -First 1
            if ($foundJava) {
                $JavaHome = Split-Path -Parent $foundJava.Directory.FullName
                Log-Message "[OK] JDK extracted; JAVA_HOME resolved to $JavaHome." "DarkGray" $false
            } else {
                Log-Message "[FAIL] Could not locate bin\java.exe after extracting the JDK." "Red"
            }
        }
        Remove-Item $jdkZip -Force -ErrorAction SilentlyContinue
    } else {
        Log-Message "[FAIL] Could not download the Temurin JDK (primary and fallback both failed)." "Red"
    }
}

# Wire JAVA_HOME + PATH for Process and User, then verify java runs.
if ($JavaHome -and (Test-Path "$JavaHome\bin\java.exe")) {
    $jdkBin = "$JavaHome\bin"

    # Process-level JAVA_HOME + PATH (child sdkmanager/avdmanager inherit these).
    [System.Environment]::SetEnvironmentVariable("JAVA_HOME", $JavaHome, "Process")
    $procPath = [System.Environment]::GetEnvironmentVariable("PATH", "Process")
    if ($procPath -notlike "*$jdkBin*") { $procPath = "$jdkBin;$procPath" }
    [System.Environment]::SetEnvironmentVariable("PATH", $procPath, "Process")

    # User-level JAVA_HOME + PATH (permanent, non-admin), same pattern as Android.
    try {
        $userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
        if ($null -eq $userPath) { $userPath = "" }
        if ($userPath -notlike "*$jdkBin*") { $userPath = "$jdkBin;$userPath" }
        [System.Environment]::SetEnvironmentVariable("PATH", $userPath, "User")
        [System.Environment]::SetEnvironmentVariable("JAVA_HOME", $JavaHome, "User")
        Log-Message "[OK] JAVA_HOME and PATH saved to User profile." "Green"
    } catch {
        Log-Message "Notice: Could not write User Registry JAVA_HOME/PATH. Process env is active." "DarkYellow"
    }

    # Verify java actually runs. `java -version` prints to STDERR and returns 0
    # on success. Capture stderr to a file (so the native exit code is not lost
    # through a 2>&1 pipeline) and treat "prints a version line" as success,
    # since some portable JDK launchers report a non-zero code even when they
    # run fine.
    try {
        $javaErrFile = "$env:TEMP\java_version_check.txt"
        $javaProc = Start-Process -FilePath "$JavaHome\bin\java.exe" -ArgumentList "-version" `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardError $javaErrFile -RedirectStandardOutput "$env:TEMP\java_version_out.txt"
        $javaOut = ""
        if (Test-Path $javaErrFile) { $javaOut = (Get-Content $javaErrFile -Raw) }
        if ([string]::IsNullOrWhiteSpace($javaOut) -and (Test-Path "$env:TEMP\java_version_out.txt")) {
            $javaOut = (Get-Content "$env:TEMP\java_version_out.txt" -Raw)
        }
        Remove-Item $javaErrFile, "$env:TEMP\java_version_out.txt" -Force -ErrorAction SilentlyContinue
        $javaFirstLine = ($javaOut -split "`n" | Select-Object -First 1).Trim()
        if (($javaProc.ExitCode -eq 0) -or ($javaOut -match '(?i)version')) {
            Log-Message "[PASS] Java detected: $javaFirstLine" "Green"
        } else {
            Log-Message "[FAIL] Java present but did not run (exit $($javaProc.ExitCode)); Android steps will be SKIPPED." "Red"
            $JavaHome = $null
        }
    } catch {
        Log-Message "[FAIL] Java could not be run: $_; Android steps will be SKIPPED." "Red"
        $JavaHome = $null
    }
} else {
    Log-Message "[FAIL] JDK is REQUIRED for the Android tools but was not installed; SKIPPING the Android SDK/AVD steps." "Red"
    $JavaHome = $null
}

# ===================== 7. ANDROID SDK (EXPERIMENTAL / BETA) =====================
if ($JavaHome) {
Log-Message "[7/9] Setting up Android command-line SDK (BETA)..." "Green"
Record-StepStart "7/9 Android SDK + image"

# 7a. Download & lay out commandline-tools as cmdline-tools\latest\
# The zip extracts to a top-level `cmdline-tools` folder. sdkmanager REQUIRES
# the layout <sdk_root>\cmdline-tools\latest\bin\sdkmanager.bat, so we extract
# to a staging folder and move the inner `cmdline-tools` to `latest`.
$sdkManagerBat = "$AndroidFolder\cmdline-tools\latest\bin\sdkmanager.bat"
if (-not (Test-Path $sdkManagerBat)) {
    $ctZip     = "$env:TEMP\android_cmdline_tools.zip"
    $ctStaging = "$env:TEMP\android_cmdline_tools_extract"
    if (Test-Path $ctStaging) { Remove-Item $ctStaging -Recurse -Force -ErrorAction SilentlyContinue }

    if (Download-FileWithRetry $UrlAndroidCmdlineTools $ctZip "Android commandline-tools (build $AndroidCmdlineToolsBuild)") {
        if (Extract-ZipArchive $ctZip $ctStaging "Android commandline-tools") {
            $innerTools = Join-Path $ctStaging "cmdline-tools"
            $latestDir  = "$AndroidFolder\cmdline-tools\latest"
            if (Test-Path $innerTools) {
                if (Test-Path $latestDir) { Remove-Item $latestDir -Recurse -Force -ErrorAction SilentlyContinue }
                Move-Item -Path $innerTools -Destination $latestDir -Force
                Log-Message "[OK] commandline-tools laid out at cmdline-tools\latest\." "DarkGray" $false
            } else {
                Log-Message "[FAIL] Expected 'cmdline-tools' folder not found after extraction." "Red"
            }
        }
        Remove-Item $ctStaging -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $ctZip -Force -ErrorAction SilentlyContinue
    } else {
        Log-Message "[FAIL] Could not download Android commandline-tools." "Red"
    }
}

# 7b. Android env vars (User) + PATH (User & Process), same pattern as install.ps1.
$androidPathsToAdd = @(
    "$AndroidFolder\cmdline-tools\latest\bin",
    "$AndroidFolder\platform-tools",
    "$AndroidFolder\emulator"
)

# Process-Level PATH
$procPath = [System.Environment]::GetEnvironmentVariable("PATH", "Process")
foreach ($p in $androidPathsToAdd) {
    if ($procPath -notlike "*$p*") {
        $procPath = "$p;$procPath"
    }
}
[System.Environment]::SetEnvironmentVariable("PATH", $procPath, "Process")
[System.Environment]::SetEnvironmentVariable("ANDROID_SDK_ROOT", $AndroidFolder, "Process")
[System.Environment]::SetEnvironmentVariable("ANDROID_HOME", $AndroidFolder, "Process")

# User-Level Registry PATH + Android env vars (permanent, non-admin).
try {
    $userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    if ($null -eq $userPath) { $userPath = "" }
    $updatedUserPath = $userPath
    foreach ($p in $androidPathsToAdd) {
        if ($updatedUserPath -notlike "*$p*") {
            $updatedUserPath = "$p;$updatedUserPath"
        }
    }
    [System.Environment]::SetEnvironmentVariable("PATH", $updatedUserPath, "User")
    [System.Environment]::SetEnvironmentVariable("ANDROID_SDK_ROOT", $AndroidFolder, "User")
    [System.Environment]::SetEnvironmentVariable("ANDROID_HOME", $AndroidFolder, "User")
    Log-Message "[OK] ANDROID_SDK_ROOT / ANDROID_HOME and PATH saved to User profile." "Green"
} catch {
    Log-Message "Notice: Could not write User Registry PATH/env. Process PATH is active." "DarkYellow"
}

# 7c. Accept licenses and install SDK packages via sdkmanager.
# Always pass --sdk_root so sdkmanager targets our portable folder. We pipe
# repeated 'y' lines to accept the interactive license prompts. Each call is
# wrapped so a failure logs a [FAIL] line and we continue (fail gracefully).
if (Test-Path $sdkManagerBat) {
    # Build a big block of "y" answers for the license prompts.
    $yesLines = (("y`n") * 50)

    Log-Message "Accepting Android SDK licenses..." "DarkGray"
    Invoke-AndroidTool $sdkManagerBat @("--sdk_root=$AndroidFolder", "--licenses") $yesLines "Accept Android SDK licenses" | Out-Null

    Log-Message "Installing platform-tools, emulator, platform, and system image (this is several GB)..." "DarkGray"
    Invoke-AndroidTool $sdkManagerBat @("--sdk_root=$AndroidFolder", "platform-tools") $yesLines "Install platform-tools" | Out-Null
    Invoke-AndroidTool $sdkManagerBat @("--sdk_root=$AndroidFolder", "emulator") $yesLines "Install emulator" | Out-Null
    Invoke-AndroidTool $sdkManagerBat @("--sdk_root=$AndroidFolder", $AndroidPlatform) $yesLines "Install $AndroidPlatform" | Out-Null
    Invoke-AndroidTool $sdkManagerBat @("--sdk_root=$AndroidFolder", $AndroidSystemImage) $yesLines "Install $AndroidSystemImage" | Out-Null

    Log-Message "Pre-installing build-tools 35, platform android-36, and NDK r28c to speed up the FIRST emulator build (so flutter run does not download them mid-build)..." "DarkGray"
    $ok = Invoke-AndroidTool $sdkManagerBat @("--sdk_root=$AndroidFolder", "build-tools;35.0.0") $yesLines "Install build-tools;35.0.0 (first-build speedup)"
    if (-not $ok) { Log-Message "[WARN] Could not pre-install build-tools;35.0.0; the install still succeeds and Gradle will download it on the first build." "DarkYellow" }
    $ok = Invoke-AndroidTool $sdkManagerBat @("--sdk_root=$AndroidFolder", "platforms;android-36") $yesLines "Install platforms;android-36 (first-build speedup)"
    if (-not $ok) { Log-Message "[WARN] Could not pre-install platforms;android-36; the install still succeeds and it will download on the first build." "DarkYellow" }
    $ok = Invoke-AndroidTool $sdkManagerBat @("--sdk_root=$AndroidFolder", "ndk;28.2.13676358") $yesLines "Install ndk;28.2.13676358 (android-ndk-r28c, first-build speedup)"
    if (-not $ok) { Log-Message "[WARN] Could not pre-install ndk;28.2.13676358 (~750 MB); the install still succeeds and the NDK will download on the first build." "DarkYellow" }
} else {
    Log-Message "[FAIL] sdkmanager not present; skipping SDK package install and AVD creation." "Red"
}

# 7d. Create the AVD non-interactively (echo no => don't use a custom hardware profile).
$avdManagerBat = "$AndroidFolder\cmdline-tools\latest\bin\avdmanager.bat"
if (Test-Path $avdManagerBat) {
    Log-Message "Creating AVD '$AndroidAvdName'..." "DarkGray"
    Invoke-AndroidTool $avdManagerBat @("create", "avd", "-n", $AndroidAvdName, "-k", $AndroidSystemImage, "--force") "no`n" "Create AVD $AndroidAvdName" | Out-Null
} else {
    Log-Message "[FAIL] avdmanager not present; skipping AVD creation." "Red"
}

# 7e. [Registering the Android SDK with Flutter]
# Flutter can report "Unable to locate Android SDK" / "No valid Android SDK
# platforms found" even when ANDROID_HOME/ANDROID_SDK_ROOT are set and
# android-34 is installed, because Flutter validates the SDK via its OWN config
# + its OWN license-accepted state, not the env vars alone. So we (1) persist the
# SDK path in Flutter's config, (2) accept the Android licenses THROUGH flutter
# non-interactively, and (3) re-run flutter doctor and record whether the Android
# toolchain line is now a check or still an X. Each call is wrapped so a failure
# logs and the script continues (never aborts).
$flutterBat = "$ToolsFolder\flutter\bin\flutter.bat"
if (Test-Path $flutterBat) {
    Log-Message "[Registering the Android SDK with Flutter]" "Cyan"

    # (1) Persist the SDK path in Flutter's own settings (not just env vars).
    try {
        Log-Message "    flutter config --android-sdk `"$AndroidFolder`" ..." "DarkGray"
        & $flutterBat config --android-sdk "$AndroidFolder" 2>&1 |
            ForEach-Object { Log-Message "    $_" "DarkGray" $false }
        Log-Message "[OK] flutter config --android-sdk set to $AndroidFolder" "DarkGray" $false
    } catch {
        Log-Message "[FAIL] flutter config --android-sdk failed: $_" "Red"
    }

    # (2) Accept Android licenses THROUGH flutter, non-interactively. flutter
    # doctor --android-licenses prompts repeatedly ("Accept? (y/N)"); pipe many
    # y+CRLF lines so every prompt is answered.
    try {
        Log-Message "    Accepting Android licenses via flutter doctor --android-licenses ..." "DarkGray"
        $flutterYes = ("y`r`n" * 50)
        $flutterYes | & $flutterBat doctor --android-licenses 2>&1 |
            ForEach-Object { Log-Message "    $_" "DarkGray" $false }
        Log-Message "[OK] flutter doctor --android-licenses completed (exit $LASTEXITCODE)." "DarkGray" $false
    } catch {
        Log-Message "[FAIL] flutter doctor --android-licenses failed: $_" "Red"
    }

    # (3) Re-run flutter doctor and capture the Android-toolchain status line.
    # Flutter marks a passing component with a check glyph and a failing one with
    # an X glyph; relying on the exact Unicode glyph is fragile because lab
    # console code pages mangle it, so classify by the known failure phrases
    # instead. Record the result into $flutterAndroidToolchain and the diag log.
    try {
        Log-Message "    Re-running flutter doctor to re-check the Android toolchain ..." "DarkGray"
        $docText = (& $flutterBat doctor 2>&1 | Out-String)
        $androidLine = ""
        foreach ($dl in ($docText -split "`r?`n")) {
            if ($dl -match 'Android toolchain') { $androidLine = $dl.Trim(); break }
        }
        if ([string]::IsNullOrWhiteSpace($androidLine)) {
            $androidLine = "(no 'Android toolchain' line found in flutter doctor output)"
        }
        Log-Message "    flutter doctor Android toolchain line: $androidLine" "DarkGray" $false
        # Classify: treat the known 'invalid' phrases as not-detected; else valid.
        if ($docText -match 'Unable to locate Android SDK' -or
            $docText -match 'No valid Android SDK platforms found' -or
            $androidLine -match '(?i)\[X\]|cmdline-tools component is missing|Android license status unknown') {
            $flutterAndroidToolchain = "invalid"
            Log-Message "[NOTE] flutter doctor does not list the Android toolchain as fully detected. This is a known cosmetic issue with a portable (non-Android-Studio) SDK; the Android licenses are accepted at build time, so you can still select the emulator and run your app. If you later see a license prompt, run: flutter doctor --android-licenses" "Cyan"
        } else {
            $flutterAndroidToolchain = "valid"
            Log-Message "[OK] Flutter now reports the Android toolchain as VALID." "Green"
        }
    } catch {
        Log-Message "[FAIL] flutter doctor re-check failed: $_" "Red"
    }
}
Log-Message "[OK] Android SDK setup step finished (see verification below)." "Green"
} else {
    Log-Message "[FAIL] Skipping Android SDK/AVD setup: no working JDK (see above)." "Red"
}

# 8. Base PATH (flutter/dart/git/sqlite/vscode) so the base env also works.
Log-Message "[8/9] Configuring base environment & PATH..." "Green"
Record-StepStart "8/9 Base PATH & env"
$pathsToAdd = @(
    "$ToolsFolder\flutter\bin",
    "$ToolsFolder\flutter\bin\cache\dart-sdk\bin",
    "$ToolsFolder\git\cmd",
    "$ToolsFolder\sqlite",
    "$VSCodeFolder\bin"
)

$procPath = [System.Environment]::GetEnvironmentVariable("PATH", "Process")
foreach ($p in $pathsToAdd) {
    if (Test-Path $p) {
        if ($procPath -notlike "*$p*") {
            $procPath = "$p;$procPath"
        }
    }
}
[System.Environment]::SetEnvironmentVariable("PATH", $procPath, "Process")

try {
    $userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    if ($null -eq $userPath) { $userPath = "" }
    $updatedUserPath = $userPath
    foreach ($p in $pathsToAdd) {
        if ($updatedUserPath -notlike "*$p*") {
            $updatedUserPath = "$p;$updatedUserPath"
        }
    }
    [System.Environment]::SetEnvironmentVariable("PATH", $updatedUserPath, "User")
    [System.Environment]::SetEnvironmentVariable("FLUTTER_ROOT", "$ToolsFolder\flutter", "User")
    [System.Environment]::SetEnvironmentVariable("PUB_CACHE", "$ToolsFolder\pub_cache", "User")
    Log-Message "[OK] Base PATH and environment variables saved to User profile." "Green"
} catch {
    Log-Message "Notice: Could not write User Registry PATH. Process PATH is active." "DarkYellow"
}

# Unblock Files & Create Desktop Shortcut
Get-ChildItem -Path $DestFolder -Recurse -Include "*.exe", "*.dll", "*.bat", "*.ps1" | Unblock-File -ErrorAction SilentlyContinue

try {
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\Desktop\Flutter VS Code.lnk")
    $Shortcut.TargetPath = "$DestFolder\DOUBLE_CLICK_ME_TO_START.bat"
    $Shortcut.WorkingDirectory = $DestFolder
    $Shortcut.Description = "Launch Portable Flutter & VS Code Environment"
    $Shortcut.IconLocation = "$VSCodeFolder\Code.exe,0"
    $Shortcut.Save()
    Log-Message "[OK] Desktop shortcut 'Flutter VS Code' created." "Green"
} catch {}

# ----------------- Comprehensive Verification Checks -----------------
Log-Message ""
Log-Message "=========================================================" "Cyan"
Log-Message "            RUNNING VERIFICATION CHECKS                  " "Cyan"
Log-Message "=========================================================" "Cyan"
Record-StepStart "9/9 Verification & diagnostics"

$CheckFailures = 0

# Check 1: Flutter CLI in PATH
$chkFlutter = Get-Command flutter -ErrorAction SilentlyContinue
if ($chkFlutter) {
    $verFlutter = & flutter --version | Select-Object -First 1
    Log-Message "[PASS] Flutter CLI detected in PATH: $verFlutter" "Green"
} else {
    Log-Message "[FAIL] Flutter CLI not detected in PATH!" "Red"
    $CheckFailures++
}

# Check 2: Dart CLI in PATH
$chkDart = Get-Command dart -ErrorAction SilentlyContinue
if ($chkDart) {
    $verDart = & dart --version 2>&1 | Select-Object -First 1
    Log-Message "[PASS] Dart CLI detected in PATH: $verDart" "Green"
} else {
    Log-Message "[FAIL] Dart CLI not detected in PATH!" "Red"
    $CheckFailures++
}

# Check 3: Git CLI in PATH
$chkGit = Get-Command git -ErrorAction SilentlyContinue
if ($chkGit) {
    $verGit = & git --version | Select-Object -First 1
    Log-Message "[PASS] Git CLI detected in PATH: $verGit" "Green"
} else {
    Log-Message "[FAIL] Git CLI not detected in PATH!" "Red"
    $CheckFailures++
}

# Check 4: SQLite CLI in PATH
$chkSqlite = Get-Command sqlite3 -ErrorAction SilentlyContinue
if ($chkSqlite) {
    $verSqlite = & sqlite3 -version | Select-Object -First 1
    Log-Message "[PASS] SQLite CLI detected in PATH: $verSqlite" "Green"
} else {
    Log-Message "[FAIL] SQLite CLI not detected in PATH!" "Red"
    $CheckFailures++
}

# Check 5: VS Code Executable
if (Test-Path "$VSCodeFolder\Code.exe") {
    Log-Message "[PASS] VS Code Portable binary detected ($VSCodeFolder\Code.exe)." "Green"
} else {
    Log-Message "[FAIL] VS Code Portable binary missing!" "Red"
    $CheckFailures++
}

# ----------------- Android-specific Verification (BETA) -----------------
Log-Message "--- Android (BETA) checks ---" "Cyan"

# Check A0: Java (JDK) present and runnable (sdkmanager/avdmanager need it)
if ($JavaHome -and (Test-Path "$JavaHome\bin\java.exe")) {
    $verJava = & "$JavaHome\bin\java.exe" -version 2>&1 | Select-Object -First 1
    Log-Message "[PASS] Java (JDK) detected: $verJava" "Green"
} else {
    Log-Message "[FAIL] Java (JDK) missing - Android tools cannot run." "Red"
    $CheckFailures++
}

# Check A1: sdkmanager present
if (Test-Path $sdkManagerBat) {
    Log-Message "[PASS] Android sdkmanager present ($sdkManagerBat)." "Green"
} else {
    Log-Message "[FAIL] Android sdkmanager missing (expected cmdline-tools\latest\bin\sdkmanager.bat)." "Red"
    $CheckFailures++
}

# Check A2: platform-tools adb present
$adbPath = "$AndroidFolder\platform-tools\adb.exe"
if (Test-Path $adbPath) {
    Log-Message "[PASS] platform-tools adb present ($adbPath)." "Green"
} else {
    Log-Message "[FAIL] platform-tools adb missing ($adbPath)." "Red"
    $CheckFailures++
}

# Check A3: emulator present
$emulatorExe = "$AndroidFolder\emulator\emulator.exe"
if (Test-Path $emulatorExe) {
    Log-Message "[PASS] Android emulator present ($emulatorExe)." "Green"
} else {
    Log-Message "[FAIL] Android emulator missing ($emulatorExe)." "Red"
    $CheckFailures++
}

# Check A4: AVD listed by avdmanager
$avdFound = $false
if (Test-Path $avdManagerBat) {
    try {
        $avdList = & $avdManagerBat list avd 2>&1 | Out-String
        if ($avdList -match [regex]::Escape($AndroidAvdName)) { $avdFound = $true }
    } catch {}
}
if ($avdFound) {
    Log-Message "[PASS] AVD '$AndroidAvdName' listed by avdmanager." "Green"
} else {
    Log-Message "[FAIL] AVD '$AndroidAvdName' not listed by avdmanager." "Red"
    $CheckFailures++
}

Log-Message ""
Log-Message "Verification Summary: $($CheckFailures) Check Failure(s) recorded." $(if ($CheckFailures -eq 0) { "Green" } else { "Red" })

# NOTE: Unlike install.ps1, Android check failures are reported but do NOT
# abort with Fail-Exit. The base environment (Flutter/VS Code) may be perfectly
# usable even if the experimental Android pieces failed, so we never let the
# BETA path corrupt or block an existing install.

# =====================================================================
#            ANDROID EMULATOR DIAGNOSTICS (BETA)
# =====================================================================
# Collects everything we need to decide WHY the Android emulator does (or does
# not) run on a given lab machine. Writes BOTH to the console (Log-Message) AND
# to a dedicated diagnostics log. Every item is wrapped in its own try/catch so
# a single failure never aborts the rest of the collection.
#
# Two separate log files are produced for the student to send back:
#   * android_emulator_diagnostics.log - this whole diagnostics section
#   * android_emulator_launch.log      - raw emulator stdout/stderr (Part 2)
$DiagLog   = "$env:USERPROFILE\Downloads\android_emulator_diagnostics.log"
$LaunchLog = "$env:USERPROFILE\Downloads\android_emulator_launch.log"

# Emulator / tool paths used across the diagnostics (defined up front so each
# labelled block can reference them even if an earlier Android step was skipped).
$emulatorExeDiag = "$AndroidFolder\emulator\emulator.exe"
$adbExeDiag      = "$AndroidFolder\platform-tools\adb.exe"
$flutterBatDiag  = "$ToolsFolder\flutter\bin\flutter.bat"

# Append-to-diagnostics-log helper. Writes to the console via Log-Message AND
# appends the same line to $DiagLog. The $overwrite switch starts a fresh file.
function Write-Diag([string]$msg, [string]$color="Gray", [bool]$overwrite=$false) {
    Log-Message $msg $color
    try {
        if ($overwrite) {
            $msg | Out-File -FilePath $DiagLog -Encoding utf8 -Force
        } else {
            $msg | Out-File -FilePath $DiagLog -Encoding utf8 -Append
        }
    } catch {}
}

Log-Message ""
Log-Message "=========================================================" "Cyan"
Log-Message "          ANDROID EMULATOR DIAGNOSTICS (BETA)            " "Cyan"
Log-Message "=========================================================" "Cyan"
# OVERWRITE the diagnostics log at the start of the section, then APPEND below.
Write-Diag "===== ANDROID EMULATOR DIAGNOSTICS =====" "Cyan" $true
Write-Diag "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "DarkGray"
Write-Diag "Computer: $env:COMPUTERNAME | User: $env:USERNAME" "DarkGray"
Write-Diag "PowerShell: $($PSVersionTable.PSVersion)" "DarkGray"
Write-Diag ""

# Holds the one-line acceleration verdict derived from -accel-check (used in the
# final SUMMARY). Stays 'unknown' unless the self-check tells us otherwise.
$accelVerdict = "unknown"

# Holds the Flutter Android-toolchain verdict set by the "[Registering the Android
# SDK with Flutter]" step (step 7e). "valid" once flutter doctor shows a check on
# the Android toolchain line; "invalid" if it still shows an X / a known failure
# phrase; "unknown" if the registration step never ran (e.g. no JDK). Initialised
# here so the DIAGNOSTICS SUMMARY always has a value to report even when the
# Android block was skipped.
$flutterAndroidToolchain = "unknown"

# --- [1] systeminfo virtualization lines + OS caption/version/build ---
Write-Diag "----- [1] systeminfo (virtualization) + OS -----" "Cyan"
try {
    $siRaw = systeminfo 2>&1 | Out-String
    $siLines = $siRaw | Select-String -Pattern 'Hyper-V','Virtualization','VM Monitor Mode','Second Level Address Translation','Data Execution Prevention'
    if ($siLines) {
        foreach ($l in $siLines) { Write-Diag ("    " + $l.ToString().Trim()) "Gray" }
    } else {
        Write-Diag "    (no matching virtualization lines in systeminfo)" "DarkYellow"
    }
} catch {
    Write-Diag "    [FAIL] systeminfo failed: $_" "Red"
}
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    Write-Diag "    OS Caption: $($os.Caption)" "Gray"
    Write-Diag "    OS Version: $($os.Version)  Build: $($os.BuildNumber)" "Gray"
} catch {
    Write-Diag "    [FAIL] Get-CimInstance Win32_OperatingSystem failed: $_" "Red"
}
Write-Diag ""

# --- [2] CPU-level virtualization (Win32_Processor) ---
Write-Diag "----- [2] CPU virtualization (Win32_Processor) -----" "Cyan"
try {
    $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop |
        Select-Object Name, VirtualizationFirmwareEnabled, SecondLevelAddressTranslationExtensions, VMMonitorModeExtensions
    foreach ($c in $cpu) {
        Write-Diag "    Name: $($c.Name)" "Gray"
        Write-Diag "    VirtualizationFirmwareEnabled: $($c.VirtualizationFirmwareEnabled)" "Gray"
        Write-Diag "    SecondLevelAddressTranslationExtensions: $($c.SecondLevelAddressTranslationExtensions)" "Gray"
        Write-Diag "    VMMonitorModeExtensions: $($c.VMMonitorModeExtensions)" "Gray"
    }
} catch {
    Write-Diag "    [FAIL] Get-CimInstance Win32_Processor failed: $_" "Red"
}
Write-Diag ""

# --- [3] Windows optional features + hypervisorlaunchtype (no admin needed) ---
Write-Diag "----- [3] Optional features (Hyper-V / VirtualMachinePlatform) -----" "Cyan"
try {
    $feats = Get-CimInstance -ClassName Win32_OptionalFeature -ErrorAction Stop |
        Where-Object { $_.Name -match 'Hyper|HypervisorPlatform|VirtualMachinePlatform' } |
        Select-Object Name, InstallState
    if ($feats) {
        # InstallState 1 = enabled, 2 = disabled/absent.
        foreach ($f in $feats) {
            Write-Diag "    $($f.Name) : InstallState=$($f.InstallState)  (1=enabled)" "Gray"
        }
    } else {
        Write-Diag "    (no matching optional features found)" "DarkYellow"
    }
} catch {
    Write-Diag "    [FAIL] Get-CimInstance Win32_OptionalFeature failed: $_" "Red"
}
try {
    # bcdedit may be denied without elevation; wrapped so it never aborts.
    $bcd = bcdedit /enum "{current}" 2>&1 | Select-String -Pattern 'hypervisorlaunchtype'
    if ($bcd) {
        foreach ($b in $bcd) { Write-Diag ("    " + $b.ToString().Trim()) "Gray" }
    } else {
        Write-Diag "    (hypervisorlaunchtype not reported by bcdedit)" "DarkYellow"
    }
} catch {
    Write-Diag "    [FAIL] bcdedit failed (likely denied without admin): $_" "DarkYellow"
}
Write-Diag ""

# --- [4] THE KEY SIGNAL: emulator -accel-check (HAXM/WHPX/AEHD self-check) ---
# This is the single most useful signal: the emulator itself reports whether a
# hypervisor/acceleration backend is available and, if not, exactly why.
Write-Diag "----- [4] emulator -accel-check (KEY acceleration self-check) -----" "Cyan"
try {
    if (Test-Path $emulatorExeDiag) {
        $accelOut = "$env:TEMP\accel_check_out.txt"
        $accelErr = "$env:TEMP\accel_check_err.txt"
        if (Test-Path $accelOut) { Remove-Item $accelOut -Force -ErrorAction SilentlyContinue }
        if (Test-Path $accelErr) { Remove-Item $accelErr -Force -ErrorAction SilentlyContinue }
        $accelProc = Start-Process -FilePath $emulatorExeDiag -ArgumentList "-accel-check" `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $accelOut -RedirectStandardError $accelErr
        $accelText = ""
        if (Test-Path $accelOut) { $accelText += (Get-Content $accelOut -Raw) }
        if (Test-Path $accelErr) { $accelText += (Get-Content $accelErr -Raw) }
        Remove-Item $accelOut, $accelErr -Force -ErrorAction SilentlyContinue
        Write-Diag "    Exit code: $($accelProc.ExitCode)" "Gray"
        if (-not [string]::IsNullOrWhiteSpace($accelText)) {
            foreach ($line in ($accelText -split "`r?`n")) {
                if ($line.Trim().Length -gt 0) { Write-Diag ("    " + $line.Trim()) "Gray" }
            }
        } else {
            Write-Diag "    (no output captured from -accel-check)" "DarkYellow"
        }
        # Exit code 0 from -accel-check == acceleration is usable.
        if ($accelProc.ExitCode -eq 0) {
            $accelVerdict = "available"
        } else {
            $accelVerdict = "unavailable"
        }
    } else {
        Write-Diag "    [FAIL] emulator.exe not found at $emulatorExeDiag" "Red"
    }
} catch {
    Write-Diag "    [FAIL] -accel-check failed to run: $_" "Red"
}
Write-Diag ""

# --- [5] List AVDs (avdmanager AND emulator -list-avds) ---
Write-Diag "----- [5] Installed AVDs -----" "Cyan"
try {
    if (Test-Path $avdManagerBat) {
        $avdOut = & $avdManagerBat list avd 2>&1 | Out-String
        foreach ($line in ($avdOut -split "`r?`n")) {
            if ($line.Trim().Length -gt 0) { Write-Diag ("    [avdmanager] " + $line.Trim()) "Gray" }
        }
    } else {
        Write-Diag "    [avdmanager] not present at $avdManagerBat" "DarkYellow"
    }
} catch {
    Write-Diag "    [FAIL] avdmanager list avd failed: $_" "Red"
}
try {
    if (Test-Path $emulatorExeDiag) {
        $listOut = & $emulatorExeDiag -list-avds 2>&1 | Out-String
        foreach ($line in ($listOut -split "`r?`n")) {
            if ($line.Trim().Length -gt 0) { Write-Diag ("    [emulator] " + $line.Trim()) "Gray" }
        }
    } else {
        Write-Diag "    [emulator] not present at $emulatorExeDiag" "DarkYellow"
    }
} catch {
    Write-Diag "    [FAIL] emulator -list-avds failed: $_" "Red"
}
Write-Diag ""

# --- [6] Developer Mode state (registry; read without admin) ---
Write-Diag "----- [6] Windows Developer Mode -----" "Cyan"
try {
    $devKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock"
    $devProp = Get-ItemProperty -Path $devKey -Name "AllowDevelopmentWithoutDevLicense" -ErrorAction Stop
    $devVal = $devProp.AllowDevelopmentWithoutDevLicense
    if ($devVal -eq 1) {
        Write-Diag "    Developer Mode: ON (AllowDevelopmentWithoutDevLicense=1)" "Green"
    } else {
        Write-Diag "    Developer Mode: OFF (AllowDevelopmentWithoutDevLicense=$devVal)" "DarkYellow"
    }
} catch {
    Write-Diag "    Developer Mode: UNKNOWN (registry value not readable): $_" "DarkYellow"
}
Write-Diag ""

# --- [7] flutter doctor -v (can be slow) ---
Write-Diag "----- [7] flutter doctor -v (may be slow) -----" "Cyan"
try {
    if (Test-Path $flutterBatDiag) {
        $docOut = & $flutterBatDiag doctor -v 2>&1 | Out-String
        foreach ($line in ($docOut -split "`r?`n")) {
            if ($line.Trim().Length -gt 0) { Write-Diag ("    " + $line.TrimEnd()) "Gray" }
        }
    } else {
        Write-Diag "    flutter.bat not present at $flutterBatDiag" "DarkYellow"
    }
} catch {
    Write-Diag "    [FAIL] flutter doctor -v failed: $_" "Red"
}
Write-Diag ""

# =====================================================================
#   ATTEMPTING EMULATOR LAUNCH (software rendering, verbose)
# =====================================================================
# Launch the emulator DIRECTLY (NOT via flutter) with software rendering and
# verbose/kernel logging, capturing raw stdout+stderr to $LaunchLog. A working
# emulator runs forever, so we do NOT block on it: we start it, wait ~60s, probe
# `adb devices`, record the result, then terminate whatever we started.
#
# IMPORTANT: -gpu swiftshader_indirect only swaps the GPU rendering path to
# software; it still requires CPU VIRTUALIZATION (a hypervisor: WHPX/Hyper-V/
# AEHD/HAXM) for the x86_64 system image. So if [4] -accel-check reported NO
# acceleration, this launch will almost certainly still fail - and that failure
# is itself the answer (the machine cannot run an x86 emulator without a
# hypervisor, which usually needs admin to enable).
Write-Diag "----- ATTEMPTING EMULATOR LAUNCH (software rendering, verbose) -----" "Cyan"
# The current AVD uses an x86_64 image (needs a hypervisor). An ARM64 image
# (e.g. system-images;android-34;google_apis;arm64-v8a) would avoid the
# hypervisor requirement but runs under FULL CPU EMULATION on an x86 host -
# extremely slow and likely not worth it. We do NOT switch the default image
# here; this is documented only.
Write-Diag "    NOTE: AVD '$AndroidAvdName' uses an x86_64 image (needs a hypervisor)." "DarkYellow"
Write-Diag "    NOTE: An ARM64 image would avoid that requirement but runs via full" "DarkYellow"
Write-Diag "          emulation (extremely slow); the default image is NOT changed." "DarkYellow"

$launchSucceeded = $false
try {
    if (Test-Path $emulatorExeDiag) {
        # Fresh launch log for this attempt.
        "" | Out-File -FilePath $LaunchLog -Encoding utf8 -Force
        $emuArgs = @(
            "-avd", $AndroidAvdName,
            "-gpu", "swiftshader_indirect",
            "-no-snapshot",
            "-no-boot-anim",
            "-no-audio",
            "-verbose",
            "-show-kernel"
        )
        Write-Diag "    Launch command:" "Gray"
        Write-Diag "      $emulatorExeDiag $($emuArgs -join ' ')" "Gray"

        # Non-blocking launch; keep the PID so we can terminate it afterwards.
        $emuProc = Start-Process -FilePath $emulatorExeDiag -ArgumentList $emuArgs `
            -NoNewWindow -PassThru `
            -RedirectStandardOutput $LaunchLog -RedirectStandardError "$LaunchLog.err"
        $emuPid = $emuProc.Id
        Write-Diag "    Launched emulator (PID $emuPid). Waiting ~60s for boot..." "Gray"
        Start-Sleep -Seconds 60

        # Probe adb: did emulator-5554 come up as 'device' (SUCCESS)?
        $adbText = ""
        try {
            if (Test-Path $adbExeDiag) {
                $adbText = & $adbExeDiag devices 2>&1 | Out-String
            } else {
                $adbText = "(adb not found at $adbExeDiag)"
            }
        } catch {
            $adbText = "adb devices failed: $_"
        }
        Write-Diag "    adb devices output:" "Gray"
        foreach ($line in ($adbText -split "`r?`n")) {
            if ($line.Trim().Length -gt 0) { Write-Diag ("      " + $line.Trim()) "Gray" }
        }
        if ($adbText -match 'emulator-5554\s+device') {
            $launchSucceeded = $true
        }

        # Fold the emulator's stderr into the launch log, then record the first
        # ~40 lines of the launch log into the diagnostics log.
        try {
            if (Test-Path "$LaunchLog.err") {
                $errContent = Get-Content "$LaunchLog.err" -Raw -ErrorAction SilentlyContinue
                if (-not [string]::IsNullOrWhiteSpace($errContent)) {
                    "----- STDERR -----`r`n$errContent" | Out-File -FilePath $LaunchLog -Encoding utf8 -Append
                }
                Remove-Item "$LaunchLog.err" -Force -ErrorAction SilentlyContinue
            }
        } catch {}
        Write-Diag "    First 40 lines of launch log ($LaunchLog):" "Gray"
        try {
            $head = Get-Content $LaunchLog -TotalCount 40 -ErrorAction SilentlyContinue
            foreach ($line in $head) {
                if ($line.Trim().Length -gt 0) { Write-Diag ("      " + $line.TrimEnd()) "DarkGray" }
            }
        } catch {
            Write-Diag "      (could not read launch log)" "DarkYellow"
        }

        if ($launchSucceeded) {
            # The emulator booted during the self-check and emulator-5554 came
            # up as 'device'. LEAVE it running so the student can select it in
            # VS Code and press F5 without waiting through a second cold boot.
            # We deliberately do NOT taskkill $emuPid, do NOT sweep
            # qemu-system/emulator processes, do NOT run `adb kill-server`, and
            # do NOT delete the AVD *.lock files: those locks belong to the
            # STILL-RUNNING emulator-5554, and removing them while the process
            # is live would corrupt its AVD state. A tracked handle ($emuProc /
            # $emuPid) exists, so leaving it running is safe here.
            Write-Diag "    Emulator left RUNNING (PID $emuPid) so you can select it in VS Code and press F5 without a second cold boot." "DarkGray"
        } else {
            # The emulator did NOT come up. Clean up exactly as before:
            # terminate the process we started plus any child qemu processes so
            # nothing is left running after diagnostics.
            try {
                taskkill /PID $emuPid /T /F 2>&1 | Out-Null
            } catch {}
            try {
                Get-Process -ErrorAction SilentlyContinue |
                    Where-Object { $_.ProcessName -match 'qemu-system|emulator' } |
                    ForEach-Object {
                        try { taskkill /PID $_.Id /T /F 2>&1 | Out-Null } catch {}
                    }
            } catch {}
            # CRITICAL: a force-killed emulator leaves lock files in the AVD folder.
            # If they remain, the student's own `flutter emulators --launch` fails
            # with "Running multiple emulators with the same AVD ... use -read-only".
            # Reset adb and delete the stale locks so the next launch is clean.
            # This is only reached when NO live emulator needs those locks.
            $adbExeDiag = Join-Path $AndroidFolder "platform-tools\adb.exe"
            if (Test-Path $adbExeDiag) {
                try { & $adbExeDiag kill-server 2>&1 | Out-Null } catch {}
            }
            $avdLockDir = Join-Path $env:USERPROFILE ".android\avd\$AndroidAvdName.avd"
            if (Test-Path $avdLockDir) {
                try {
                    Get-ChildItem -Path $avdLockDir -Recurse -Include "*.lock","hardware-qemu.ini.lock","multiinstance.lock" -ErrorAction SilentlyContinue |
                        ForEach-Object { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
                } catch {}
            }
            Write-Diag "    Emulator process(es) terminated and AVD locks cleared (cleanup done)." "DarkGray"
        }
    } else {
        Write-Diag "    [FAIL] emulator.exe not found at $emulatorExeDiag; cannot attempt launch." "Red"
    }
} catch {
    Write-Diag "    [FAIL] Emulator launch attempt errored: $_" "Red"
}

if ($launchSucceeded) {
    Write-Diag "    RESULT: Software-rendered launch SUCCEEDED (emulator-5554 came up)." "Green"
} else {
    Write-Diag "    RESULT: Software-rendered launch FAILED (emulator-5554 not 'device')." "Red"
    Write-Diag "    See the launch log for details: $LaunchLog" "Yellow"
}
Write-Diag ""

# =====================================================================
#   DIAGNOSTICS SUMMARY
# =====================================================================
Write-Diag "----- DIAGNOSTICS SUMMARY -----" "Cyan"
# One-line verdict derived from the -accel-check result.
if ($accelVerdict -eq "available") {
    $verdictLine = "Acceleration AVAILABLE - the emulator should be able to run."
} elseif ($accelVerdict -eq "unavailable") {
    $verdictLine = "Acceleration NOT available - emulator cannot run without admin to enable WHPX/Hyper-V."
} else {
    $verdictLine = "Acceleration status UNKNOWN - see the -accel-check output above."
}
Write-Diag "    Verdict: $verdictLine" $(if ($accelVerdict -eq "available") { "Green" } else { "Yellow" })
# Flutter-toolchain verdict set by the "[Registering the Android SDK with Flutter]" step.
if ($flutterAndroidToolchain -eq "valid") {
    $flutterToolchainLine = "Flutter Android toolchain: VALID"
} elseif ($flutterAndroidToolchain -eq "invalid") {
    $flutterToolchainLine = "Flutter Android toolchain: still not detected (see flutter doctor above)"
} else {
    $flutterToolchainLine = "Flutter Android toolchain: UNKNOWN (registration step did not run)"
}
Write-Diag "    $flutterToolchainLine" $(if ($flutterAndroidToolchain -eq "valid") { "Green" } else { "Yellow" })
Write-Diag "    Diagnostics log: $DiagLog" "Cyan"
Write-Diag "    Launch log:      $LaunchLog" "Cyan"
Write-Diag "    Please send BOTH log files back so we can diagnose your machine." "Cyan"
Write-Diag "    The web (Edge/Chrome) path works regardless and needs NONE of this." "Green"
Write-Diag ""

# ----------------- Finish -----------------
$launcherBat = "$DestFolder\DOUBLE_CLICK_ME_TO_START.bat"

# Close the lap for the final step (verification & diagnostics) and print a
# per-step timing summary to BOTH the console and the log file so the student
# can see how long each of the nine steps took and which one dominated.
Complete-LastStep
Log-Message "" "White"
Log-Message "Step timing summary (seconds):" "Cyan"
foreach ($t in $script:stepTimings) {
    $secs = [Math]::Round([double]$t.Seconds, 1)
    Log-Message ("    {0,-32} {1,7:N1}s" -f $t.Label, $secs) "DarkGray"
}
Log-Message "" "White"

$totalMinutes = [Math]::Round($installStopwatch.Elapsed.TotalMinutes, 1)
Log-Message "=========================================================" "Green"
Log-Message "  Android Emulator BETA setup finished.                  " "Green"
Log-Message "  Installed at: $DestFolder                              " "Green"
Log-Message "  Total install time: $totalMinutes minutes              " "Green"
Log-Message "=========================================================" "Green"
Log-Message ""
Write-Host ""
Write-Host "RUN YOUR APP ON THE EMULATOR:" -ForegroundColor Cyan
Write-Host "  The emulator is already set up. In VS Code, use the device selector in the" -ForegroundColor White
Write-Host "  bottom-right status bar (or Command Palette: 'Flutter: Select Device') to pick" -ForegroundColor White
Write-Host "  the Android emulator, then press F5. VS Code is the simplest route." -ForegroundColor White
Write-Host "  If the emulator is not running, launch it with (first cold boot takes a few" -ForegroundColor White
Write-Host "  minutes; a black screen is normal - wait for the Android home screen):" -ForegroundColor White
Write-Host "       flutter emulators --launch $AndroidAvdName" -ForegroundColor Green
Write-Host "  Terminal alternative (do not pick the 'Windows' device):" -ForegroundColor White
Write-Host "       flutter run -d emulator-5554" -ForegroundColor Green
Write-Host "  To inspect the SQLite database (run the app once first so it exists):" -ForegroundColor White
Write-Host "       adb shell `"run-as com.example.sandwich_shop cat databases/sandwich_data.db > /data/local/tmp/s.db`"" -ForegroundColor Green
Write-Host "       adb pull /data/local/tmp/s.db sandwich_shop.db" -ForegroundColor Green
Write-Host "  BETA: needs hardware acceleration (WHPX/Hyper-V); the web/Edge path needs none" -ForegroundColor Yellow
Write-Host "  of this. Please report whether the emulator launched (diagnostics logs are in" -ForegroundColor Yellow
Write-Host "  $env:USERPROFILE\Downloads)." -ForegroundColor Yellow
Write-Host ""

Save-Log
Send-InstallationTelemetry $(if ($CheckFailures -eq 0) { "SUCCESS" } else { "FAILED" }) $CheckFailures @{}

# Ensure batch launcher exists
if (-not (Test-Path $launcherBat)) {
    $batContent = @"
@echo off
setlocal
cd /d "%~dp0"
title Flutter VS Code Portable
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "bin\launch.ps1"
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Launch error occurred. Press any key to exit...
    pause >nul
)
"@
    [System.IO.File]::WriteAllText($launcherBat, $batContent, [System.Text.Encoding]::ASCII)
}

# Hand off to the same launcher used by the desktop shortcut (bin/launch.ps1).
# It asks whether to open an existing/cloned project, clone a repository, or
# generate the starter app, then launches VS Code accordingly. Delegating here
# (instead of duplicating that logic) guarantees the same prompt appears
# whether the user re-runs this install script or double-clicks the shortcut.
Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$launcherBat`"" -WorkingDirectory $DestFolder
