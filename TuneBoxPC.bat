@echo off
REM ============================================================
REM  TuneBox PC - portable launcher (no install needed).
REM  Double-click, then click YES on the admin prompt.
REM ============================================================
fltmc >nul 2>&1
if %errorlevel%==0 goto admin_ok
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b
:admin_ok
set "PS1=%~dp0src\TuneBoxPC.ps1"
if not exist "%PS1%" set "PS1=%~dp0TuneBoxPC.ps1"
start "" powershell -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%PS1%"
exit /b
