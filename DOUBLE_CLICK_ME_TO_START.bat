@echo off
setlocal enabledelayedexpansion
title Southsea Cinema - Portable Dev Environment

:: Launch PowerShell runner
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bin\launch.ps1"
if %ERRORLEVEL% neq 0 (
    echo.
    echo ========================================================
    echo An error occurred during environment startup.
    echo Press any key to close this window.
    echo ========================================================
    pause >nul
)
