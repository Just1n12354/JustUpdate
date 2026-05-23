## v2.6.9

**Neu: Patch-Notes-Fenster komplett uebersichtlich neu gebaut.**
- Vorher war alles Plain-Text in einer Box - Versionen liefen
  ineinander, `**fett**` und `` `code` `` wurden roh angezeigt,
  Listen nicht erkennbar.
- Jetzt:
  - **Sidebar links** mit klickbarer Versions-Liste - ein Klick
    scrollt direkt zur entsprechenden Version. Aktuelle Version
    farblich (rot) hervorgehoben.
  - **Cards rechts**, eine pro Version, mit eigenem Header,
    Trenner und sauber eingerueckten Stichpunkten.
  - **Markdown wird gerendert:** `**fett**` -> echte Fett-Schrift,
    `` `code` `` -> Consolas mit Akzent-Farbe, `- ` -> Bullet,
    `1. ` -> Nummerierte Liste, `> ` -> Zitat-Block mit rotem
    Strich links.
  - **"AKTUELL"-Badge** rot rechts neben der laufenden Version,
    damit der Kunde sofort sieht, wo er steht.
  - Verschiebbar durch Klick auf die Header-Leiste, Esc schliesst.

## v2.6.8

**Vollstaendige Versions-Historie im Patchlog.**
- Der Patchlog-Button (eingefuehrt in v2.6.7) zeigte bisher nur die
  Versionen ab v2.5.1. Jetzt **alle Versionen** von der ersten EXE-
  Phase (2026-05-03, vor v2.3.4) bis heute. Kunden sehen direkt im
  Patchlog-Fenster die komplette Entstehungsgeschichte:
  - **Pre-History (v2.0 - v2.3.3):** EXE-basierte Variante mit
    C#-Launcher, verworfen wegen Smart-App-Control-Block.
  - **v2.3.4 - v2.4.8:** PowerShell-MODERN-Phase (UI rot, Watchdog,
    Pre-Download-Hinweise, Heartbeat, ...).
  - **v2.5.1 - v2.6.8:** Aktuelle Phase mit Release-Pipeline, Self-
    Update, Fleet-Reporting, Tray-Apps-Handling, Mail-Flow.

## v2.6.7

**Neu: Patch-Notes-Button in der Titelleiste.**
- Oben links neben dem "i"-Button gibt es jetzt einen "?"-Button.
  Ein Klick oeffnet ein scrollbares Fenster mit der **kompletten
  Versions-Historie** - von der ersten Version bis heute. Kunden
  koennen jederzeit nachsehen, was sich in welcher Version geaendert
  hat, ohne den Support anschreiben zu muessen.
- Quelle: lokales CHANGELOG.md, Fallback Online vom Verteil-Repo
  (`github.com/Just1n12354/JustUpdate`). Funktioniert also auch bei
  einer reinen EXE-Installation, solange Internet da ist.

## v2.6.6

**UX: "Mail senden" / "Schliessen" statt "Ja" / "Nein".**
- Der Abschluss-Dialog hatte vorher Ja/Nein-Buttons. Kunden klickten
  reflexhaft "Ja" und wunderten sich, warum eine Mail-Vorschau aufging.
  Jetzt eigener Dialog im Programm-Stil mit explizit beschrifteten
  Buttons: links rot "Mail an Support senden", rechts neutral
  "Schliessen". "Schliessen" ist Default - Enter loest also KEINE
  Mail mehr ungewollt aus.

**Bugfix: "Keine Internet-Verbindung" obwohl online.**
- Single-HEAD-Request auf microsoft.com mit 5 s Timeout schlug bei
  DNS-Lag, IPv6-Problemen oder kurz nicht erreichbarem MS-Server
  faelschlich fehl. Jetzt:
  1. **Windows NetworkListManager (COM)** zuerst befragt - die selbe
     API, die das Windows-Tray-Icon "Verbunden" nutzt.
  2. Fallback: HTTP-HEAD gegen **microsoft.com / github.com /
     cloudflare.com** mit je 8 s Timeout, Abbruch bei erstem Treffer.
  Nur wenn ALLES fehlschlaegt -> Offline-Hinweis.

