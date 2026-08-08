# Southsea Cinema - Portable Flutter & VS Code Environment

A zero-install, portable development environment designed for university lab computers without administrative rights.

## Features

- **Portable VS Code**: Runs entirely from the user's Downloads folder without installation or elevation.
- **Pre-installed Extensions**:
  - GitHub Copilot & GitHub Copilot Chat
  - Flutter & Dart SDK extensions
  - Error Lens (inline error and warning highlights for clear debugging)
  - Material Icon Theme
  - GitHub Pull Requests and Issues
  - SQLite Viewer (direct visual inspection of `.db` files)
- **Pre-configured Settings**:
  - Auto-save enabled (`afterDelay`)
  - Auto-format and organize imports on save
  - Flutter UI guide lines enabled
  - Marketplace lockdown (offline safe)
- **Bundled Tools**:
  - Flutter SDK & Dart SDK
  - Portable Git (MinGit)
  - SQLite CLI tools
  - Pre-warmed pub package cache
- **Coursework Ready**: Configured for the [Southsea Cinema Coursework](https://github.com/manighahrmani/southsea_cinema).

---

## Quick Setup (For Students)

Open **PowerShell** on the lab computer and paste:

```powershell
irm https://raw.githubusercontent.com/manighahrmani/flutter_vscode_package/main/install.ps1 | iex
```

### What this does:
1. Downloads `flutter_vscode_package.zip` into `C:\Users\<username>\Downloads\flutter_vscode_package`.
2. Extracts and unblocks all tools and binaries.
3. Creates a **Southsea Cinema VS Code** shortcut on your Desktop.
4. Automatically prompts for your GitHub Fork URL or opens the starter template.

---

## Manual Startup

If already downloaded, simply double-click:
```
DOUBLE_CLICK_ME_TO_START.bat
```
inside your `C:\Users\<username>\Downloads\flutter_vscode_package` folder.
