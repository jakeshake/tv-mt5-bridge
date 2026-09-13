@echo off
REM Entry point dockur/windows runs automatically after Windows setup
REM completes (files under the mounted oem/ folder land in C:\OEM inside
REM the VM, and install.bat there is executed once, unattended).
REM All real work happens in PowerShell for readability/logging.

set LOGFILE=C:\OEM\provision.log
echo [%date% %time%] Starting MT5 provisioning > "%LOGFILE%"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\OEM\setup-mt5.ps1" >> "%LOGFILE%" 2>&1

echo [%date% %time%] Provisioning script exited with code %ERRORLEVEL% >> "%LOGFILE%"
