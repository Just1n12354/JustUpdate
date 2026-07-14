# =====================================================================
# EVENTS
# =====================================================================
$e.xStart.Add_Click({ Start-Maintenance })
$e.xStop.Add_Click({ End-Session })
$e.xLog.Add_Click({ Start-Process notepad.exe "`"$($script:LogPath)`"" })
$e.xPatch.Add_Click({ Show-PatchHistory })

# Zeitplan-Button: legt eine woechentliche geplante Aufgabe an (Sonntag 11:00),
# die JustUpdate im Automatik-Modus (-Auto) startet - oder entfernt sie wieder.
# Laeuft als angemeldeter User mit hoechsten Rechten (RunLevel Highest), damit
# kein UAC-Prompt den unbeaufsichtigten Lauf blockiert. Bewusst Interactive:
# als SYSTEM koennte das WPF-Fenster in Session 0 nicht zuverlaessig laufen.
$e.xSched.Add_Click({
    $taskName = "JustUpdate Auto-Wartung"
    try {
        $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($existing) {
            $a = [System.Windows.MessageBox]::Show(
                "Die automatische Wartung ist bereits eingeplant:`n`n" +
                "  Aufgabe: $taskName`n  Rhythmus: woechentlich, Sonntag 11:00`n`n" +
                "Geplante Aufgabe ENTFERNEN?",
                "JustUpdate - Zeitplan",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Question)
            if ($a -eq [System.Windows.MessageBoxResult]::Yes) {
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
                [System.Windows.MessageBox]::Show("Die geplante Aufgabe wurde entfernt.",
                    "JustUpdate - Zeitplan", "OK", "Information") | Out-Null
            }
            return
        }
        $a = [System.Windows.MessageBox]::Show(
            "JustUpdate kann die komplette Wartung automatisch ausfuehren:`n`n" +
            "  - jeden Sonntag um 11:00 Uhr (PC muss an + User angemeldet sein)`n" +
            "  - mit den aktuell gespeicherten Modulen`n" +
            "  - ohne Nachfragen und ohne Abschluss-Dialog`n" +
            "  - laufende Programme werden NICHT geschlossen`n`n" +
            "Jetzt einplanen?",
            "JustUpdate - Zeitplan",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Question)
        if ($a -ne [System.Windows.MessageBoxResult]::Yes) { return }
        Save-JUSettings
        if ($isExe) {
            $action = New-ScheduledTaskAction -Execute $ScriptPath -Argument "-Auto"
        } else {
            $action = New-ScheduledTaskAction -Execute "powershell.exe" `
                        -Argument "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$ScriptPath`" -Auto"
        }
        $trigger   = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "11:00"
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
                        -RunLevel Highest -LogonType Interactive
        $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
                        -DontStopIfGoingOnBatteries -StartWhenAvailable `
                        -ExecutionTimeLimit (New-TimeSpan -Hours 4)
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
            -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
        [System.Windows.MessageBox]::Show(
            "Eingeplant: '$taskName' laeuft jeden Sonntag um 11:00 Uhr.`n`n" +
            "Verpasste Termine werden nachgeholt, sobald der PC wieder an ist.`n" +
            "Entfernen: einfach nochmal auf das Uhr-Symbol klicken.",
            "JustUpdate - Zeitplan", "OK", "Information") | Out-Null
    } catch {
        [System.Windows.MessageBox]::Show(
            "Zeitplan konnte nicht angelegt/geaendert werden:`n`n$($_.Exception.Message)",
            "JustUpdate - Zeitplan", "OK", "Warning") | Out-Null
    }
})

