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
$UrlJdkPrimary  = "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.9+9.1/OpenJDK17U-jdk_x64_windows_hotspot_17.0.9_9.zip"
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
$FlutterVersion    = "3.47.5"
$UrlFlutter        = "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_$FlutterVersion-stable.zip"
$UrlGit            = "https://github.com/git-for-windows/git/releases/download/v2.44.0.windows.1/MinGit-2.44.0-64-bit.zip"
$UrlSQLite         = "https://www.sqlite.org/2024/sqlite-tools-win-x64-3450300.zip"

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
$codeCmd = "$VSCodeFolder\bin\code.cmd"
$extDir  = "$VSCodeFolder\data\extensions"
$userDataDir = "$VSCodeFolder\data\user-data"

foreach ($ext in $RequiredExtensions) {
    Log-Message "Installing extension: $ext..." "DarkGray"
    $installed = $false
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        try {
            & $codeCmd --extensions-dir $extDir --user-data-dir $userDataDir --install-extension $ext --force 2>&1 | Out-Null
            $installed = $true
            break
        } catch {
            Start-Sleep -Milliseconds 500
        }
    }
    if (-not $installed) {
        Log-Message "Warning: Failed to install extension $ext via CLI: $_" "DarkYellow"
    }
}

# 6.5 Lock down Extension Marketplace (Prevent installing further extensions)
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

# ===================== 6.9 PORTABLE JDK (BETA) =====================
# sdkmanager/avdmanager need Java. Download & extract a no-admin Temurin JDK 17
# into $JdkFolder, resolve $JavaHome, wire JAVA_HOME + PATH (Process & User),
# and verify. The Android steps below are gated on $JavaHome being set.
Log-Message "[6/9] Setting up portable JDK (BETA)..." "Green"

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

# 7e. Point Flutter at the Android SDK if flutter is available.
$flutterBat = "$ToolsFolder\flutter\bin\flutter.bat"
if (Test-Path $flutterBat) {
    Log-Message "Pointing Flutter at the Android SDK..." "DarkGray"
    Invoke-AndroidTool $flutterBat @("config", "--android-sdk", $AndroidFolder) $null "flutter config --android-sdk" | Out-Null
}
Log-Message "[OK] Android SDK setup step finished (see verification below)." "Green"
} else {
    Log-Message "[FAIL] Skipping Android SDK/AVD setup: no working JDK (see above)." "Red"
}

# 8. Base PATH (flutter/dart/git/sqlite/vscode) so the base env also works.
Log-Message "[8/9] Configuring base environment & PATH..." "Green"
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

# ----------------- Finish -----------------
$launcherBat = "$DestFolder\DOUBLE_CLICK_ME_TO_START.bat"

Log-Message "=========================================================" "Green"
Log-Message "  Android Emulator BETA setup finished.                  " "Green"
Log-Message "  Installed at: $DestFolder                              " "Green"
Log-Message "=========================================================" "Green"
Log-Message ""
Write-Host ""
Write-Host "HOW TO LAUNCH THE EMULATOR:" -ForegroundColor Cyan
Write-Host "  1. Open a NEW terminal (so the updated PATH is loaded), then run:" -ForegroundColor White
Write-Host "       flutter emulators --launch $AndroidAvdName" -ForegroundColor Green
Write-Host "  2. Wait for the emulator window to appear, then in your project run:" -ForegroundColor White
Write-Host "       flutter run" -ForegroundColor Green
Write-Host ""
Write-Host "==========================================================================" -ForegroundColor Yellow
Write-Host "  IMPORTANT BETA / EXPERIMENTAL CAVEATS - PLEASE READ" -ForegroundColor Yellow
Write-Host "==========================================================================" -ForegroundColor Yellow
Write-Host "  * The Android emulator needs HARDWARE ACCELERATION (WHPX / Hyper-V on" -ForegroundColor White
Write-Host "    Windows, or HAXM on older machines). Many locked-down lab machines" -ForegroundColor White
Write-Host "    DISABLE virtualization or forbid enabling it without admin rights." -ForegroundColor White
Write-Host "    On such hardware the emulator will NOT launch even though this" -ForegroundColor White
Write-Host "    installer reported success." -ForegroundColor White
Write-Host "  * The Android SDK + system image download is MULTIPLE GIGABYTES." -ForegroundColor White
Write-Host "  * This is an EXPERIMENTAL / BETA path and is UNTESTED on lab hardware." -ForegroundColor White
Write-Host "  * A portable JDK is now downloaded and configured AUTOMATICALLY by this" -ForegroundColor White
Write-Host "    script (no manual Java install needed)." -ForegroundColor White
Write-Host "  * Your existing install.ps1 environment is NOT affected by this script." -ForegroundColor White
Write-Host "" -ForegroundColor White
Write-Host "  >> PLEASE REPORT BACK whether the emulator actually LAUNCHES on your" -ForegroundColor Magenta
Write-Host "     machine (yes/no + any error), so we know if this path is viable." -ForegroundColor Magenta
Write-Host "==========================================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "RUNNING A FLUTTER PROJECT ON THE EMULATOR:" -ForegroundColor Cyan
Write-Host "  A Flutter project must have Android enabled to run on the emulator." -ForegroundColor White
Write-Host "  If your project has no 'android/' folder, enable it first by running" -ForegroundColor White
Write-Host "  this INSIDE the project folder:" -ForegroundColor White
Write-Host "       flutter create --platforms=android ." -ForegroundColor Green
Write-Host "  Then launch the emulator and run on it:" -ForegroundColor White
Write-Host "       flutter run -d emulator-5554" -ForegroundColor Green
Write-Host ""

Save-Log
Send-InstallationTelemetry $(if ($CheckFailures -eq 0) { "SUCCESS" } else { "FAILED" }) $CheckFailures @{}
