@echo off
REM ============================================================
REM  TuneBox PC - uninstaller.
REM  Reverses system changes, then removes the app and shortcuts.
REM  Needs admin to undo app-blocking and the scheduled task.
REM ============================================================
fltmc >nul 2>&1
if %errorlevel%==0 goto admin_ok
echo Asking for admin so changes can be fully reversed...
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b
:admin_ok
set "DST=%LOCALAPPDATA%\Programs\TuneBox PC"
echo Reversing system changes (unblocking apps, removing auto power off)...
if exist "%DST%\src\Cleanup_System_Changes.ps1" powershell -NoProfile -ExecutionPolicy Bypass -File "%DST%\src\Cleanup_System_Changes.ps1"
echo Removing shortcuts and files...
del "%USERPROFILE%\Desktop\TuneBox PC.lnk" >nul 2>&1
del "%APPDATA%\Microsoft\Windows\Start Menu\Programs\TuneBox PC.lnk" >nul 2>&1
powershell -NoProfile -Command "Start-Sleep 1; Remove-Item -LiteralPath '%DST%' -Recurse -Force -ErrorAction SilentlyContinue"
echo.
echo TuneBox PC has been uninstalled.
echo (Apps you removed via Debloat can be reinstalled from the Microsoft Store.)
echo.
pause
