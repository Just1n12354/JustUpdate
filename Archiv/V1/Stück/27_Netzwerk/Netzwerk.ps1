        # ── NETWORK ──
        if ($cfg.Network) {
            if (IsStopped) { $sync.Done = $true; return }
            M "Network" "run"
            L "--------------------------------------------"
            L "  MODUL $($i+1)/${total}: Netzwerk reparieren"
            L "--------------------------------------------"
            try {
                $netFailures = @()

                # Helper: Native EXE mit OEM-Encoding ausfuehren (ipconfig emittiert CP850).
                function Invoke-OemCapture([string]$exe, [string]$argString) {
                    $p = New-Object System.Diagnostics.ProcessStartInfo
                    $p.FileName = $exe
                    $p.Arguments = $argString
                    $p.RedirectStandardOutput = $true
                    $p.RedirectStandardError = $true
                    $p.UseShellExecute = $false
                    $p.CreateNoWindow = $true
                    $p.StandardOutputEncoding = $oemEnc
                    $p.StandardErrorEncoding  = $oemEnc
                    $pr = [System.Diagnostics.Process]::Start($p)
                    # Async lesen + 120s-Hardtimeout: ipconfig kehrt praktisch immer sofort zurueck,
                    # aber ein blockierter Netzwerk-Stack (haengender WLAN-Treiber, VPN-Client) darf
                    # die Wartung nicht endlos aufhalten. ReadToEnd() wuerde bei so einem Haenger
                    # selbst blockieren - darum ReadToEndAsync(), damit WaitForExit(timeout) greift.
                    $soTask = $pr.StandardOutput.ReadToEndAsync()
                    $seTask = $pr.StandardError.ReadToEndAsync()
                    if ($pr.WaitForExit(120000)) {
                        return @{ Out = ($soTask.Result + $seTask.Result) -split "`r?`n"; Exit = $pr.ExitCode }
                    }
                    # Timeout: Prozessbaum hart beenden (gleiche Methode wie Invoke-MonitoredProcess).
                    try { Start-Process taskkill.exe -ArgumentList "/PID $($pr.Id) /T /F" -WindowStyle Hidden -Wait -ErrorAction Stop } catch { try { $pr.Kill() } catch {} }
                    return @{ Out = @("[Timeout] $exe $argString nach 120s abgebrochen"); Exit = -1 }
                }

                L "  Schritt 1/5: DNS-Cache leeren..."
                $dns = Invoke-OemCapture "ipconfig.exe" "/flushdns"
                $dns.Out | ForEach-Object { $l = "$_".Trim(); if ($l.Length -gt 1) { L "    $l" } }
                if ($dns.Exit -ne 0) { $netFailures += "DNS-Flush" }

                L "  Schritt 2/5: Winsock-Katalog zuruecksetzen..."
                $wsOut = & netsh winsock reset 2>&1
                $wsOut | ForEach-Object { $l = "$_".Trim(); if ($l.Length -gt 1) { L "    $l" } }
                if ($LASTEXITCODE -ne 0) {
                    $netFailures += "Winsock-Reset"
                }

                L "  Schritt 3/5: IP-Adresse freigeben..."
                [void](Invoke-OemCapture "ipconfig.exe" "/release")

                L "  Schritt 4/5: Neue IP-Adresse beziehen..."
                $ren = Invoke-OemCapture "ipconfig.exe" "/renew"
                $ren.Out | ForEach-Object { $l = "$_".Trim(); if ($l.Length -gt 1) { L "    $l" } }

                L "  Schritt 5/5: TCP/IP-Stack zuruecksetzen..."
                $tcpOut = & netsh int ip reset 2>&1
                # netsh int ip reset emittiert ~16 Zeilen ohne Schluessel-Namen (leere
                # Uebersetzung im NSI-Layer). Wir loggen Zeilen mit Praefix einzeln,
                # die anonymen "wird zurueckgesetzt... OK/Fehler" aggregieren wir.
                $anonOk = 0; $anonErr = 0; $lastWasAnonErr = $false
                $uU = [char]0x00FC  # ü fuer "zurückgesetzt"
                $anonPattern = "^(wird zur${uU}ckgesetzt|Resetting)\.{0,3}\s*(OK|Fehler|Failed|Failed\.|denied|verweigert)?\s*$"
                foreach ($line in $tcpOut) {
                    $l = "$line".Trim()
                    if ($l.Length -lt 2) { $lastWasAnonErr = $false; continue }
                    if ($l -match $anonPattern) {
                        if ($l -match 'OK\s*$') { $anonOk++; $lastWasAnonErr = $false } else { $anonErr++; $lastWasAnonErr = $true }
                        continue
                    }
                    if ($lastWasAnonErr -and $l -match '^(Zugriff verweigert|Access is denied)\s*$') { $lastWasAnonErr = $false; continue }
                    $lastWasAnonErr = $false
                    L "    $l"
                }
                if (($anonOk + $anonErr) -gt 0) {
                    L "    (Weitere Reset-Schritte: $anonOk OK$(if ($anonErr -gt 0) { ", $anonErr Fehler (gesperrte Registry-Keys, harmlos)" }))"
                }
                # Hinweis: einzelne "Zugriff verweigert" Zeilen auf NSI-Registry-Keys
                # (z.B. {eb004a00-...}\26) sind ein bekannter harmloser Windows-Artefakt.
                # netsh setzt dann $LASTEXITCODE=1, druckt aber die Erfolgsmeldung
                # "Starten Sie den Computer neu". Wir pruefen deshalb auf diese
                # Erfolgsmeldung statt auf den Exit-Code.
                $tcpSuccess = ($tcpOut -match "Starten Sie den Computer neu|Restart the computer")
                $deniedCount = ($tcpOut | Where-Object { "$_" -match "verweigert|denied" }).Count
                if (-not $tcpSuccess) {
                    $netFailures += "TCP/IP-Reset"
                } elseif ($deniedCount -gt 0) {
                    L "  (Hinweis: $deniedCount gesperrte Registry-Key(s) uebersprungen - harmlos, bekanntes Windows-Verhalten)"
                }

                L ""
                if ($netFailures.Count -eq 0) {
                    L "  [OK] Netzwerk-Reset abgeschlossen"
                    L "  >>> NEUSTART EMPFOHLEN fuer vollstaendige Wirkung <<<"
                    Mark "Network" "ok" "alle Schritte erfolgreich"
                } else {
                    L "  [WARNUNG] Folgende Schritte fehlgeschlagen: $($netFailures -join ', ')"
                    L "  Admin-Rechte erforderlich fuer Winsock/TCP-IP-Reset"
                    Mark "Network" "warn" "fehlgeschlagen: $($netFailures -join ', ')"
                }
            } catch {
                L "  [FEHLER] $($_.Exception.Message)"
                Mark "Network" "err" $_.Exception.Message
            }
            Finish-Module
            $i++; P ($i / $total * 100)
            L ""
        }

