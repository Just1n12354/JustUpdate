        # ── STORE APPS ──
        if ($cfg.Store) {
            if (IsStopped) { $sync.Done = $true; return }
            M "Store" "run"
            L "--------------------------------------------"
            L "  MODUL $($i+1)/${total}: Microsoft Store Apps"
            L "--------------------------------------------"
            try {
                # Schritt 1: MDM-Scan triggern (signalisiert dem Store-Backend dass es Updates pruefen soll).
                L "  Schritt 1/2: MDM Update-Scan triggern..."
                $mdmOk = $false
                try {
                    $ns = "root\cimv2\mdm\dmmap"
                    $cls = "MDM_EnterpriseModernAppManagement_AppManagement01"
                    $obj = Get-CimInstance -Namespace $ns -ClassName $cls -ErrorAction Stop
                    Invoke-CimMethod -InputObject $obj -MethodName "UpdateScanMethod" -ErrorAction Stop | Out-Null
                    $mdmOk = $true
                    L "    [OK] MDM-Scan getriggert"
                } catch {
                    L "    [WARNUNG] MDM nicht verfuegbar: $($_.Exception.Message)"
                }

                # Schritt 2: WUA mit Microsoft-Store-Service-ID nutzen - das macht echtes Download+Install
                # statt nur einen async Hintergrund-Hint. Service-ID 855E8A7C-...8289 = Microsoft Store.
                L "  Schritt 2/2: Microsoft Store Service via WUA pruefen..."
                $storeServiceId = "855E8A7C-ECB4-4CA3-B045-1DFA50104289"
                $storeOk = $false
                $installedCount = 0
                $availableCount = 0
                try {
                    # Store-Service registrieren (idempotent - falls schon registriert)
                    try {
                        $svcMgr = New-Object -ComObject Microsoft.Update.ServiceManager
                        $svcMgr.ClientApplicationID = "JustUpdate"
                        # Flag 3 = AllowPendingRegistration(1) + AllowOnlineRegistration(2).
                        # Bewusst OHNE Flag 4 (RegisterServiceWithAU) - gleiches Prinzip
                        # wie beim Microsoft-Update-Service in Modul 3/4: der Auto-
                        # Updater des Geraets soll nicht dauerhaft umgehaengt werden.
                        # (Bis v2.7.3 stand hier 7, also inkl. Flag 4 - inkonsistent.)
                        $null = $svcMgr.AddService2($storeServiceId, 3, "")
                    } catch {
                        # 0x80240020 = bereits registriert, ignorieren
                    }
                    $storeSession = New-Object -ComObject Microsoft.Update.Session
                    $storeSearcher = $storeSession.CreateUpdateSearcher()
                    $storeSearcher.ServiceID = $storeServiceId
                    $storeSearcher.SearchScope = 1   # MachineAndUser
                    $storeSearcher.ServerSelection = 3  # ssOthers (= benutze ServiceID)
                    L "    Suche Store-Updates ueber WUA..."
                    $storeResult = $storeSearcher.Search("IsInstalled=0")
                    $availableCount = $storeResult.Updates.Count

                    if ($availableCount -eq 0) {
                        L "    [OK] Keine Store-Updates verfuegbar - alle Apps aktuell"
                        $storeOk = $true
                    } else {
                        L "    $availableCount Store-Update(s) gefunden:"
                        $storeDl = New-Object -ComObject Microsoft.Update.UpdateColl
                        foreach ($u in $storeResult.Updates) {
                            L "      - $($u.Title)"
                            if (-not $u.EulaAccepted) { try { $u.AcceptEula() | Out-Null } catch {} }
                            if (-not $u.IsDownloaded) { $storeDl.Add($u) | Out-Null }
                        }
                        if ($storeDl.Count -gt 0) {
                            L "    Lade $($storeDl.Count) Store-Update(s) herunter..."
                            L "    (Download kann mehrere Minuten dauern - bitte warten)"
                            $sd = $storeSession.CreateUpdateDownloader()
                            $sd.Updates = $storeDl
                            $hb = Start-Heartbeat "      Store-Download "
                            try { $sdr = $sd.Download() } finally { Stop-Heartbeat $hb }
                            if ($sdr.ResultCode -ne 2 -and $sdr.ResultCode -ne 3) {
                                L "    [WARNUNG] Store-Download Code $($sdr.ResultCode)"
                            }
                        }
                        $storeInst = New-Object -ComObject Microsoft.Update.UpdateColl
                        foreach ($u in $storeResult.Updates) {
                            if ($u.IsDownloaded) { $storeInst.Add($u) | Out-Null }
                        }
                        if ($storeInst.Count -gt 0) {
                            L "    Installiere $($storeInst.Count) Store-Update(s)..."
                            L "    (Installation kann mehrere Minuten dauern - bitte warten)"
                            $si = $storeSession.CreateUpdateInstaller()
                            $si.Updates = $storeInst
                            $hb = Start-Heartbeat "      Store-Installation "
                            try { $sir = $si.Install() } finally { Stop-Heartbeat $hb }
                            for ($k = 0; $k -lt $storeInst.Count; $k++) {
                                $r = $sir.GetUpdateResult($k)
                                # 2 = Succeeded, 3 = SucceededWithErrors
                                if ($r.ResultCode -eq 2 -or $r.ResultCode -eq 3) {
                                    $installedCount++
                                    L "      [OK] $($storeInst.Item($k).Title)"
                                } else {
                                    L "      [FEHLER] $($storeInst.Item($k).Title) (Code $($r.ResultCode))"
                                }
                            }
                            # v2.7.6: gegen ALLE gefundenen Updates messen, nicht nur die
                            # heruntergeladenen - sonst "ok" obwohl Downloads fehlten
                            # (Log sagte ehrlich "3 von 5", Status widersprach sich selbst).
                            if ($installedCount -eq $availableCount) { $storeOk = $true }
                        }
                    }
                } catch {
                    L "    [WARNUNG] Store-WUA-Pfad fehlgeschlagen: $($_.Exception.Message)"
                }

                # Endbewertung: nur ok wenn WUA-Pfad echt etwas verifiziert hat (installiert oder nichts da).
                if ($storeOk -and $installedCount -gt 0) {
                    L "  [OK] $installedCount von $availableCount Store-Update(s) installiert"
                    Mark "Store" "ok" "$installedCount Store-Updates installiert"
                } elseif ($storeOk -and $availableCount -eq 0) {
                    L "  [OK] Microsoft Store ist auf dem neuesten Stand"
                    Mark "Store" "ok" "alle Store-Apps aktuell"
                } elseif ($installedCount -gt 0) {
                    Mark "Store" "warn" "$installedCount von $availableCount installiert"
                } elseif ($availableCount -gt 0) {
                    # v2.7.6: Updates gefunden, aber keins installiert (Download-/
                    # Install-Totalausfall) - vorher fiel das faelschlich auf
                    # "nur MDM-Scan im Hintergrund".
                    L "  [WARNUNG] $availableCount Store-Update(s) gefunden, keines installiert"
                    Mark "Store" "warn" "0 von $availableCount installiert (Download/Installation fehlgeschlagen)"
                } elseif ($mdmOk) {
                    L "  [WARNUNG] WUA-Store-Pfad lieferte nichts - MDM-Scan laeuft asynchron weiter"
                    Mark "Store" "warn" "nur MDM-Scan im Hintergrund"
                } else {
                    Mark "Store" "err" "weder WUA noch MDM verfuegbar"
                }
            } catch {
                L "  [FEHLER] $($_.Exception.Message)"
                Mark "Store" "err" $_.Exception.Message
            }
            Finish-Module
            $i++; P ($i / $total * 100)
            L ""
        }

