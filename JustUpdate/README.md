# JustUpdate (C#)

Windows-Wartung als Konsolen-Anwendung. Neun Module, die nacheinander laufen:
Wiederherstellungspunkt, Defender-Signaturen, Windows-Updates, Treiber, Apps
(winget), Microsoft Store, SFC/DISM, Netzwerk-Reset, Temp-Bereinigung.

Ziel-Framework: **net10.0-windows**.

## Aufbau

```
JustUpdate/
  Program.cs              Dispatcher: Modulauswahl, Log, Zusammenfassung, Exit-Code
  app.manifest            requireAdministrator
  Infrastruktur/
    Mitschnitt.cs         Konsole + Logdatei gleichzeitig, Status je Modul
  Module/
    Wiederherstellungspunkt.cs
    Defender.cs
    WindowsUpdate.cs
    Treiber.cs
    Apps.cs
    Store.cs
    SystemReparatur.cs
    Netzwerk.cs
    Bereinigung.cs
tests/
  checks.ps1              Selbsttest ohne UAC
```

Ein Modul = eine Datei = eine Klasse mit `Name` und `Ausfuehren()`. Neues Modul:
Datei anlegen und eine Zeile in die Modul-Tabelle in `Program.cs` eintragen.

Anders als die PowerShell-Version braucht das **kein Build-Skript**: der Compiler
zieht alle `.cs`-Dateien des Projekts von selbst zusammen. Es gibt keinen
Monolithen, der aus Teilen wieder zusammengesetzt werden müsste.

## Starten

Die App verlangt **Administratorrechte** (`app.manifest` →
`requireAdministrator`). Ohne Elevation überspringen fünf Module ihre Arbeit.

```powershell
JustUpdate.exe                       # volle Wartung, alle neun Module
JustUpdate.exe defender bereinigung  # nur die genannten Module
JustUpdate.exe --help                # Modulliste
```

Module: `wiederherstellungspunkt`, `defender`, `windowsupdate`, `treiber`,
`apps`, `store`, `reparatur`, `netzwerk`, `bereinigung`

**Achtung bei der vollen Wartung:** sie installiert echte Windows-Updates und
Treiber, führt `winget upgrade --all` aus, lässt SFC/DISM laufen und macht einen
`netsh int ip reset` (Netzwerk-Stack, verlangt danach einen Neustart). Rechne mit
etwa einer Stunde. Zum Testen einzelne Module angeben.

## Ausgabe

| | |
|---|---|
| Log | `%LOCALAPPDATA%\JustUpdate\logs\Maintenance_<Zeitstempel>.log` (UTF-8, mit Zeitstempel pro Zeile) |
| Zusammenfassung | Status + Dauer pro Modul am Ende |
| Exit-Code | `0` = alles OK, `1` = Warnungen, `2` = Fehler |

Der Modul-Status wird aus den Markern abgeleitet, die die Module ohnehin ausgeben:
`[FEHLER]` → Fehler, `[WARNUNG]` → Warnung, sonst OK.

## Entwickeln

```powershell
dotnet build
powershell -ExecutionPolicy Bypass -File tests\checks.ps1
```

Die Tests laufen über `dotnet <dll>` statt über die EXE — das umgeht das
`requireAdministrator`-Manifest, sodass ohne Elevation getestet werden kann.

**Visual Studio:** Wegen des Manifests schlägt F5 aus einem nicht-elevierten VS
fehl. VS als Administrator starten.

## Bekannte Einschränkung

Sechs der neun Module sind **PowerShell-Skripte in C#-Stringliteralen**, die über
`powershell.exe -ExecutionPolicy Bypass -Command <skript>` gestartet werden. Das
hat zwei Konsequenzen, die man kennen muss:

1. **Kein AV-Vorteil gegenüber der PowerShell-Version.** Eine EXE, die
   `powershell.exe` mit `-ExecutionPolicy Bypass` und einem langen Inline-Skript
   startet, ist ein klassischer EDR-/Defender-ASR-Trigger.
2. **Der Compiler prüft die eigentliche Logik nicht** — sie liegt in Strings.

Wer den Nutzen von C# wirklich einlösen will, spricht die Windows Update Agent
API über typisiertes COM-Interop (`WUApiLib`) direkt aus C# an und ruft
winget/sfc/dism über `Process` auf — ohne PowerShell dazwischen.
