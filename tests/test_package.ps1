# ==============================================================================
# Flutter VS Code Package - Automated Validation & Test Suite
# ==============================================================================

$ErrorActionPreference = "Stop"
$ScriptRoot = Split-Path -Parent $PSScriptRoot
if (-not $ScriptRoot) { $ScriptRoot = Get-Location }

Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "  Flutter VS Code Package - Test Suite           " -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "Root Directory: $ScriptRoot`n"

$FailedTests = 0
$PassedTests = 0

function Assert-Test {
    param(
        [string]$Name,
        [scriptblock]$TestBlock
    )
    Write-Host "[TEST] $Name ... " -NoNewline
    try {
        & $TestBlock
        Write-Host "PASS" -ForegroundColor Green
        $global:PassedTests++
    }
    catch {
        Write-Host "FAIL" -ForegroundColor Red
        Write-Host "   Error: $_" -ForegroundColor DarkRed
        $global:FailedTests++
    }
}

# ------------------------------------------------------------------------------
# 1. Structure Tests
# ------------------------------------------------------------------------------
Assert-Test "File Existence - Core Files" {
    $RequiredFiles = @(
        "$ScriptRoot\install.ps1",
        "$ScriptRoot\DOUBLE_CLICK_ME_TO_START.bat",
        "$ScriptRoot\bin\launch.ps1",
        "$ScriptRoot\vscode\data\user-data\User\settings.json",
        "$ScriptRoot\.devcontainer\devcontainer.json",
        "$ScriptRoot\.devcontainer\Dockerfile",
        "$ScriptRoot\README.md"
    )
    foreach ($File in $RequiredFiles) {
        if (-not (Test-Path $File)) {
            throw "Missing required file: $File"
        }
    }
}

# ------------------------------------------------------------------------------
# 2. Syntax Validation Tests
# ------------------------------------------------------------------------------
Assert-Test "Syntax - PowerShell Scripts (AST Parsing)" {
    $PsScripts = Get-ChildItem -Path $ScriptRoot -Recurse -Filter "*.ps1" | Where-Object { $_.FullName -notmatch "\\\.git\\" }
    foreach ($Script in $PsScripts) {
        $Tokens = $null
        $Errors = $null
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile($Script.FullName, [ref]$Tokens, [ref]$Errors)
        if ($Errors.Count -gt 0) {
            throw "Syntax error in $($Script.Name): $($Errors[0].Message)"
        }
    }
}

Assert-Test "Syntax - JSON Files (Strict Parsing)" {
    $JsonFiles = Get-ChildItem -Path $ScriptRoot -Recurse -Filter "*.json" | Where-Object { $_.FullName -notmatch "\\\.git\\" }
    foreach ($Json in $JsonFiles) {
        try {
            $Content = Get-Content $Json.FullName -Raw | ConvertFrom-Json
            if ($null -eq $Content) {
                throw "Empty JSON document: $($Json.Name)"
            }
        }
        catch {
            throw "Invalid JSON in $($Json.FullName): $_"
        }
    }
}

# ------------------------------------------------------------------------------
# 3. VS Code Configuration Integrity Tests
# ------------------------------------------------------------------------------
Assert-Test "VS Code Settings - AutoSave Enabled" {
    $Settings = Get-Content "$ScriptRoot\vscode\data\user-data\User\settings.json" -Raw | ConvertFrom-Json
    if ($Settings.'files.autoSave' -ne "afterDelay") {
        throw "files.autoSave is not configured to 'afterDelay'"
    }
}

Assert-Test "VS Code Settings - Default Flutter Device (Edge)" {
    $Settings = Get-Content "$ScriptRoot\vscode\data\user-data\User\settings.json" -Raw | ConvertFrom-Json
    if ($Settings.'dart.defaultFlutterDevice' -ne "edge") {
        throw "dart.defaultFlutterDevice is not configured to 'edge'"
    }
}

Assert-Test "VS Code Settings - Auto Run Pub Get Enabled" {
    $Settings = Get-Content "$ScriptRoot\vscode\data\user-data\User\settings.json" -Raw | ConvertFrom-Json
    if ($Settings.'dart.runPubGetOnPubspecChanges' -ne "always") {
        throw "dart.runPubGetOnPubspecChanges is not configured to 'always'"
    }
}

Assert-Test "VS Code Settings - Telemetry Disabled" {
    $Settings = Get-Content "$ScriptRoot\vscode\data\user-data\User\settings.json" -Raw | ConvertFrom-Json
    if ($Settings.'telemetry.telemetryLevel' -ne "off") {
        throw "telemetry.telemetryLevel is not configured to 'off'"
    }
}

Assert-Test "VS Code Settings - Workspace Trust Disabled" {
    $Settings = Get-Content "$ScriptRoot\vscode\data\user-data\User\settings.json" -Raw | ConvertFrom-Json
    if ($Settings.'security.workspace.trust.enabled' -ne $false) {
        throw "security.workspace.trust.enabled is not configured to false"
    }
}