**Bugfix: Vor-Update-Schritt listet jetzt welche Programme.**
- Vorher: "12 laufende Programme geschlossen" - Kunden dachten OBS sei
  dabei gewesen, obwohl OBS gar nicht lief. Jetzt mit konkreter Liste:
  "12 Programme geschlossen -> Steam, Discord, OneDrive, Teams, ...".
  Auch der Fall "0 Programme gefunden" wird klar gemeldet.

**Bugfix: Mail enthielt nur die letzten 50 Log-Zeilen.**
- Outlook-Variante: jetzt ist der **vollstaendige Log direkt im Mail-
  Body** (Outlook hat keine Laengenbegrenzung) - plus weiterhin als
  Anhang. Support sieht alles ohne Attachment-Klick.
- mailto-Fallback (Thunderbird/Webmail): kann technisch nur ~1800
  Zeichen URL-Body. Loesung: kompakter Body in der URL, voller Log
  landet automatisch in der **Zwischenablage** - der Kunde drueckt
  einmal Strg+V im Mail-Body.

## v2.6.5

**Bugfix: Winget scheitert nicht mehr an Tray-Apps (OBS, Epic, Steam, …).**
- Vor-Update-Schritt erweitert: zusaetzliche Whitelist haerter beendeter
  Tray-Blocker (obs64, EpicGamesLauncher, EpicWebHelper, Steam, Discord,
  Spotify, Teams, OneDrive, Slack, Code, Cursor, Zoom, WhatsApp,
  Telegram u.a.). Bisher liefen die ohne MainWindow im Tray weiter und
  sperrten Installer-Dateien -> winget brach mit Exit 1603 / 6 ab.

**Neu: Winget-Retry pro Paket bei "Datei in Verwendung".**
- Output-Stream wird pro Paket geparst. Bei 1603 / 6 oder Klartext
  "von anderer Anwendung verwendet" -> EIN gezielter Retry nach
  Tray-Kill (`winget upgrade --id <Paket> --exact`). Status zeigt
  jetzt "Teilweise aktualisiert (3 OK) - noch offen: OBS Studio" statt
  Exit-Code-Zahl.

**Support-Mail: nur noch "Senden" klicken.**
- Outlook installiert -> COM-Automation oeffnet fertige Mail mit Log +
  result-JSON bereits angehaengt. Kein Outlook -> mailto-Fallback packt
  die letzten 50 Log-Zeilen + Modul-Status direkt in den Mail-Body.

## v2.6.4

**Bugfix: Self-Update überlebt jetzt Antivirus-Quarantäne.**
- Wenn ein Antivirus (z.B. HP Wolf Security) die heruntergeladene
  `JustUpdate_remote.ps1` aus `%TEMP%` sofort in Quarantäne stellt, warf
  `Get-Content` einen non-terminating `UnauthorizedAccessException` — der
  bisherige catch-Block fing ihn nicht, der User sah einen roten Stacktrace
  beim App-Start. Jetzt mit `-ErrorAction Stop` an `Get-Item`/`Get-Content`/
  `Copy-Item`, sodass der AV-Block sauber in den catch fällt und die App mit
  der installierten Version weiterläuft.

**Bugfix: DISM Retry bei Datei-Konflikt (Exit 32).**
- Modul System-Reparatur bricht nicht mehr beim ersten `ERROR_SHARING_VIOLATION`
  ab. Bei Exit 32 (typisch wenn ein Antivirus parallel scannt) wartet DISM
  45 Sekunden und versucht es einmal nochmal. Bleibt der Lock bestehen, wird
  ein konkreter Klartext-Hinweis im Log ausgegeben:
  „Antivirus vorübergehend pausieren und JustUpdate erneut starten".

## v2.6.3

**Neu: Optionale Updates werden jetzt mitgemacht.**
- Module **Windows Updates** und **Treiber** binden Microsoft Update als Quelle
  ein (`ServerSelection=ssOthers`, ServiceID
  `7971f918-a847-4430-9279-4a52d1efe18d`). Damit kommen jetzt auch die Updates
  durch, die bisher nur unter **Einstellungen → Windows Update → Erweiterte
  Optionen → Optionale Updates** sichtbar waren — optionale Treiber,
  Preview-/Nicht-Sicherheits-KBs und Office/MS-Produkte.
