        # ── REPAIR ──
        if ($cfg.Repair) {
            if (IsStopped) { $sync.Done = $true; return }
            M "Repair" "run"
            L "--------------------------------------------"
            L "  MODUL $($i+1)/${total}: System-Reparatur"
            L "--------------------------------------------"
            try {
                L "  Schritt 1/2: SFC (System File Checker)"
                L "  Pruefe Integritaet der Systemdateien..."
                L "  (Bricht nach 30 Min ohne Reaktion automatisch ab)"
                L ""

                # SFC gibt UTF-16 LE aus - sonst bekommen wir Gibberish.
                # Ueberwacht mit 30-Min-Timeout, damit ein haengendes sfc.exe die
                # Wartung nicht endlos blockiert (Bug: 145 Min ohne Reaktion).
                $sfcRun = Invoke-MonitoredProcess -FileName "sfc.exe" -Arguments "/scannow" `
                            -TimeoutSec 1800 -OutEncoding ([System.Text.Encoding]::Unicode)
                $sfcExit     = $sfcRun.ExitCode
                $sfcTimedOut = $sfcRun.TimedOut
                # v2.7.6: User-Abbruch beendet sfc.exe via Watchdog - der Exit-Code
                # ist dann ein Abbruch-Artefakt (taskkill), kein SFC-Fehler. Vorher
                # wurde "[FEHLER] SFC fehlgeschlagen" geloggt, DISM lief trotzdem
                # noch an und das Modul endete auf "err - Admin-Rechte pruefen".
                if (IsStopped) { $sync.Done = $true; return }
                # Pending-Reboot wird von sfc.exe mit Exit-Code 1 + Meldung "Systemreparatur aus" /
                # "Neustart erfordert" / "pending system repair" gemeldet. Das ist kein Fehler — SFC
                # konnte legitim nicht laufen, weil ein vorheriger CBS-Vorgang noch nicht durch ist.
                $sfcCombined = ($sfcRun.Lines -join " ")
                # v2.7.6: EN-Varianten ergaenzt - die reale EN-Meldung lautet
                # "There is a system repair pending which requires reboot" (andere
                # Wortreihenfolge als das alte Pattern, "reboot" statt "restart").
                $sfcPending = (-not $sfcTimedOut) -and ($sfcExit -ne 0) -and ($sfcCombined -match 'Systemreparatur aus|Neustart erfordert|pending system repair|system repair pending|requires a restart|requires reboot')
                $sfcOk = (-not $sfcTimedOut) -and ($sfcExit -eq 0)
                if ($sfcOk) {
                    L "  [OK] SFC abgeschlossen"
                } elseif ($sfcTimedOut) {
                    L "  [WARNUNG] SFC reagierte 30 Min nicht - abgebrochen und uebersprungen"
                } elseif ($sfcPending) {
                    L "  [WARNUNG] SFC uebersprungen - Neustart erforderlich, dann erneut ausfuehren"
                    $sync.RebootRequired = $true
                } else {
                    L "  [FEHLER] SFC fehlgeschlagen (Exit-Code: $sfcExit)"
                }

                L ""
                L "  Schritt 2/2: DISM (Deployment Image Servicing)"
                L "  Repariere Windows-Komponentenspeicher..."
                L "  (Bricht nach 45 Min ohne Reaktion automatisch ab)"
                L ""

                # DISM emittiert OEM-Codepage (CP850 auf DE-Locale), nicht UTF-8.
                # 45-Min-Timeout: DISM /restorehealth haengt sich klassisch auf, wenn
                # der Komponentenspeicher beschaedigt ist oder Windows Update nicht
                # erreichbar ist - genau die Ursache fuer den 145-Min-Hang.
                # Heartbeat: DISM gibt KEINE Progress-Zeilen aus (anders als WUA/winget) —
                # ohne Heartbeat sieht der User 45 Min lang absolut nichts.
                $dismHb = Start-Heartbeat "    DISM-Repair " 30
                $dismRun = Invoke-MonitoredProcess -FileName "dism.exe" `
                             -Arguments "/online /cleanup-image /restorehealth" `
                             -TimeoutSec 2700 -OutEncoding $oemEnc
                Stop-Heartbeat $dismHb
                $dismExit     = $dismRun.ExitCode
                $dismTimedOut = $dismRun.TimedOut

                # v2.6.4: Retry bei Exit 32 (ERROR_SHARING_VIOLATION). Klassische
                # Ursache: ein Antivirus (HP Wolf, Defender Real-Time, Drittanbieter)
                # scannt parallel eine Datei aus dem Komponentenspeicher und hat sie
                # gelockt. 45 Sekunden reichen meistens, damit der Scan fertig ist.
                # Wir versuchen es genau einmal nochmal - laenger zu warten lohnt
                # nicht, dann ist's vermutlich kein vorvoruebergehender Lock mehr.
                if (-not $dismTimedOut -and $dismExit -eq 32) {
                    L "  [HINWEIS] DISM meldet Datei-Konflikt (Exit 32) - typisch bei aktivem Antivirus."
                    L "           Warte 45 Sekunden und versuche es nochmal..."
                    Start-Sleep -Seconds 45
                    $dismRun = Invoke-MonitoredProcess -FileName "dism.exe" `
                                 -Arguments "/online /cleanup-image /restorehealth" `
                                 -TimeoutSec 2700 -OutEncoding $oemEnc
                    $dismExit     = $dismRun.ExitCode
                    $dismTimedOut = $dismRun.TimedOut
                }

                # v2.7.6: User-Abbruch waehrend DISM nicht als DISM-Fehler bewerten.
                if (IsStopped) { $sync.Done = $true; return }

                # v2.7.6: Exit 3010 = dokumentierter DISM-Erfolg mit ausstehendem
                # Neustart - vorher als "[FEHLER] DISM fehlgeschlagen (3010)" gemeldet.
                $dismOk = (-not $dismTimedOut) -and ($dismExit -eq 0 -or $dismExit -eq 3010)
                if ($dismExit -eq 3010) {
                    $sync.RebootRequired = $true
                    L "  [HINWEIS] DISM erfolgreich - PC-Neustart zum Abschliessen noetig (Exit 3010)"
                }
                if ($dismOk) {
                    L "  [OK] DISM abgeschlossen"
                } elseif ($dismTimedOut) {
                    L "  [WARNUNG] DISM reagierte 45 Min nicht - abgebrochen und uebersprungen"
                } elseif ($dismExit -eq 32) {
                    L "  [FEHLER] DISM auch nach Retry mit Datei-Konflikt (Exit 32)"
                    L "         Tipp: Antivirus voruebergehend pausieren und JustUpdate erneut starten"
                } else {
                    L "  [FEHLER] DISM fehlgeschlagen (Exit-Code: $dismExit)"
                }

                L ""
                if ($sfcOk -and $dismOk) {
                    L "  [OK] System-Reparatur abgeschlossen"
                    Mark "Repair" "ok" "SFC + DISM erfolgreich"
                } elseif ($sfcPending -and $dismOk) {
                    L "  [WARNUNG] DISM OK - SFC braucht Neustart, dann erneut ausfuehren"
                    Mark "Repair" "warn" "Kein echter Fehler: Eine fruehere Windows-Reparatur ist noch offen. Bitte den PC neu starten und JustUpdate danach nochmal ausfuehren."
                } elseif ($sfcTimedOut -or $dismTimedOut) {
                    $slow = @(); if ($sfcTimedOut) { $slow += "SFC" }; if ($dismTimedOut) { $slow += "DISM" }
                    L "  [WARNUNG] System-Reparatur abgebrochen (Zeitueberschreitung: $($slow -join ' + '))"
                    Mark "Repair" "warn" "$($slow -join ' + ') hat zu lange nicht reagiert und wurde nach dem Zeitlimit abgebrochen. Meist nur voruebergehend - bitte den PC neu starten und JustUpdate spaeter erneut ausfuehren."
                } elseif ($sfcOk -or $dismOk) {
                    $who = if ($sfcOk) { "DISM" } else { "SFC" }
                    L "  [WARNUNG] Teilweise erfolgreich - $who fehlgeschlagen"
                    Mark "Repair" "warn" "$who konnte nicht abgeschlossen werden (der andere Teil war erfolgreich). Bitte JustUpdate als Administrator erneut ausfuehren."
                } else {
                    L "  [FEHLER] SFC und DISM fehlgeschlagen - Admin-Rechte pruefen"
                    Mark "Repair" "err" "SFC und DISM fehlgeschlagen - bitte JustUpdate als Administrator starten (Rechtsklick > Als Administrator ausfuehren)."
                }
            } catch {
                L "  [FEHLER] $($_.Exception.Message)"
                Mark "Repair" "err" $_.Exception.Message
            }
            Finish-Module
            $i++; P ($i / $total * 100)
            L ""
        }