$e.xInfo.Add_Click({
    $infoMsg = @"
JustUpdate haelt Ihren PC sauber und aktuell - mit einem einzigen Klick.

WAS DIESE ANWENDUNG MACHT:

1. Wiederherstellungspunkt
   Erstellt vor allen Aenderungen einen Sicherungspunkt von Windows.
   So koennen Sie bei Problemen wieder zum vorherigen Zustand zurueck.

2. Defender aktualisieren
   Laedt die neuesten Viren-Signaturen fuer den Windows-Virenschutz herunter.

3. Windows Updates
   Sucht nach offiziellen Microsoft-Updates fuer Windows und installiert diese.
   (Treiber-Updates werden separat in Schritt 4 behandelt.)

4. Treiber aktualisieren
   Sucht ueber Windows Update nach neueren Geraete-Treibern (Drucker, Grafik, etc.)
   und installiert diese.

5. Apps aktualisieren (Winget)
   Aktualisiert alle installierten Programme, die ueber den Windows-Paketmanager
   (winget) bekannt sind - z.B. Browser, Office-Tools, Entwickler-Programme.

6. Microsoft Store Apps
   Stoesst die Aktualisierung aller Apps aus dem Microsoft Store an.
   (Laeuft im Hintergrund weiter, deshalb als 'Warnung' markiert.)

7. System-Reparatur
   Pruefen die Systemdateien (SFC) und reparieren beschaedigte Komponenten (DISM).
   Das ist die offizielle Microsoft-Methode bei Windows-Problemen.

8. Netzwerk reparieren
   Setzt DNS-Cache, Winsock und IP-Konfiguration zurueck.
   Hilft bei Internet-Problemen. Standardmaessig deaktiviert.

9. Bereinigung
   Leert Papierkorb, DNS-Cache und temporaere Dateien aller Benutzer auf diesem PC.
   Setzt den Thumbnail-Cache zurueck und gibt Speicher im Windows-Update-Ordner frei.

ZUSAETZLICHE FUNKTIONEN:

- Vor Updates fragt JustUpdate, ob alle offenen Programme geschlossen werden
  sollen, damit sich Update-Installationen nicht an gesperrten Dateien aufhaengen.
- Die Modul-Bezeichnungen links wechseln waehrend der Wartung die Farbe:
  WEISS = noch nicht gestartet, ROT = laeuft gerade, GRUEN = erfolgreich abgeschlossen.
- Alle Aktionen werden mitprotokolliert. Den letzten Log oeffnen Sie ueber 'LOG OEFFNEN'.
- Es werden maximal die 10 neuesten Logs aufbewahrt, aeltere werden automatisch geloescht.
- Ihre Modul-Auswahl und Sprache werden gespeichert und beim naechsten Start
  automatisch wiederhergestellt.
- Ueber das Uhr-Symbol oben rechts laesst sich eine woechentliche automatische
  Wartung einplanen (Sonntag 11:00). Sie laeuft ohne Nachfragen, schliesst keine
  Programme und beendet sich selbst. Erneuter Klick entfernt den Zeitplan.
- Vor der Wartung prueft JustUpdate automatisch: Internet-Verbindung, offener
  Windows-Neustart, Akku-Betrieb und freier Speicherplatz - und sagt klar,
  wenn etwas davon die Wartung beeintraechtigen koennte.

WAS DIESE ANWENDUNG NICHT MACHT:

- JustUpdate installiert keine Programme, die noch nicht auf Ihrem PC sind.
- JustUpdate verschickt keine Daten ins Internet (ausser fuer den Update-Download
  von Microsoft direkt) und sammelt keine persoenlichen Informationen.
- JustUpdate aendert keine persoenlichen Dateien (Dokumente, Bilder, Videos).
- JustUpdate ueberschreibt keine eigenen Einstellungen wie Hintergrundbild,
  Browser-Favoriten oder installierte Programme.
- Die Bereinigung loescht nur temporaere Dateien, die aelter als drei Tage sind -
  keine eigenen Dokumente, Downloads oder Programmdaten.

WICHTIGE HINWEISE:

- Bitte lassen Sie den PC waehrend der Wartung eingeschaltet.
- Manche Updates verlangen einen Neustart - JustUpdate weist Sie darauf hin.
- Fuer alle Module sind Administratorrechte noetig (wird automatisch angefragt).
- Bei Fragen oder Problemen oeffnen Sie das Log und schicken den Inhalt an Ihre
  IT-Person oder an Justin (info@itintechsolutions.ch).

Vielen Dank, dass Sie JustUpdate verwenden!
"@
    [System.Windows.MessageBox]::Show($infoMsg, "Info - Was macht JustUpdate?", "OK", "Information") | Out-Null
})

