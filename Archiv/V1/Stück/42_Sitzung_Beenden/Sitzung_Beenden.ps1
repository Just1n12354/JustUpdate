function End-Session {
    param([switch]$completed)
    # Reentrancy-Guard: Stop-Klick (End-Session) und der Done-Tick des UI-Timers
    # (End-Session -completed) koennen fast gleichzeitig feuern - ein bereits in der
    # Dispatcher-Queue stehender Tick laeuft trotz $UITimer.Stop() noch durch. Ohne
    # Guard liefe der Report-/Mail-/Dialog-Block doppelt und griffe auf die schon
    # disposte Pipeline / genullte SyncHash-Werte zu.
    if ($script:SessionEnded) { return }
    $script:SessionEnded = $true
    if ($script:UITimer)    { $script:UITimer.Stop() }
    if ($script:ClockTimer) { $script:ClockTimer.Stop() }
    if (-not $completed -and $script:SyncHash) { $script:SyncHash.Stop = $true }
    # Bug-Fix v2.7.6 (K2): Beim ABBRUCH nicht synchron stoppen. Stop()/
    # Dispose()/Close() warten, bis die Pipeline einen Checkpoint erreicht -
    # ein laufender WUA-COM-Call (Download()/Install(), bis zu 30 Min) blockte
    # damit den UI-Thread: Fenster "Keine Rueckmeldung", Kunde killt den
    # Prozess mitten in der Update-Installation. BeginStop kehrt sofort
    # zurueck; $sync.Stop laesst die Watchdogs laufende Kindprozesse binnen
    # ~1s beenden. Bewusst KEIN sofortiges Dispose/Close im Abbruch-Pfad
    # (beide stoppen ebenfalls synchron) - das Prozessende raeumt auf.
    if ($completed) {
        if ($script:Pipeline) { try { $script:Pipeline.Stop() } catch {}; try { $script:Pipeline.Dispose() } catch {} }
        if ($script:Runspace)  { try { $script:Runspace.Close() } catch {} }
    } else {
        if ($script:Pipeline) { try { [void]$script:Pipeline.BeginStop($null, $null) } catch {} }
    }
    $e.xStop.IsEnabled  = $false
    if ($completed) {
        $e.xStatus.Text = T "Done"
        $ok   = 0; $warn = 0; $err = 0
        if ($script:SyncHash) {
            $ok   = [int]$script:SyncHash.SummaryOk
            $warn = [int]$script:SyncHash.SummaryWarn
            $err  = [int]$script:SyncHash.SummaryErr
        }
        # --- Maschinenlesbarer Report (Fleet-Monitoring ueber mehrere Geraete) ---
        # Komplett gekapselt: ein Fehler hier darf den Abschluss-Dialog NIE stoppen.
        try {
            $modules = @()
            if ($script:SyncHash -and $script:SyncHash.Results) {
                foreach ($k in @($script:SyncHash.Results.Keys)) {
                    $r = $script:SyncHash.Results[$k]
                    $modules += [PSCustomObject]@{
                        module          = $k
                        status          = [string]$r.Status
                        details         = [string]$r.Details
                        durationSeconds = if ($r.ContainsKey('DurationSeconds')) { [int]$r.DurationSeconds } else { $null }
                    }
                }
            }
            $reportVer = $script:JUVersion
            $started = $script:StartTime
            $report = [PSCustomObject]@{
                tool            = "JustUpdate"
                version         = $reportVer
                host            = $env:COMPUTERNAME
                user            = $env:USERNAME
                startedUtc      = if ($started) { $started.ToUniversalTime().ToString("o") } else { $null }
                finishedUtc     = (Get-Date).ToUniversalTime().ToString("o")
                durationSeconds = if ($started) { [int]((Get-Date) - $started).TotalSeconds } else { $null }
                summary         = [PSCustomObject]@{ ok = $ok; warnings = $warn; errors = $err }
                overall         = if ($err -gt 0) { "error" } elseif ($warn -gt 0) { "warning" } else { "ok" }
                rebootRequired  = [bool]($script:SyncHash -and $script:SyncHash.RebootRequired)
                autoMode        = [bool]$script:AutoMode
                modules         = $modules
            }
            # Nur den DATEINAMEN umschreiben (verankert), nicht den ganzen Pfad per
            # ungeankertem Regex - sonst wuerde ein Ordnerpfad, der "Maintenance_"
            # enthaelt, mitumgeschrieben und das JSON landete im Nirgendwo.
            $logDir   = Split-Path $script:LogPath
            $logLeaf  = [IO.Path]::GetFileNameWithoutExtension($script:LogPath) -replace '^Maintenance_', 'result_'
            $jsonPath = Join-Path $logDir "$logLeaf.json"
            # BOM-frei schreiben: ConvertTo-Json | Out-File -Encoding utf8 setzt in
            # PS5.1 ein fuehrendes UTF-8-BOM (EF BB BF) VOR die '{' - strikte JSON-
            # Parser (Fleet-Auswertung, .NET System.Text.Json, Linux/NAS-Tools)
            # stolpern darueber. WriteAllText mit UTF8Encoding($false) = ohne BOM.
            [IO.File]::WriteAllText($jsonPath, ($report | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
            $script:LastResultJson = $jsonPath
            # Rotation: max. 20 Result-JSONs behalten (analog Log-Rotation)
            Get-ChildItem -Path (Split-Path $jsonPath) -Filter "result_*.json" -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -Skip 20 |
                ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }

            # Fleet-Monitoring: Report zusaetzlich zentral ablegen, wenn ein
            # Sammelpfad gesetzt ist ($env:JUSTUPDATE_REPORT_DIR, z.B. OneDrive/
            # NAS). Dateiname mit Host -> kollisionsfrei ueber viele Geraete.
            # fleet-report.ps1 -Path <dieser Ordner> wertet das aus.
            if ($env:JUSTUPDATE_REPORT_DIR) {
                try {
                    $fleetDir = $env:JUSTUPDATE_REPORT_DIR
                    if (-not (Test-Path $fleetDir)) { New-Item -ItemType Directory -Path $fleetDir -Force -ErrorAction Stop | Out-Null }
                    Copy-Item $jsonPath (Join-Path $fleetDir ("{0}__{1}" -f $env:COMPUTERNAME, (Split-Path $jsonPath -Leaf))) -Force -ErrorAction Stop
                } catch { }
            }
        } catch { }

        # Automatik-Modus: kein Dialog, kein Mail-Prompt - Report ist geschrieben,
        # Exit-Code gesetzt, Fenster zu. Task Scheduler sieht 0/1/2.
        if ($script:AutoMode) {
            $script:AutoExitCode = if ($err -gt 0) { 2 } elseif ($warn -gt 0) { 1 } else { 0 }
            try { $Window.Close() } catch {}
            return
        }

        # Dezenter Abschluss-Sound - der User darf waehrend der langen Wartung
        # woanders sein und hoert trotzdem, dass sie fertig ist.
        try { [System.Media.SystemSounds]::Asterisk.Play() } catch {}

        $msg    = "$ok erfolgreich, $warn Warnungen, $err Fehler"
        $rebootNeeded = [bool]($script:SyncHash -and $script:SyncHash.RebootRequired)
        # Neustart-Hinweis NICHT mehr als statischer Text in der Zusammenfassung -
        # er kommt weiter unten als eigener Ja/Nein-Vorschlag ("Jetzt neu starten?").
        $icon   = if ($err -gt 0) { "Error" } elseif ($warn -gt 0) { "Warning" } else { "Information" }
        $header = if ($err -gt 0) { "Wartung mit Fehlern beendet" }
                  elseif ($warn -gt 0) { "Wartung mit Warnungen beendet" }
                  else { T "Done" }
        if ($err -gt 0 -or $warn -gt 0) {
            $details = if ($script:SyncHash) { [string]$script:SyncHash.SummaryDetails } else { "" }
            if ($details.Trim().Length -gt 0) {
                $msg += "`n`n--- Was genau ---`n`n$details"
            }
            $msg += "`n`nVollstaendige Details: Button 'LOG OEFFNEN'."
            $msg += "`n`nMit 'Mail an Support senden' wird automatisch eine Mail "
            $msg += "`nmit Log + Diagnose vorbereitet - du musst nur noch auf "
            $msg += "`n'Senden' klicken. Mit 'Schliessen' passiert nichts."
            $lvl = if ($err -gt 0) { "err" } else { "warn" }
            $sendMail = Show-SupportPrompt -Title $header -Body $msg -Level $lvl
            if ($sendMail) {
                # Mail-Header / Body bauen — fuer BEIDE Wege (Outlook + mailto) identisch.
                $subj = "JustUpdate Bericht - $($env:COMPUTERNAME) - $ok OK / $warn Warn / $err Fehler"
                $head = "Automatischer JustUpdate-Bericht`r`n`r`n" +
                        "Host: $($env:COMPUTERNAME)`r`nBenutzer: $($env:USERNAME)`r`n" +
                        "Version: v$($script:JUVersion)`r`n" +
                        "Ergebnis: $ok OK, $warn Warnungen, $err Fehler`r`n" +
                        "Log-Datei: $($script:LogPath)`r`n"
                # Modul-Details (kompakte Liste der warn/err) aus dem SyncHash
                $modTxt = ""
                if ($script:SyncHash -and $script:SyncHash.Results) {
                    $bad = @()
                    foreach ($k in @($script:SyncHash.Results.Keys)) {
                        $r = $script:SyncHash.Results[$k]
                        if ($r.Status -eq "warn" -or $r.Status -eq "err") {
                            $bad += "  [$($r.Status.ToUpper())] $k - $($r.Details)"
                        }
                    }
                    if ($bad.Count -gt 0) {
                        $modTxt = "`r`n--- Module mit Problemen ---`r`n" + ($bad -join "`r`n") + "`r`n"
                    }
                }
                # Voller Log fuer die Zwischenablage zusammenbauen — Kunde
                # macht einmal Strg+V im Mail-Body und hat alles drin.
                $fullLog = ""
                try {
                    if (Test-Path $script:LogPath) {
                        $fullLog = [IO.File]::ReadAllText($script:LogPath)
                    }
                } catch {}
                $bodyFull = $head + $modTxt
                if ($fullLog) {
                    $bodyFull += "`r`n--- Log (vollstaendig) ---`r`n" + $fullLog + "`r`n"
                }

                # IMMER ueber Standard-Mail-Handler (mailto:) — respektiert die
                # Mail-App, die der Kunde in Windows als Default gesetzt hat
                # (Outlook, Thunderbird, Apple Mail, Web-Mail-Handler, ...).
                # Frueher (v2.6.5 - v2.6.9): direkte Outlook-COM-Automation
                # hat IMMER Outlook geoeffnet, auch wenn der Kunde lieber eine
                # andere App benutzt - jetzt entfernt.
                try {
                    # 1) Vollen Log + Diagnose in die Zwischenablage. mailto-
                    #    URLs sind laengen-limitiert (~2000 Bytes), aber der
                    #    Kunde kann mit einem Strg+V den gesamten Inhalt im
                    #    Mail-Body einfuegen.
                    try { Set-Clipboard -Value $bodyFull -ErrorAction Stop } catch {}

                    # 2) Kompakter Body in der mailto-URL: Header + Modul-
                    #    Stati + Klartext-Hinweis was zu tun ist.
                    $hint = "`r`n--- WICHTIG ---`r`n" +
                            "Der vollstaendige Log liegt bereits in der ZWISCHENABLAGE." +
                            "`r`nBitte hier im Mail-Body einmal Strg+V druecken, dann Senden." +
                            "`r`n" +
                            "`r`nAlternativ liegt die Log-Datei im gerade geoeffneten" +
                            "`r`nOrdner und kann als Anhang reingezogen werden.`r`n"
                    $bodyForUri = $head + $modTxt + $hint
                    if ($bodyForUri.Length -gt 1800) {
                        $bodyForUri = $bodyForUri.Substring(0, 1800) +
                                      "`r`n[gekuerzt - voller Log in Zwischenablage]"
                    }
                    $u = "mailto:info@itintechsolutions.ch?subject=$([uri]::EscapeDataString($subj))&body=$([uri]::EscapeDataString($bodyForUri))"
                    # Start-Process auf mailto-URL -> Windows fragt den
                    # registrierten Default-Mail-Handler. Hat der Kunde keinen
                    # Default gesetzt, kommt der "Eine App auswaehlen"-Dialog
                    # von Windows - genau richtig.
                    Start-Process $u
                    # Ordner mit Log + result_*.json oeffnen (Backup-Pfad fuer
                    # Anhang). Sicht statt /select, damit beide Dateien sichtbar.
                    Start-Process explorer.exe ("`"" + (Split-Path $script:LogPath) + "`"")
                } catch {}
            }
        } else {
            [System.Windows.MessageBox]::Show($msg, $header, "OK", $icon) | Out-Null
        }

        # ── Neustart-Nachfrage ──────────────────────────────────────────────
        # Liegt ein Neustart an, kommt NACH der Zusammenfassung ein eigener
        # Ja/Nein-Dialog. Reiner Vorschlag: bei "Nein" passiert nichts (der
        # Hinweis bleibt im Log + result-JSON erhalten). Im Automatik-Modus
        # erscheint er nicht (dort oben bereits per return verlassen).
        if ($rebootNeeded) {
            $rb = [System.Windows.MessageBox]::Show(
                "Einige Aenderungen wirken erst nach einem Neustart vollstaendig`n" +
                "(z.B. Defender-Signaturen, Windows-Updates, SFC, Netzwerk-Reset).`n`n" +
                "Moechtest du den PC JETZT neu starten?`n`n" +
                "(Bei 'Nein' kannst du jederzeit spaeter selbst neu starten.)",
                "JustUpdate - Neustart empfohlen",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Question)
            $rbMsg = if ($rb -eq [System.Windows.MessageBoxResult]::Yes) {
                "Neustart vom Benutzer bestaetigt - PC wird in 20s neu gestartet (Abbruch: 'shutdown /a')."
            } else {
                "Neustart vom Benutzer verschoben (Vorschlag mit 'Nein' abgelehnt)."
            }
            try { [IO.File]::AppendAllText($script:LogPath, "[$(Get-Date -F 'HH:mm:ss')]   [INFO] $rbMsg`r`n", (New-Object System.Text.UTF8Encoding($false))) } catch {}
            if ($rb -eq [System.Windows.MessageBoxResult]::Yes) {
                # Geplanter Neustart mit 20s Karenz - Windows zeigt seine eigene
                # Vorwarnung, der User kann mit 'shutdown /a' noch abbrechen.
                try {
                    Start-Process shutdown.exe -ArgumentList @('/r','/t','20','/c','JustUpdate: Neustart nach Wartung') -WindowStyle Hidden
                } catch {
                    try { Restart-Computer -Force } catch {}
                }
            }
        }
    } else {
        $e.xStatus.Text = T "Stopped"
    }
    # Bug-Fix v2.7.6 (K3): START erst wieder freigeben, wenn ALLE Abschluss-
    # Dialoge (Zusammenfassung, Neustart-Frage) durch sind. Vorher stand die
    # Freigabe VOR den ownerlosen MessageBoxen - waehrend die offen waren,
    # konnte ein neuer Lauf starten und der Neustart-Prompt von Lauf 1 setzte
    # dann 'shutdown /r' mitten in Lauf 2 ab.
    $script:MaintRunning = $false
    $e.xStart.IsEnabled = $true
}

