<#
.SYNOPSIS
    Environment Launcher for Portable Flutter & VS Code Package
#>

$ScriptRoot = Split-Path -Parent $PSScriptRoot
$ToolsDir   = "$ScriptRoot\tools"
$VSCodeExe  = "$ScriptRoot\vscode\Code.exe"
$Workspace  = "$ScriptRoot\workspace\project"

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "     Portable Flutter & VS Code Environment Launcher     " -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host ""

# Helper: Scaffolds a complete, ready-to-run Flutter Starter Project
function Initialize-StarterFlutterProject([string]$destPath) {
    Write-Host "Generating starter Flutter project at:" -ForegroundColor Cyan
    Write-Host "  $destPath" -ForegroundColor White

    # Attempt flutter create if flutter CLI is available
    $flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
    if ($flutterCmd) {
        Write-Host "Running 'flutter create'..." -ForegroundColor Green
        try {
            $parentDir = Split-Path -Parent $destPath
            & flutter create --template=app --platforms=web,windows project
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
    $mainDart = @"
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
              'Welcome to Flutter!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
"@
    $mainDart | Out-File -FilePath "$destPath\lib\main.dart" -Encoding utf8 -Force

    # 2. pubspec.yaml
    $pubspec = @"
name: flutter_app
description: "A starter Flutter application"
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
"@
    $pubspec | Out-File -FilePath "$destPath\pubspec.yaml" -Encoding utf8 -Force

    # 3. analysis_options.yaml
    $analysisOptions = @"
include: package:flutter_lints/flutter.yaml

linter:
  rules:
    prefer_const_constructors: true
    prefer_const_declarations: true
    avoid_print: false
"@
    $analysisOptions | Out-File -FilePath "$destPath\analysis_options.yaml" -Encoding utf8 -Force

    # 4. web/index.html
    $indexHtml = @"
<!DOCTYPE html>
<html>
<head>
  <base href="`$FLUTTER_BASE_HREF">
  <meta charset="UTF-8">
  <meta content="IE=Edge" http-equiv="X-UA-Compatible">
  <meta name="description" content="Flutter Application">
  <title>Flutter App</title>
</head>
<body>
  <script src="flutter_bootstrap.js" async></script>
</body>
</html>
"@
    $indexHtml | Out-File -FilePath "$destPath\web\index.html" -Encoding utf8 -Force

    # 5. README.md
    $readme = @"
# Flutter Application

A Flutter application created with the Portable Flutter & VS Code Environment.

## Getting Started

1. Open this project in VS Code.
2. Select Chrome or your connected device.
3. Press **F5** or run `flutter run -d chrome`.
"@
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
  "dart.runPubGetOnPubspecChanges": "always"
}
"@
    $workspaceSettings | Out-File -FilePath "$destPath\.vscode\settings.json" -Encoding utf8 -Force

    Write-Host "[OK] Complete Flutter Starter project generated with Edge device configuration." -ForegroundColor Green
}

# Helper: Pre-warms and runs pub get, ensures Edge device configuration in any project
function Invoke-ProjectPreparation([string]$destPath) {
    if (-not (Test-Path "$destPath\pubspec.yaml")) {
        return
    }

    # Ensure .vscode configuration for target device: Edge
    $vscodeFolder = "$destPath\.vscode"
    if (-not (Test-Path $vscodeFolder)) {
        New-Item -Path $vscodeFolder -ItemType Directory -Force | Out-Null
    }
    $settingsFile = "$vscodeFolder\settings.json"
    if (-not (Test-Path $settingsFile)) {
        $projSettings = @"
{
  "dart.defaultFlutterDevice": "edge",
  "dart.runPubGetOnPubspecChanges": "always"
}
"@
        $projSettings | Out-File -FilePath $settingsFile -Encoding utf8 -Force
    }
    $launchFile = "$vscodeFolder\launch.json"
    if (-not (Test-Path $launchFile)) {
        $projLaunch = @"
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
        $projLaunch | Out-File -FilePath $launchFile -Encoding utf8 -Force
    }

    # Run flutter pub get / dart pub get
    Write-Host ""
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host "   Resolving Dependencies & Preparing Environment        " -ForegroundColor Cyan
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host "Running 'flutter pub get' for $destPath..." -ForegroundColor White

    $flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
    if ($flutterCmd) {
        try {
            Push-Location $destPath
            & flutter pub get
            Pop-Location
            Write-Host "[OK] Dependencies successfully resolved via Flutter CLI." -ForegroundColor Green
        } catch {
            Write-Host "[WARN] Flutter pub get encountered an issue: $_" -ForegroundColor Yellow
            Pop-Location
        }
    } else {
        $dartCmd = Get-Command dart -ErrorAction SilentlyContinue
        if ($dartCmd) {
            try {
                Push-Location $destPath
                & dart pub get
                Pop-Location
                Write-Host "[OK] Dependencies successfully resolved via Dart CLI." -ForegroundColor Green
            } catch {
                Write-Host "[WARN] Dart pub get encountered an issue: $_" -ForegroundColor Yellow
                Pop-Location
            }
        } else {
            Write-Host "Note: Portable Flutter CLI will initialize dependencies when VS Code opens." -ForegroundColor DarkGray
        }
    }
}

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

# 2. Detect Edge / Chrome Executable for Flutter Web (Prioritize Edge)
$browserCandidates = @(
    "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    "C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe",
    "C:\Program Files\Google\Chrome\Application\chrome.exe",
    "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
)

$detectedBrowser = $null
foreach ($b in $browserCandidates) {
    if (Test-Path $b) {
        $detectedBrowser = $b
        break
    }
}

if ($detectedBrowser) {
    $env:CHROME_EXECUTABLE = $detectedBrowser
    Write-Host "[OK] Target browser detected (Edge/Chromium): $detectedBrowser" -ForegroundColor Green
} else {
    Write-Host "[WARN] Edge/Chrome not found in standard paths. Flutter web will use system default." -ForegroundColor Yellow
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
    }
}

# 4. Workspace & Repository Handling
if (-not (Test-Path "$ScriptRoot\workspace")) {
    New-Item -Path "$ScriptRoot\workspace" -ItemType Directory -Force | Out-Null
}

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
            Remove-Item $Workspace -Recurse -Force -ErrorAction SilentlyContinue
            Initialize-StarterFlutterProject $Workspace
        }
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
        Initialize-StarterFlutterProject $Workspace
    }
}

# 5. Resolve dependencies and ensure target device is Edge
Invoke-ProjectPreparation $Workspace

# 6. Launch VS Code directly into the Workspace folder
Write-Host ""
Write-Host "Launching Portable VS Code in project folder..." -ForegroundColor Green

if (Test-Path $VSCodeExe) {
    Start-Process -FilePath $VSCodeExe -ArgumentList "`"$Workspace`"" -WorkingDirectory $ScriptRoot
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
