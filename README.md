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

## Android emulator setup (Worksheet 6 onwards)

From Worksheet 6 the app stores data in a local SQLite database, which is easiest to see
running on an Android emulator. For that, use the Android installer instead of the main one.
Open **PowerShell** and run:

```powershell
irm https://raw.githubusercontent.com/manighahrmani/flutter_vscode_package/main/install-android-beta.ps1 | iex
```

It installs the normal environment **plus** a portable JDK, a command-line Android SDK, and a
ready-made emulator, then opens VS Code on your project exactly like the main installer. It is
a separate, self-contained script and does **not** change the main `install.ps1` setup above.

> ⚠️ This installer is much larger and takes **significantly longer** to run than the main one
> (it downloads several gigabytes of Android tools, typically around 7-10 minutes), and the
> emulator needs hardware acceleration (WHPX/Hyper-V) which is available on the university lab
> machines but disabled on some others. Only use it from **Worksheet 6 onwards**, when the app
> needs a SQLite database. For Worksheets 1 to 5, use the main `install.ps1` above and run on
> Edge.
