@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-dsh.ps1" -PauseOnError
exit /b %ERRORLEVEL%
