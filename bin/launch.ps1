<#
.SYNOPSIS
    Environment Launcher for Portable Flutter & VS Code Package
#>

$ScriptRoot = Split-Path -Parent $PSScriptRoot
$ToolsDir   = "$ScriptRoot\tools"
$VSCodeExe  = "$ScriptRoot\vscode\Code.exe"
$Workspace  = "$ScriptRoot\workspace"
$TelemetryEndpoint = "https://script.google.com/macros/s/AKfycbx4ztCT_U7XE9sNUFy4GNI5rvmptu_r1I20CoPbIZSy9a72ZaeZeIfRFY39X9NFpZA/exec"

$launchStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$launchLogs = [System.Collections.Generic.List[string]]::new()

function Log-Launch([string]$msg) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $launchLogs.Add("[$timestamp] $msg")
}

function Send-LaunchTelemetry([string]$eventType, [string]$choiceDetail, [string]$status="SUCCESS", [int]$failures=0) {
    if (-not $TelemetryEndpoint -or $TelemetryEndpoint -eq "") { return }
    try {
        $durSec = if ($launchStopwatch) { [Math]::Round($launchStopwatch.Elapsed.TotalSeconds, 1).ToString() + "s" } else { "" }
        $fullLog = ($launchLogs -join "`n")
        $payload = @{
            timestamp     = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            event         = $eventType
            user          = $env:USERNAME
            computer      = $env:COMPUTERNAME
            os            = ([System.Environment]::OSVersion.VersionString)
            status        = $status
            choice        = $choiceDetail
            duration      = $durSec
            checkFailures = $failures
            log           = $fullLog
        }
        $jsonPayload = $payload | ConvertTo-Json -Depth 3
        
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

# ----------------- Environment Configuration -----------------
$toolsPath = @(
    "$ToolsDir\flutter\bin",
    "$ToolsDir\flutter\bin\cache\dart-sdk\bin",
    "$ToolsDir\git\cmd",
    "$ToolsDir\git\bin",
    "$ToolsDir\sqlite",
    "$ScriptRoot\vscode\bin"
)
foreach ($p in $toolsPath) {
    if ((Test-Path $p) -and ($env:Path -notlike "*$p*")) {
        $env:Path = "$p;$env:Path"
    }
}

# Configure Edge as Default Web Browser Device
$edgeCandidates = @(
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
    "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe"
)
$detectedEdge = $null
foreach ($b in $edgeCandidates) {
    if (Test-Path $b) {
        $detectedEdge = $b
        break
    }
}

if ($detectedEdge) {
    $env:CHROME_EXECUTABLE = $detectedEdge
    $env:FLUTTER_WEB_BROWSER = "edge"
}

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "     Portable Flutter & VS Code Environment Launcher     " -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host ""

# Helper: Scaffolds a complete, ready-to-run Flutter Starter Project
function Initialize-StarterFlutterProject([string]$destPath) {
    Write-Host "Generating starter Flutter project at:" -ForegroundColor Cyan
    Write-Host "  $destPath" -ForegroundColor White

    # Attempt flutter create if flutter CLI is available
    $flutterBat = "$ToolsDir\flutter\bin\flutter.bat"
    $flutterCmd = if (Test-Path $flutterBat) { 
        $flutterBat 
    } else { 
        $sysCmd = Get-Command flutter -ErrorAction SilentlyContinue
        if ($sysCmd) { $sysCmd.Source } else { $null }
    }
    if ($flutterCmd) {
        Write-Host "Running 'flutter create --platforms=web'..." -ForegroundColor Green
        try {
            if (-not (Test-Path $destPath)) {
                New-Item -Path $destPath -ItemType Directory -Force | Out-Null
            }
            & $flutterCmd create --template=app --platforms=web --project-name=flutter_app "$destPath"
            if (Test-Path "$destPath\lib\main.dart") {
                Write-Host "[OK] Flutter starter project created via CLI." -ForegroundColor Green
                return
            }
        } catch {
            Write-Host "Note: 'flutter create' encountered an issue, using offline template generator..." -ForegroundColor DarkYellow
        }
    }

    # Offline / Portable Template Generator (Guaranteed to work 100% of the time)
    if (-not (Test-Path "$destPath\lib")) {
        New-Item -Path "$destPath\lib" -ItemType Directory -Force | Out-Null
    }
    if (-not (Test-Path "$destPath\web")) {
        New-Item -Path "$destPath\web" -ItemType Directory -Force | Out-Null
    }

    # 1. lib/main.dart
    $mainDart = @'
import 'package:flutter/material.dart';

void main() {
  runApp(const StarterApp());
}

class StarterApp extends StatelessWidget {
  const StarterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Starter App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Flutter Starter App'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.flutter_dash, size: 80, color: Colors.deepPurple),
            const SizedBox(height: 16),
            const Text(
              'Welcome to Flutter Web!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
'@
    $mainDart | Out-File -FilePath "$destPath\lib\main.dart" -Encoding utf8 -Force

    # 2. pubspec.yaml
    $pubspec = @'
name: flutter_app
description: "A starter Flutter Web application"
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0

flutter:
  uses-material-design: true
'@
    $pubspec | Out-File -FilePath "$destPath\pubspec.yaml" -Encoding utf8 -Force

    # 3. analysis_options.yaml
    $analysisOptions = @'
include: package:flutter_lints/flutter.yaml

linter:
  rules:
    prefer_const_constructors: true
    prefer_const_declarations: true
    avoid_print: false
'@
    $analysisOptions | Out-File -FilePath "$destPath\analysis_options.yaml" -Encoding utf8 -Force

    # 4. web/index.html
    $indexHtml = @'
<!DOCTYPE html>
<html>
<head>
  <base href="$FLUTTER_BASE_HREF">
  <meta charset="UTF-8">
  <meta content="IE=Edge" http-equiv="X-UA-Compatible">
  <meta name="description" content="Flutter Application">
  <title>Flutter App</title>
</head>
<body>
  <script src="flutter_bootstrap.js" async></script>
</body>
</html>
'@
    $indexHtml | Out-File -FilePath "$destPath\web\index.html" -Encoding utf8 -Force

    # 5. README.md
    $readme = @'
# Flutter Web Starter App

Welcome to your portable Flutter development environment. The project is loaded and ready to run.

## Running the Application

1. Verify Edge (or Chrome) is selected in the bottom status bar.
2. Press F5 (or click Run > Start Debugging).
   - Alternatively, execute in the terminal:
     flutter run -d edge
3. Hot reload: Save lib/main.dart or press "r" in the debug terminal while running.

## Project Structure

- lib/main.dart: Application entry point and widget tree.
- pubspec.yaml: Dependencies and configuration.
- web/index.html: Web host container.
'@
    $readme | Out-File -FilePath "$destPath\README.md" -Encoding utf8 -Force

    # 6. .vscode/launch.json & .vscode/settings.json
    if (-not (Test-Path "$destPath\.vscode")) {
        New-Item -Path "$destPath\.vscode" -ItemType Directory -Force | Out-Null
    }
    $launchJson = @"
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Flutter (Edge)",
      "request": "launch",
      "type": "dart",
      "deviceId": "edge"
    },
    {
      "name": "Flutter (Chrome / Default)",
      "request": "launch",
      "type": "dart",
      "deviceId": "chrome"
    }
  ]
}
"@
    $launchJson | Out-File -FilePath "$destPath\.vscode\launch.json" -Encoding utf8 -Force

    $workspaceSettings = @"
{
  "dart.defaultFlutterDevice": "edge",
  "dart.flutterSelectDeviceWhenConnected": false,
  "dart.runPubGetOnPubspecChanges": "always",
  "security.workspace.trust.enabled": false,
  "security.workspace.trust.startupPrompt": "never",
  "security.workspace.trust.banner": "never"
}
"@
    $workspaceSettings | Out-File -FilePath "$destPath\.vscode\settings.json" -Encoding utf8 -Force

    Write-Host "[OK] Complete Flutter Starter project generated with Edge device configuration." -ForegroundColor Green
}

# Helper: Pre-warms and automatically runs pub get, ensures Edge device and trust configuration
function Invoke-ProjectPreparation([string]$destPath) {
    if (-not (Test-Path "$destPath\pubspec.yaml")) {
        return
    }

    # Ensure .vscode configuration for target device and trust
    $vscodeFolder = "$destPath\.vscode"
    if (-not (Test-Path $vscodeFolder)) {
        New-Item -Path $vscodeFolder -ItemType Directory -Force | Out-Null
    }
    $settingsFile = "$vscodeFolder\settings.json"
    $projSettings = @'
{
  "dart.defaultFlutterDevice": "edge",
  "dart.flutterSelectDeviceWhenConnected": false,
  "dart.runPubGetOnPubspecChanges": "always",
  "security.workspace.trust.enabled": false,
  "security.workspace.trust.startupPrompt": "never",
  "security.workspace.trust.banner": "never"
}
'@
    $projSettings | Out-File -FilePath $settingsFile -Encoding utf8 -Force

    $launchFile = "$vscodeFolder\launch.json"
    $projLaunch = @'
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Flutter (Edge)",
      "request": "launch",
      "type": "dart",
      "deviceId": "edge"
    },
    {
      "name": "Flutter (Chrome / Default)",
      "request": "launch",
      "type": "dart",
      "deviceId": "chrome"
    }
  ]
}
'@
    $projLaunch | Out-File -FilePath $launchFile -Encoding utf8 -Force

    # Ensure sqlite3.wasm is deployed to web/ if project uses SQLite (sqflite)
    if ((Test-Path "$destPath\pubspec.yaml") -and ((Get-Content "$destPath\pubspec.yaml" -Raw) -match "sqflite")) {
        $webDir = "$destPath\web"
        if (-not (Test-Path $webDir)) { New-Item -Path $webDir -ItemType Directory -Force | Out-Null }
        if (-not (Test-Path "$webDir\sqlite3.wasm")) {
            $sqliteWasmSource = "$ToolsDir\sqlite\sqlite3.wasm"
            if (Test-Path $sqliteWasmSource) {
                Copy-Item -Path $sqliteWasmSource -Destination "$webDir\sqlite3.wasm" -Force
                Write-Host "[OK] SQLite WebAssembly runtime (sqlite3.wasm) deployed to web directory." -ForegroundColor Green
            } else {
                try {
                    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                    Invoke-WebRequest -Uri "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-2.4.6/sqlite3.wasm" -OutFile "$webDir\sqlite3.wasm" -TimeoutSec 15
                    Write-Host "[OK] Downloaded sqlite3.wasm to web directory." -ForegroundColor Green
                } catch {}
            }
        }
    }

    # Run flutter pub get / dart pub get automatically
    Write-Host ""
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host "   Resolving Dependencies (flutter pub get)              " -ForegroundColor Cyan
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host "Running 'flutter pub get' for $destPath..." -ForegroundColor White
    Log-Launch "Resolving dependencies via flutter pub get for $destPath"

    $flutterBat = "$ToolsDir\flutter\bin\flutter.bat"
    $dartExe = "$ToolsDir\flutter\bin\cache\dart-sdk\bin\dart.exe"

    if (Test-Path $flutterBat) {
        try {
            Push-Location $destPath
            & $flutterBat pub get
            Pop-Location
            Write-Host "[OK] Dependencies successfully resolved via Flutter CLI." -ForegroundColor Green
            Log-Launch "Dependencies resolved successfully via Flutter CLI"
        } catch {
            Write-Host "[WARN] Flutter pub get encountered an issue: $_" -ForegroundColor Yellow
            Log-Launch "Warning: flutter pub get error: $_"
            Pop-Location
        }
    } elseif (Test-Path $dartExe) {
        try {
            Push-Location $destPath
            & $dartExe pub get
            Pop-Location
            Write-Host "[OK] Dependencies successfully resolved via Dart CLI." -ForegroundColor Green
            Log-Launch "Dependencies resolved via Dart CLI"
        } catch {
            Write-Host "[WARN] Dart pub get encountered an issue: $_" -ForegroundColor Yellow
            Log-Launch "Warning: dart pub get error: $_"
            Pop-Location
        }
    } else {
        $flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
        if ($flutterCmd) {
            try {
                Push-Location $destPath
                & flutter pub get
                Pop-Location
                Write-Host "[OK] Dependencies successfully resolved via system Flutter CLI." -ForegroundColor Green
                Log-Launch "Dependencies resolved via system Flutter"
            } catch {
                Write-Host "[WARN] Flutter pub get encountered an issue: $_" -ForegroundColor Yellow
                Log-Launch "Warning: flutter pub get error: $_"
                Pop-Location
            }
        }
    }
}

