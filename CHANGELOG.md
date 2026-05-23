# JustUpdate — Changelog

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

**UI-Politur:**
- Sanftes Fenster-Fade-In beim Start (280 ms, EaseOut) statt Hartschnitt.
- Fortschrittsbalken animiert jetzt smooth (CubicEase 450 ms) statt zu springen;
  Re-Trigger-Schutz gegen Ruckeln, sauberes Zurücksetzen je Lauf.
- Alle Animationen mit try/catch-Fallback → GUI bricht nie.

**Maschinenlesbarer Report:**
- Nach jedem Lauf wird `logs\result_<timestamp>.json` geschrieben (Host, Version,
  Zeit, Dauer, pro-Modul-Status, Summe). Ermöglicht Fleet-Monitoring über mehrere
  Kundengeräte hinweg.

## v2.5.1

- Watchdog-Timeout für SFC/DISM/Winget; Klartext-Gründe im Abschluss-Popup.
