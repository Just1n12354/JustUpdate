# JustUpdate — Changelog

## v2.7.8.1 (14.07.2026)

Erste Version, die sich über das Self-Update der neuen App verteilt — gleichzeitig
der Test dafür.

- **App-Symbol.** Das rote Quadrat mit dem weissen „J" liegt jetzt als echtes
  Programmsymbol vor und erscheint in Taskleiste, Startmenü und auf dem Desktop.
- **Versionsanzeige korrigiert.** Die vierte Stelle wurde verschluckt: eine
  Version 2.7.8.1 erschien im Fenster als „2.7.8".

## v2.7.8 (14.07.2026)

**Die neue JustUpdate-App (C#).** Ersetzt die PowerShell-Fassung.

- Oberfläche mit ein- und ausschaltbaren Modulen, Live-Log und Ergebnis je Modul.
- **Info-Fenster**: zu jedem Modul steht, was es macht — und was es ausdrücklich
  nicht macht.
- **Patch-Notes** und **Update-Prüfung** direkt in der Titelleiste.
- **Automatik**: wöchentliche Wartung. War der Rechner zum Termin aus, wird sie
  nach dem nächsten Start nachgeholt — es fällt kein Lauf mehr aus.
- Ein abstürzendes Modul reisst die restliche Wartung nicht mehr mit, und der
  Exit-Code sagt endlich die Wahrheit (0 = OK, 1 = Warnungen, 2 = Fehler).

## v2.7.7 (14.07.2026)

**JustUpdate wird zur richtigen Anwendung.** Diese Version der PowerShell-Fassung
hat nur noch eine Aufgabe: sie übergibt an den Nachfolger.

- **Umstieg auf die neue JustUpdate-App (v3).** Beim nächsten Start lädt
  JustUpdate einmalig die neue Programmdatei, biegt die vorhandenen
  Verknüpfungen darauf um und startet sie. **Kein Neuinstallieren nötig.**
- Die neue App ist in C# geschrieben statt in PowerShell: sie startet schneller,
  bricht bei Fehlern nicht mehr mitten im Lauf ab, und jedes Wartungsmodul
  meldet sauber, ob es erfolgreich war.
- **Neue Oberfläche**: Module einzeln an- und abwählbar, Live-Log neben der
  Modulliste, Fortschritt und Ergebnis pro Modul auf einen Blick.
- Die neue App bringt ihre eigene Update-Funktion mit — künftige Versionen
  kommen wie gewohnt automatisch.
- Die alte PowerShell-Fassung bleibt als Rückfalloption liegen; der Umstieg ist
  umkehrbar.

## v2.7.6 (12.07.2026)

Befunde aus dem ersten echten v2.7.5-Lauf (Log 13:20 Uhr, Winget-Modul):

- **Fix: Hex-Exit-Codes von winget wurden falsch geparst.** Bei
  `Installation fehlgeschlagen mit Exitcode: 0x8a150003` fischte der Parser aus
  dem Hex-Wert nur die fuehrende `0` — der echte Code ging verloren. Hex wird
  jetzt erkannt und sauber nach Int32 gewandelt.
- **Fix: `remove_all: Zugriff verweigert` zaehlt jetzt als "in Verwendung".**
  Beim Upgrade portabler Pakete (z.B. Rclone, das gerade als Mount/Daemon
  laeuft) ist die alte Version von einem laufenden Prozess gelockt. Vorher:
  sofort als Fehlschlag verbucht. Jetzt greift der Retry-Pass — passende
  Prozesse werden beendet und das Upgrade einmal wiederholt.
- **Log: Der Retry-Kill-Pass schreibt jetzt, WAS er beendet hat** (bzw. dass
  kein bekannter Tray/Helper-Prozess lief). Vorher war im Log nicht
  nachvollziehbar, ob der Kill ueberhaupt etwas traf — wichtig fuer Faelle wie
  OBS, wo die Dateien trotz beendeter App gelockt bleiben (Game-Hook in einem
  laufenden Spiel).
- Neue Parser-Regressionstests in `tests/checks.ps1` fuer beide Faelle,
  abgeleitet aus dem echten Kundenlog.

Zusaetzlich aus einem Multi-Agenten-Review (Threading, Parser, WUA) vor dem Release:

- **Fix (KRITISCH): Doppelstart im selben Prozess.** Der "Apps schliessen?"-Dialog
  liess Klicks aufs Hauptfenster durch — ein Doppelklick auf START konnte zwei
  Wartungs-Worker parallel starten (der Mutex schuetzt nur prozessuebergreifend).
  Jetzt Reentrancy-Guard als allererste Zeile.
- **Fix (KRITISCH): UI-Freeze beim Abbrechen.** `Pipeline.Stop()` blockierte den
  UI-Thread, bis der laufende WUA-COM-Call (bis 30 Min) fertig war — Fenster
  "Keine Rueckmeldung", Kunden killten den Prozess mitten im Update. Abbruch
  nutzt jetzt `BeginStop` (asynchron); die Watchdogs beenden Kindprozesse weiter
  binnen ~1s.
- **Fix (KRITISCH): Neustart-Prompt von Lauf 1 traf Lauf 2.** START wurde vor den
  Abschluss-Dialogen wieder freigegeben; startete man waehrenddessen neu, konnte
  der Neustart-Prompt des ALTEN Laufs `shutdown /r` mitten in den neuen Lauf
  setzen. Freigabe jetzt erst nach allen Dialogen.
- **Fix (KRITISCH): MSI-Erfolg mit Reboot-Pflicht (3010) zaehlte als Fehlschlag.**
  winget druckt dafuer NUR "Restart your PC to finish installation" — keine
  "Successfully installed"-Zeile. Der Parser kannte die Meldung nicht (5. Instanz
  dieser Bug-Klasse; betraf z.B. Zoom/Poly Lens). Zaehlt jetzt als Erfolg, setzt
  `rebootRequired` und wird als Hinweis geloggt.
- **Fix: Blacklist-Zaehler wurde fuer nie versuchte Treiber geloescht.** Ein beim
  Download uebersprungener Treiber (RC3) bekam seinen Fail-Zaehler faelschlich
  zurueckgesetzt — chronische Treiber mit Download-Flakes haetten den Threshold
  nie erreicht. Reset jetzt nur noch fuer tatsaechlich installierte+verifizierte.
  Dazu: uebersprungene Downloads zaehlen als offen (kein "ok" mehr trotz
  fehlendem Treiber), Titel-Duplikate werden nur 1x gebucht, versteckte
  Geraete-Zwillinge nicht mehr als Fehlschlag gewertet, Blacklist-Datei wird
  atomar geschrieben (temp+rename).
- **Fix: Exit 1638 loest keinen sinnlosen Kill+Retry mehr aus** ("andere Version
  bereits installiert" ist kein Datei-Lock — ein Retry kann nie gelingen).
- **Fix: EN-Windows-Erkennung.** Die realen englischen in-use-Meldungen ("are
  being used", "is currently running") und die SFC-Pending-Meldung ("system
  repair pending … requires reboot") matchten nicht — Retry bzw. Warn-Statt-
  Fehler griffen auf EN-Systemen nie.
- **Fix: Franzoesisch war komplett tot.** Alle FR-Pattern waren ohne Akzente
  geschrieben ("Trouve" statt "Trouvé") — auf FR-Windows wurde KEIN Paket
  erkannt und das Modul meldete faelschlich "ok". Literale jetzt mit Wildcards.
- **Fix: DISM Exit 3010 = Erfolg mit Neustart** (dokumentiert) — wurde als
  "[FEHLER] DISM fehlgeschlagen" gemeldet.
- **Fix: User-Abbruch waehrend SFC/DISM** erzeugte "[FEHLER] SFC fehlgeschlagen
  … Admin-Rechte pruefen" und startete DISM trotzdem noch. Abbruch wird jetzt
  vor der Bewertung erkannt.
- **Fix: Store-Status log gegen sich selbst.** "ok" obwohl nur 3 von 5 Updates
  installiert wurden; Download-Totalausfall wurde als "nur MDM-Scan" gemeldet.
  Gemessen wird jetzt gegen alle gefundenen Updates.
- **Robuster: Modul-3-Treiberfilter** prueft jetzt primaer das dokumentierte
  `IUpdate.Type=2` statt nur den undokumentierten Kategorie-Typ "Driver".
- **Log: Winget meldet uebersprungene Pakete mit anderer Installationstechnologie**
  (z.B. TeamSpeak 5→6) jetzt als klaren Hinweis statt nur im Roh-Output.
- **Technisch: Die .ps1 traegt jetzt ein UTF-8-BOM** — Windows PowerShell las die
  Datei bisher als ANSI; literale Sonderzeichen wurden zu Zeichensalat (Ursache
  des Maximieren-Button-Bugs aus v2.7.5).

## v2.7.5 (12.07.2026)

- **Fix (KRITISCH): Chronisch fehlschlagende Treiber machen den Lauf nicht mehr
  dauerhaft "error".** Manche Microsoft-Update-Katalog-Eintraege (klassisch: der
  superseded HP-USB-Treiber von 2018) bietet Windows Update dem PC endlos an, obwohl
  der In-Box-Treiber neuer und aktiv ist. WUA meldet `Install=OK`, der Re-Scan findet
  ihn aber weiter offen — dadurch war der Overall-Status jedes Laufs strukturell
  `error`, egal wie sauber die anderen 7 Module liefen. Neu: Nach 3 Fehlversuchen
  desselben Treibers (per `UpdateID`) wird er automatisch aus der Suche genommen und
  im Log als `ignoriert` ausgewiesen. Persistiert in
  `%APPDATA%\JustUpdate\driver_blacklist.json`; ein Treiber, der doch mal durchgeht,
  loescht seinen Zaehler wieder.
- **Fix: DISM-/Modul-Dauer-Anzeige sprang um eine Minute.** `[int]($sekunden/60)`
  nutzte PowerShells Banker-Rounding (round-half-to-even), also wurde z.B. aus 90 s
  faelschlich `2m 30s` statt `1m 30s`. Jetzt via `[Math]::Floor` — betrifft den
  DISM-Heartbeat und die "(Modul-Dauer: …)"-Zeile.
- **Fix: Winget listete die verfuegbaren Apps nicht mehr doppelt.** Der separate
  `winget upgrade`-Vorab-Aufruf entfaellt; das Listing von `winget upgrade --all`
  reicht — ein Netzwerkaufruf weniger, Log lesbarer.
- **Fix: WU-Cache-Bereinigung konnte frische Downloads doch loeschen.** Der
  Schutz aus v2.3.3 ("frische Dateien schonen") prueft nur Dateien — ORDNER mit
  altem Datum wurden aber rekursiv geloescht, inklusive frischer Dateien darin
  (das Ordner-Datum aendert sich nur bei direktem Inhaltswechsel). Jetzt werden
  nur Dateien aelter als 1 Tag geloescht und danach leer gewordene Ordner
  entfernt. Zusaetzlich meldet das Log den TATSAECHLICH freigegebenen Platz
  statt der Cache-Gesamtgroesse.
- **Fix: Gespeicherte Sprache wurde beim Start nicht auf die UI angewendet.**
  `Restore-JUSettings` lief nach `Update-UI`, der SelectionChanged-Handler war
  aber noch nicht registriert — die ComboBox zeigte z.B. English, alle Texte
  blieben Deutsch. Reihenfolge getauscht.
- **Fix: Zweiter Wartungslauf in derselben Sitzung ueberschrieb das
  result-JSON des ersten.** Log-Datei (und damit der abgeleitete
  `result_*.json`-Name) wurde nur einmal beim App-Start erzeugt; Lauf 2 haengte
  ans selbe Log an. Jetzt bekommt jeder Lauf seine eigene Log-Datei.
- **Fix: Treiber-Suche respektiert jetzt `IsHidden=0`** (wie Modul 3) — Treiber,
  die der User in den Windows-Einstellungen ausgeblendet hat, werden nicht mehr
  zwangsinstalliert.
- **Fix: Treiber-Download mit `ResultCode 3` (SucceededWithErrors) verwirft
  nicht mehr alle Treiber.** Vollstaendig geladene Treiber werden installiert,
  nicht geladene einzeln uebersprungen und geloggt (wie Modul 3).
- **Kosmetik: Maximieren-Button zeigte Zeichensalat.** Das Symbol stand als
  literales Unicode-Zeichen in der BOM-losen .ps1 — Windows PowerShell liest die
  Datei als ANSI, aus `☐` wurde Mojibake. Jetzt als XML-Entity `&#x2610;`.

## v2.7.4 (05.07.2026)

- **SICHERHEIT: Der aggressive Prozess-Kill im Winget-Retry ist jetzt eingezaeunt.**
  Scheiterte ein App-Update mit "Datei in Verwendung", wurden bisher alle Prozesse
  beendet, deren EXE-Pfad ein Wort aus dem Paketnamen enthielt — bei einem Paket wie
  "Microsoft Edge" haette das Keyword "Microsoft" JEDEN Prozess unter
  `C:\Program Files\Microsoft ...` getroffen (z.B. Word mit ungespeichertem Dokument)
  und ueber den DisplayName-Match sogar den Defender-Dienst gestoppt. Jetzt:
  Stopword-Liste fuer generische Woerter (Microsoft, Windows, Update, ...), Prozesse
  unter `C:\Windows` und der eigene Prozess sind grundsaetzlich tabu, und Services
  werden nur noch ueber den technischen Namen gematcht, nie ueber den DisplayName.
- **NEU: Single-Instance-Schutz.** Ein Doppelklick zu viel (oder der Zeitplan waehrend
  einer offenen GUI) startete bisher eine zweite Wartung parallel — DISM/SFC doppelt,
  Winget-Installer blockieren sich gegenseitig. Jetzt haelt ein globaler Mutex die
  zweite Instanz auf: kurze Meldung, sauberer Exit. Im Automatik-Modus meldet der
  uebersprungene Lauf Exit-Code 3 (statt faelschlich 0/1/2). Vor Self-Update-Neustart
  und EXE-Migration wird der Mutex explizit freigegeben, damit die Folge-Instanz
  nicht abgewiesen wird.
- **Fix: Apps mit eigenem Auto-Updater erzeugten falsche Warnungen.** Meldet winget
  "Fuer die installierte Version wurde kein anwendbares Upgrade gefunden" (typisch
  Edge/Teams, die sich selbst aktualisieren), fiel die Zeile durch alle Parser-Zweige
  und das Paket wurde beim naechsten "(N/M) Gefunden" faelschlich als fehlgeschlagen
  verbucht. Zaehlt jetzt als "uebersprungen" — weder Erfolg noch Fehler.
- **Fix: Winget-Ausgabe wird jetzt als UTF-8 dekodiert.** Der Kommentar versprach es
  laengst, die drei `Invoke-MonitoredProcess`-Aufrufe (source update, upgrade --all,
  Retry) lasen aber ohne Encoding-Override — Umlaute in Paketnamen wurden im Log zu
  Ersatzzeichen.
- **Fix: Store-Service-Registrierung ohne `RegisterServiceWithAU`.** Beim
  Microsoft-Update-Service (Modul 3/4) wird Flag 4 bewusst weggelassen, damit der
  Auto-Updater des Geraets nicht dauerhaft umgehaengt wird — die Store-Registrierung
  nutzte aber Flag 7 (inkl. Flag 4). Jetzt konsistent Flag 3.
- **Haerter: Live-Protokoll verliert keine Zeilen mehr, wenn die Aufbereitung wirft.**
  `Format-LiveLine` (Regressions-Quelle von v2.7.2) ist jetzt einzeln abgesichert:
  schlaegt die Aufbereitung fehl, erscheint die Zeile roh statt gar nicht.
- **NEU: CI-Gate fuer den Update-Kanal.** `main` ist der Live-Verteilkanal (Self-Update
  laedt direkt von dort). Eine GitHub Action prueft jetzt bei jedem Push: Skript
  parsebar, Versions-Angaben konsistent (Header, Fallback, Changelog), Parser-Checks
  (`tests/checks.ps1`). Ein kaputter Commit erreicht so keine Kunden mehr.

## v2.7.3 (04.07.2026)

- **NEU: Fortschritts-Heartbeat fuer die DISM-Reparatur.** `dism /restorehealth` gibt
  - anders als Windows-Update/Winget/Treiber - keine im Log verwertbaren Fortschritts-
  zeilen aus; der Filter fuer Fortschrittsrauschen verwarf sie. Dadurch blieb das Live-
  Protokoll waehrend der bis zu 45 Minuten langen Komponentenspeicher-Reparatur komplett
  still, und man konnte den Eindruck bekommen, die App haenge. Jetzt loggt ein Heartbeat -
  wie bei Download/Installation - alle 30 Sekunden "laeuft seit X...".
- **Haerter: 120-Sekunden-Timeout fuer die ipconfig-Aufrufe im Netzwerk-Modul.**
  `ipconfig /flushdns | /release | /renew` wurde bisher synchron und ohne Zeitlimit
  gelesen. In der Praxis kehren die Aufrufe sofort zurueck, aber ein blockierter
  Netzwerk-Stack (haengender WLAN-Treiber, VPN-Client) haette das Netzwerk-Modul
  theoretisch endlos aufhalten koennen. Die Ausgabe wird jetzt asynchron gelesen und
  der Aufruf nach 120 s hart abgebrochen, damit die Wartung garantiert weiterlaeuft.

## v2.7.2 (15.06.2026)

- **Fix: Live-Protokoll blieb waehrend der Wartung komplett leer (Regression aus
  v2.7.1).** Die in v2.7.1 neu eingefuehrte Aufbereitungs-Funktion `Format-LiveLine`
  war nur lokal in `Start-Maintenance` definiert. Der UI-Timer-Tick feuert aber
  erst, NACHDEM `Start-Maintenance` zurueckgekehrt ist - dann existiert die lokale
  Funktion nicht mehr, der Aufruf wirft "nicht erkannt", und weil die Zeile zuvor
  schon aus der Queue entfernt wurde, verschluckte das `catch { break }` jede Zeile.
  Ergebnis: Fortschrittsbalken lief, aber das Live-Feld blieb leer. Fix: Funktion
  in den `script:`-Scope gelegt, damit sie auch im Timer-Tick erreichbar bleibt.
  Die Logdatei war nie betroffen.

## v2.7.1 (15.06.2026)

- **Fix: Defender meldete einen harten Fehler bei einem reinen RPC-Aussetzer.**
  `Update-MpSignature` spricht den Defender-Dienst per RPC an; dieser Aufruf
  scheitert haeufig transient mit "Der Remoteprozeduraufruf ist fehlgeschlagen"
  (0x800706BE) - typisch waehrend/nach einem Defender-Plattform-Update oder bei
  ausstehendem Neustart. Bisher landete das als roter Fehler im Ergebnis
  (`overall: error`). Jetzt versucht JustUpdate zuerst einen echten Fallback
  ueber `MpCmdRun.exe` (eigener Prozess, kein PowerShell-RPC); klappt auch das
  nicht und steht ein Neustart aus, wird es - analog zu SFC/Reparatur - nur als
  Warnung gemeldet ("Kein echter Fehler, bitte neu starten") statt als Defekt.
- **NEU: Neustart-Nachfrage am Ende.** Steht nach der Wartung ein Neustart an,
  erscheint jetzt - nach der Zusammenfassung - ein eigener Ja/Nein-Dialog
  ("Jetzt neu starten?"). Reiner Vorschlag: "Ja" startet geplant in 20 s neu
  (abbrechbar mit `shutdown /a`), "Nein" laesst alles wie es ist. Der bisherige
  statische ">>> NEUSTART ERFORDERLICH <<<"-Text in der Abschlussmeldung
  entfaellt dadurch. Im Automatik-Modus erscheint die Nachfrage nicht.
- **Verbessert: Live-Ansicht waehrend der Wartung leserlicher.** Das
  Terminal-Feld in der App zeigt den Ablauf jetzt menschenfreundlich aufbereitet
  (Zeitstempel und Trennlinien raus, Modul-Koepfe als klare "Schritt X von N"-
  Ueberschriften, Status-Marker als Symbole). Die **Logdatei bleibt unveraendert**
  1:1 mit allen Zeitstempeln erhalten - nur die Bildschirm-Darstellung ist
  entkoppelt und fuehrt den Benutzer besser durch den Lauf.

## v2.7.0 (12.06.2026)

**Gross-Update: Automatik-Modus, Zeitplan, gespeicherte Einstellungen, System-Vorabcheck.**

- **NEU: Automatik-Modus (`-Auto`).** JustUpdate laeuft komplett unbeaufsichtigt:
  startet die Wartung selbst, zeigt keine Dialoge, schliesst keine laufenden
  Programme, beendet sich danach von selbst und liefert einen Exit-Code fuers
  Fleet-Monitoring (0=OK, 1=Warnungen, 2=Fehler). Auch aktivierbar ueber die
  Umgebungsvariable `JUSTUPDATE_AUTO=1`. Self-Update ist in diesem Modus aus
  (braeuchte eine Bestaetigung) - der naechste manuelle Start holt es nach.
- **NEU: Zeitplan-Button (Uhr-Symbol in der Titelleiste).** Ein Klick legt eine
  woechentliche geplante Aufgabe an (Sonntag 11:00, hoechste Rechte, verpasste
  Termine werden nachgeholt sobald der PC wieder an ist) - ein erneuter Klick
  entfernt sie wieder.
- **NEU: Einstellungen bleiben erhalten.** Modul-Auswahl und Sprache werden in
  `settings.json` (im Log-Ordner) gespeichert und beim naechsten Start
  automatisch wiederhergestellt.
- **NEU: System-Vorabcheck.** Vor den Modulen prueft JustUpdate: Wartet Windows
  bereits auf einen Neustart? Laeuft das Geraet auf Akku? Sind weniger als
  10 GB auf der Systemplatte frei? -> klare Hinweise im Log statt kryptischer
  Folgefehler.
- **NEU: Neustart-Sammelmeldung.** "Neustart erforderlich" aus Windows-Update,
  Treibern und SFC wird gesammelt und landet sichtbar im Abschluss-Dialog, in
  der Log-Zusammenfassung und im result-JSON (`rebootRequired`).
- **NEU: Modul-Dauer.** Jedes Modul loggt am Ende seine Laufzeit, die Dauer
  steht zusaetzlich im result-JSON (`durationSeconds`) - "WO hing die Wartung
  so lange?" ist damit auf einen Blick beantwortbar. Die Modul-Header zeigen
  ausserdem "MODUL 3/7" (Position/ausgewaehlte Module) statt fixer Nummern.
- **NEU: Schliessen-Schutz.** X-Klick oder Alt+F4 waehrend laufender Wartung
  killte den Lauf bisher kommentarlos - mitten in einer Update-Installation.
  Jetzt kommt eine Rueckfrage, und erst bei "Ja" wird sauber gestoppt.
- **NEU: Bereinigung Schritt 6/6.** Der Delivery-Optimization-Cache (Peer-
  Cache fuer Windows-Updates) wird per offiziellem Microsoft-Cmdlet geleert.
- **Winget: Quellen-Index vor dem Upgrade aktualisiert** (`winget source
  update`) - ein Tage alter Index uebersieht sonst frische Updates.
- **Fix: Laufzeit-Uhr ging vor.** Die Anzeige rundete kaufmaennisch
  ([int]-Cast statt Floor) und sprang dadurch ab Sekunde 30 jeder Minute
  bereits eine Minute weiter.
- **Aufgeraeumt: Tray-Blocker-Liste dedupliziert.** Die Liste der Update-
  Blocker (OBS/Steam/Discord/...) stand doppelt im Code (Haupt-Thread und
  Worker-Runspace) und konnte auseinanderlaufen - jetzt EINE Quelle, die per
  SyncHash in den Worker wandert.
- **Abschluss-Sound** nach fertiger Wartung (nur im interaktiven Modus).

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
