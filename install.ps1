<#
.SYNOPSIS
    Installs the Portable Flutter & VS Code development environment.
.DESCRIPTION
    Designed for non-admin University Lab Windows machines.
    Downloads, extracts, configures, and verifies:
      - VS Code Portable x64
      - Flutter SDK & Dart SDK
      - MinGit CLI
      - SQLite CLI Tools
      - Agreed VS Code Extensions (Flutter, Dart, Copilot, PRs, ErrorLens, Icons, SQLite Viewer)
      - Default Flutter Settings, Auto-save, and Edge Web debugging
      - Permanent User PATH and environment variables
.USAGE
    From PowerShell:
      irm https://raw.githubusercontent.com/manighahrmani/flutter_vscode_package/main/install.ps1 | iex
#>

$ErrorActionPreference = "Continue"

$DestFolder   = "$env:USERPROFILE\Downloads\flutter_vscode_package"
$ToolsFolder  = "$DestFolder\tools"
$VSCodeFolder = "$DestFolder\vscode"
$LogPath      = "$env:USERPROFILE\Downloads\flutter_vscode_install.log"
$SupportEmail = "mani.ghahremani@port.ac.uk"
$IssuesUrl    = "https://github.com/manighahrmani/flutter_vscode_package/issues"

# Component Download URLs
$UrlPackageRelease = "https://github.com/manighahrmani/flutter_vscode_package/releases/latest/download/flutter_vscode_package.zip"
$UrlVSCode         = "https://update.code.visualstudio.com/latest/win32-x64-archive/stable"
$UrlFlutter        = "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.24.5-stable.zip"
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
            choice        = "Portable Flutter & VS Code Installation"
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

# ----------------- Helper Functions -----------------
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

# ----------------- Remote Telemetry Dispatcher -----------------
$TelemetryEndpoint = "" # Set Google Apps Script / Cloud Webhook URL to receive live telemetry
function Send-InstallationTelemetry([string]$status, [int]$checkFailures, [hashtable]$timings) {
    if (-not $TelemetryEndpoint -or $TelemetryEndpoint.Trim() -eq "") {
        return
    }
    try {
        $payload = @{
            timestamp        = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            user             = $env:USERNAME
            computer         = $env:COMPUTERNAME
            os               = [System.Environment]::OSVersion.VersionString
            psVersion        = "$($PSVersionTable.PSVersion)"
            status           = $status
            checkFailures    = $checkFailures
            timings          = $timings
            log              = ($logEntries -join "`n")
        } | ConvertTo-Json -Depth 5

        # Asynchronous non-blocking HTTP POST
        [System.Threading.Tasks.Task]::Run([Action]{
            try {
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
                $req = [System.Net.WebRequest]::Create($TelemetryEndpoint)
                $req.Method = "POST"
                $req.ContentType = "application/json"
                $req.ContentLength = $bytes.Length
                $req.Timeout = 4000
                $stream = $req.GetRequestStream()
                $stream.Write($bytes, 0, $bytes.Length)
                $stream.Close()
                $resp = $req.GetResponse()
                $resp.Close()
            } catch {}
        }) | Out-Null
    } catch {}
}

# ----------------- Start Installation -----------------
Clear-Host
Log-Message "=========================================================" "Cyan"
Log-Message "     Portable Flutter & VS Code Environment Setup        " "Cyan"
Log-Message "=========================================================" "Cyan"
Log-Message "Target Directory: $DestFolder" "DarkGray"
Log-Message "Log File:         $LogPath" "DarkGray"
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
if (Test-Path $DestFolder) {
    Log-Message "Existing installation found at: $DestFolder" "Yellow"
    $choice = Read-Host "Do you want to re-install / verify? (y/N)"
    if ($choice -ne 'y' -and $choice -ne 'Y') {
        Log-Message "Launching existing installation..." "Green"
        Save-Log
        Start-Process "$DestFolder\DOUBLE_CLICK_ME_TO_START.bat" -WorkingDirectory $DestFolder
        exit 0
    }
}

