        # ── WINDOWS UPDATE ──
        if ($cfg.WinUpdate) {
            if (IsStopped) { $sync.Done = $true; return }
            M "WinUpdate" "run"
            L "--------------------------------------------"
            L "  MODUL $($i+1)/${total}: Windows Updates"
            L "--------------------------------------------"
            try {
                L "  Windows Update Service initialisieren..."
                $session = New-Object -ComObject Microsoft.Update.Session
                $searcher = $session.CreateUpdateSearcher()

                # v2.6.3: Microsoft Update Service einbinden, damit auch die "Optionalen
                # Updates" aus Settings -> Erweiterte Optionen erfasst werden. Default-
                # ServerSelection liefert je nach Geraete-Policy (WSUS/Intune/MU-Toggle aus)
                # nur einen Teil und laesst optionale Preview-/Office-/Server-Updates weg.
                # ServiceID 7971f918-... entspricht dem Settings-Toggle "Updates fuer andere
                # Microsoft-Produkte erhalten". Flag 2 (AllowOnlineRegistration), bewusst
                # OHNE Flag 4 (RegisterServiceWithAU) - der Auto-Updater des Geraets soll
                # nicht dauerhaft umgehaengt werden.
                $muServiceId = "7971f918-a847-4430-9279-4a52d1efe18d"
                try {
                    $svcMgr = New-Object -ComObject Microsoft.Update.ServiceManager
                    $muRegistered = $false
                    foreach ($svc in $svcMgr.Services) {
                        if ($svc.ServiceID -eq $muServiceId) { $muRegistered = $true; break }
                    }
                    if (-not $muRegistered) {
                        $svcMgr.AddService2($muServiceId, 2, "") | Out-Null
                        L "  Microsoft Update Service registriert (fuer optionale Updates)"
                    }
                    $searcher.ServerSelection = 3   # ssOthers
                    $searcher.ServiceID       = $muServiceId
                    L "  Suche via Microsoft Update (inkl. optionale Updates)..."
                } catch {
                    L "  [WARNUNG] Microsoft Update nicht verfuegbar - Fallback auf Default-Server"
                    L "           Optionale Updates koennen ausgelassen werden. Grund: $($_.Exception.Message)"
                }

                # FIX v2.3.3: Type='Software'-Filter weggelassen, damit Vorschau-/Preview-Updates
                # (z.B. KB5083631) ebenfalls gefunden werden. Treiber filtern wir gleich raus,
                # weil die in Modul 4 separat behandelt werden.
                $result = $searcher.Search("IsInstalled=0 AND IsHidden=0")
                $softwareUpdates = @($result.Updates | Where-Object {
                    # v2.7.6: IUpdate.Type=2 (utDriver) ist der DOKUMENTIERTE Treiber-
                    # Indikator; der bisherige Kategorie-Check ($cat.Type -eq "Driver")
                    # haengt an einem undokumentierten Wert und bleibt nur als
                    # zweite Absicherung stehen.
                    $isDriver = $false
                    try { if ($_.Type -eq 2) { $isDriver = $true } } catch {}
                    if (-not $isDriver) {
                        foreach ($cat in $_.Categories) { if ($cat.Type -eq "Driver") { $isDriver = $true; break } }
                    }
                    -not $isDriver
                })

                if ($softwareUpdates.Count -eq 0) {
                    L "  [OK] Windows ist auf dem neuesten Stand - keine Updates verfuegbar"
                    Mark "WinUpdate" "ok" "keine Updates verfuegbar"
                } else {
                    L "  $($softwareUpdates.Count) Update(s) gefunden:"
                    L ""
                    $dlColl = New-Object -ComObject Microsoft.Update.UpdateColl
                    $updateNum = 1
                    foreach ($u in $softwareUpdates) {
                        $size = ""
                        try {
                            $sizeMb = [Math]::Round($u.MaxDownloadSize / 1MB, 1)
                            # Sanity-Check: einige cumulative Updates (z.B. KB5089549) liefern absurd hohe MaxDownloadSize-Werte
                            # (z.B. 92489.9 MB) - Anzeige unterdruecken statt User mit Fake-Zahl zu verwirren.
                            if ($sizeMb -gt 0 -and $sizeMb -lt 50000) { $size = " ($sizeMb MB)" }
                        } catch {}
                        L "    [$updateNum/$($softwareUpdates.Count)] $($u.Title)$size"
                        if (-not $u.EulaAccepted) { try { $u.AcceptEula() | Out-Null } catch {} }
                        if (-not $u.IsDownloaded) { $dlColl.Add($u) | Out-Null }
                        $updateNum++
                    }
                    L ""

                    $dlFailed = $false
                    if ($dlColl.Count -gt 0) {
                        L "  Lade $($dlColl.Count) Update(s) herunter..."
                        L "  (Download kann mehrere Minuten dauern - bitte warten, App reagiert solange nicht)"
                        $dl = $session.CreateUpdateDownloader()
                        $dl.Updates = $dlColl
                        $hb = Start-Heartbeat "    Download "
                        try { $dlResult = $dl.Download() } finally { Stop-Heartbeat $hb }
                        # ResultCode: 2=Success, 3=SucceededWithErrors, 4=Failed, 5=Aborted
                        if ($dlResult.ResultCode -eq 2) {
                            L "  [OK] Download abgeschlossen"
                        } elseif ($dlResult.ResultCode -eq 3) {
                            L "  [WARNUNG] Download mit Warnungen abgeschlossen"
                        } else {
                            $dlFailed = $true
                            $reason = switch ($dlResult.ResultCode) { 4 {"FEHLGESCHLAGEN"} 5 {"ABGEBROCHEN"} default {"Code $($dlResult.ResultCode)"} }
                            L "  [FEHLER] Download $reason (HResult: 0x$('{0:X}' -f $dlResult.HResult))"
                            L "         Typischer Grund: fehlende Admin-Rechte oder Windows-Update-Dienst inaktiv"
                        }
                    } else {
                        L "  Alle Updates bereits heruntergeladen"
                    }

                    $instColl = New-Object -ComObject Microsoft.Update.UpdateColl
                    foreach ($u in $softwareUpdates) { if ($u.IsDownloaded) { $instColl.Add($u) | Out-Null } }

                    if ($instColl.Count -gt 0) {
                        L "  Installiere $($instColl.Count) Update(s)..."
                        L "  (Installation kann 5-30 Minuten dauern - bitte nicht abbrechen, PC nicht herunterfahren)"
                        $inst = $session.CreateUpdateInstaller()
                        $inst.Updates = $instColl
                        $hb = Start-Heartbeat "    Installation "
                        try { $r = $inst.Install() } finally { Stop-Heartbeat $hb }

                        $successCount = 0
                        $failCount = 0
                        for ($idx = 0; $idx -lt $instColl.Count; $idx++) {
                            $uResult = $r.GetUpdateResult($idx)
                            $status = switch ($uResult.ResultCode) { 2 {"OK"} 3 {"OK (mit Warnung)"} 4 {"FEHLGESCHLAGEN"} 5 {"ABGEBROCHEN"} default {"Status $($uResult.ResultCode)"} }
                            L "    [$status] $($instColl.Item($idx).Title)"
                            if ($uResult.ResultCode -eq 2 -or $uResult.ResultCode -eq 3) { $successCount++ } else { $failCount++ }
                        }
                        L ""
                        L "  $successCount von $($instColl.Count) Updates erfolgreich installiert"
                        if ($r.RebootRequired) { L "  >>> NEUSTART ERFORDERLICH <<<"; $sync.RebootRequired = $true }

                        if ($failCount -eq 0 -and -not $dlFailed) {
                            Mark "WinUpdate" "ok" "$successCount Updates installiert"
                        } elseif ($successCount -gt 0) {
                            Mark "WinUpdate" "warn" "$successCount von $($instColl.Count) installiert, $failCount fehlgeschlagen"
                        } else {
                            Mark "WinUpdate" "err" "Installation aller $($instColl.Count) Updates fehlgeschlagen"
                        }
                    } elseif ($dlFailed) {
                        Mark "WinUpdate" "err" "Downloads fehlgeschlagen (keine Installation moeglich)"
                    } else {
                        Mark "WinUpdate" "warn" "Updates gefunden, aber nichts installiert"
                    }
                }
            } catch {
                L "  [FEHLER] COM-API: $($_.Exception.Message)"
                Mark "WinUpdate" "err" "COM-API Fehler: $($_.Exception.Message)"
            }
            Finish-Module
            $i++; P ($i / $total * 100)
            L ""
        }

