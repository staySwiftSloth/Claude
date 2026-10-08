@echo off
rem dockur/windows runs C:\OEM\install.bat at the final step of unattended setup.
rem Hardening happens before anyone logs in for real. Results: C:\OEM\harden.log, C:\OEM\harden-report.json
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0harden.ps1" -Config "%~dp0selection.json" >> "%~dp0install.log" 2>&1
rem Always return success so a single failed removal can't stall Windows setup; check the report instead.
exit /b 0
