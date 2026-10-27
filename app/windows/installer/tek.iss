; Tek for Windows: installs for the current user only, so no administrator
; rights are needed to install or update.
; Build: ISCC /DAppVersion=1.2.3 tek.iss (after `flutter build windows` and
; copying tek-core.exe, wintun.dll and the VC++ runtime next to Tek.exe).

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#define AppExe "Tek.exe"
#define SourceDir "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{6C1E0D4B-3F5A-4E7B-9B0C-5A2D8E1F7C34}
AppName=Tek
AppVersion={#AppVersion}
AppVerName=Tek {#AppVersion}
AppPublisher=TekVPN
AppPublisherURL=https://tekvpn.com
AppSupportURL=https://tekvpn.com
VersionInfoVersion={#AppVersion}
VersionInfoProductName=Tek
DefaultDirName={localappdata}\Programs\Tek
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir=..\..\..\dist
OutputBaseFilename=Tek-{#AppVersion}-windows-x64-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName=Tek
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
CloseApplications=no
ShowLanguageDialog=no
LanguageDetectionMethod=uilanguage

[Languages]
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Tek"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\Tek"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Registry]
; tek:// links from tekvpn.com ("Открыть в приложении") open Tek.
Root: HKCU; Subkey: "Software\Classes\tek"; ValueType: string; ValueName: ""; ValueData: "URL:Tek"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\tek"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\tek\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"",0"
Root: HKCU; Subkey: "Software\Classes\tek\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" ""%1"""

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,Tek}"; Flags: nowait postinstall skipifsilent

[Code]
// Closes a running Tek before its files are replaced or removed. The core
// notices that the app is gone, turns the VPN off and puts the system proxy
// back, then exits; the pause gives it time to do that.
procedure StopTek();
var
  Code: Integer;
begin
  if Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM {#AppExe}', '', SW_HIDE, ewWaitUntilTerminated, Code) and (Code = 0) then
    Sleep(3000);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  StopTek();
  Result := '';
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    StopTek();
end;
