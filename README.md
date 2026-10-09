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

## Experimental

An **experimental** Android-emulator beta installer lives at `install-android-beta.ps1`.
It installs the normal environment **plus** a command-line Android SDK and emulator so you
can try `flutter run` on Android instead of Chrome/Edge. It is a separate, self-contained
script and does **not** affect the main `install.ps1` setup above.

This path is **untested on university lab hardware**: the emulator needs hardware
acceleration (WHPX/Hyper-V) that many locked-down machines disable, and the download is
several gigabytes. Try it only if you want to help test it, and report back whether the
emulator actually launches.
