# JustUpdate — Changelog

## v2.6.13 (10.06.2026)

**Stabilitaets-Release: 6 Bugs aus einem vollstaendigen Code-Audit gefixt.**

- **Stop-Button wurde als Timeout fehlgemeldet.** Brach der Nutzer einen
  laufenden Winget-/SFC-/DISM-Schritt per Stop ab, setzte der Watchdog
  trotzdem `Killed=true` -> die Wartung meldete faelschlich
  „nach X Min abgebrochen / reagierte nicht", obwohl der User selbst
  gestoppt hatte. Jetzt wird ein User-Stop sauber vom echten Timeout
  unterschieden; der Prozess wird zwar beendet (kein verwaister
  Installer), aber nicht mehr als Timeout gewertet.

- **Deadlock-Risiko beim Ausfuehren externer Tools.** `Invoke-Monitored-
  Process` las erst stdout komplett, DANN stderr. Schrieb ein Tool
  (z.B. DISM mit vielen Warnungen) genug nach stderr um den ~4-KB-Puffer
  zu fuellen WAEHREND es weiter auf stdout schrieb, blockierten beide
  Seiten gegenseitig bis der Watchdog nach Timeout killte. stderr wird
  jetzt parallel in einem eigenen Runspace geleert -> kein Deadlock.
  (Mit cmd-Stresstest 200 Zeilen stdout+stderr verifiziert.)

- **Treiber-Modul meldete faelschlich „alle installiert (verifiziert)".**
  Der pnputil-Fallback zaehlte ALLE `.inf` im Windows-Treiber-Cache als
  Erfolg und rechnete sie gegen die haengenden Treiber - da der Cache
  i.d.R. viel mehr `.inf` enthaelt, wurde die Fehlerzahl auf 0 gedrueckt.
  Jetzt wird nach pnputil erneut verifiziert, welche der haengenden
  Treiber WIRKLICH installiert wurden; nur die zaehlen.

- **Abschluss lief bei Stop+Fertig doppelt.** `End-Session` war nicht
  reentrant - Stop-Klick und der „fertig"-Tick des UI-Timers konnten es
  fast gleichzeitig aufrufen, wodurch Report/Mail/Abschluss-Dialog
  doppelt liefen und auf die bereits freigegebene Pipeline zugriffen.
  Guard-Flag eingebaut.