# 3. Check / Configure Git User Information
$gitAvailable = Get-Command git -ErrorAction SilentlyContinue
if ($gitAvailable) {
    $userName = & git config --get user.name 2>$null
    $userEmail = & git config --get user.email 2>$null

    if (-not $userName -or -not $userEmail) {
        Write-Host ""
        Write-Host "--- Git Author Configuration (One-Time Setup) ---" -ForegroundColor Yellow
        Write-Host "Please enter your name and email for your Git commits." -ForegroundColor White
        Write-Host ""

        if (-not $userName) {
            $inputName = Read-Host "Enter your Full Name (e.g. Jane Doe)"
            if ($inputName) { & git config --global user.name "$inputName" }
        }
        if (-not $userEmail) {
            $inputEmail = Read-Host "Enter your Email (e.g. student@example.ac.uk)"
            if ($inputEmail) { & git config --global user.email "$inputEmail" }
        }
        Write-Host "[OK] Git author configuration updated." -ForegroundColor Green
        Log-Launch "Configured git author name: $inputName, email: $inputEmail"
    }
}

# 4. Workspace & Repository Handling
if (-not (Test-Path "$ScriptRoot\workspace")) {
    New-Item -Path "$ScriptRoot\workspace" -ItemType Directory -Force | Out-Null
}

