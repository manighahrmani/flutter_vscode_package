<#
.SYNOPSIS
    Installs the Portable Flutter & VS Code development package.
.DESCRIPTION
    Designed for non-admin University Lab Windows machines.
    Downloads and extracts the pre-configured package directly to the student's Downloads folder:
    C:\Users\<username>\Downloads\flutter_vscode_package
.USAGE
    From PowerShell:
      irm https://raw.githubusercontent.com/manighahrmani/flutter_vscode_package/main/install.ps1 | iex
#>

$ErrorActionPreference = "Continue"

$DownloadUrl = "https://github.com/manighahrmani/flutter_vscode_package/releases/latest/download/flutter_vscode_package.zip"
$DestFolder  = "$env:USERPROFILE\Downloads\flutter_vscode_package"
$TempZip     = "$env:TEMP\flutter_vscode_package_download.tmp"
$ZipPath     = "$env:TEMP\flutter_vscode_package.zip"
$FallbackUrl = "https://github.com/manighahrmani/flutter_vscode_package/releases/latest"
$LogPath     = "$env:USERPROFILE\Downloads\flutter_vscode_install.log"
$SupportEmail = "mani.ghahremani@port.ac.uk"
$IssuesUrl   = "https://github.com/manighahrmani/flutter_vscode_package/issues"

# ----------------- Telemetry & Logging Setup -----------------
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
    } catch {
        # Non-critical if logging fails to disk
    }
}

function Fail-Exit([string]$reason) {
    Log-Message "FATAL ERROR: $reason" "Red"
    Save-Log
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
    $choice = Read-Host "Do you want to re-install / overwrite? (y/N)"
    if ($choice -ne 'y' -and $choice -ne 'Y') {
        Log-Message "Launching existing installation..." "Green"
        Save-Log
        Start-Process "$DestFolder\DOUBLE_CLICK_ME_TO_START.bat" -WorkingDirectory $DestFolder
        exit 0
    }
    Log-Message "Removing previous installation..." "Yellow"
    try {
        Remove-Item $DestFolder -Recurse -Force -ErrorAction Stop
        Log-Message "Previous installation removed." "DarkGray" $false
    } catch {
        Log-Message "WARNING: Some previous files could not be removed (may be open). Overwriting in place..." "DarkYellow"
    }
}

# 2. Download Archive with Multi-Tool Resiliency
Log-Message "[1/4] Downloading flutter_vscode_package.zip..." "Green"
$downloadTimer = [System.Diagnostics.Stopwatch]::StartNew()
$downloadSucceeded = $false

# Method A: curl.exe (Built-in to Windows 10/11)
$curlCmd = Get-Command curl.exe -ErrorAction SilentlyContinue
if ($curlCmd) {
    Log-Message "Using curl.exe for accelerated download..." "DarkGray"
    if (Test-Path $TempZip) { Remove-Item $TempZip -Force -ErrorAction SilentlyContinue }
    try {
        & curl.exe -L -C - --retry 3 --retry-delay 2 -o $TempZip --progress-bar $DownloadUrl
        if ($LASTEXITCODE -eq 0 -and (Test-Path $TempZip) -and (Get-Item $TempZip).Length -gt 100) {
            Move-Item -Path $TempZip -Destination $ZipPath -Force
            $downloadSucceeded = $true
            Log-Message "curl.exe download completed ($((Get-Item $ZipPath).Length) bytes)." "DarkGray" $false
        } else {
            $sz = if (Test-Path $TempZip) { (Get-Item $TempZip).Length } else { 0 }
            Log-Message "curl.exe returned code $LASTEXITCODE (size: $sz bytes). Falling back to WebClient..." "DarkYellow"
        }
    } catch {
        Log-Message "curl.exe failed: $_" "DarkYellow"
    }
}