# Ensure Directory Hierarchy
$dirs = @(
    $DestFolder,
    "$ToolsFolder\flutter",
    "$ToolsFolder\git",
    "$ToolsFolder\sqlite",
    "$ToolsFolder\pub_cache",
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
Log-Message "[1/6] Setting up base launcher scripts and configuration..." "Green"
$pkgZip = "$env:TEMP\flutter_vscode_pkg.zip"
if (Download-FileWithRetry $UrlPackageRelease $pkgZip "Package Template") {
    Extract-ZipArchive $pkgZip $DestFolder "Base Launcher & Config Template" | Out-Null
    Remove-Item $pkgZip -Force -ErrorAction SilentlyContinue
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
  "update.mode": "none"
}
"@
$settingsContent | Out-File -FilePath $settingsFile -Encoding utf8 -Force
Log-Message "[OK] Default VS Code Flutter settings configured." "Green"

# 3. Setup VS Code Portable
Log-Message "[2/6] Setting up VS Code Portable..." "Green"
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
Log-Message "[3/6] Setting up Flutter SDK..." "Green"
if (-not (Test-Path "$ToolsFolder\flutter\bin\flutter.bat")) {
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
Log-Message "[4/6] Setting up Git and SQLite command-line tools..." "Green"
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
Log-Message "[OK] Git and SQLite CLI tools ready." "Green"

# 6. Install VS Code Extensions
Log-Message "[5/6] Installing VS Code Extensions..." "Green"
$codeCmd = "$VSCodeFolder\bin\code.cmd"
$extDir  = "$VSCodeFolder\data\extensions"
$userDataDir = "$VSCodeFolder\data\user-data"

foreach ($ext in $RequiredExtensions) {
    Log-Message "Installing extension: $ext..." "DarkGray"
    try {
        & $codeCmd --extensions-dir $extDir --user-data-dir $userDataDir --install-extension $ext --force 2>&1 | Out-Null
    } catch {
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

# 7. Configure PATH (Process & User Registry)
Log-Message "[6/6] Configuring Environment & System PATH..." "Green"
$pathsToAdd = @(
    "$ToolsFolder\flutter\bin",
    "$ToolsFolder\flutter\bin\cache\dart-sdk\bin",
    "$ToolsFolder\git\cmd",
    "$ToolsFolder\sqlite",
    "$VSCodeFolder\bin"
)

# Process-Level PATH
$procPath = [System.Environment]::GetEnvironmentVariable("PATH", "Process")
foreach ($p in $pathsToAdd) {
    if (Test-Path $p) {
        if ($procPath -notlike "*$p*") {
            $procPath = "$p;$procPath"
        }
    }
}
[System.Environment]::SetEnvironmentVariable("PATH", $procPath, "Process")

# User-Level Registry PATH (Permanent for the student account without Admin rights)
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
    Log-Message "[OK] PATH and environment variables saved to User profile." "Green"
} catch {
    Log-Message "Notice: Could not write User Registry PATH. Process PATH is active." "DarkYellow"
}

# 8. Unblock Files & Create Desktop Shortcut
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

# Check 6: Installed Extensions Verification
$installedExts = Get-ChildItem -Path $extDir -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }
$missingExts = @()
foreach ($ext in $RequiredExtensions) {
    $match = $installedExts | Where-Object { $_ -like "$($ext.ToLower())*" }
    if ($match) {
        Log-Message "  - Extension: $ext [INSTALLED]" "DarkGray"
    } else {
        Log-Message "  - Extension: $ext [MISSING]" "Yellow"
        $missingExts += $ext
    }
}
if ($missingExts.Count -eq 0) {
    Log-Message "[PASS] All $($RequiredExtensions.Count) required VS Code extensions verified." "Green"
} else {
    Log-Message "[WARN] $($missingExts.Count) extension(s) not found in local cache: $($missingExts -join ', ')" "Yellow"
}

# Check 7: VS Code Settings Verification
if (Test-Path $settingsFile) {
    try {
        $parsed = Get-Content $settingsFile -Raw | ConvertFrom-Json
        if ($parsed.'dart.defaultFlutterDevice' -eq "edge" -and $parsed.'files.autoSave' -eq "afterDelay") {
            Log-Message "[PASS] VS Code Settings verified (AutoSave + Edge Target Device)." "Green"
        } else {
            Log-Message "[FAIL] VS Code Settings missing required Flutter/Edge parameters!" "Red"
            $CheckFailures++
        }
    } catch {
        Log-Message "[FAIL] VS Code Settings JSON parsing failed: $_" "Red"
        $CheckFailures++
    }
} else {
    Log-Message "[FAIL] VS Code Settings file missing at $settingsFile!" "Red"
    $CheckFailures++
}

Log-Message ""
Log-Message "Verification Summary: $($CheckFailures) Check Failure(s) recorded." $(if ($CheckFailures -eq 0) { "Green" } else { "Red" })

if ($CheckFailures -gt 0) {
    Fail-Exit "Verification checks failed. Please check the diagnostic log for details."
}

# ----------------- Finish & Launch -----------------
$launcherBat = "$DestFolder\DOUBLE_CLICK_ME_TO_START.bat"
Log-Message "=========================================================" "Green"
Log-Message "  Installation & Verification Completed Successfully!   " "Green"
Log-Message "  Installed at: $DestFolder                              " "Green"
Log-Message "  Shortcut:     Desktop -> 'Flutter VS Code'             " "Green"
Log-Message "=========================================================" "Green"
Log-Message ""
Log-Message "Launching Portable Flutter & VS Code Environment..." "Cyan"

Save-Log
Send-InstallationTelemetry "SUCCESS" 0 @{}
Start-Process -FilePath $launcherBat -WorkingDirectory $DestFolder
