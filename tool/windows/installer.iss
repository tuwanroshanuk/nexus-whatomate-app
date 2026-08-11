#ifndef BuildDir
  #error BuildDir must point to the Flutter Windows release directory
#endif
#ifndef RedistPath
  #error RedistPath must point to vc_redist.x64.exe
#endif
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif

[Setup]
AppId={{6FBBF30B-03E2-4B56-A3A0-7D6FB31FB44A}
AppName=Nexus One
AppVersion={#AppVersion}
AppPublisher=Nexus Cloud
DefaultDirName={autopf}\Nexus One
DefaultGroupName=Nexus One
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=Nexus-One-Windows-Setup-{#AppVersion}
SetupIconFile=app_icon.ico
UninstallDisplayIcon={app}\whatomate_app.exe
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked
Name: "startup"; Description: "Start Nexus One when I sign in (recommended for receiving calls)"; GroupDescription: "Calling:"; Flags: checkedonce

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#RedistPath}"; DestDir: "{tmp}"; DestName: "vc_redist.x64.exe"; Flags: deleteafter

[Icons]
Name: "{autoprograms}\Nexus One"; Filename: "{app}\whatomate_app.exe"
Name: "{autodesktop}\Nexus One"; Filename: "{app}\whatomate_app.exe"; Tasks: desktopicon
Name: "{userstartup}\Nexus One"; Filename: "{app}\whatomate_app.exe"; Tasks: startup

[Run]
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Installing Microsoft Visual C++ runtime..."; Flags: waituntilterminated
Filename: "{app}\whatomate_app.exe"; Description: "Launch Nexus One"; Flags: nowait postinstall skipifsilent
