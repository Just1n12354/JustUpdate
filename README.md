# JustUpdate — Wartungs-GUI für Windows

Wartungs-Tool für Windows-PCs: One-Click-Installation von Updates, Treibern, SFC/DISM-Reparatur, Bereinigung und mehr.

## Voraussetzungen

- Windows 10/11 (PowerShell 5.1 oder PowerShell 7)
- Administratorrechte (für Reparatur-Module, Updates, Neustart)
- Internetverbindung (für Winget, Windows Update, Treiber, Defender-Signaturen)

## Installation

1. Lade die neueste Version von [GitHub Releases](https://github.com/Just1n12354/JustUpdate/releases) herunter.
2. Entpacke den Ordner an einen festen Ort (z. B. `%USERPROFILE%\JustUpdate`).
3. Starte `MaintenanceProGUI_MODERN.ps1` (oder die kompilierte `.exe`, falls verfügbar).

Alternativ: Starte JustUpdate und klicke auf **Self-Update**, es lädt die neueste Version automatisch herunter.

## Verwendung

### Interaktiver Modus (GUI)

1. Starte das Skript — eine WPF-GUI öffnet sich.
2. Wähle die gewünschten Wartungs-Module aus:
   - **Wiederherstellungspunkt** — Sicherungspunkt erstellen
   - **Windows Defender** — Signaturen aktualisieren
   - **Windows Updates** — KB-Updates installieren
   - **Treiber** — Optionale Treiber über Microsoft Update
   - **Apps (Winget)** — Third-Party-Updates (Chrome, Firefox, 7-Zip, …)
   - **Microsoft Store** — Store-App-Updates
   - **System-Reparatur** — SFC / DISM Komponentenspeicher-Reparatur
   - **Netzwerk-Reparatur** — DNS-Cache leeren, IP-Release/Renew
   - **Bereinigung** — temporäre Dateien, Delivery-Optimization-Cache
3. Klicke auf **Wartung starten** — die Module werden nacheinander abgearbeitet.
4. Am Ende siehst du die Zusammenfassung mit OK/Warnung/Fehler pro Modul.

### Automatik-Modus

Für ungeplante Wartung (Task Scheduler, Cron-ähnliche Aufgaben):

```powershell
MaintenanceProGUI_MODERN.ps1 -Auto
```

Oder setze die Umgebungsvariable `JUSTUPDATE_AUTO=1`. Im Automatik-Modus:
- Keine GUI, keine Dialoge
- Keine laufenden Programme werden geschlossen
- Exit-Code: `0` = OK, `1` = Warnungen, `2` = Fehler
- Ergebnis wird als `result_<timestamp>.json` im Log-Ordner gespeichert

### Zeitplan

Klicke auf das **Uhr-Symbol** in der Titelleiste, um eine wöchentliche geplante Aufgabe anzulegen (Sonntag 11:00 Uhr, höchste Rechte). Ein erneuter Klick entfernt sie wieder.

## Ausgabe

| Datei | Beschreibung |
|---|---|
| `logs\Maintenance_YYYY-MM-DD_HH-mm-ss_v<X>.log` | Vollständiges Protokoll aller Lauf-Zeilen |
| `logs\result_YYYY-MM-DD_HH-mm-ss.json` | Maschinenlesbarer Report (Host, Version, Dauer, pro-Modul-Status, `rebootRequired`) |

## Konfiguration

Einstellungen (Modul-Auswahl, Sprache) werden in `settings.json` im Log-Ordner gespeichert und beim nächsten Start automatisch wiederhergestellt.

## Versions-Update

JustUpdate kann sich selbst aktualisieren. Beim Self-Update wird ein Changelog-Fenster gezeigt (was ist neu seit deiner Version).

## Support

Bei Problemen: Klicke im Fehler-Fenster auf **„Bericht an Support senden"** — die Mail ist vorausgefüllt mit Log und Ergebnis-JSON.

Oder kontaktiere: [info@itintechsolutions.ch](mailto:info@itintechsolutions.ch)

## Lizenz

Copyright (c) 2026 Itin TechSolutions / Justin Itin  
Alle Rechte vorbehalten.