# Method B: .NET WebClient (Suboptimal Contingency Backup)
if (-not $downloadSucceeded) {
    Log-Message "Using .NET WebClient download contingency..." "Yellow"
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
        $webClient.DownloadFile($DownloadUrl, $ZipPath)
        if ((Test-Path $ZipPath) -and (Get-Item $ZipPath).Length -gt 100) {
            $downloadSucceeded = $true
            Log-Message ".NET WebClient download completed ($((Get-Item $ZipPath).Length) bytes)." "DarkGray" $false
        }
    } catch {
        Log-Message "WebClient download failed: $_" "DarkYellow"
    }
}

# Method C: Invoke-WebRequest (Tertiary Contingency Backup)
if (-not $downloadSucceeded) {
    Log-Message "Using Invoke-WebRequest contingency..." "Yellow"
    try {
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipPath -UseBasicParsing -ErrorAction Stop
        if ((Test-Path $ZipPath) -and (Get-Item $ZipPath).Length -gt 100) {
            $downloadSucceeded = $true
            Log-Message "Invoke-WebRequest completed successfully." "DarkGray" $false
        }
    } catch {
        Log-Message "Invoke-WebRequest download failed: $_" "DarkYellow"
    }
}

if (-not $downloadSucceeded) {
    Fail-Exit "Failed to download package from $DownloadUrl. Check network connection or proxy."
}

$downloadTimer.Stop()
$zipSize = [math]::Round((Get-Item $ZipPath).Length / 1MB, 1)
Log-Message "[OK] Downloaded ${zipSize} MB in $([math]::Round($downloadTimer.Elapsed.TotalSeconds, 1))s" "Green"

# 3. Unblock Archive
Unblock-File -Path $ZipPath -ErrorAction SilentlyContinue

# 4. Multi-Tier Resilient Extraction
Log-Message "[2/4] Extracting package to Downloads folder (this may take 30-60s)..." "Green"
$extractTimer = [System.Diagnostics.Stopwatch]::StartNew()
$extracted = $false

if (-not (Test-Path $DestFolder)) {
    New-Item -Path $DestFolder -ItemType Directory -Force | Out-Null
}

# Extraction Tier 1: Windows 11 Native tar.exe (Fastest)
$tarCmd = Get-Command tar.exe -ErrorAction SilentlyContinue
if ($tarCmd) {
    Log-Message "Attempting Extraction Tier 1: Native tar.exe..." "DarkGray"
    try {
        & tar.exe -xf $ZipPath -C $DestFolder 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0 -and (Test-Path "$DestFolder\DOUBLE_CLICK_ME_TO_START.bat")) {
            $extracted = $true
            Log-Message "Extraction Tier 1 (tar.exe) succeeded." "DarkGray" $false
        }
    } catch {
        Log-Message "tar.exe extraction encountered an error: $_" "DarkYellow"
    }
}

# Extraction Tier 2: .NET ZipFile API (Fast, Reliable Contingency with Overwrite)
if (-not $extracted) {
    Log-Message "Attempting Extraction Tier 2: .NET ZipFile API..." "Yellow"
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
        $zipArchive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        foreach ($entry in $zipArchive.Entries) {
            $targetPath = Join-Path $DestFolder $entry.FullName
            if ([string]::IsNullOrEmpty($entry.Name)) {
                # Directory entry
                if (-not (Test-Path $targetPath)) {
                    New-Item -ItemType Directory -Path $targetPath -Force -ErrorAction SilentlyContinue | Out-Null
                }
            } else {
                $entryDir = Split-Path -Parent $targetPath
                if (-not (Test-Path $entryDir)) {
                    New-Item -ItemType Directory -Path $entryDir -Force -ErrorAction SilentlyContinue | Out-Null
                }
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $targetPath, $true)
            }
        }
        $zipArchive.Dispose()
        if (Test-Path "$DestFolder\DOUBLE_CLICK_ME_TO_START.bat") {
            $extracted = $true
            Log-Message "Extraction Tier 2 (.NET ZipFile) succeeded." "DarkGray" $false
        }
    } catch {
        Log-Message ".NET ZipFile extraction failed: $_" "DarkYellow"
    }
}

