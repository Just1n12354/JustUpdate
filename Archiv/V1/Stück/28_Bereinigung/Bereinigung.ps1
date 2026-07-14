        # ── CLEANUP ──
        if ($cfg.Cleanup) {
            if (IsStopped) { $sync.Done = $true; return }
            M "Cleanup" "run"
            L "--------------------------------------------"
            L "  MODUL $($i+1)/${total}: Bereinigung & Optimierung"
            L "--------------------------------------------"
            try {
                # Papierkorb
                L "  Schritt 1/6: Papierkorb leeren..."
                try {
                    Clear-RecycleBin -Force -ErrorAction Stop
                    L "    [OK] Papierkorb geleert"
                } catch {
                    L "    Papierkorb bereits leer oder Zugriff verweigert"
                }

                # DNS Cache
                L "  Schritt 2/6: DNS-Cache leeren..."
                & ipconfig /flushdns 2>&1 | Out-Null
                L "    [OK] DNS-Cache geleert"

                # Temp Dateien (alle User-Profile + System-Temp)
                # Iteriert C:\Users\*\AppData\Local\Temp dynamisch — keine Hardcoded-Usernames.
                L "  Schritt 3/6: Temporaere Dateien entfernen..."
                $removed = 0
                $freedMB = 0
                $tempDirs = New-Object System.Collections.Generic.List[string]
                $tempDirs.Add("C:\Windows\Temp") | Out-Null
                $usersRoot = Join-Path $env:SystemDrive "Users"
                if (Test-Path $usersRoot) {
                    Get-ChildItem -Path $usersRoot -Directory -Force -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -notin @("Public","Default","Default User","All Users","WDAGUtilityAccount") } |
                        ForEach-Object {
                            $userTemp = Join-Path $_.FullName "AppData\Local\Temp"
                            if (Test-Path $userTemp) { $tempDirs.Add($userTemp) | Out-Null }
                        }
                }
                foreach ($dir in $tempDirs) {
                    L "    Durchsuche: $dir"
                    Get-ChildItem $dir -Recurse -Force -ErrorAction SilentlyContinue |
                        Where-Object { -not $_.PSIsContainer -and $_.LastWriteTime -lt (Get-Date).AddDays(-3) } |
                        ForEach-Object {
                            try {
                                $sz = $_.Length
                                Remove-Item $_.FullName -Force -ErrorAction Stop
                                $freedMB += $sz / 1MB
                                $removed++
                            } catch {}
                        }
                }
                L "    [OK] $removed Dateien entfernt ($([Math]::Round($freedMB, 1)) MB freigegeben)"

                # Windows Update Cache
                # FIX v2.3.3: wuauserv + bits stoppen vor dem Wipe — sonst koennen halb-fertige
                # Downloads von Settings/UsoSvc den Fehler 0x80070003 ausloesen. Aelter-als-1-Tag-Filter
                # verhindert ausserdem, dass eine LAUFENDE Settings-Update-Sitzung gekillt wird.
                L "  Schritt 4/6: Windows Update Cache..."
                try {
                    $wuCache = "C:\Windows\SoftwareDistribution\Download"
                    if (Test-Path $wuCache) {
                        $services = @("wuauserv","bits","UsoSvc")
                        $stoppedSvcs = @()
                        foreach ($svcName in $services) {
                            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
                            if ($svc -and $svc.Status -eq "Running") {
                                try { Stop-Service -Name $svcName -Force -ErrorAction Stop; $stoppedSvcs += $svcName } catch {}
                            }
                        }
                        Start-Sleep -Milliseconds 500
                        $sz = [Math]::Round((Get-ChildItem $wuCache -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB, 1)
                        L "    Cache-Groesse: $sz MB"
                        $cutoff = (Get-Date).AddDays(-1)
                        $skipped = 0
                        # Bug-Fix v2.7.5: NUR Dateien loeschen, danach leer gewordene
                        # Ordner. Vorher wurden auch ORDNER mit altem Datum rekursiv
                        # geloescht - inklusive FRISCHER Dateien darin (das Ordner-Datum
                        # aendert sich nur bei direktem Inhaltswechsel, nicht bei
                        # Aenderungen tiefer unten). Das hebelte den "frische Dateien
                        # schonen"-Schutz gegen 0x80070003 wieder aus.
                        Get-ChildItem $wuCache -Recurse -Force -ErrorAction SilentlyContinue |
                            Where-Object { -not $_.PSIsContainer } | ForEach-Object {
                                if ($_.LastWriteTime -gt $cutoff) {
                                    $skipped++
                                } else {
                                    try { Remove-Item $_.FullName -Force -ErrorAction Stop } catch {}
                                }
                            }
                        # Leer gewordene Unterordner entfernen - tiefste zuerst, damit
                        # Eltern-Ordner nach dem Leeren ihrer Kinder auch dran sind.
                        Get-ChildItem $wuCache -Recurse -Force -ErrorAction SilentlyContinue |
                            Where-Object { $_.PSIsContainer } |
                            Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
                                try {
                                    if (-not (Get-ChildItem $_.FullName -Force -ErrorAction SilentlyContinue)) {
                                        Remove-Item $_.FullName -Force -ErrorAction Stop
                                    }
                                } catch {}
                            }
                        foreach ($svcName in $stoppedSvcs) {
                            try { Start-Service -Name $svcName -ErrorAction Stop } catch {}
                        }
                        # Ehrliche Zahl: tatsaechlich freigegebenen Platz messen, statt
                        # die Gesamtgroesse zu melden obwohl frische Dateien bleiben.
                        $szAfter = [Math]::Round((Get-ChildItem $wuCache -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB, 1)
                        $szFreed = [Math]::Max(0, [Math]::Round($sz - $szAfter, 1))
                        if ($skipped -gt 0) {
                            L "    [OK] $szFreed MB freigegeben ($skipped frische Dateien geschont fuer laufende Downloads)"
                        } else {
                            L "    [OK] $szFreed MB freigegeben"
                        }
                    } else {
                        L "    Kein WU-Cache gefunden"
                    }
                } catch { L "    Zugriff verweigert (Windows Update laeuft moeglicherweise)" }

                # Thumbnail Cache (alle User-Profile)
                # Iteriert C:\Users\*\AppData\Local\Microsoft\Windows\Explorer dynamisch.
                L "  Schritt 5/6: Thumbnail-Cache..."
                try {
                    $thumbCount = 0
                    $thumbSize = 0
                    $usersRoot = Join-Path $env:SystemDrive "Users"
                    if (Test-Path $usersRoot) {
                        Get-ChildItem -Path $usersRoot -Directory -Force -ErrorAction SilentlyContinue |
                            Where-Object { $_.Name -notin @("Public","Default","Default User","All Users","WDAGUtilityAccount") } |
                            ForEach-Object {
                                $thumbDir = Join-Path $_.FullName "AppData\Local\Microsoft\Windows\Explorer"
                                if (Test-Path $thumbDir) {
                                    $files = Get-ChildItem $thumbDir -Filter "thumbcache_*.db" -Force -ErrorAction SilentlyContinue
                                    foreach ($f in $files) {
                                        try {
                                            $thumbSize += $f.Length
                                            Remove-Item $f.FullName -Force -ErrorAction Stop
                                            $thumbCount++
                                        } catch {}
                                    }
                                }
                            }
                    }
                    L "    [OK] $thumbCount Cache-Dateien ($([Math]::Round($thumbSize / 1MB, 1)) MB)"
                } catch {}

                # Delivery-Optimization-Cache (Peer-Cache fuer Windows-Updates).
                # Offizielles Microsoft-Cmdlet, loescht NUR den DO-Cache - keine
                # User-Daten. Auf aelteren Systemen fehlt das Cmdlet -> ueberspringen.
                L "  Schritt 6/6: Delivery-Optimization-Cache..."
                try {
                    if (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue) {
                        Delete-DeliveryOptimizationCache -Force -ErrorAction Stop
                        L "    [OK] Delivery-Optimization-Cache geleert"
                    } else {
                        L "    Auf diesem System nicht verfuegbar - uebersprungen"
                    }
                } catch { L "    Konnte nicht geleert werden (laeuft evtl. gerade ein Download) - uebersprungen" }

                L ""
                L "  [OK] Bereinigung abgeschlossen"
                Mark "Cleanup" "ok" "$removed Dateien, $([Math]::Round($freedMB,1)) MB freigegeben"
            } catch {
                L "  [FEHLER] $($_.Exception.Message)"
                Mark "Cleanup" "err" $_.Exception.Message
            }
            Finish-Module
            $i++; P ($i / $total * 100)
            L ""
        }

