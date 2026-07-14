# JustUpdate

Windows-Wartung mit Bordmitteln: Wiederherstellungspunkt, Defender, Windows Update,
Treiber, winget, Microsoft Store, SFC/DISM, Netzwerk-Reset, Temp-Bereinigung.

Itin TechSolutions — info@itintechsolutions.ch

---

## ⚠️ Diese zwei Dateien im Wurzelverzeichnis NICHT verschieben

Sie sind keine Doku, sie sind **Auslieferungsinfrastruktur**. Jede installierte
Kopie von JustUpdate ruft sie bei jedem Start über `raw.githubusercontent.com` ab:

| Datei | Wer ruft sie ab | Passiert beim Verschieben |
|---|---|---|
| `MaintenanceProGUI_MODERN.ps1` | Self-Update aller v1-Installationen | 404 → **kein Kunde bekommt je wieder ein Update** (stiller Fehlschlag, der Kunde merkt nichts) |
| `CHANGELOG.md` | Patch-Notes-Fenster in v1 **und** v2 | 404 → Patch-Notes bleiben leer |

Beide sind **generiert bzw. gespiegelt**, nicht handgepflegt:
`MaintenanceProGUI_MODERN.ps1` entsteht aus `Archiv/V1/Stück/` über
`Archiv/V1/Stück/build.ps1` und wird von dort in die Wurzel kopiert.

---

## Aufbau

```
MaintenanceProGUI_MODERN.ps1   v1 (PowerShell) - Auslieferungsstand, generiert
CHANGELOG.md                   Versions-Historie, wird von beiden Versionen gelesen
Archiv/V1/                     Quelle von v1: Stück/<NN_Name>/<Name>.ps1 + build.ps1
JustUpdate/                    v2 (C#) - Visual-Studio-Projektmappe
  JustUpdate/                    Motor: Module/ (die neun Wartungsmodule) + Program.cs
  JustUpdate.Ui/                 Oberfläche (WPF) - das, was der Kunde bekommt
  veroeffentlichen.ps1           baut die Kunden-EXE und legt das GitHub-Release an
```

`JustUpdate` (Konsole) heisst als Datei **JustUpdateCli.exe**. Der Name
`JustUpdate.exe` gehört der Oberfläche — nach genau diesem Dateinamen sucht die
EXE-Migration im Release.

---

## Der Update-Weg zum Kunden

```
v1 2.7.6  ──Self-Update──▶  v1 2.7.7  ──EXE-Migration──▶  v2 2.7.8 (EXE)
 (.ps1)      raw main         (.ps1)      Release-Asset       ab hier
                                                          eigenes Self-Update
```

1. **Self-Update** (`Archiv/V1/Stück/03_Self_Update`): vergleicht `# Version:`
   aus Zeile 1 mit der Datei auf `main`, fragt nach, überschreibt sich, startet neu.
   Läuft nur beim **manuellen** Start — im Automatik-Modus würde die Rückfrage
   einen unbeaufsichtigten Lauf blockieren.
2. **EXE-Migration** (`Archiv/V1/Stück/04_EXE_Migration`): lädt das Release-Asset
   `JustUpdate.exe`, prüft PE-Header und Grösse, biegt Desktop- und
   Startmenü-Verknüpfungen um, startet die neue App. Einmalig (Marker
   `.exe_migrated`, enthält den Rückweg). Notbremse: `JUSTUPDATE_MIGRATE_EXE=0`.
3. **Ab v2** aktualisiert sich die App selbst über die GitHub-Releases
   (`JustUpdate.Ui/SelbstAktualisierung.cs`). Abschaltbar mit
   `JUSTUPDATE_NO_SELFUPDATE=1`.

**Kunden mit einer `.exe`-Installation aus der Zeit vor v2.7.8 werden nicht
erreicht** — sowohl Self-Update als auch Migration prüfen `-not $isExe` und
überspringen sich dort.

## Neue Version veröffentlichen

```powershell
cd JustUpdate
.\veroeffentlichen.ps1                 # baut nur:  dist\JustUpdate.exe
.\veroeffentlichen.ps1 -Release 2.7.9  # baut + legt das GitHub-Release an
```

Die EXE ist **self-contained** (der Kunde hat kein .NET-Runtime) und darum rund
62 MB gross. Das Release-Asset **muss** `JustUpdate.exe` heissen.

Vorher die Version in `JustUpdate.Ui/JustUpdate.Ui.csproj` (`<Version>`) hochsetzen
und den Abschnitt in `CHANGELOG.md` ergänzen — das Self-Update vergleicht den
`tag_name` des Releases mit der Assembly-Version.

> **Die EXE ist nicht signiert.** SmartScreen warnt, Virenscanner können sie in
> Quarantäne legen (in v1 für HP Wolf Security dokumentiert). Vor grösseren
> Ausrollungen gehört hier eine Code-Signatur hin.

## Entwickeln

```powershell
cd JustUpdate
dotnet build                                    # beide Projekte
dotnet run --project JustUpdate -- bereinigung  # einzelnes Modul, ohne Oberfläche
```

Die Module brauchen Administratorrechte (`app.manifest`). Ein Lauf ohne
Elevation meldet das und überspringt die betroffenen Module.

Jeder Lauf schreibt ein Protokoll nach
`%LOCALAPPDATA%\JustUpdate\logs\Maintenance_<Zeitstempel>.log`.
Exit-Codes: `0` = OK, `1` = Warnungen, `2` = Fehler.
