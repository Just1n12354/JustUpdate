        # ── DRIVERS ──
        if ($cfg.Drivers) {
            if (IsStopped) { $sync.Done = $true; return }
            M "Drivers" "run"
            L "--------------------------------------------"
            L "  MODUL $($i+1)/${total}: Treiber-Updates"
            L "--------------------------------------------"
            try {
                L "  Windows Update Service fuer Treiber initialisieren..."
                $session = New-Object -ComObject Microsoft.Update.Session
                $searcher = $session.CreateUpdateSearcher()

                # v2.6.3: Microsoft Update Service auch fuer Treiber nutzen - damit die
                # "Optionalen Treiber-Updates" aus Settings -> Erweiterte Optionen ->
                # Treiber-Updates erfasst werden. Default-Sucher haengt sonst an der
                # WU-Default-Policy (ExcludeWUDriversInQualityUpdate / MU-Toggle aus)
                # vorbei und liefert nur "wichtige" Treiber. Selbe ServiceID/Flags wie
                # in Modul 3, idempotent (AddService2 wird uebersprungen falls schon da).
                $muServiceId = "7971f918-a847-4430-9279-4a52d1efe18d"
                try {
                    $svcMgr = New-Object -ComObject Microsoft.Update.ServiceManager
                    $muRegistered = $false
                    foreach ($svc in $svcMgr.Services) {
                        if ($svc.ServiceID -eq $muServiceId) { $muRegistered = $true; break }
                    }
                    if (-not $muRegistered) {
                        $svcMgr.AddService2($muServiceId, 2, "") | Out-Null
                        L "  Microsoft Update Service registriert (fuer optionale Treiber)"
                    }
                    $searcher.ServerSelection = 3   # ssOthers
                    $searcher.ServiceID       = $muServiceId
                    L "  Suche via Microsoft Update (inkl. optionale Treiber)..."
                } catch {
                    L "  [WARNUNG] Microsoft Update nicht verfuegbar - Fallback auf Default-Server"
                    L "           Optionale Treiber koennen ausgelassen werden. Grund: $($_.Exception.Message)"
                }

                L "  Suche nach verfuegbaren Treiber-Updates..."
                # v2.7.5: IsHidden=0 wie in Modul 3 - Treiber, die der User in den
                # Windows-Einstellungen ausgeblendet hat, werden respektiert statt
                # zwangsinstalliert. (Die Verifikations-Re-Scans bleiben bewusst
                # ohne den Filter - fuers Nachpruefen ist breiter sicherer.)
                $drvResult = $searcher.Search("IsInstalled=0 AND IsHidden=0 AND Type='Driver'")

                # Bug-Fix v2.7.5: chronisch fehlschlagende Treiber (per UpdateID) nach
                # $DrvBlacklistThreshold Fehlversuchen aus der Liste nehmen. Ohne das bleibt
                # z.B. der superseded HP-USB-Treiber ewig haengen und drueckt den Overall-
                # Status jedes Laufs strukturell auf "error". $drvIdByTitle merkt sich die
                # UpdateID pro Titel fuer die Fehl-/Erfolgs-Buchung am Ende.
                $drvBlacklist = Load-DriverBlacklist
                $drvIdByTitle = @{}
                $usableDrv    = @()
                $drvIgnored   = @()
                foreach ($d in $drvResult.Updates) {
                    $uid = try { [string]$d.Identity.UpdateID } catch { $null }
                    if ($uid) { $drvIdByTitle[$d.Title] = $uid }
                    if ($uid -and $drvBlacklist.ContainsKey($uid) -and
                        $drvBlacklist[$uid].FailCount -ge $script:DrvBlacklistThreshold) {
                        $drvIgnored += $d.Title
                    } else {
                        $usableDrv += $d
                    }
                }
                if ($drvIgnored.Count -gt 0) {
                    L "  [INFO] $($drvIgnored.Count) chronisch fehlschlagende(r) Treiber uebersprungen (>= $($script:DrvBlacklistThreshold) Fehlversuche):"
                    foreach ($t in $drvIgnored) { L "    - $t (ignoriert)" }
                }

                if ($usableDrv.Count -eq 0) {
                    if ($drvIgnored.Count -gt 0) {
                        L "  [OK] Keine neuen Treiber - $($drvIgnored.Count) chronischer Fehlschlag dauerhaft ignoriert"
                        Mark "Drivers" "ok" "keine neuen Treiber ($($drvIgnored.Count) chronischer Fehlschlag ignoriert)"
                    } else {
                        L "  [OK] Alle Treiber sind auf dem neuesten Stand"
                        Mark "Drivers" "ok" "keine Treiber-Updates verfuegbar"
                    }
                } else {
                    L "  $($usableDrv.Count) Treiber-Update(s) gefunden:"
                    L ""
                    $dColl = New-Object -ComObject Microsoft.Update.UpdateColl
                    $drvNum = 1
                    foreach ($d in $usableDrv) {
                        L "    [$drvNum/$($usableDrv.Count)] $($d.Title)"
                        if (-not $d.EulaAccepted) { try { $d.AcceptEula() | Out-Null } catch {} }
                        $dColl.Add($d) | Out-Null
                        $drvNum++
                    }
                    L ""
                    L "  Lade Treiber herunter..."
                    L "  (Download kann mehrere Minuten dauern - bitte warten, App reagiert solange nicht)"
                    $dl = $session.CreateUpdateDownloader()
                    $dl.Updates = $dColl
                    $hb = Start-Heartbeat "    Treiber-Download "
                    try { $dlRes = $dl.Download() } finally { Stop-Heartbeat $hb }
                    $drvTotal = $dColl.Count      # Gesamtzahl VOR evtl. RemoveAt (fuer ehrliche Zaehlung)
                    $drvDlSkipped = 0             # beim Download uebersprungene Treiber (RC3)
                    if ($dlRes.ResultCode -eq 2) {
                        L "  [OK] Download abgeschlossen"
                    } elseif ($dlRes.ResultCode -eq 3) {
                        # v2.7.5: SucceededWithErrors wie in Modul 3 akzeptieren -
                        # ein teilweiser Download soll nicht ALLE Treiber verwerfen.
                        L "  [WARNUNG] Download mit Warnungen abgeschlossen"
                        # Nicht heruntergeladene Treiber aus der Install-Liste nehmen -
                        # IUpdateInstaller.Install() wirft sonst fuer die GANZE Liste.
                        for ($di = $dColl.Count - 1; $di -ge 0; $di--) {
                            if (-not $dColl.Item($di).IsDownloaded) {
                                L "  [WARNUNG] Nicht heruntergeladen - uebersprungen: $($dColl.Item($di).Title)"
                                $dColl.RemoveAt($di)
                                $drvDlSkipped++   # v2.7.6: zaehlt unten als offen, sonst "ok" trotz fehlendem Treiber
                            }
                        }
                        if ($dColl.Count -eq 0) {
                            Mark "Drivers" "err" "Treiber-Download fehlgeschlagen (kein Treiber vollstaendig geladen)"
                            throw "Download failed"
                        }
                    } else {
                        L "  [FEHLER] Treiber-Download fehlgeschlagen (Status: $($dlRes.ResultCode), HResult: 0x$('{0:X}' -f $dlRes.HResult))"
                        L "         Typischer Grund: fehlende Admin-Rechte"
                        Mark "Drivers" "err" "Treiber-Download fehlgeschlagen"
                        throw "Download failed"
                    }
                    L "  Installiere Treiber..."
                    L "  (Installation kann mehrere Minuten dauern - bitte warten)"
                    $inst = $session.CreateUpdateInstaller()
                    $inst.Updates = $dColl
                    $hb = Start-Heartbeat "    Treiber-Installation "
                    try { $r = $inst.Install() } finally { Stop-Heartbeat $hb }

                    $drvOk = 0; $drvFail = $drvDlSkipped   # uebersprungene Downloads zaehlen als offen (v2.7.6)
                    $reportedOk = @()  # Treiber, die WUA als OK meldet — die werden gleich verifiziert
                    $drvHardFailTitles = @()  # ResultCode 4 o.ae. — echte Install-Fehlschlaege (fuer Blacklist)
                    for ($idx = 0; $idx -lt $dColl.Count; $idx++) {
                        $uResult = $r.GetUpdateResult($idx)
                        $status = switch ($uResult.ResultCode) { 2 {"OK"} 3 {"OK (Warnung)"} 4 {"FEHLGESCHLAGEN"} default {"Status $($uResult.ResultCode)"} }
                        L "    [$status] $($dColl.Item($idx).Title)"
                        if ($uResult.ResultCode -eq 2 -or $uResult.ResultCode -eq 3) {
                            $drvOk++
                            $reportedOk += $dColl.Item($idx).Title
                        } else { $drvFail++; $drvHardFailTitles += $dColl.Item($idx).Title }
                    }
                    if ($r.RebootRequired) { L "  >>> NEUSTART ERFORDERLICH <<<"; $sync.RebootRequired = $true }

                    # FIX v2.3.3: Verifikation - WUA-ResultCode=2 luegt bei optionalen/superseded Treibern.
                    # Re-Search; was immer noch IsInstalled=0 ist, wurde NICHT wirklich installiert.
                    # Fallback: pnputil mit den heruntergeladenen Treiber-Dateien (Microsoft-signiert).
                    $drvVerifyPending = @()  # Treiber, die trotz WUA-OK nach Re-Scan offen bleiben (fuer Blacklist)
                    $drvVerifyCrashed = $false  # Re-Scan geworfen -> Blacklist-Zaehler unangetastet lassen
                    if ($reportedOk.Count -gt 0) {
                        L ""
                        L "  Verifiziere Installation (Re-Scan)..."
                        try {
                            $verSearcher = $session.CreateUpdateSearcher()
                            # v2.6.3: Re-Search MUSS dieselbe Quelle nutzen wie die
                            # urspruengliche Suche, sonst false positives (MU-Treiber
                            # waere im Default-Sucher unbekannt -> faelschlich "installiert").
                            if ($searcher.ServerSelection -eq 3 -and $searcher.ServiceID) {
                                $verSearcher.ServerSelection = 3
                                $verSearcher.ServiceID       = $searcher.ServiceID
                            }
                            $verResult = $verSearcher.Search("IsInstalled=0 AND Type='Driver'")
                            $stillPending = @()
                            foreach ($v in $verResult.Updates) {
                                # v2.7.6: vom User VERSTECKTE Eintraege nicht als "offen"
                                # werten. Szenario: User hat Geraete-Zwilling A (gleicher
                                # Titel) in den Windows-Einstellungen ausgeblendet, B wird
                                # installiert - der Re-Scan fand sonst den versteckten A
                                # und buchte den ERFOLG von B als Fehlschlag.
                                $vHidden = $false; try { $vHidden = [bool]$v.IsHidden } catch {}
                                if ($vHidden) { continue }
                                if ($reportedOk -contains $v.Title) { $stillPending += $v.Title }
                            }
                            if ($stillPending.Count -eq 0) {
                                L "  [OK] Alle als installiert gemeldeten Treiber sind weg"
                            } else {
                                L "  [WARNUNG] $($stillPending.Count) Treiber wurden trotz [OK] NICHT installiert:"
                                foreach ($t in $stillPending) { L "    - $t" }
                                L "  Versuche pnputil-Fallback ueber Treiber-Cache..."

                                $pnpInstalled = 0
                                $cacheRoot = "C:\Windows\SoftwareDistribution\Download"
                                if (Test-Path $cacheRoot) {
                                    $infFiles = Get-ChildItem -Path $cacheRoot -Recurse -Filter *.inf -ErrorAction SilentlyContinue
                                    L "    $($infFiles.Count) .inf-Dateien im Treiber-Cache gefunden"
                                    foreach ($inf in $infFiles) {
                                        try {
                                            $pnpOut = & pnputil.exe /add-driver $inf.FullName /install 2>&1
                                            if ($LASTEXITCODE -eq 0 -or "$pnpOut" -match "erfolgreich|success") {
                                                $pnpInstalled++
                                            }
                                        } catch {}
                                    }
                                    L "  [OK] pnputil-Fallback: $pnpInstalled Treiber-Paket(e) uebernommen"
                                    # Ehrliche Verifikation statt blinder .inf-Zaehlung:
                                    # der Cache enthaelt i.d.R. WEIT mehr .inf als haengende
                                    # Treiber (mehrere .inf pro Paket + Altbestaende).
                                    # $pnpInstalled gegen $stillPending zu rechnen drueckte
                                    # $drvFail faelschlich auf 0 -> "alle Treiber installiert
                                    # (verifiziert)" obwohl pnputil nur fremde .inf einspielte.
                                    # Nach pnputil deshalb erneut suchen, welche der zuvor
                                    # haengenden Treiber JETZT noch IsInstalled=0 sind.
                                    $reallyPending = $stillPending
                                    try {
                                        $reSearcher = $session.CreateUpdateSearcher()
                                        if ($searcher.ServerSelection -eq 3 -and $searcher.ServiceID) {
                                            $reSearcher.ServerSelection = 3
                                            $reSearcher.ServiceID       = $searcher.ServiceID
                                        }
                                        $reResult = $reSearcher.Search("IsInstalled=0 AND Type='Driver'")
                                        $reallyPending = @($reResult.Updates | Where-Object { ($stillPending -contains $_.Title) -and -not $_.IsHidden } | ForEach-Object { $_.Title })
                                    } catch {
                                        L "  [WARNUNG] Re-Verifikation nach pnputil fehlgeschlagen - werte haengende Treiber als offen"
                                    }
                                    # Inkrementell gegen die WUA-Zaehler verrechnen (wie der
                                    # No-Cache-Zweig) - NICHT mit $dColl.Count ueberschreiben,
                                    # sonst gingen echte WUA-Fehlschlaege aus der Install-Schleife
                                    # verloren.
                                    $drvFail += @($reallyPending).Count
                                    $drvOk    = [Math]::Max(0, $drvOk - @($reallyPending).Count)
                                    $drvVerifyPending = @($reallyPending)
                                    if (@($reallyPending).Count -gt 0) {
                                        L "  [WARNUNG] $(@($reallyPending).Count) Treiber haengen weiterhin (auch nach pnputil):"
                                        foreach ($t in $reallyPending) { L "    - $t" }
                                    }
                                } else {
                                    L "  [WARNUNG] Kein Treiber-Cache fuer pnputil-Fallback vorhanden"
                                    $drvFail += $stillPending.Count
                                    $drvOk = [Math]::Max(0, $drvOk - $stillPending.Count)
                                    $drvVerifyPending = @($stillPending)
                                }
                            }
                        } catch {
                            L "  [WARNUNG] Verifikation fehlgeschlagen: $($_.Exception.Message)"
                            $drvVerifyCrashed = $true
                        }
                    }

                    # Blacklist pflegen (Bug-Fix v2.7.5): Treiber, die auch nach Verifikation/
                    # pnputil offen bleiben (oder hart mit ResultCode 4 scheitern), hochzaehlen;
                    # erfolgreich installierte ihren Zaehler wieder loeschen. Erreicht ein Treiber
                    # $DrvBlacklistThreshold, ueberspringt der naechste Lauf ihn automatisch.
                    try {
                        $drvUnresolved = @(@($drvHardFailTitles) + @($drvVerifyPending) | Select-Object -Unique)
                        $nowStamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                        $processedUids = @{}
                        foreach ($d in $usableDrv) {
                            $uid = $drvIdByTitle[$d.Title]
                            if (-not $uid) { continue }
                            # v2.7.6: Titel-Duplikate (zwei identische Geraete -> gleicher
                            # Titel, verschiedene UpdateIDs, aber Map liefert nur EINE) nur
                            # einmal pro Lauf buchen - sonst zaehlt ein Fehlschlag doppelt
                            # und der Threshold ist nach 2 statt 3 Laeufen erreicht.
                            if ($processedUids.ContainsKey($uid)) { continue }
                            $processedUids[$uid] = $true
                            if ($drvUnresolved -contains $d.Title) {
                                $prev = if ($drvBlacklist.ContainsKey($uid)) { [int]$drvBlacklist[$uid].FailCount } else { 0 }
                                $newCount = $prev + 1
                                $drvBlacklist[$uid] = @{ Title = $d.Title; FailCount = $newCount; LastAttempt = $nowStamp }
                                if ($newCount -ge $script:DrvBlacklistThreshold) {
                                    L "  [INFO] '$($d.Title)' hat $newCount Fehlversuche - wird kuenftig uebersprungen"
                                }
                            } elseif (-not $drvVerifyCrashed -and ($reportedOk -contains $d.Title) -and $drvBlacklist.ContainsKey($uid)) {
                                # Zuruecksetzen NUR fuer Treiber, die in diesem Lauf
                                # tatsaechlich installiert UND verifiziert wurden
                                # ($reportedOk). Ohne den Check wurde der Zaehler auch
                                # fuer Treiber geloescht, die beim Download uebersprungen
                                # wurden (RC3) und nie einen Install-Versuch sahen -
                                # ein chronischer Treiber mit Download-Flakes haette
                                # den Threshold so nie erreicht.
                                [void]$drvBlacklist.Remove($uid)   # diesmal verifiziert geklappt -> Zaehler weg
                            }
                        }
                        Save-DriverBlacklist $drvBlacklist
                    } catch {}

                    if ($drvFail -eq 0) {
                        Mark "Drivers" "ok" "$drvOk Treiber installiert (verifiziert)"
                    } elseif ($drvOk -gt 0) {
                        Mark "Drivers" "warn" "$drvOk von $drvTotal Treibern installiert, $drvFail haengen (siehe Optionale Updates)"
                    } else {
                        Mark "Drivers" "err" "Alle $drvTotal Treiber-Updates fehlgeschlagen"
                    }
                }
            } catch {
                if (-not $sync.Results.ContainsKey("Drivers")) {
                    L "  [FEHLER] $($_.Exception.Message)"
                    Mark "Drivers" "err" $_.Exception.Message
                }
            }
            Finish-Module
            $i++; P ($i / $total * 100)
            L ""
        }