- Idempotente Registrierung via `Microsoft.Update.ServiceManager.AddService2`
  mit Flag 2 (AllowOnlineRegistration) — **bewusst ohne** Flag 4
  (RegisterServiceWithAU), damit der Auto-Updater des Geräts nicht dauerhaft
  auf MU umgehängt wird. Nur der JustUpdate-Lauf nutzt MU.
- Fallback: schlägt die MU-Registrierung fehl (Policy, Offline, GPO), läuft das
  Modul mit der Default-Quelle weiter — Klartext-Warnung im Log statt Abbruch.

**Bugfix (sonst false positives):**
- Re-Search im Treiber-Verifikations-Block nutzt jetzt dieselbe Quelle wie die
  Erst-Suche. Sonst hätte der Default-Sucher einen via MU installierten
  optionalen Treiber nicht gekannt und fälschlich als „weg" gemeldet.

## v2.6.2

**Neu: „Was ist neu" beim Update.**
- Beim Self-Update sieht der Kunde jetzt **was geändert wurde — kumulativ ab
  seiner installierten Version**. Wer von v2.5.0 auf v2.6.2 springt, sieht alle
  Einträge dazwischen; wer von v2.6.1 kommt, nur v2.6.2. Scrollbares Fenster,
  danach läuft die Installation normal weiter.
- Komplett gekapselt: schlägt der Changelog-Abruf fehl (offline o. Ä.), wird er
  übersprungen — das Update selbst läuft trotzdem.

**Härtung / QA:**
- Versions-Erkennung im Self-Update abgesichert (kein Absturz mehr bei einem
  unsauberen Versions-Header).
- Voller Code-Durchgang: Self-Update-, Migrations- und Modulpfade geprüft.

## v2.6.1

**Stabilisierung (weniger Fehlalarme auf Fremd-/Kundengeräten):**
- **Restore-Modul gehärtet:** Windows-24h-Sperre (1 Punkt/Tag) wird für den
  Lauf ausgehebelt und exakt zurückgesetzt; deaktivierter/per-GPO gesperrter
  Systemschutz wird als klarer Hinweis (warn) statt rotem Fehler gemeldet.
- **Defender bei Drittanbieter-AV:** Norton/Avast/… wird erkannt → Defender
  passiv = „OK (Fremd-AV aktiv)" statt Warnung/Fehler (keine Support-Anrufe
  wegen Nicht-Problem).
- **Connectivity-Precheck:** einmalige klare Offline-Meldung statt mehrerer
  kryptischer Timeouts in Defender/WinUpdate/Winget/Store.

**Fleet-Monitoring nutzbar gemacht:**
- `$env:JUSTUPDATE_REPORT_DIR` → result-JSON wird zusätzlich zentral
  (OneDrive/NAS) abgelegt, Dateiname mit Host. `fleet-report.ps1` wertet aus
  → endlich Sichtbarkeit über alle Kundengeräte.

**Support-Flow:**
- Bei Fehler/Warnung optional „Bericht an Support senden" → öffnet
  vorausgefüllte Mail an info@itintechsolutions.ch + Log-Ordner zum Anhängen.

**Tooling:** `build.ps1 -SkipExe` (sauberer PowerShell-only-Release), Build
bricht bei gesperrter/veralteter EXE klar ab statt falsches „OK".
*(Hinweis: Codepage war bereits dynamisch — kein Handlungsbedarf.)*

## v2.6.0

**Release-Pipeline (Itin-TechSolutions-Ops):**
- `VERSION` als Single Source of Truth — Version steht nur noch an EINER Stelle.
- `build.ps1`: ein Befehl synct Version in `.ps1` + `.iss`, kompiliert den
  Installer, legt ihn unter `Releases\v<X>\` ab, synct Skript + HISTORY ins
  Verteil-Repo. `-Push` committet/pusht beide Repos. Schliesst die Lücke
  "Source ≠ Verteil-Repo → Kunden ohne Update".

**Robusteres Self-Update:**
- Heruntergeladenes Skript wird vor dem Überschreiben **syntaktisch validiert**
  (PowerShell-Parser) und auf gültigen `# Version:`-Header geprüft. Ein
  abgebrochener/korrupter Download kann die Installation nicht mehr „bricken".

