        # ── DEFENDER ──
        if ($cfg.Defender) {
            if (IsStopped) { $sync.Done = $true; return }
            M "Defender" "run"
            L "--------------------------------------------"
            L "  MODUL $($i+1)/${total}: Windows Defender"
            L "--------------------------------------------"
            try {
                # Drittanbieter-AV (Norton/Avast/...) erkennen: dann ist Defender
                # passiv -> "nicht verfuegbar" ist NORMAL, kein Fehler/Warnung.
                $otherAv = $null
                try {
                    $avs = Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue
                    $otherAv = ($avs | Where-Object { $_.displayName -and $_.displayName -notmatch 'Windows Defender|Microsoft Defender' } | Select-Object -First 1).displayName
                } catch {}
                if (Get-Command Update-MpSignature -ErrorAction SilentlyContinue) {
                    # Aktuelle Version vor dem Update merken (fuer Verifikation)
                    $defOldVer = $null
                    $defOldTime = $null
                    try {
                        $defStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue
                        if ($defStatus) {
                            $defOldVer = $defStatus.AntivirusSignatureVersion
                            $defOldTime = $defStatus.AntivirusSignatureLastUpdated
                            L "  Aktueller Status:"
                            L "    Antivirus-Version:  $defOldVer"
                            L "    Letztes Update:     $defOldTime"
                            L "    Echtzeit-Schutz:    $(if($defStatus.RealTimeProtectionEnabled){'Aktiv'}else{'Inaktiv'})"
                        }
                    } catch {}
                    L "  Lade neueste Signaturen herunter..."
                    Update-MpSignature -ErrorAction Stop
                    # Verifikation: neue Version oder neuere Update-Zeit?
                    $defNewVer = $null
                    $defNewTime = $null
                    try {
                        $defNew = Get-MpComputerStatus -ErrorAction SilentlyContinue
                        if ($defNew) {
                            $defNewVer = $defNew.AntivirusSignatureVersion
                            $defNewTime = $defNew.AntivirusSignatureLastUpdated
                            L "  Neue Version:         $defNewVer"
                            L "  Neues Update-Datum:   $defNewTime"
                        }
                    } catch {}
                    if ($defNewVer -and $defOldVer -and ($defNewVer -ne $defOldVer)) {
                        L "  [OK] Defender-Signaturen erfolgreich aktualisiert (neu: $defNewVer)"
                        Mark "Defender" "ok" "Signaturen aktualisiert ($defNewVer)"
                    } elseif ($defNewTime -and $defOldTime -and ($defNewTime -gt $defOldTime)) {
                        L "  [OK] Defender-Signaturen erfolgreich aktualisiert"
                        Mark "Defender" "ok" "Signaturen aktualisiert"
                    } elseif ($defNewVer -and $defOldVer -and ($defNewVer -eq $defOldVer)) {
                        L "  [OK] Defender war bereits aktuell ($defNewVer)"
                        Mark "Defender" "ok" "bereits aktuell"
                    } else {
                        L "  [WARNUNG] Update-Befehl lief durch, Verifikation aber nicht moeglich"
                        Mark "Defender" "warn" "Status nicht verifizierbar"
                    }
                } elseif ($otherAv) {
                    L "  [OK] Windows Defender inaktiv - Drittanbieter-Virenschutz aktiv:"
                    L "       $otherAv  (aktualisiert sich selbst - kein Handlungsbedarf)"
                    Mark "Defender" "ok" "Fremd-AV aktiv ($otherAv) - Defender passiv, normal"
                } else {
                    L "  [WARNUNG] Windows Defender ist auf diesem System nicht verfuegbar"
                    Mark "Defender" "warn" "Defender nicht verfuegbar"
                }
            } catch {
                if ($otherAv) {
                    L "  [OK] Defender-Update nicht moeglich - Drittanbieter-AV aktiv: $otherAv"
                    Mark "Defender" "ok" "Fremd-AV aktiv ($otherAv)"
                } else {
                    # Update-MpSignature ruft den Defender-Dienst per RPC auf. Dieser
                    # Aufruf scheitert haeufig TRANSIENT mit "Der Remoteprozeduraufruf
                    # ist fehlgeschlagen" (0x800706BE) - typisch waehrend/nach einem
                    # Defender-Plattform-Update oder bei ausstehendem Neustart. Das ist
                    # kein echter Defekt -> nicht als harter Fehler melden.
                    $defErr = $_.Exception.Message
                    $isRpc  = $defErr -match 'Remoteprozeduraufruf|800706BE|RPC server'
                    # 1) Echter Reparaturversuch: MpCmdRun.exe laeuft als eigener Prozess
                    #    (kein PowerShell-RPC) und kommt oft durch, wo das Cmdlet scheitert.
                    $mpCmd = $null
                    $platformBase = Join-Path $env:ProgramData 'Microsoft\Windows Defender\Platform'
                    if (Test-Path $platformBase) {
                        $mpCmd = Get-ChildItem $platformBase -Directory -ErrorAction SilentlyContinue |
                            Sort-Object Name -Descending |
                            ForEach-Object { Join-Path $_.FullName 'MpCmdRun.exe' } |
                            Where-Object { Test-Path $_ } | Select-Object -First 1
                    }
                    if (-not $mpCmd) {
                        $fb = Join-Path $env:ProgramFiles 'Windows Defender\MpCmdRun.exe'
                        if (Test-Path $fb) { $mpCmd = $fb }
                    }
                    $fallbackOk = $false
                    if ($mpCmd) {
                        L "  Cmdlet fehlgeschlagen ($defErr) - Fallback ueber MpCmdRun.exe..."
                        try {
                            $mpOut = & $mpCmd -SignatureUpdate 2>&1
                            if ($LASTEXITCODE -eq 0) {
                                L "  [OK] Defender-Signaturen ueber MpCmdRun aktualisiert"
                                Mark "Defender" "ok" "Signaturen aktualisiert (MpCmdRun-Fallback)"
                                $fallbackOk = $true
                            } else {
                                L "  MpCmdRun-Fallback ohne Erfolg (Exit $LASTEXITCODE)"
                            }
                        } catch {
                            L "  MpCmdRun-Fallback nicht ausfuehrbar: $($_.Exception.Message)"
                        }
                    }
                    # 2) Auch der Fallback hat nicht geklappt: bei RPC-/Neustart-Lage als
                    #    WARNUNG melden (kein echter Fehler), sonst als harten Fehler.
                    if (-not $fallbackOk) {
                        if ($isRpc -or $pendingReboot -or $sync.RebootRequired) {
                            L "  [WARNUNG] Defender-Signatur-Update aktuell nicht moeglich (RPC/Neustart ausstehend)."
                            L "  Kein echter Fehler: bitte den PC neu starten - Defender aktualisiert sich danach selbst."
                            Mark "Defender" "warn" "Kein echter Fehler: RPC fehlgeschlagen / Neustart ausstehend. Bitte den PC neu starten - Defender aktualisiert sich danach selbst."
                        } else {
                            L "  [FEHLER] $defErr"
                            Mark "Defender" "err" $defErr
                        }
                    }
                }
            }
            Finish-Module
            $i++; P ($i / $total * 100)
            L ""
        }

