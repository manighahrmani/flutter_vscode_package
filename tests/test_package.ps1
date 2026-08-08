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

Assert-Test "VS Code Settings - Telemetry Disabled" {
    $Settings = Get-Content "$ScriptRoot\vscode\data\user-data\User\settings.json" -Raw | ConvertFrom-Json
    if ($Settings.'telemetry.telemetryLevel' -ne "off") {
        throw "telemetry.telemetryLevel is not configured to 'off'"
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
    }
    finally {
        if (Test-Path $TestTempDir) {
            Remove-Item -Path $TestTempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
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
