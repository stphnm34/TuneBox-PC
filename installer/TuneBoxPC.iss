; Inno Setup script for TuneBox PC -> builds a real Setup.exe
; Free tool: https://jrsoftware.org/isdl.php  (install, open this file, click Compile)
; The Setup.exe installs the app, makes shortcuts, and registers an uninstaller
; in Add/Remove Programs that reverses the system changes.

#define AppName "TuneBox PC"
#define AppVersion "1.0.0"
#define AppPublisher "DJ"

[Setup]
AppId={{B6E2D9A1-7C4E-4F3A-9E21-PCOPT0000001}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\TuneBox PC
DefaultGroupName=TuneBox PC
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=TuneBox-PC-Setup
SetupIconFile=..\assets\icon.ico
UninstallDisplayIcon={app}\assets\icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin

[Files]
Source: "..\src\TuneBoxPC.ps1";            DestDir: "{app}\src";    Flags: ignoreversion
Source: "..\src\Cleanup_System_Changes.ps1";  DestDir: "{app}\src";    Flags: ignoreversion
Source: "..\assets\icon.ico";                 DestDir: "{app}\assets"; Flags: ignoreversion
Source: "..\TuneBoxPC.bat";                DestDir: "{app}";        Flags: ignoreversion

[Icons]
Name: "{group}\TuneBox PC";        Filename: "{app}\TuneBoxPC.bat"; IconFilename: "{app}\assets\icon.ico"; WorkingDir: "{app}"
Name: "{autodesktop}\TuneBox PC";  Filename: "{app}\TuneBoxPC.bat"; IconFilename: "{app}\assets\icon.ico"; WorkingDir: "{app}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"

[Run]
Filename: "{app}\TuneBoxPC.bat"; Description: "Launch TuneBox PC now"; Flags: postinstall nowait skipifsilent

[UninstallRun]
; Reverse system changes before files are removed
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\src\Cleanup_System_Changes.ps1"""; Flags: runhidden; RunOnceId: "RevertChanges"
