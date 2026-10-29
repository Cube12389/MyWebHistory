@echo off
setlocal
chcp 65001 >nul
title DSH profile setup

rem --- elevate if needed ---
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set "PS1=%~dp0setup-dsh-profile.ps1"
if not exist "%PS1%" (
    echo [ERROR] setup-dsh-profile.ps1 not found next to this script.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
set RC=%errorLevel%

echo.
if %RC% neq 0 (
    echo [FAILED] exit code %RC% - see setup-log.txt
) else (
    echo [DONE] Fully quit DSH and start it again, then refresh the page.
)
pause
exit /b %RC%
