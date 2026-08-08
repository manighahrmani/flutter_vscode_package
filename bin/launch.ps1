<#
.SYNOPSIS
    Environment Launcher for Southsea Cinema Coursework
#>

$ScriptRoot = Split-Path -Parent $PSScriptRoot
$ToolsDir   = "$ScriptRoot\tools"
$VSCodeExe  = "$ScriptRoot\vscode\Code.exe"
$Workspace  = "$ScriptRoot\workspace\southsea_cinema"
$TemplateGit = "https://github.com/manighahrmani/southsea_cinema.git"

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "  Southsea Cinema Coursework Environment Launcher         " -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Setup Process-Level PATH and Tool Variables
$env:FLUTTER_ROOT = "$ToolsDir\flutter"
$env:PUB_CACHE    = "$ToolsDir\pub_cache"

$pathsToAdd = @(
    "$ToolsDir\flutter\bin",
    "$ToolsDir\flutter\bin\cache\dart-sdk\bin",
    "$ToolsDir\git\cmd",
    "$ToolsDir\git\bin",
    "$ToolsDir\sqlite"
)

$currentPath = [System.Environment]::GetEnvironmentVariable("PATH", "Process")
foreach ($p in $pathsToAdd) {
    if (Test-Path $p) {
        $currentPath = "$p;$currentPath"
    }
}
[System.Environment]::SetEnvironmentVariable("PATH", $currentPath, "Process")

# 2. Detect Chrome Executable for Flutter Web
$chromeCandidates = @(
    "C:\Program Files\Google\Chrome\Application\chrome.exe",
    "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
    "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
)

$detectedBrowser = $null
foreach ($b in $chromeCandidates) {
    if (Test-Path $b) {
        $detectedBrowser = $b
        break
    }
}

if ($detectedBrowser) {
    $env:CHROME_EXECUTABLE = $detectedBrowser
    Write-Host "[OK] Browser detected: $detectedBrowser" -ForegroundColor Green
} else {
    Write-Host "[WARN] Chrome not found in standard paths. Flutter web will use system default." -ForegroundColor Yellow
}

# 3. Check / Configure Git User Information
$gitAvailable = Get-Command git -ErrorAction SilentlyContinue
if ($gitAvailable) {
    $userName = & git config --get user.name 2>$null
    $userEmail = & git config --get user.email 2>$null

    if (-not $userName -or -not $userEmail) {
        Write-Host ""
        Write-Host "--- Git Author Configuration (One-Time Setup) ---" -ForegroundColor Yellow
        Write-Host "Please enter your name and email for your GitHub commits." -ForegroundColor White
        Write-Host ""

        if (-not $userName) {
            $inputName = Read-Host "Enter your Full Name (e.g. Jane Doe)"
            if ($inputName) { & git config --global user.name "$inputName" }
        }
        if (-not $userEmail) {
            $inputEmail = Read-Host "Enter your University or GitHub Email (e.g. up123456@myport.ac.uk)"
            if ($inputEmail) { & git config --global user.email "$inputEmail" }
        }
        Write-Host "[OK] Git author configuration updated." -ForegroundColor Green
    }
}

# 4. Workspace & Repository Handling
if (-not (Test-Path "$ScriptRoot\workspace")) {
    New-Item -Path "$ScriptRoot\workspace" -ItemType Directory -Force | Out-Null
}

if (Test-Path "$Workspace\.git") {
    Write-Host ""
    Write-Host "Existing project found at:" -ForegroundColor Cyan
    Write-Host "  $Workspace" -ForegroundColor White
    Write-Host ""
    Write-Host "[1] Open existing project in VS Code (Default)" -ForegroundColor Green
    Write-Host "[2] Clone a different fork from GitHub" -ForegroundColor Yellow
    Write-Host "[3] Reset / re-clone Southsea Cinema template" -ForegroundColor Red
    Write-Host ""
    $action = Read-Host "Choose an option [1-3] (Press Enter for 1)"
    
    if ($action -eq "2") {
        $forkUrl = Read-Host "Paste your GitHub Fork URL (e.g. https://github.com/<your-username>/southsea_cinema)"
        if ($forkUrl) {
            Remove-Item $Workspace -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "Cloning $forkUrl..." -ForegroundColor Green
            & git clone $forkUrl $Workspace
        }
    } elseif ($action -eq "3") {
        $confirm = Read-Host "Are you sure you want to delete and reset to clean template? (y/N)"
        if ($confirm -eq 'y' -or $confirm -eq 'Y') {
            Remove-Item $Workspace -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "Cloning fresh template..." -ForegroundColor Green
            & git clone $TemplateGit $Workspace
        }
    }
} else {
    Write-Host ""
    Write-Host "No project found in workspace." -ForegroundColor Yellow
    Write-Host "Do you have your own GitHub Fork URL?" -ForegroundColor White
    Write-Host "  - Paste your fork URL: https://github.com/<your-username>/southsea_cinema" -ForegroundColor DarkGray
    Write-Host "  - Or press Enter to clone the default template." -ForegroundColor DarkGray
    Write-Host ""
    $repoUrl = Read-Host "Repo URL (or press Enter for default)"
    if (-not $repoUrl) { $repoUrl = $TemplateGit }

    Write-Host "Cloning project from $repoUrl..." -ForegroundColor Green
    if ($gitAvailable) {
        & git clone $repoUrl $Workspace
    } else {
        Write-Host "WARNING: Git not found. Skipping clone." -ForegroundColor Red
    }
}

# 5. Launch VS Code
Write-Host ""
Write-Host "Launching Portable VS Code..." -ForegroundColor Green

if (Test-Path $VSCodeExe) {
    Start-Process -FilePath $VSCodeExe -ArgumentList "`"$Workspace`"" -WorkingDirectory $ScriptRoot
} else {
    # If code.exe is on system PATH as fallback
    $sysCode = Get-Command code -ErrorAction SilentlyContinue
    if ($sysCode) {
        Start-Process "code" -ArgumentList "`"$Workspace`""
    } else {
        Write-Host "ERROR: VS Code executable not found at: $VSCodeExe" -ForegroundColor Red
        pause
    }
}
