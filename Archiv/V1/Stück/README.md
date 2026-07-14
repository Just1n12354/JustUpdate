# Stück — die Quelle von JustUpdate

`MaintenanceProGUI_MODERN.ps1` im Wurzelverzeichnis ist **kein Handarbeits-File mehr,
sondern ein Build-Ergebnis**. Bearbeitet wird hier, pro Teil.

## Warum überhaupt so?

Ausgeliefert wird weiterhin **eine einzige Datei**:

- der **Self-Update** lädt genau `MaintenanceProGUI_MODERN.ps1` von GitHub raw und
  überschreibt sich damit selbst,
- die **EXE** wird aus derselben Datei kompiliert.

Ein Laufzeit-Split (Skript lädt Teildateien beim Start) würde beides brechen — der
eine heruntergeladene File brächte die Teile nicht mit. Also: klein bearbeiten,
gross ausliefern.

## Arbeitsablauf

1. Teil in `Stück\<NN_Name>\<Name>.ps1` bearbeiten.
2. Bauen:
   ```powershell
   powershell -ExecutionPolicy Bypass -File "Stück\build.ps1"
   ```
3. Testen (`tests\checks.ps1`), dann committen — **Teile *und* die gebaute
   `MaintenanceProGUI_MODERN.ps1` zusammen**, sonst zieht sich der Self-Update
   einen alten Stand.

| Aufruf | Wirkung |
|---|---|
| `build.ps1` | baut `MaintenanceProGUI_MODERN.ps1` neu |
| `build.ps1 -Check` | prüft nur, ob der Monolith zu den Teilen passt (Exit 1 bei Abweichung) |
| `build.ps1 -Force` | baut trotz Hand-Änderung am Monolithen |

Der Build bricht ab, wenn das Ergebnis nicht parst oder Zeile 1 keine
`# Version: X.Y.Z` ist (die liest der Self-Update).

**Nicht direkt am Monolithen editieren.** `build.ps1` merkt das (Hash in
`.build_hash`) und stoppt, statt die Änderung still zu überschreiben.

## Die Teile

Reihenfolge = Ordnername. Die Nummer bestimmt, wo der Block in der gebauten Datei landet.

| Ordner | Inhalt |
|---|---|
| `00_Kopf` | Version, `-Auto`-Parameter, Admin-Elevation |
| `01_Changelog_Fenster` | Changelog-Fenster beim Self-Update |
| `02_Single_Instance` | Mutex gegen Doppelstart |
| `03_Self_Update` | Versionsvergleich + Selbstaktualisierung von GitHub |
| `04_EXE_Migration` | Bestandskunden `.ps1` → `JustUpdate.exe` |
| `05_Pfade_und_Log` | Pfade, Logdatei anlegen |
| `06_Uebersetzungen` | DE/EN-Texte |
| `07_XAML_Oberflaeche` | die komplette WPF-GUI |
| `08_Fenster_Laden` | XAML laden, Controls verdrahten |
| `09_Sprache` | Sprachumschaltung (`Update-UI`) |
| `10_Einstellungen` | `settings.json` speichern/laden |
| `11_Init` | Startzustand herstellen |
| `12_Wartung_Start` | `Start-Maintenance`: Apps schliessen, SyncHash, Runspace |
| `13_Worker_Helfer` | Helfer **im** Worker: `L`/`P`/`M`/`Mark`/`Finish-Module`, Heartbeat, `Invoke-MonitoredProcess`, Treiber-Blacklist, Vorabchecks |
| **`20_Wiederherstellungspunkt`** | Modul: Systemwiederherstellungspunkt |
| **`21_Defender`** | Modul: Defender-Signaturen |
| **`22_Windows_Update`** | Modul: Windows Updates (WUA-COM) |
| **`23_Treiber`** | Modul: optionale Treiber |
| **`24_Apps_Winget`** | Modul: winget-Updates |
| **`25_Microsoft_Store`** | Modul: Store-Apps |
| **`26_System_Reparatur`** | Modul: SFC / DISM |
| **`27_Netzwerk`** | Modul: DNS-Cache, IP-Release/Renew |
| **`28_Bereinigung`** | Modul: temporäre Dateien, DO-Cache |
| `30_Zusammenfassung` | Abschluss-Bilanz, Ende des Worker-Runspace |
| `31_Live_Log_und_Timer` | Live-Protokoll-Aufbereitung, UI-Timer |
| `40_Patch_Historie` | Changelog-Ansicht in der App |
| `41_Support_Bericht` | Support-Mail mit Log + JSON |
| `42_Sitzung_Beenden` | Abschluss-Popup, `result_*.json`, Exit-Code |
| `43_Events` | Button-Handler |
| `44_Programmstart` | Fenster zeigen, App starten |

## Zwei Fallen

**1. Die Module sind kein eigenständiger Code.** `20`–`28` laufen *innerhalb* des
Runspace-Scriptblocks aus `12`/`13` und benutzen dessen lokale Helfer (`L`, `P`,
`M`, `Mark`, `Finish-Module`, `IsStopped`, `$sync`, `$cfg`, `$i`, `$total`).
Einzeln aufrufbar sind sie nicht — sie sind Textblöcke mit Kontext-Abhängigkeit.
Neues Modul = Ordner `29_…` anlegen **und** in `12_Wartung_Start` (Config) sowie
`07_XAML_Oberflaeche` (Toggle) eintragen.

**2. UTF-8 **mit BOM** ist Pflicht.** PowerShell 5.1 liest BOM-lose Dateien als ANSI.
Dann matchen die Umlaut-Pattern nicht (SFC-Filter, GUI-Texte) — und ein Skript, das
den Pfad `Stück` literal enthält, greift plötzlich auf `StÃ¼ck` zu und legt sich
lautlos einen falschen Ordner an. `build.ps1` umgeht das über `$PSScriptRoot` und
schreibt die Ausgabe immer mit BOM.
