@echo off
start "" "%WINDIR%\System32\conhost.exe" --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0AIUsageWidget.ps1"
