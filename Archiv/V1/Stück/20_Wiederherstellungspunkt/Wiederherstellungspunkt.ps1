        # ── RESTORE POINT ──
        if ($cfg.Restore) {
            if (IsStopped) { $sync.Done = $true; return }
            M "Restore" "run"
            L "--------------------------------------------"
            L "  MODUL $($i+1)/${total}: Wiederherstellungspunkt"
            L "--------------------------------------------"
            L "  Systemschutz aktivieren auf C:\..."
            try {
                try { Enable-ComputerRestore -Drive "C:\" -ErrorAction Stop }
                catch { L "  [Hinweis] Systemschutz liess sich nicht aktivieren (evtl. per Richtlinie gesperrt)" }

                # Windows erlaubt per Default nur 1 Restore-Punkt / 24h und
                # ueberspringt weitere STILL (sieht aus wie Erfolg, ist aber keiner).
                # Frequenz-Sperre fuer diesen Lauf aushebeln, danach zuruecksetzen.
                $srKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
                $freqOrig = $null
                try {
                    if (-not (Test-Path $srKey)) { New-Item -Path $srKey -Force | Out-Null }
                    $freqOrig = (Get-ItemProperty -Path $srKey -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency
                    Set-ItemProperty -Path $srKey -Name SystemRestorePointCreationFrequency -Value 0 -Type DWord -ErrorAction SilentlyContinue
                } catch {}

                $rpName = "MaintenancePro_$(Get-Date -F 'yyyyMMdd_HHmm')"
                L "  Erstelle Wiederherstellungspunkt..."
                L "  Name: $rpName"
                try {
                    Checkpoint-Computer -Description $rpName -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
                    L "  [OK] Wiederherstellungspunkt erfolgreich erstellt"
                    Mark "Restore" "ok" "erstellt"
                } catch {
                    $em = $_.Exception.Message
                    # Systemschutz aus / per GPO gesperrt = KEIN Fehler des Wartungs-
                    # laufs -> als klaren Hinweis (warn) statt rotem Fehler melden.
                    if ($em -match 'disabled|deaktiviert|0x8004230F|VSS|shadow|policy|Richtlinie|81000101|frequency|0x81000101') {
                        L "  [HINWEIS] Wiederherstellungspunkt uebersprungen:"
                        L "    Systemschutz ist auf diesem PC deaktiviert oder per"
                        L "    Firmen-Richtlinie gesperrt - kein Wartungsfehler."
                        Mark "Restore" "warn" "Systemschutz deaktiviert/gesperrt - Punkt uebersprungen (kein Geraetefehler)"
                    } else {
                        L "  [FEHLER] $em"
                        Mark "Restore" "err" $em
                    }
                } finally {
                    # Frequenz-Sperre exakt wie vorgefunden wiederherstellen.
                    try {
                        if ($null -ne $freqOrig) { Set-ItemProperty -Path $srKey -Name SystemRestorePointCreationFrequency -Value $freqOrig -Type DWord -ErrorAction SilentlyContinue }
                        else { Remove-ItemProperty -Path $srKey -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue }
                    } catch {}
                }
            } catch {
                L "  [FEHLER] $($_.Exception.Message)"
                Mark "Restore" "err" $_.Exception.Message
            }
            Finish-Module
            $i++; P ($i / $total * 100)
            L ""
        }

