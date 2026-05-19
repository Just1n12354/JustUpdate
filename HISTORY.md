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
