; =====================================================================
; JustUpdate - Setup (Inno Setup 6)
;
; Gebaut wird das Setup ueber veroeffentlichen.ps1, nicht von Hand:
;   .\veroeffentlichen.ps1            -> dist\JustUpdate.exe + dist\JustUpdate-Setup.exe
;
; Zwei Dinge, die ein Standard-Setup NICHT tut und die hier wichtig sind:
;
; 1. Die App aktualisiert sich SELBST: sie benennt ihre eigene EXE um und legt
;    die neue daneben (SelbstAktualisierung.cs). In "Program Files" darf das nur
;    ein erhoehter Prozess - JustUpdate laeuft ohnehin erhoeht (app.manifest),
;    also passt das. Wuerde man ohne Adminrechte nach %LOCALAPPDATA% installieren,
;    liefe die Wartung selbst ohne Rechte und die halben Module braechen ab.
;
; 2. Bestandskunden der PowerShell-Fassung sollen NICHT doppelt installieren.
;    Die erkennen wir an einer vorhandenen MaintenanceProGUI_MODERN.ps1 und
;    weisen darauf hin, dass ihr vorhandenes JustUpdate sich von allein
;    aktualisiert (Self-Update 2.7.7 -> Migration auf die EXE).
; =====================================================================

#define Name        "JustUpdate"
#define Firma       "Itin TechSolutions"
#define Web         "https://itintechsolutions.ch"
#define ExeName     "JustUpdate.exe"
#define Quelle      "..\dist\JustUpdate.exe"

; Version wird von veroeffentlichen.ps1 hereingereicht (/DVersion=2.7.9)
#ifndef Version
  #define Version "0.0.0"
#endif

[Setup]
; Feste AppId: daran erkennt Inno eine bestehende Installation und ersetzt sie,
; statt eine zweite danebenzustellen. NIEMALS aendern.
AppId={{8F3C1B27-4E2A-4B6D-9C71-2A5D8E4F1C93}
AppName={#Name}
AppVersion={#Version}
AppVerName={#Name} {#Version}
AppPublisher={#Firma}
AppPublisherURL={#Web}
AppSupportURL={#Web}
VersionInfoVersion={#Version}

DefaultDirName={autopf}\{#Name}
DefaultGroupName={#Name}
DisableProgramGroupPage=yes
DisableDirPage=auto

; Die Wartungsmodule brauchen Adminrechte - also auch das Setup, damit es nach
; "Program Files" schreiben darf.
PrivilegesRequired=admin

OutputDir=..\dist
OutputBaseFilename=JustUpdate-Setup
SetupIconFile=..\JustUpdate.Ui\justupdate.ico
UninstallDisplayIcon={app}\{#ExeName}
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "de"; MessagesFile: "compiler:Languages\German.isl"

[Tasks]
Name: "desktopicon"; Description: "Verknüpfung auf dem Desktop anlegen"; GroupDescription: "Zusätzliche Symbole:"

[Files]
Source: "{#Quelle}"; DestDir: "{app}"; DestName: "{#ExeName}"; Flags: ignoreversion
; Neben der EXE, damit die Patch-Notes auch ohne Internet lesbar sind.
Source: "..\..\CHANGELOG.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#Name}"; Filename: "{app}\{#ExeName}"
Name: "{group}\{#Name} deinstallieren"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#Name}"; Filename: "{app}\{#ExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#ExeName}"; Description: "{#Name} jetzt starten"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Die App legt beim Self-Update die alte EXE als .alt daneben. Ohne diesen
; Eintrag bliebe sie nach der Deinstallation als 60-MB-Leiche im Ordner liegen.
Type: files; Name: "{app}\{#ExeName}.alt"

[Code]
function AltinstallationGefunden(): Boolean;
var
  Pfade: TArrayOfString;
  I: Integer;
begin
  Result := False;

  SetArrayLength(Pfade, 4);
  Pfade[0] := ExpandConstant('{autopf}\JustUpdate\MaintenanceProGUI_MODERN.ps1');
  Pfade[1] := ExpandConstant('{localappdata}\JustUpdate\MaintenanceProGUI_MODERN.ps1');
  Pfade[2] := ExpandConstant('{userdocs}\JustUpdate\MaintenanceProGUI_MODERN.ps1');
  Pfade[3] := ExpandConstant('{userdesktop}\MaintenanceProGUI_MODERN.ps1');

  for I := 0 to GetArrayLength(Pfade) - 1 do
  begin
    if FileExists(Pfade[I]) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

function InitializeSetup(): Boolean;
begin
  Result := True;

  if AltinstallationGefunden() then
  begin
    Result := MsgBox(
      'Auf diesem Rechner ist bereits die ältere PowerShell-Fassung von JustUpdate installiert.' + #13#10 + #13#10 +
      'Du musst nichts neu installieren: Starte einfach dein vorhandenes JustUpdate — es aktualisiert sich von allein auf die neue Version und biegt die Verknüpfungen um.' + #13#10 + #13#10 +
      'Trotzdem hier weiter installieren?',
      mbConfirmation, MB_YESNO) = IDYES;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Aufgabe: Integer;
begin
  if CurStep = ssPostInstall then
  begin
    // Eine geplante Wartung aus der Vorgaengerversion zeigt noch auf den alten
    // Pfad und wuerde ins Leere laufen. Die Aufgabe wird entfernt; der Kunde
    // richtet sie in der App neu ein (Wecker-Symbol).
    Exec(ExpandConstant('{sys}\schtasks.exe'),
         '/Delete /TN "JustUpdate Wartung" /F',
         '', SW_HIDE, ewWaitUntilTerminated, Aufgabe);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Aufgabe: Integer;
begin
  if CurUninstallStep = usUninstall then
  begin
    // Ohne das bliebe eine geplante Aufgabe zurueck, die eine geloeschte EXE
    // startet - Windows meldet das dann woechentlich als Fehler.
    Exec(ExpandConstant('{sys}\schtasks.exe'),
         '/Delete /TN "JustUpdate Wartung" /F',
         '', SW_HIDE, ewWaitUntilTerminated, Aufgabe);
  end;
end;
