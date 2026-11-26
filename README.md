# TuneBox PC

A free, open-source optimizer and maintenance app for **Windows 10 and 11**, with a
simple dark UI. It uses only tools built into Windows, so nothing extra has to be
installed to run it.

![icon](assets/icon.ico)

## Features

**Clean up**
- Clean temp files (shows MB freed)
- Empty Recycle Bin
- Clean Windows Update leftovers

**Speed**
- Ultimate Performance / Balanced power plans
- View startup apps
- Visual effects settings
- Optimize drives (SSD TRIM / HDD defrag)

**Check**
- PC health check (CPU, RAM, disks, top apps)
- Drive health check (health %, temperature, lifespan estimate, read-speed test)
- PC activity history (uptime, on-time per day, most-used and recently opened apps)

**Fix**
- Flush DNS
- Repair Windows files (DISM + SFC)

**Tools**
- **Debloat and block apps** - remove preinstalled junk apps, turn off ads and
  suggestions, turn off background features, and optionally *block* chosen apps
  (blocking is reversible - untick and Apply to allow again). A restore point is
  created before any change.
- **Auto power off** - when the screen turns off from inactivity, the PC shuts down
  60 seconds later; moving the mouse in that time cancels it.

The top of the window shows live CPU, memory, system-drive and uptime cards.

## Install

Download or clone this repo, then:

- **Easy:** run `Install.bat`. It copies the app into your user folder and makes a
  Start menu + desktop shortcut with the icon. Launch it from there (click **Yes**
  on the admin prompt).
- **Portable:** just run `TuneBoxPC.bat` from the folder - no install.
- **Real setup .exe:** see `installer/BUILD_EXE.md` to build one with Inno Setup.

To remove it, run `Uninstall.bat` (it reverses the system changes first, then
deletes the app).

## Requirements
- Windows 10 or 11
- Windows PowerShell 5 (built in) and admin rights (the app asks on launch)

## A note on antivirus
The app changes system settings, so some antivirus tools (SentinelOne, Defender and
others) may warn about it - especially the app-blocking feature, which uses a Windows
setting that malware also uses. On your own PC you can add the install folder as an
exclusion. On a work PC, ask whoever manages the antivirus to review the source
(it's all here) and allow-list it. See `installer/BUILD_EXE.md` for details.

## Warning / disclaimer
This tool changes Windows settings, deletes temporary files, and can block apps and
shut the PC down. It tries to be safe - it avoids risky "tweaks", asks before
destructive actions, and can create a restore point - but **use it at your own
risk**. Always create a restore point before making changes. The authors are not
responsible for any data loss or problems.

## How it works / contributing
Everything is a single PowerShell script, `src/TuneBoxPC.ps1` (WPF for the UI).
It's readable and commented, so feel free to open issues or PRs.

## License
MIT - see [LICENSE](LICENSE).