- **Report-JSON: Pfad-Bug bei bestimmten Ordnernamen.** Der Dateiname
  wurde per ungeankertem Regex aus dem GANZEN Pfad ersetzt - lag der
  Log-Ordner z.B. unter `...\Maintenance_Logs\`, wurde auch der
  Ordnername umgeschrieben und das JSON landete im Nirgendwo. Jetzt
  wird nur noch der Dateiname (verankert) umbenannt.

- **Report-JSON hatte ein BOM.** `ConvertTo-Json | Out-File -Encoding
  utf8` schrieb in PS5.1 ein UTF-8-BOM vor die `{` - strikte JSON-Parser
  (Fleet-Auswertung, andere Tools) stolperten darueber. Wird jetzt
  BOM-frei geschrieben.

## v2.6.12 (10.06.2026)

**Bugfix: Apps mit „Neustart noetig" wurden faelschlich als fehlgeschlagen gemeldet.**
- Im Kundenlauf vom 10.06.2026 meldete Modul „Apps (Winget)"
  `Teilweise aktualisiert: 16 OK, 2 fehlgeschlagen` fuer **Claude**
  und **Microsoft Teams** — obwohl beide Updates **sauber durchliefen**.
- Ursache: Diese Pakete (Claude, Teams, weitere Edge-/Squirrel-basierte
  Apps) geben statt `Erfolgreich installiert` den Satz
  *„Die Installation war erfolgreich. Starten Sie die Anwendung neu,
  um das Upgrade abzuschliessen."* aus. Diese Zeile fiel durch alle
  Parser-Zweige; das Paket blieb im Puffer haengen und wurde beim
  naechsten `(N/M) Gefunden` als **fehlgeschlagen** verbucht — ein
  reiner Auswertungs-Fehler, kein echtes Update-Problem.
- Fix: Die Erfolgs-Erkennung akzeptiert jetzt auch
  „Die Installation war erfolgreich" sowie die Neustart-noetig-Phrasen
  (DE/EN/FR). Solche Pakete zaehlen als **erfolgreich aktualisiert**.
- Neu: Erfolgreich aktualisierte Apps, die nur noch einen App-Neustart
  brauchen, werden klar als Hinweis ausgegeben
  (`[HINWEIS] N App(s) aktualisiert - Neustart der App schliesst das
  Upgrade ab: ...`) statt als Fehlalarm. Dieselbe Erkennung greift im
  Hauptlauf, im in-use-Retry und in der Gesamt-Statusberechnung.

## v2.6.11 (23.05.2026 23:00)

**Versions-Bump damit der Hotfix bei Kunden ankommt.**
- Die Patches aus v2.6.10 (Datums-Pille im Patchlog, aggressiver
  OBS-Kill mit Pfad-Match + Services + Diagnose) waren zwar im
  Verteil-Repo, aber Self-Update prueft den `# Version:`-Header.
  Da der bei v2.6.10 blieb, hat Self-Update den Patch nicht
  gezogen - Kunden bleiben sonst auf dem alten Stand kleben.
- Mit v2.6.11 zieht Self-Update jetzt sauber durch.

## v2.6.10 (23.05.2026 22:42)

**Neu: Release-Datum im Patch-Notes-Fenster.**
- Jedes Versions-Header im Patchlog zeigt jetzt rechts neben der
  Version das **Release-Datum + Uhrzeit** als kleine Pille
  (z.B. `v2.6.10  23.05.2026 22:42`). So sieht man auf einen Blick
  WANN welche Version rausgegangen ist.
- Sidebar links bleibt kompakt mit Version ohne Datum.

**Bugfix: OBS-Update scheitert weiterhin trotz Wildcard.**
- Im User-Log: `obs*` Wildcard matched keinen Prozess, OBS-Update
  scheitert mit Exit 6 ("Datei in Verwendung") - vermutlich weil
  OBS einen Helper-Prozess mit untypischem Namen laufen hat
  (Auto-Updater, Streamlabs/StreamElements-Plugin, Stream Deck
  Companion, ...) oder einen Windows-Service.
- Zweiter Pass beim Retry: pro fehlgeschlagenes Paket werden jetzt
  alle Prozesse beendet, deren **EXE-Pfad** das Paket-Schluessel-
  wort enthaelt (z.B. "OBS" -> alle Prozesse aus dem OBS-Installa-
  tionsordner) PLUS alle Windows-Services mit passendem Namen.
  Das fasst auch Helper, die nicht in der Wildcard-Liste stehen.
- Diagnose-Log: was zusaetzlich beendet wurde, wird namentlich
  + Pfad ausgegeben - so erkennt der Support beim naechsten Fall
  sofort, was den Lock verursacht hatte.

**Bugfix: Mail nicht mehr zwingend Outlook 2016.**
- Bisher: JustUpdate startete bei "Mail an Support" per COM-Automation
  **immer Outlook**, auch wenn der Kunde laengst Thunderbird, die
  Windows-Mail-App oder einen Webmail-Handler als Default eingestellt
  hatte. Outlook-COM ist komplett entfernt.
- Jetzt: `mailto:` -> Windows oeffnet die App, die der Kunde als
  **Standard-Mail-Programm** in den Windows-Einstellungen ausgewaehlt
  hat. Kein Default gesetzt? Windows zeigt den "App auswaehlen"-Dialog.
- Vollstaendiger Log liegt weiterhin in der Zwischenablage - Kunde
  drueckt einmal Strg+V im Mail-Body und hat alles drin.

**Bugfix: OBS-Fehler obwohl OBS nicht offen ist.**
- Bisher war die Tray-Kill-Liste fest auf `obs64`, `obs32`,
  `obs-browser-page`. OBS-Studio startet aber bei Bedarf weitere
  Helper-Prozesse (`obs-ffmpeg-mux`, `obs-amf-test`,
  `OBS-Studio-Updater`, ...), die im Hintergrund bleiben und den
  winget-Installer mit "Datei in Verwendung" / Exit 1603/6 ausbremsen.
- Fix: Wildcard `obs*` matcht **alle** OBS-Familien-Prozesse auf
  einmal. Wenn winget OBS aktualisiert, ist garantiert nichts mehr
  am Installer-Verzeichnis aktiv.

**Bugfix: Ja/Nein-Dialog tauchte noch im Notfall-Fallback auf.**
- Wenn das schicke Custom-Dialog-XAML aus irgend einem Grund
  scheiterte (z.B. bei sehr alten Windows-Versionen ohne Aero-
  Composition), fiel der Code zurueck auf
  `MessageBox.Show(..., YesNo, ...)` - genau die Ja/Nein-Box, die
  Kunden reflexhaft falsch klicken.
- Fix: Fallback ist jetzt selbst ein WPF-Window mit echten
  beschrifteten Buttons ("Mail an Support senden" / "Schliessen").
  Sollte auch DIESES scheitern, kommt **gar kein** Dialog (still
  abgebrochen) - lieber keine Mail als die falsche durch Reflex.

**Neu: Logdateien mit Version + ausfuehrlichem Kopf.**
- Dateiname enthaelt jetzt die Version:
  `Maintenance_2026-05-23_22-15-30_v2.6.10.log` - so weiss der
  Support beim Anhang sofort, welche JustUpdate-Version den Lauf
  produziert hat.
- Logdatei-Kopf enthaelt jetzt Version, Host, Benutzer, Zeitstempel
  und Skript-Pfad in klaren Zeilen. Auch der Live-Sitzungs-Start im
  GUI-Log zeigt jetzt `Version: v...`, `Host: ...`, `Zeit: ...`,
  `Module: N ausgewaehlt`.

## v2.6.9 (23.05.2026 22:34)

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

## v2.6.8 (23.05.2026 22:29)

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

## v2.6.7 (23.05.2026 22:23)

**Neu: Patch-Notes-Button in der Titelleiste.**
- Oben links neben dem "i"-Button gibt es jetzt einen "?"-Button.
  Ein Klick oeffnet ein scrollbares Fenster mit der **kompletten
  Versions-Historie** - von der ersten Version bis heute. Kunden
  koennen jederzeit nachsehen, was sich in welcher Version geaendert
  hat, ohne den Support anschreiben zu muessen.
- Quelle: lokales CHANGELOG.md, Fallback Online vom Verteil-Repo
  (`github.com/Just1n12354/JustUpdate`). Funktioniert also auch bei
  einer reinen EXE-Installation, solange Internet da ist.

## v2.6.6 (23.05.2026 22:18)

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

## v2.6.5 (23.05.2026 22:02)

**Bugfix: Winget scheitert nicht mehr an Tray-Apps (OBS, Epic, Steam, …).**
- Bisher schloss der Vor-Update-Schritt nur Apps mit sichtbarem Fenster.
  OBS, Epic Games Launcher & Co. laufen aber im Tray ohne MainWindow und
  haben ihre Installer-Dateien gesperrt — winget brach mit Exit 1603 / 6
  ("Datei in Verwendung") ab. Jetzt zusaetzliche Whitelist haerter
  beendeter Tray-Blocker: `obs64`, `EpicGamesLauncher`, `EpicWebHelper`,
  `Steam`, `steamwebhelper`, `Discord`, `Spotify`, `Teams`, `OneDrive`,
  `Slack`, `Code`, `Cursor`, `Zoom`, `WhatsApp`, `Telegram` u.a.
- Wartezeit nach dem Close von 2 auf 3 Sekunden — gibt File-Handles
  zuverlaessiger Zeit zum Freigeben.

**Neu: Winget-Retry pro Paket bei "Datei in Verwendung".**
- Output-Stream wird pro Paket geparst (Name, ID, Exitcode). Bei 1603 / 6
  oder Klartext-Meldung "von anderer Anwendung verwendet" wird **EIN
  gezielter Retry** versucht: vorher harter Tray-Kill, dann
  `winget upgrade --id <Paket> --exact`. Behebt den haeufigsten Lauf-
  Fehler ohne Eingreifen des Kunden.
- Status-Anzeige differenziert jetzt: "Teilweise aktualisiert (3 OK) -
  noch offen: OBS Studio" statt blankes "Exit-Code -1978335188".

**Support-Mail: nur noch "Senden" klicken.**
- Outlook installiert? -> COM-Automation oeffnet eine fertige Mail mit
  Log-Datei + result-JSON **bereits angehaengt** und vorgefuelltem Body.
  Kunde klickt nur noch Senden. Keine Datei mehr von Hand reinziehen.
- Kein Outlook? -> mailto-Fallback packt die **letzten 50 Log-Zeilen +
  Modul-Status direkt in den Mail-Body** — damit der Support auch ohne
  Attachment sofort die Diagnose hat. Log-Ordner wird zusaetzlich
  geoeffnet (statt nur die Logdatei selektiert), damit auch
  `result_*.json` mitgenommen werden kann.

## v2.6.4 (23.05.2026 21:36)

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

## v2.6.3 (23.05.2026 21:18)

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

## v2.6.2 (19.05.2026)

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

## v2.6.1 (19.05.2026 21:37)

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

## v2.6.0 (19.05.2026 20:59)

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

## v2.5.1 (19.05.2026 00:26)

- Watchdog-Timeout für SFC/DISM/Winget; Klartext-Gründe im Abschluss-Popup.

## v2.4.8 (12.05.2026 19:35)

**Neu: Heartbeat-Runspace fuer blockierende WUA-Calls.**
- Windows Update Agent (WUA) kann minutenlang ohne Ausgabe blockieren -
  vorher sah es nach "haengen geblieben" aus, der User brach ab. Jetzt
  laeuft ein Heartbeat-Runspace nebenher und schreibt im 30-Sek-Takt
  einen "noch dran, Sekunde X" ins Live-Log. So weiss der Kunde, dass
  weitergearbeitet wird, und unterbricht nicht vorzeitig.

## v2.4.7 (12.05.2026 19:24)

**Neu: Pre-Download-Hinweis + Size-Sanity-Check in Modul 3/4/Store.**
- Bevor ein grosser Download startet, kommt ein Klartext-Hinweis im Log
  ("ca. 850 MB - das kann dauern"), damit der User nicht denkt der PC
  haengt.
- Sanity-Check auf die heruntergeladenen Bytes: passt die Groesse zum
  erwarteten Wert? Wenn nein -> Abbruch mit verstaendlicher Fehlermeldung
  statt stillem Wegfall.

## v2.4.6 (12.05.2026 19:16)

**Bugfix: ProgressPreference fuer Self-Update-Download.**
- `Invoke-WebRequest` rendert in Windows PowerShell standardmaessig eine
  deutsche Fortschrittsanzeige ("Webanforderung wird geschrieben") -
  die wurde ueber das WPF-Fenster gezeichnet und machte den Download
  ~10x langsamer. Jetzt wird `$ProgressPreference = 'SilentlyContinue'`
  fuer den Self-Update-Download gesetzt und danach wiederhergestellt.

## v2.4.5 (10.05.2026 22:17)

**Bugfix: Winget-Modul Output-Wording.**
- Winget meldet bei "nichts zu tun" in deutscher Sprache "Es wurde kein
  installiertes Paket gefunden" - das klang wie ein Fehler. Re-Wording
  zu klarem "Alle Apps sind aktuell - keine Updates verfuegbar".

## v2.4.4 (10.05.2026 21:53)

**Tooling: Installer ins Repo.**
- Kompilierter Inno-Setup-Installer wird jetzt unter `Releases/v<X>/`
  ins Repo gelegt. Damit ist die genaue Build-Version archiviert und
  jederzeit reproduzierbar / nachinstallierbar.

## v2.4.3 (10.05.2026 14:48)

**Grosse UI- und UX-Ueberarbeitung:**
- **UI rot:** durchgaengiges Itin-TechSolutions-Farbschema (Akzentfarbe
  `#A3243B`), passt zur Marke statt generisches Windows-Blau.
- **Status-Farben:** Module mit OK / Warnung / Fehler werden in der
  Liste sofort farblich erkennbar statt nur als Text.
- **Logs in App-Ordner:** Log-Dateien landen jetzt im Installations-
  ordner statt in `%TEMP%`, wo Windows sie unangekuendigt loescht.
- **Multi-User-Cleanup:** Bereinigungs-Modul leert temporaere Dateien
  fuer alle Benutzerprofile auf dem PC, nicht nur den aktuell
  angemeldeten User.
- **Apps-schliessen-Dialog:** Vor Update-Modulen fragt JustUpdate, ob
  laufende Apps geschlossen werden sollen - verhindert dass Update-
  Installer sich an gesperrten Dateien aufhaengen.
- **Info-Button (i):** Klartext-Erklaerung was diese App eigentlich
  macht - reduziert Support-Anrufe von neuen Kunden.
- **Store via WUA:** Microsoft-Store-Updates werden ueber den Windows
  Update Agent angestossen statt ueber den unzuverlaessigen Store-
  Trigger.
- **Queue-Bugfix:** Bei sehr schnellem Modul-Wechsel gingen einzelne
  Status-Updates verloren - jetzt ueber eine synchronisierte Queue,
  jeder Status wird angezeigt.

## v2.3.7 (10.05.2026 13:57)

- **Update-Dialog Test:** Version-Bump um den Self-Update-Dialog
  produktiv zu pruefen (echter Versions-Sprung statt Mock).

## v2.3.6 (10.05.2026 13:55)

- **Versionsnummer im Footer angezeigt.** Hilft im Support: Kunde kann
  beim Anruf direkt die laufende Version vorlesen statt sie in den
  Dateieigenschaften zu suchen.

## v2.3.5 (10.05.2026 13:46)

- **Bump auf 2.3.5** fuer den ersten echten Test des Update-Dialogs.

## v2.3.4 (10.05.2026 13:42)

- **Initial Release** von `MaintenanceProGUI_MODERN.ps1` (2026-05-10).
  WPF-basierte Wartungs-GUI, 9 Module: Wiederherstellungspunkt,
  Windows Defender, Windows Updates, Treiber, Apps (Winget),
  Microsoft Store, System-Reparatur (SFC/DISM), Netzwerk-Reparatur,
  Bereinigung. Erste produktive Version fuer den Kundenrollout.

## v2.0 - v2.3.3 (03.05.2026 - 10.05.2026)

**EXE-Phase (verworfen).**
- Vor v2.3.4 existierte JustUpdate als kompilierte **`JustUpdate.exe`**
  mit eigenem **C#-Launcher** (`JustUpdateLauncher.cs`).
- Verteilt wurde ein Inno-Setup-Installer (`JustUpdate_Setup.exe`),
  der die EXE installierte. Mehrere Iterationen zwischen 2026-05-03
  und 2026-05-10 wurden lokal entwickelt, aber nicht systematisch
  versioniert.

**Warum verworfen:**
- **Windows Smart App Control / WDAC** blockierte die unsignierte
  EXE mit Fehler **4551** ("App wurde blockiert"). Eine Signatur
  war zu diesem Zeitpunkt nicht beschaffbar.
- Folge: Migration **weg von einer eigenen EXE**, hin zu einem
  reinen PowerShell-Skript (`MaintenanceProGUI_MODERN.ps1`).
  Shortcuts zeigen seither direkt auf `powershell.exe -File`,
  der Launcher entfaellt komplett.
- Bei v2.3.4 wurden die alten Artefakte (`JustUpdate.exe`,
  `JustUpdateLauncher.cs`, alter `JustUpdate_Setup.exe`) endgueltig
  aus dem Repo entfernt.

**Was technisch schon da war (uebernommen in v2.3.4):**
- Inno-Setup-Build-Pipeline (`JustUpdate_Setup.iss`).
- App-Icon, App-Verzeichnis (`{autopf}\JustUpdate`),
  Deinstallations-Registrierung.
- Grundzueg des Multi-Modul-Konzepts.

> Pre-v2.3.4 ist nicht ueber Self-Update erreichbar - wer noch
> eine alte EXE-Installation hat, muss den aktuellen Installer
> (`JustUpdate_Setup_v<X>.exe`) frisch installieren.