# ------------------------------------------------------------------------------
# 4. Launcher & Starter App Logic Tests
# ------------------------------------------------------------------------------
Assert-Test "Starter Project Scaffold Generator Verification" {
    $TestTempDir = Join-Path $env:TEMP "flutter_pkg_test_$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $TestTempDir -Force | Out-Null
    try {
        # Dot source launch.ps1 with dummy run
        $LaunchContent = Get-Content "$ScriptRoot\bin\launch.ps1" -Raw
        
        # Test file generator function extraction
        if ($LaunchContent -notmatch "function Initialize-StarterFlutterProject") {
            throw "Initialize-StarterFlutterProject function not found in launch.ps1"
        }
        
        # Verify scaffolded filenames in script definition
        if ($LaunchContent -notmatch "pubspec\.yaml" -or $LaunchContent -notmatch "main\.dart") {
            throw "Starter generator does not define required Flutter core files"
        }
        
        # Verify that $_counter is preserved literally and not interpolated away by PowerShell
        if (-not $LaunchContent.Contains('$_counter')) {
            throw "Starter generator main.dart is missing `$_counter counter variable interpolation"
        }

        # Verify that starter generator targets Web platform only
        if ($LaunchContent -notmatch "--platforms=web") {
            throw "Starter generator does not configure --platforms=web"
        }
    }
    finally {
        if (Test-Path $TestTempDir) {
            Remove-Item -Path $TestTempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ------------------------------------------------------------------------------
# 5. Installer Verification Checks & PATH Logic Tests
# ------------------------------------------------------------------------------
Assert-Test "Installer - Verification Checks and PATH Configuration" {
    $InstallContent = Get-Content "$ScriptRoot\install.ps1" -Raw
    
    # Verify PATH registry configuration
    if ($InstallContent -notmatch '\[System\.Environment\]::SetEnvironmentVariable\("PATH"') {
        throw "install.ps1 missing SetEnvironmentVariable PATH logic"
    }
    # Verify CLIs verification checks
    if ($InstallContent -notmatch 'chkFlutter' -or $InstallContent -notmatch 'chkDart' -or $InstallContent -notmatch 'chkGit') {
        throw "install.ps1 missing CLI verification checks"
    }
    # Verify extensions installation logic
    if ($InstallContent -notmatch 'RequiredExtensions') {
        throw "install.ps1 missing RequiredExtensions definition"
    }
    # Verify extension marketplace lockdown
    if ($InstallContent -notmatch 'extensionsGallery') {
        throw "install.ps1 missing extensionsGallery marketplace lockdown"
    }
    # Verify extraction timing logic
    if ($InstallContent -notmatch 'extractStopwatch' -or $InstallContent -notmatch 'Send-InstallationTelemetry') {
        throw "install.ps1 missing extraction timing or telemetry logic"
    }
    # Verify 4 extraction tiers
    if ($InstallContent -notmatch 'tar\.exe' -or $InstallContent -notmatch 'ZipFile' -or $InstallContent -notmatch 'Expand-Archive' -or $InstallContent -notmatch 'Shell\.Application') {
        throw "install.ps1 missing 4-tier extraction contingency"
    }
}

# ------------------------------------------------------------------------------
# 6. Telemetry & Logger Configuration Integrity Tests
# ------------------------------------------------------------------------------
Assert-Test "Telemetry - Configuration & Dispatcher Integrity" {
    $InstallContent = Get-Content "$ScriptRoot\install.ps1" -Raw
    $LaunchContent = Get-Content "$ScriptRoot\bin\launch.ps1" -Raw
    
    # Verify active telemetry endpoint in install.ps1 and launch.ps1
    if ($InstallContent -notmatch '\$TelemetryEndpoint\s*=\s*"https://script\.google\.com/macros/s/[^"]+"') {
        throw "install.ps1 missing valid active TelemetryEndpoint URL"
    }
    if ($LaunchContent -notmatch '\$TelemetryEndpoint\s*=\s*"https://script\.google\.com/macros/s/[^"]+"') {
        throw "launch.ps1 missing valid active TelemetryEndpoint URL"
    }
    # Ensure no empty override exists in install.ps1
    if ($InstallContent -match '\$TelemetryEndpoint\s*=\s*""') {
        throw "install.ps1 contains an empty TelemetryEndpoint override"
    }
}

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
Write-Host "`n-------------------------------------------------" -ForegroundColor Cyan
Write-Host "  Test Results: $PassedTests Passed, $FailedTests Failed" -ForegroundColor $(if ($FailedTests -eq 0) { "Green" } else { "Red" })
Write-Host "-------------------------------------------------" -ForegroundColor Cyan

if ($FailedTests -gt 0) {
    exit 1
}
else {
    exit 0
}
