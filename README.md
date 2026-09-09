# Portable Flutter & VS Code Package

A zero-install, portable development environment designed for uni computers without admin rights.

## Setup

Open **PowerShell** on your Windows computer and enter the following:

```powershell
irm https://raw.githubusercontent.com/manighahrmani/flutter_vscode_package/main/install.ps1 | iex
```

When the launcher starts, it checks your global Git author configuration. It
shows the current values if they exist and lets you change them. If either value
is missing, you must enter your GitHub username and the email address associated
with your GitHub account before choosing or creating a project.

## Troubleshooting

If setup fails, find the log file in your Downloads folder: `flutter_vscode_install.log`

- Upload it to [GitHub Issues](https://github.com/manighahrmani/flutter_vscode_package/issues/new), or
- Email it to me (`mani.ghahremani@port.ac.uk`)
