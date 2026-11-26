@echo off
REM ============================================================
REM  TuneBox PC - installer (no admin needed to install).
REM  Copies the app into your user folder and makes shortcuts.
REM ============================================================
echo Installing TuneBox PC...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$src = Split-Path -Parent '%~f0';" ^
  "$dst = Join-Path $env:LOCALAPPDATA 'Programs\TuneBox PC';" ^
  "New-Item -ItemType Directory -Force -Path $dst, (Join-Path $dst 'src'), (Join-Path $dst 'assets') | Out-Null;" ^
  "Copy-Item (Join-Path $src 'src\TuneBoxPC.ps1') (Join-Path $dst 'src') -Force;" ^
  "Copy-Item (Join-Path $src 'src\Cleanup_System_Changes.ps1') (Join-Path $dst 'src') -Force;" ^
  "Copy-Item (Join-Path $src 'assets\icon.ico') (Join-Path $dst 'assets') -Force;" ^
  "Copy-Item (Join-Path $src 'TuneBoxPC.bat') $dst -Force;" ^
  "Copy-Item (Join-Path $src 'Uninstall.bat') $dst -Force;" ^
  "$ws = New-Object -ComObject WScript.Shell;" ^
  "$launch = Join-Path $dst 'TuneBoxPC.bat';" ^
  "$icon = Join-Path $dst 'assets\icon.ico';" ^
  "function MakeLnk($p){ $s=$ws.CreateShortcut($p); $s.TargetPath=$launch; $s.WorkingDirectory=$dst; $s.IconLocation=\"$icon,0\"; $s.Description='TuneBox PC'; $s.Save(); $b=[IO.File]::ReadAllBytes($p); $b[0x15]=$b[0x15] -bor 0x20; [IO.File]::WriteAllBytes($p,$b) }" ^
  "MakeLnk (Join-Path ([Environment]::GetFolderPath('Desktop')) 'TuneBox PC.lnk');" ^
  "$sm = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\TuneBox PC.lnk'; MakeLnk $sm;" ^
  "Write-Host 'Installed to' $dst"
echo.
echo Done. Open "TuneBox PC" from the Start menu or desktop.
echo (Click YES on the admin prompt when it opens.)
echo.
pause
