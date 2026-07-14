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

; Die fertige Setup-Datei landet neben diesem Skript - das ist die Datei, die
; man auf einen beliebigen Windows-PC kopiert und doppelklickt.
OutputDir=.
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
; shellexec ist PFLICHT, nicht Kosmetik:
; Inno startet "postinstall"-Eintraege bewusst als der urspruengliche,
; NICHT erhoehte Benutzer - und zwar per CreateProcess. JustUpdate.exe verlangt
; im Manifest Adminrechte, CreateProcess kann nicht selbst elevieren und bricht
; mit "CreateProcess schlug fehl; Code 740" ab.
; shellexec geht ueber ShellExecute, das loest den UAC-Dialog aus.
Filename: "{app}\{#ExeName}"; Description: "{#Name} jetzt starten"; Flags: nowait postinstall skipifsilent shellexec

[UninstallDelete]
; Die App legt beim Self-Update die alte EXE als .alt daneben. Ohne diesen
; Eintrag bliebe sie nach der Deinstallation als 60-MB-Leiche im Ordner liegen.
Type: files; Name: "{app}\{#ExeName}.alt"

[Code]
const
  // Die Vorgaenger-Installation ("JustUpdate - System Maintenance Pro", v2.4.5)
  // war ebenfalls ein Inno-Setup und hat einen eigenen Eintrag in "Programme
  // und Features". Ohne Abloesung stehen dort ZWEI JustUpdate-Eintraege und im
  // Programmordner zwei Deinstallierer.
  AltSchluessel = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\JustUpdate - System Maintenance Pro_is1';

function AlterDeinstallierer(): String;
var
  Wert: String;
begin
  Result := '';

  if RegQueryStringValue(HKLM, AltSchluessel, 'UninstallString', Wert) then
    Result := RemoveQuotes(Wert)
  else if RegQueryStringValue(HKLM32, AltSchluessel, 'UninstallString', Wert) then
    Result := RemoveQuotes(Wert);
end;

// Entfernt die Vorgaenger-Installation, BEVOR die neue geschrieben wird.
// Der alte Deinstallierer raeumt nur weg, was er selbst installiert hat (die
// .ps1, sein Symbol, seine Verknuepfungen) - eine per EXE-Migration
// dazugekommene JustUpdate.exe fasst er nicht an.
procedure AltinstallationAbloesen();
var
  Pfad: String;
  Code: Integer;
begin
  Pfad := AlterDeinstallierer();

  if Pfad = '' then
    Exit;

  if FileExists(Pfad) then
  begin
    Exec(Pfad, '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART',
         '', SW_HIDE, ewWaitUntilTerminated, Code);
  end
  else
  begin
    // Der Eintrag steht noch in "Programme und Features", der Deinstallierer
    // ist aber weg (Ordner von Hand geloescht). So ein Zombie-Eintrag laesst
    // sich vom Kunden nicht mehr entfernen - also raeumen wir ihn hier weg.
    RegDeleteKeyIncludingSubkeys(HKLM, AltSchluessel);
    RegDeleteKeyIncludingSubkeys(HKLM32, AltSchluessel);
  end;
end;

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

  if AltinstallationGefunden() and (AlterDeinstallierer() = '') then
  begin
    // Alte PowerShell-Fassung da, aber ohne Installer-Eintrag (von Hand
    // hingelegt). Dann kann das Setup sie nicht abloesen - der Kunde soll
    // wissen, dass er gar nichts tun muesste.
    Result := MsgBox(
      'Auf diesem Rechner liegt bereits die ältere PowerShell-Fassung von JustUpdate.' + #13#10 + #13#10 +
      'Du musst nichts neu installieren: Starte einfach dein vorhandenes JustUpdate — es aktualisiert sich von allein auf die neue Version und biegt die Verknüpfungen um.' + #13#10 + #13#10 +
      'Trotzdem hier weiter installieren?',
      mbConfirmation, MB_YESNO) = IDYES;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Aufgabe: Integer;
begin
  // Vor dem Kopieren: die Vorgaenger-Installation sauber abloesen, damit nicht
  // zwei JustUpdate-Eintraege in "Programme und Features" stehen.
  if CurStep = ssInstall then
    AltinstallationAbloesen();

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