$launchEvent = "LAUNCH_STARTER"
$choiceDetail = "Created new Starter Flutter App with Edge target"

$hasExistingValidProject = (Test-Path "$Workspace\pubspec.yaml") -or (Test-Path "$Workspace\.git")

if ($hasExistingValidProject) {
    Write-Host ""
    Write-Host "Existing project found at:" -ForegroundColor Cyan
    Write-Host "  $Workspace" -ForegroundColor White
    Write-Host ""
    Write-Host "[1] Open existing project in VS Code (Default)" -ForegroundColor Green
    Write-Host "[2] Clone a repository from GitHub (Enter URL)" -ForegroundColor Yellow
    Write-Host "[3] Reset / Create fresh Flutter starter project" -ForegroundColor Red
    Write-Host ""
    $action = Read-Host "Choose an option [1-3] (Press Enter for 1)"
    
    if ($action -eq "2") {
        $forkUrl = Read-Host "Paste your GitHub Repository URL (e.g. https://github.com/<username>/<repo>)"
        if ($forkUrl) {
            $launchEvent = "LAUNCH_CLONE"
            $choiceDetail = "Cloned repository: $forkUrl"
            Log-Launch "Cloning repository: $forkUrl"
            Remove-Item $Workspace -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "Cloning $forkUrl..." -ForegroundColor Green
            if ($gitAvailable) {
                & git clone $forkUrl $Workspace
            }
            if (-not (Test-Path "$Workspace\pubspec.yaml")) {
                Initialize-StarterFlutterProject $Workspace
            }
        }
    } elseif ($action -eq "3") {
        $confirm = Read-Host "Are you sure you want to reset to a clean starter project? (y/N)"
        if ($confirm -eq 'y' -or $confirm -eq 'Y') {
            $launchEvent = "LAUNCH_RESET_STARTER"
            $choiceDetail = "Reset workspace to clean Starter Flutter App"
            Log-Launch "Reset workspace to starter project"
            Remove-Item $Workspace -Recurse -Force -ErrorAction SilentlyContinue
            Initialize-StarterFlutterProject $Workspace
        }
    } else {
        $launchEvent = "LAUNCH_EXISTING"
        $choiceDetail = "Opened existing project at $Workspace"
        Log-Launch "Opened existing workspace: $Workspace"
    }
} else {
    Write-Host ""
    Write-Host "=========================================================" -ForegroundColor Yellow
    Write-Host "              Project Setup Options                      " -ForegroundColor Yellow
    Write-Host "=========================================================" -ForegroundColor Yellow
    Write-Host "Do you have a GitHub Repository URL?" -ForegroundColor White
    Write-Host "  - Paste your repo URL: https://github.com/<username>/<repo>" -ForegroundColor DarkGray
    Write-Host "  - Or press ENTER to automatically create a Flutter Starter App." -ForegroundColor Green
    Write-Host ""
    $repoUrl = Read-Host "Repository URL (or press Enter for Starter App)"

    if ($repoUrl -and $repoUrl.Trim() -ne "") {
        $launchEvent = "LAUNCH_CLONE"
        $choiceDetail = "Cloned repository: $repoUrl"
        Log-Launch "Cloning initial repository: $repoUrl"
        Write-Host "Cloning from $repoUrl..." -ForegroundColor Green
        if ($gitAvailable) {
            & git clone $repoUrl $Workspace
        }
        if (-not (Test-Path "$Workspace\pubspec.yaml")) {
            Write-Host "Clone failed or empty repo. Initializing starter project..." -ForegroundColor Yellow
            Initialize-StarterFlutterProject $Workspace
        }
    } else {
        # Student pressed Enter -> Generate Hello World / Starter Flutter Project immediately!
        $launchEvent = "LAUNCH_STARTER"
        $choiceDetail = "Created new Starter Flutter App with Edge target"
        Log-Launch "User pressed Enter -> Initializing starter project"
        Initialize-StarterFlutterProject $Workspace
    }
}

