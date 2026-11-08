@echo off
setlocal
title RustDesk Remote Access Setup
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
set "setup_result=%errorlevel%"
echo.
if not "%setup_result%"=="0" echo Setup did not complete. Review the error above.
pause
exit /b %setup_result%