**Maschinenlesbarer Report:**
- Nach jedem Lauf wird `logs\result_<timestamp>.json` geschrieben (Host, Version,
  Zeit, Dauer, pro-Modul-Status, Summe). Ermöglicht Fleet-Monitoring über mehrere
  Kundengeräte hinweg.

# Commit-History: JustUpdate

Repo: https://github.com/Just1n12354/JustUpdate
Stand: 2026-05-18 18:38 | Commits: 18

```text
d1ed65a | 2026-05-12 19:35 | Just1n12354 | Justin 2026-05-12 19:35 - v2.4.8: Heartbeat-Runspace fuer blockierende WUA-Calls
68204b0 | 2026-05-12 19:24 | Just1n12354 | Justin 2026-05-12 19:24 - v2.4.7: Pre-Download-Hinweis + Size-Sanity-Check in Modul 3/4/Store
39043bc | 2026-05-12 19:16 | Just1n12354 | Justin 2026-05-12 19:16 - v2.4.6: ProgressPreference-Fix fuer Self-Update-Download
d8e8439 | 2026-05-10 22:17 | Just1n12354 | Justin 2026-05-10 22:17 - v2.4.5: Winget-Modul Output-Wording fix
c44b22b | 2026-05-10 14:54 | Just1n12354 | Justin 2026-05-10 14:54 - aktualisiert: MaintenanceProGUI_MODERN.ps1 (+1/-1)
36df6bd | 2026-05-10 14:45 | Just1n12354 | Justin 2026-05-10 14:45 - aktualisiert: MaintenanceProGUI_MODERN.ps1 (+1/-1)
b4538aa | 2026-05-10 14:45 | Just1n12354 | Justin 2026-05-10 14:45 - aktualisiert: MaintenanceProGUI_MODERN.ps1 (+122/-26)
da69890 | 2026-05-10 14:32 | Just1n12354 | Justin 2026-05-10 14:32 - aktualisiert: MaintenanceProGUI_MODERN.ps1 (+172/-15)
4157ead | 2026-05-10 14:28 | Just1n12354 | Justin 2026-05-10 14:28 - aktualisiert: MaintenanceProGUI_MODERN.ps1 (+135/-32)
1589dc6 | 2026-05-10 14:09 | Just1n12354 | Justin 2026-05-10 14:09 - aktualisiert: MaintenanceProGUI_MODERN.ps1 (+17/-17)
8a83210 | 2026-05-10 14:07 | Just1n12354 | Justin 2026-05-10 14:07 - aktualisiert: MaintenanceProGUI_MODERN.ps1 (+2/-2)
6d7a3f4 | 2026-05-10 14:07 | Just1n12354 | Justin 2026-05-10 14:07 - aktualisiert: MaintenanceProGUI_MODERN.ps1 (+2/-2)
707ab6c | 2026-05-10 14:07 | Just1n12354 | Justin 2026-05-10 14:07 - aktualisiert: MaintenanceProGUI_MODERN.ps1 (+17/-15)
4799ced | 2026-05-10 13:57 | Just1n12354 | Justin 2026-05-10 13:57 - Bump to 2.3.7 (Update-Dialog Test)
48fc2da | 2026-05-10 13:55 | Just1n12354 | Justin 2026-05-10 13:55 - v2.3.6: Versionsnummer im Footer angezeigt
4707321 | 2026-05-10 13:46 | Just1n12354 | Justin 2026-05-10 13:46 - Bump version to 2.3.5 (test des Update-Dialogs)
21ce189 | 2026-05-10 13:42 | Just1n12354 | Justin 2026-05-10 13:42 - Initial: MaintenanceProGUI_MODERN.ps1 v2.3.4
aa9470e | 2026-05-10 13:38 | Just1n12354 | Justin 2026-05-10 13:38 - Initial commit
```