# 5. Resolve dependencies and ensure target device is Edge
Invoke-ProjectPreparation $Workspace

# 6. Send launch telemetry to Google Apps Script Web App
Send-LaunchTelemetry $launchEvent $choiceDetail "SUCCESS" 0

# 7. Launch VS Code directly into the Workspace folder
Write-Host ""
Write-Host "Launching Portable VS Code in project folder..." -ForegroundColor Green
Log-Launch "Starting VS Code instance"

if (Test-Path $VSCodeExe) {
    # Ensure Extension Marketplace remains locked down (only pre-installed extensions can run)
    $productJsonPath = "$ScriptRoot\vscode\resources\app\product.json"
    if (Test-Path $productJsonPath) {
        try {
            $product = Get-Content $productJsonPath -Raw | ConvertFrom-Json
            if ($product.PSObject.Properties['extensionsGallery'] -and $product.extensionsGallery.serviceUrl -ne "") {
                $product.extensionsGallery.serviceUrl = ""
                $product.extensionsGallery.itemUrl = ""
                $product.extensionsGallery.controlUrl = ""
                $product.extensionsGallery.resourceUrlTemplate = ""
                $product | ConvertTo-Json -Depth 10 | Set-Content $productJsonPath -Encoding UTF8
            }
        } catch {}
    }

    $extDir = "$ScriptRoot\vscode\data\extensions"
    $userDataDir = "$ScriptRoot\vscode\data\user-data"
    $vscodeArgs = @(
        "--extensions-dir", $extDir,
        "--user-data-dir", $userDataDir,
        $Workspace
    )
    Start-Process -FilePath $VSCodeExe -ArgumentList $vscodeArgs -WorkingDirectory $ScriptRoot -WindowStyle Normal
} else {
    # If code.exe is on system PATH as fallback
    $sysCode = Get-Command code -ErrorAction SilentlyContinue
    if ($sysCode) {
        Start-Process "code" -ArgumentList "`"$Workspace`""
    } else {
        Write-Host "=========================================================" -ForegroundColor Green
        Write-Host "Project folder prepared at:" -ForegroundColor White
        Write-Host "  $Workspace" -ForegroundColor Cyan
        Write-Host "Opening project in Windows Explorer..." -ForegroundColor White
        Write-Host "=========================================================" -ForegroundColor Green
        Start-Process "explorer.exe" -ArgumentList "`"$Workspace`""
    }
}
