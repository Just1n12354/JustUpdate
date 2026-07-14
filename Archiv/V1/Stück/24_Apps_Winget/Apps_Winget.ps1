        # ── WINGET ──
        if ($cfg.Winget) {
            if (IsStopped) { $sync.Done = $true; return }
            M "Winget" "run"
            L "--------------------------------------------"
            L "  MODUL $($i+1)/${total}: Apps aktualisieren (Winget)"
            L "--------------------------------------------"
            try {
                $wg = (Get-Command winget.exe -ErrorAction SilentlyContinue).Source
                if (-not $wg) {
                    # Elevierter Admin-Prozess hat oft NICHT den WindowsApps-PATH des
                    # angemeldeten Users -> Get-Command findet winget nicht, obwohl
                    # installiert. Haeufigster Kunden-Fehlalarm "Winget nicht
                    # installiert". Robust ueber bekannte Speicherorte aufloesen:
                    $wgCand = @()
                    # 1. Echtes Paket unter Program Files\WindowsApps (fuer Admin lesbar,
                    #    zuverlaessigster Pfad im elevierten Kontext - kein Recurse).
                    try {
                        $pkgDir = Get-ChildItem "$env:ProgramFiles\WindowsApps" -Directory -ErrorAction SilentlyContinue |
                                  Where-Object { $_.Name -like 'Microsoft.DesktopAppInstaller_*_8wekyb3d8bbwe' } |
                                  Sort-Object Name -Descending | Select-Object -First 1
                        if ($pkgDir) { $wgCand += (Join-Path $pkgDir.FullName 'winget.exe') }
                    } catch {}
                    # 2. WindowsApps-Alias des aktuellen + aller realen Benutzerprofile
                    #    (eleviert != angemeldeter User -> alle Profile pruefen).
                    $wgCand += "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"
                    try {
                        $wgCand += Get-ChildItem "$env:SystemDrive\Users" -Directory -ErrorAction SilentlyContinue |
                                   ForEach-Object { Join-Path $_.FullName 'AppData\Local\Microsoft\WindowsApps\winget.exe' }
                    } catch {}
                    $wg = $wgCand | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
                    if ($wg) { L "  Winget ueber Fallback-Pfad aufgeloest (PATH unvollstaendig im Admin-Kontext)" }
                }
                if ($wg) {
                    L "  Winget gefunden: $wg"

                    # Quellen-Index aktualisieren - sonst arbeitet winget u.U. mit
                    # einem Tage alten Paket-Index und uebersieht frische Updates.
                    # Kurzes Timeout, Fehler unkritisch (dann gilt der alte Index).
                    L "  Aktualisiere Winget-Quellen..."
                    # winget emittiert UTF-8; ohne Override dekodiert .NET mit der
                    # OEM-Codepage und Umlaute in Paketnamen werden zu Gibberish.
                    $utf8Enc = [System.Text.UTF8Encoding]::new($false)
                    $null = Invoke-MonitoredProcess -FileName $wg `
                              -Arguments "source update --disable-interactivity" -TimeoutSec 120 `
                              -OutEncoding $utf8Enc

                    # Bug-Fix v2.7.5: frueher lief hier erst ein separates `winget upgrade`
                    # nur zum Anzeigen und danach `winget upgrade --all` - das die Liste vor
                    # der Installation selbst noch einmal ausgibt. Ergebnis: identische Tabelle
                    # zweimal im Log + ein ueberfluessiger Netzwerkaufruf. Das Listing von
                    # `upgrade --all` reicht, also nur noch dieser eine Lauf.
                    L "  Starte Upgrade aller Apps (winget listet die betroffenen Apps selbst auf)..."
                    L ""

                    # Erfolgs-Erkennung. NEBEN dem klaren "Erfolgreich installiert" gibt
                    # es Pakete (z.B. Claude, Microsoft Teams, Edge-basierte Apps), die
                    # melden "Die Installation war erfolgreich. Starten Sie die Anwendung
                    # neu, um das Upgrade abzuschliessen." - das ist KEIN Fehler, sondern
                    # ein erfolgreicher Update der nur noch einen App-Neustart braucht.
                    # Frueher fiel dieser Satz durch alle Parser-Branches, das Paket blieb
                    # in $cur haengen und wurde beim naechsten "(N/M) Gefunden" faelschlich
                    # als fehlgeschlagen verbucht. Beide Phrasen zaehlen jetzt als Erfolg.
                    # v2.7.6: FR-Literale mit .-Wildcard statt Akzent (die Datei-
                    # Patterns "reussie"/"Redemarrez" matchten das echte "réussie"/
                    # "Rédemarrez" NIE - FR-Systeme meldeten faelschlich "ok" ohne
                    # ein einziges erkanntes Paket). Neu ausserdem: die MSI-3010-
                    # Meldung "Restart your PC to finish installation" - winget
                    # druckt bei ERROR_SUCCESS_REBOOT_REQUIRED NUR diese Zeile
                    # (kein "Successfully installed"!), sie fiel durch alle
                    # Branches und Erfolge zaehlten als Fehlschlag (5. Instanz
                    # dieser Bug-Klasse; betraf z.B. Zoom/Poly Lens).
                    $okRx = 'Successfully installed|Erfolgreich installiert|Installation r.ussie|Die Installation war erfolgreich|installation was successful|Restart the application to complete|Starten Sie die Anwendung neu|Red.marrez l.application|Restart your PC to finish|Starten Sie (Ihren|den) PC neu|Red.marrez (votre|le) PC'
                    # Untermenge von $okRx: erfolgreich, aber App-Neustart noch offen.
                    $restartRx = 'Restart the application to complete|Starten Sie die Anwendung neu|Red.marrez l.application'
                    # Untermenge von $okRx: erfolgreich, aber PC-NEUSTART noetig (MSI 3010).
                    $pcRebootRx = 'Restart your PC to finish|Starten Sie (Ihren|den) PC neu|Red.marrez (votre|le) PC'

                    # Inline-Parser: Output-Stream auswerten und pro Paket Status sammeln.
                    # Wichtig fuer in-use-Retry: wir muessen wissen WELCHE Apps wegen
                    # "Datei in Verwendung" gescheitert sind (Exit 1603/6 oder Klartext).
                    $parseWg = {
                        param([string[]]$Lines)
                        $fail = @(); $ok = @(); $cur = $null
                        # v2.7.6: "remove_all: Zugriff verweigert" beim Upgrade portabler
                        # Pakete (z.B. Rclone laeuft gerade als Mount/Daemon) bedeutet:
                        # die ALTE Version ist von einem laufenden Prozess gelockt ->
                        # wie in-use behandeln, damit der Retry-Pass (Prozess-Kill +
                        # erneuter Versuch) eine Chance bekommt statt sofort aufzugeben.
                        # v2.7.6: die REALEN EN-Meldungen aus winget.resw ergaenzt
                        # ("are being used", "is currently running", "currently in
                        # use") - die alten EN-Alternativen matchten keine davon,
                        # auf EN-Windows hing der Retry allein an der Exit-Code-
                        # Liste. DE-Ergaenzung: "Dateien werden verwendet" (FileInUse).
                        $inUseRx = 'einer anderen Anwendung verwendet|in use by another|currently being used|being used by another|are being used|is currently running|currently in use|Dateien werden verwendet|^remove_all:.*(Zugriff verweigert|Access is denied|Acc.s refus)'
                        foreach ($raw in $Lines) {
                            $t = "$raw".Trim()
                            if ($t -match '^\(\d+/\d+\)\s+(?:Gefunden|Found|Trouv.)\s+(.+?)\s+\[([^\]]+)\]') {
                                if ($cur) { $fail += $cur }
                                $cur = @{ Name = $Matches[1].Trim(); Id = $Matches[2].Trim(); Exit = $null; InUse = $false; Restart = $false; PcReboot = $false }
                            }
                            elseif ($t -match $inUseRx) {
                                if ($cur) { $cur.InUse = $true }
                            }
                            elseif ($t -match '(?:Installation fehlgeschlagen mit Exitcode|Installer failed with exit code|Installation echouee avec le code de sortie)\D*?(0x[0-9a-fA-F]+|-?\d+)') {
                                if ($cur) {
                                    # v2.7.6: winget druckt manche Exit-Codes HEX ("0x8a150003").
                                    # Der alte \D*(-?\d+)-Capture fischte daraus nur die
                                    # fuehrende "0" - der echte Code ging verloren. Hex
                                    # erkennen und sauber nach Int32 (signed) wandeln.
                                    $exRaw = $Matches[1]
                                    if ($exRaw -match '^0x') {
                                        $exVal = [Convert]::ToInt64($exRaw.Substring(2), 16)
                                        if ($exVal -gt 2147483647) { $exVal -= 4294967296 }
                                        $cur.Exit = [int]$exVal
                                    } else {
                                        $cur.Exit = [int]$exRaw
                                    }
                                    # v2.7.6: 1638 RAUS aus der in-use-Liste. MSI 1638 =
                                    # "andere Version bereits installiert" - kein Datei-
                                    # Lock, ein Retry kann NIE gelingen. Vorher: sinnlose
                                    # Prozess-/Service-Kills + garantiert erneut 1638.
                                    if ($cur.Exit -in 1603,6,1618) { $cur.InUse = $true }
                                    $fail += $cur; $cur = $null
                                }
                            }
                            elseif ($t -match 'kein anwendbares Upgrade|No applicable upgrade|No applicable update|Aucune mise . niveau applicable') {
                                # Installierte Version ist neuer als das winget-Manifest
                                # (haeufig bei Apps mit eigenem Auto-Updater wie Edge/Teams).
                                # Weder Erfolg noch Fehler - Paket unveraendert, KEIN Fail.
                                # Vorher fiel das durch alle Branches und wurde beim naechsten
                                # "(N/M) Gefunden" faelschlich als fehlgeschlagen verbucht.
                                if ($cur) { $cur = $null }
                            }
                            elseif ($t -match $okRx) {
                                if ($cur) {
                                    if ($t -match $restartRx) { $cur.Restart = $true }
                                    if ($t -match $pcRebootRx) { $cur.PcReboot = $true }
                                    $ok += $cur; $cur = $null
                                }
                            }
                        }
                        if ($cur) { $fail += $cur }
                        return [pscustomobject]@{ Failed = $fail; Installed = $ok }
                    }

                    # 1. Hauptlauf
                    # 60-Min-Timeout: ein haengender Installer darf die Wartung nicht
                    # endlos blockieren.
                    $wgRun = Invoke-MonitoredProcess -FileName $wg `
                               -Arguments "upgrade --all --include-unknown --disable-interactivity --accept-source-agreements --accept-package-agreements" `
                               -TimeoutSec 3600 -OutEncoding $utf8Enc
                    $wgUpgradeOutput = $wgRun.Lines
                    $wgTimedOut = $wgRun.TimedOut
                    $exitCode   = $wgRun.ExitCode
                    $combined = ($wgUpgradeOutput -join " ")
                    $nothingToDo = $combined -match 'kein installiertes Paket|No installed package|Aucun package install'
                    $parsed = & $parseWg $wgUpgradeOutput
                    $installedAny = ($parsed.Installed.Count -gt 0) -or ($combined -match $okRx)
                    $inUseFails = @($parsed.Failed | Where-Object { $_.InUse })

                    # 2. Retry-Pass NUR fuer in-use-Failures (1603/6/Klartext). Hartes
                    #    Stop-Process auf Tray-Reste, dann gezielt diese Pakete nochmal.
                    #    Behebt den Fall aus v2.6.4: OBS/Epic-Helper bleiben im Tray,
                    #    erster Lauf scheitert, zweiter Lauf nach Force-Kill geht durch.
                    $retryInstalled = @()
                    $retryStillFailed = @()
                    if (-not $wgTimedOut -and $inUseFails.Count -gt 0) {
                        L ""
                        L "  [HINWEIS] $($inUseFails.Count) App(s) wegen 'Datei in Verwendung' fehlgeschlagen:"
                        foreach ($f in $inUseFails) { L "    - $($f.Name)" }
                        L "  Beende Tray/Helper-Prozesse und versuche es nochmal..."
                        # Inline-Tray-Kill — wir sind im Worker-Runspace, die globale
                        # Close-RunningUserApps ist hier nicht sichtbar. Wildcards
                        # via -like (z.B. 'obs*' fuer alle OBS-Helper). Liste kommt
                        # aus $script:TrayBlockers (via $sync) - EINE Quelle.
                        $retryBlockers = @($sync.TrayBlockers)
                        $retryKilled = New-Object System.Collections.Generic.List[string]
                        Get-Process -ErrorAction SilentlyContinue | Where-Object {
                            $pn = $_.ProcessName
                            (@($retryBlockers | Where-Object { $pn -like $_ }).Count -gt 0)
                        } | ForEach-Object {
                            try {
                                Stop-Process -Id $_.Id -Force -ErrorAction Stop
                                [void]$retryKilled.Add($_.ProcessName)
                            } catch {}
                        }
                        # v2.7.6: Sichtbar machen WAS beendet wurde - vorher war im Log
                        # nicht nachvollziehbar, ob der Kill-Pass ueberhaupt was traf.
                        if ($retryKilled.Count -gt 0) {
                            L "    Beendet: $(@($retryKilled | Sort-Object -Unique) -join ', ')"
                        } else {
                            L "    (kein bekannter Tray/Helper-Prozess lief)"
                        }

                        # AGGRESSIVER 2. PASS: pro fehlgeschlagenes Paket auch
                        # alle Prozesse killen, deren EXE-Pfad zum Paket-Namen
                        # passt. Behebt den Fall aus dem User-Log: OBS-Studio
                        # hatte Helper laufen, die NICHT mit "obs" beginnen
                        # (Auto-Update-Service, Streamlabs-Plugin, etc.) - die
                        # tauchten nicht in der Wildcard-Liste auf, blockierten
                        # den Installer aber trotzdem.
                        # Generische Woerter, die in Paket-Namen/IDs stecken, aber als
                        # Kill-Keyword viel zu breit treffen wuerden. Beispiel aus der
                        # Praxis: "Microsoft Edge" -> Keyword "Microsoft" haette JEDEN
                        # Prozess unter "C:\Program Files\Microsoft ..." gekillt (Word
                        # mit ungespeichertem Dokument!) und Services wie den Defender
                        # ("Microsoft Defender Antivirus Service") gestoppt.
                        $kwStop = @(
                            'Microsoft','Windows','Corporation','Software','Update','Updater',
                            'Install','Installer','Installation','Application','Applications',
                            'Program','Programs','Files','System','Service','Services','Version',
                            'x64','x86','win32','win64','amd64','arm64','the','and','fuer','for','GmbH','Inc','LLC','Ltd'
                        )
                        foreach ($pkg in $inUseFails) {
                            # Paket-Schluesselwort raus: "OBSProject.OBSStudio"
                            # -> Suchbegriffe "OBSStudio", "OBSProject", "OBS"
                            $kw = @()
                            if ($pkg.Name) { $kw += ($pkg.Name -split '\W+' | Where-Object { $_.Length -ge 3 }) }
                            if ($pkg.Id)   { $kw += ($pkg.Id   -split '[\W_]+' | Where-Object { $_.Length -ge 3 }) }
                            $kw = @($kw | Where-Object { $kwStop -notcontains $_ } | Sort-Object -Unique)
                            $killed = New-Object System.Collections.Generic.List[string]
                            $winRoot = [regex]::Escape($env:windir)
                            foreach ($p in Get-Process -ErrorAction SilentlyContinue) {
                                try {
                                    # Nie: uns selbst oder irgendwas unter C:\Windows
                                    # (System-Prozesse, PowerShell-Host, svchost & Co).
                                    if ($p.Id -eq $PID) { continue }
                                    $path = $p.Path
                                    if (-not $path) { continue }
                                    if ($path -match "^$winRoot\\") { continue }
                                    foreach ($k in $kw) {
                                        if ($path -match [regex]::Escape($k)) {
                                            try {
                                                Stop-Process -Id $p.Id -Force -ErrorAction Stop
                                                [void]$killed.Add("$($p.ProcessName) (Pfad: $path)")
                                            } catch {}
                                            break
                                        }
                                    }
                                } catch {}
                            }
                            # Windows-Services mit passendem NAMEN stoppen — OBS-
                            # Studio installiert keinen Service standardmaessig,
                            # aber Plugins/Updater-Tools tun es manchmal.
                            # Bewusst NUR der technische Service-Name, NICHT der
                            # DisplayName: DisplayNames sind Marketing-Text und
                            # matchen viel zu breit (s. Defender-Beispiel oben).
                            foreach ($k in $kw) {
                                try {
                                    Get-Service -ErrorAction SilentlyContinue |
                                        Where-Object { $_.Name -like "*$k*" } |
                                        ForEach-Object {
                                            try {
                                                if ($_.Status -eq 'Running') {
                                                    Stop-Service -Name $_.Name -Force -ErrorAction Stop
                                                    [void]$killed.Add("Service: $($_.Name)")
                                                }
                                            } catch {}
                                        }
                                } catch {}
                            }
                            if ($killed.Count -gt 0) {
                                L "  Zusaetzlich beendet fuer $($pkg.Name):"
                                foreach ($k in $killed) { L "    - $k" }
                            }
                        }
                        Start-Sleep -Seconds 3
                        foreach ($pkg in $inUseFails) {
                            if (IsStopped) { break }
                            L ""
                            L "  Retry: $($pkg.Name) [$($pkg.Id)]"
                            $r = Invoke-MonitoredProcess -FileName $wg `
                                   -Arguments "upgrade --id `"$($pkg.Id)`" --exact --disable-interactivity --accept-source-agreements --accept-package-agreements" `
                                   -TimeoutSec 1800 -OutEncoding $utf8Enc
                            $rOut = $r.Lines -join " "
                            if ($r.ExitCode -eq 0 -and ($rOut -match $okRx)) {
                                L "    [OK] $($pkg.Name) im Retry aktualisiert"
                                if ($rOut -match $pcRebootRx) { $sync.RebootRequired = $true }
                                $retryInstalled += $pkg
                            } else {
                                L "    [WARNUNG] $($pkg.Name) auch im Retry fehlgeschlagen (Exit $($r.ExitCode))"
                                $retryStillFailed += $pkg
                            }
                        }
                    }

                    # Endstatus berechnen
                    $totalInstalled = $parsed.Installed.Count + $retryInstalled.Count
                    # Failures = alle Fails OHNE die, die im Retry doch noch durchkamen
                    $finalFails = @($parsed.Failed | Where-Object {
                        $id = $_.Id
                        -not ($retryInstalled | Where-Object { $_.Id -eq $id })
                    })
                    # Erfolgreich aktualisiert, aber App-Neustart noch offen (kein Fehler).
                    $restartNeeded = @($parsed.Installed | Where-Object { $_.Restart })

                    L ""
                    if ($restartNeeded.Count -gt 0) {
                        $rsNames = ($restartNeeded | ForEach-Object { $_.Name }) -join ", "
                        L "  [HINWEIS] $($restartNeeded.Count) App(s) aktualisiert - Neustart der App schliesst das Upgrade ab: $rsNames"
                    }
                    # v2.7.6: MSI-3010-Updates (erfolgreich, PC-Neustart noetig) melden
                    # + RebootRequired setzen, damit die Neustart-Frage am Ende kommt.
                    $pcRebootApps = @($parsed.Installed | Where-Object { $_.PcReboot })
                    if ($pcRebootApps.Count -gt 0) {
                        $sync.RebootRequired = $true
                        L "  [HINWEIS] $($pcRebootApps.Count) App(s) aktualisiert - PC-NEUSTART schliesst das Upgrade ab: $(($pcRebootApps | ForEach-Object { $_.Name }) -join ', ')"
                    }
                    # v2.7.6: winget ueberspringt Pakete, deren neue Version eine andere
                    # Installationstechnologie nutzt (z.B. TeamSpeak 5 -> 6). Vorher
                    # stand das nur versteckt im Roh-Output - der User sah "7 verfuegbar,
                    # 2 OK, 2 Fehler" und wunderte sich ueber den Rest.
                    if ($combined -match 'andere Installationstechnologie|different installer technology|technologie d.installation') {
                        L "  [HINWEIS] Mindestens 1 App uebersprungen: neue Version nutzt eine andere"
                        L "            Installationstechnologie - bitte einmal manuell deinstallieren und neu installieren."
                    }
                    if ($wgTimedOut) {
                        L "  [WARNUNG] App-Updates nach 60 Min ohne Reaktion abgebrochen"
                        Mark "Winget" "warn" "Nach 60 Min abgebrochen - eine App hat zu lange gebraucht. Die uebrigen Apps wurden aktualisiert; bitte JustUpdate spaeter erneut ausfuehren."
                    } elseif ($nothingToDo -and -not $installedAny -and $finalFails.Count -eq 0) {
                        L "  [OK] Keine App-Updates verfuegbar - alle Apps aktuell"
                        Mark "Winget" "ok" "keine Updates verfuegbar"
                    } elseif ($finalFails.Count -eq 0 -and ($exitCode -eq 0 -or $exitCode -eq -1978335189 -or $totalInstalled -gt 0)) {
                        if ($totalInstalled -gt 0) {
                            L "  [OK] $totalInstalled App(s) erfolgreich aktualisiert"
                            Mark "Winget" "ok" "$totalInstalled App(s) aktualisiert"
                        } else {
                            L "  [OK] Winget-Lauf abgeschlossen"
                            Mark "Winget" "ok" "Lauf abgeschlossen"
                        }
                    } else {
                        $failNames = ($finalFails | ForEach-Object { $_.Name }) -join ", "
                        if ($totalInstalled -gt 0) {
                            L "  [WARNUNG] Teilweise aktualisiert: $totalInstalled OK, $($finalFails.Count) fehlgeschlagen"
                            L "  Fehlgeschlagen: $failNames"
                            Mark "Winget" "warn" "Teilweise aktualisiert ($totalInstalled OK) - noch offen: $failNames"
                        } else {
                            L "  [WARNUNG] Keine App aktualisiert - $($finalFails.Count) fehlgeschlagen"
                            L "  Fehlgeschlagen: $failNames"
                            Mark "Winget" "warn" "Nicht aktualisiert: $failNames (Exit-Code $exitCode)"
                        }
                    }
                } else {
                    L "  [WARNUNG] Winget ist nicht installiert"
                    L "  Installiere Winget ueber: Microsoft Store > 'App Installer'"
                    Mark "Winget" "err" "Winget nicht installiert"
                }
            } catch {
                L "  [FEHLER] $($_.Exception.Message)"
                Mark "Winget" "err" $_.Exception.Message
            }
            Finish-Module
            $i++; P ($i / $total * 100)
            L ""
        }