# Extraction Tier 3: PowerShell Expand-Archive (Built-in Contingency)
if (-not $extracted) {
    Log-Message "Attempting Extraction Tier 3: PowerShell Expand-Archive..." "Yellow"
    try {
        $oldProgress = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        Expand-Archive -Path $ZipPath -DestinationPath $DestFolder -Force -ErrorAction Stop
        $ProgressPreference = $oldProgress
        if (Test-Path "$DestFolder\DOUBLE_CLICK_ME_TO_START.bat") {
            $extracted = $true
            Log-Message "Extraction Tier 3 (Expand-Archive) succeeded." "DarkGray" $false
        }
    } catch {
        Log-Message "Expand-Archive failed: $_" "DarkYellow"
    }
}

# Extraction Tier 4: Shell.Application COM Object (Legacy Windows Contingency)
if (-not $extracted) {
    Log-Message "Attempting Extraction Tier 4: Windows Shell COM Object..." "Yellow"
    try {
        $shell = New-Object -ComObject Shell.Application
        $zipPackage = $shell.NameSpace($ZipPath)
        $destination = $shell.NameSpace($DestFolder)
        $destination.CopyHere($zipPackage.Items(), 16) # 16 = Respond 'Yes to All'
        if (Test-Path "$DestFolder\DOUBLE_CLICK_ME_TO_START.bat") {
            $extracted = $true
            Log-Message "Extraction Tier 4 (Shell COM) succeeded." "DarkGray" $false
        }
    } catch {
        Log-Message "Shell COM extraction failed: $_" "DarkYellow"
    }
}

if (-not $extracted) {
    Fail-Exit "All extraction methods failed to extract $ZipPath into $DestFolder."
}

$extractTimer.Stop()
Log-Message "[OK] Extracted successfully in $([math]::Round($extractTimer.Elapsed.TotalSeconds, 1))s" "Green"

# 5. Unblock Binaries & Scripts
Log-Message "[3/4] Unblocking downloaded executables and scripts..." "Green"
Get-ChildItem -Path $DestFolder -Recurse -Include "*.exe", "*.dll", "*.bat", "*.ps1" | Unblock-File -ErrorAction SilentlyContinue

# 6. Cleanup Temporary Zip
Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue

# 7. Create Desktop Shortcut for Students
Log-Message "[4/4] Creating Desktop shortcut..." "Green"
try {
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\Desktop\Flutter VS Code.lnk")
    $Shortcut.TargetPath = "$DestFolder\DOUBLE_CLICK_ME_TO_START.bat"
    $Shortcut.WorkingDirectory = $DestFolder
    $Shortcut.Description = "Launch Portable Flutter & VS Code Environment"
    $Shortcut.IconLocation = "$DestFolder\vscode\Code.exe,0"
    $Shortcut.Save()
    Log-Message "Desktop shortcut created successfully." "DarkGray" $false
} catch {
    Log-Message "Warning: Could not create desktop shortcut. You can launch from Downloads folder." "DarkYellow"
}

# 8. Verification & Launch
$launcherBat = "$DestFolder\DOUBLE_CLICK_ME_TO_START.bat"
if (-not (Test-Path $launcherBat)) {
    Fail-Exit "Extraction completed, but launcher script ($launcherBat) is missing."
}

Log-Message ""
Log-Message "=========================================================" "Green"
Log-Message "  Setup completed successfully!                          " "Green"
Log-Message "  Installed at: $DestFolder                              " "Green"
Log-Message "  Shortcut:     Desktop -> 'Flutter VS Code'             " "Green"
Log-Message "=========================================================" "Green"
Log-Message ""
Log-Message "Starting environment..." "Cyan"

Save-Log
Start-Process -FilePath $launcherBat -WorkingDirectory $DestFolder
