# Building a standalone .exe (optional)

The project runs fine as-is: `TuneBoxPC.bat` launches `src/TuneBoxPC.ps1`.
You only need an `.exe` if you want a single clickable file with the icon baked in.

## A) Real installer (recommended) - Inno Setup
1. Install Inno Setup (free): https://jrsoftware.org/isdl.php
2. Open `installer/TuneBoxPC.iss` in Inno Setup.
3. Click **Build > Compile**.
4. `dist/TuneBox-PC-Setup.exe` is created. That's your installer.

## B) Single-file app .exe - PS2EXE
```powershell
Install-Module ps2exe -Scope CurrentUser
cd path\to\TuneBox-PC
Invoke-ps2exe .\src\TuneBoxPC.ps1 .\dist\TuneBoxPC.exe -iconFile .\assets\icon.ico -requireAdmin -noConsole -title "TuneBox PC"
```

## Antivirus note
Both methods make an **unsigned** `.exe`. Security tools such as SentinelOne,
Defender or others may warn about it or quarantine it, partly because the app's
"Block apps" feature uses a Windows setting (IFEO Debugger) that malware also uses.

On your **own** PC you can add an exclusion for the install folder in your
antivirus. On a **managed/work** PC, ask whoever runs the antivirus to allow-list
it - the full source is right here for them to review. Do not try to hide the app
from a security tool; that is what malware does and it makes things worse.
The only fix that travels with the app is a paid code-signing certificate.
