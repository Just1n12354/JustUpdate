        $cfg = $sync.Config
        $logFile = $sync.LogPath
        try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
        # OEM-Codepage fuer Legacy-Tools (DISM, ipconfig). winget/netsh/sfc bleiben UTF-8/UTF-16
        # und bekommen pro Aufruf ihre eigene Encoding-Override. Ohne $oemEnc dekodiert
        # PowerShell DISM-Bytes als UTF-8 -> Umlaute werden zu U+FFFD ("f�r", "Tempor�re").
        $oemEnc = try { [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage) } catch { [System.Text.Encoding]::GetEncoding(850) }

        # Filtert hochfrequente Fortschrittszeilen aus SFC/DISM/winget Output. Behaelt nur
        # 100%-Endzeile von Progress-Bars und nicht-Block-Inhaltszeilen.
        function IsProgressNoise([string]$line) {
            if ($null -eq $line) { return $true }
            $t = $line.Trim()
            if ($t.Length -lt 1) { return $true }
            # SFC: "Überprüfung 5 % abgeschlossen." - nur 100% behalten.
            # Codepoint-Syntax fuer Umlaute weil PS5.1 die Datei sonst als ANSI liest und das Pattern nicht matcht.
            $uUml = [char]0x00DC  # Ü
            $lUml = [char]0x00FC  # ü
            if ($t -match "^(${uUml}berpr${lUml}fung|Verification|Verifikation)\s+(\d{1,3})\s*%\s*(abgeschlossen|complete|terminee)\.?\s*$") {
                return ($Matches[2] -ne '100')
            }
            # DISM Fortschrittsbalken: "[==     3.8%     ]" - nur 100% behalten
            if ($t -match '^\[=*\s*(\d{1,3}(?:\.\d+)?)%\s*=*\s*\]$') {
                return ([double]$Matches[1] -lt 100)
            }
            # winget Block-Progress: Block-Elements U+2580..U+259F gefolgt von % oder Byte-Counter.
            # Codepoint-Range statt Literal-Zeichen verwenden, damit das Script in jeder Encoding lesbar bleibt.
            if ($t -match "^[$([char]0x2580)-$([char]0x259F)\s]+(\d+\s*%|\d+(\.\d+)?\s*(KB|MB|GB|B)\s*/\s*\d+(\.\d+)?\s*(KB|MB|GB|B))\s*$") {
                return $true
            }
            return $false
        }

        function L($m) {
            $line = "[$(Get-Date -F 'HH:mm:ss')] $m"
            try { $line | Out-File $logFile -Append -Encoding utf8 } catch {}
            $sync.Lines.Add($line) | Out-Null
        }
        function P($v) { $sync.Progress = [Math]::Min(100, [int]$v) }
        # Queue statt Single-Slot - sonst gehen schnelle Statuswechsel verloren wenn ein
        # Modul kuerzer als ein UI-Tick (150ms) braucht (z.B. Restore wenn schnell, Defender
        # wenn schon up-to-date). Vorher: $sync.Module = "id|state" wurde vom naechsten Modul
        # ueberschrieben bevor der UI-Timer "ok" -> Gruen anzeigen konnte.
        function M($id,$s) {
            # "run" merkt sich Modul + Startzeit -> Finish-Module kann am Ende
            # die Dauer loggen und in die Results haengen (Fleet-Report).
            if ($s -eq "run") { $script:CurModule = $id; $script:CurModuleT0 = Get-Date }
            [void]$sync.ModuleQueue.Add("$id|$s")
        }
        function IsStopped { $sync.Stop -eq $true }
        # Mark result: status = ok|warn|err, details = free-text summary
        # UI: ok -> Gruen, warn -> Orange ("!"), err -> Rot+X
        function Mark($id, $status, $details) {
            $sync.Results[$id] = @{ Status = $status; Details = $details }
            $uiState = switch ($status) { "ok" { "ok" } "warn" { "warn" } default { "err" } }
            M $id $uiState
        }
        # Modul-Dauer ins Log + in die Results (landet im result_*.json).
        # Beantwortet die Support-Frage "WO hing die Wartung so lange?".
        function Finish-Module {
            if (-not $script:CurModule -or -not $script:CurModuleT0) { return }
            $secs = [int]((Get-Date) - $script:CurModuleT0).TotalSeconds
            $m2 = [int][Math]::Floor($secs / 60); $s2 = $secs % 60
            $dTxt = if ($m2 -gt 0) { "${m2}m ${s2}s" } else { "${s2}s" }
            L "  (Modul-Dauer: $dTxt)"
            try {
                if ($sync.Results.ContainsKey($script:CurModule)) {
                    $sync.Results[$script:CurModule].DurationSeconds = $secs
                }
            } catch {}
            $script:CurModule = $null
        }

        # =====================================================================
        # TREIBER-BLACKLIST (Bug-Fix v2.7.5): chronisch fehlschlagende Treiber
        # Manche Microsoft-Update-Katalog-Eintraege (klassisch: der superseded
        # HP-USB-Treiber von 2018) bietet Windows Update dem PC endlos an, obwohl
        # der In-Box-Treiber neuer und aktiv ist. WUA meldet Install=OK, ein
        # Re-Scan findet ihn aber weiter offen -> der Lauf ist strukturell IMMER
        # "error", egal wie sauber die anderen Module laufen. Nach
        # $DrvBlacklistThreshold Fehlschlaegen desselben Treibers (per UpdateID)
        # blenden wir ihn aus der Suche aus, damit der Overall-Status wieder
        # ehrlich wird. Der User behaelt die Info im Log ("... ignoriert").
        # Erfolgreich installierte Treiber loeschen ihren Zaehler wieder.
        # Datei: %APPDATA%\JustUpdate\driver_blacklist.json
        # =====================================================================
        $script:DrvBlacklistThreshold = 3
        $script:DrvBlacklistPath = Join-Path $env:APPDATA "JustUpdate\driver_blacklist.json"
        function Load-DriverBlacklist {
            $bl = @{}
            try {
                if (Test-Path $script:DrvBlacklistPath) {
                    $raw = Get-Content $script:DrvBlacklistPath -Raw -ErrorAction Stop | ConvertFrom-Json
                    foreach ($p in $raw.PSObject.Properties) {
                        $bl[$p.Name] = @{
                            Title       = [string]$p.Value.Title
                            FailCount   = [int]$p.Value.FailCount
                            LastAttempt = [string]$p.Value.LastAttempt
                        }
                    }
                }
            } catch {}
            return $bl
        }
        function Save-DriverBlacklist($bl) {
            try {
                $dir = Split-Path -Parent $script:DrvBlacklistPath
                if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null }
                $obj = [pscustomobject]@{}
                foreach ($k in $bl.Keys) {
                    $obj | Add-Member -NotePropertyName $k -NotePropertyValue ([pscustomobject]$bl[$k])
                }
                # v2.7.6: atomar schreiben (temp + rename) - ein Absturz mitten im
                # Write hinterliess sonst korruptes JSON und ALLE Zaehler waren weg.
                $tmp = "$($script:DrvBlacklistPath).tmp"
                [IO.File]::WriteAllText($tmp, ($obj | ConvertTo-Json -Depth 5),
                    (New-Object System.Text.UTF8Encoding($false)))
                Move-Item -Path $tmp -Destination $script:DrvBlacklistPath -Force
            } catch {}
        }

        # Heartbeat-Runspace fuer blockierende WUA-Calls (Download/Install). Die WUA-COM-APIs
        # IUpdateDownloader.Download() und IUpdateInstaller.Install() sind synchron und geben
        # keinen Fortschritt zurueck. Ohne Heartbeat sieht der User minutenlang nichts und denkt
        # die App haengt. Loesung: paralleler Runspace logt alle 30s "...laeuft seit Xm Ys..."
        # via $sync.Lines (synchronized) - der UI-Timer rendert das auf dem Live-Log.
        function Start-Heartbeat([string]$prefix, [int]$intervalSec = 30) {
            $hbRs = [runspacefactory]::CreateRunspace()
            $hbRs.ApartmentState = 'STA'
            $hbRs.Open()
            $hbRs.SessionStateProxy.SetVariable('sync', $sync)
            $hbRs.SessionStateProxy.SetVariable('hbPrefix', $prefix)
            $hbRs.SessionStateProxy.SetVariable('hbInterval', $intervalSec)
            $hbRs.SessionStateProxy.SetVariable('hbLogFile', $logFile)
            $hbPs = [powershell]::Create()
            $hbPs.Runspace = $hbRs
            [void]$hbPs.AddScript({
                $started = Get-Date
                while ($true) {
                    Start-Sleep -Seconds $hbInterval
                    if ($sync.Stop -eq $true) { break }
                    $elapsed = [int]((Get-Date) - $started).TotalSeconds
                    $min = [int][Math]::Floor($elapsed / 60); $sec = $elapsed % 60
                    $timeStr = if ($min -gt 0) { "${min}m ${sec}s" } else { "${sec}s" }
                    $line = "[$(Get-Date -F 'HH:mm:ss')] ${hbPrefix}laeuft seit $timeStr - bitte warten..."
                    try { $line | Out-File $hbLogFile -Append -Encoding utf8 } catch {}
                    $sync.Lines.Add($line) | Out-Null
                }
            })
            $handle = $hbPs.BeginInvoke()
            return @{ Ps = $hbPs; Handle = $handle; Rs = $hbRs }
        }
        function Stop-Heartbeat($hb) {
            if ($null -eq $hb) { return }
            if ($hb.Ps) {
                try { $hb.Ps.Stop() } catch {}
                try { $hb.Ps.Dispose() } catch {}
            }
            if ($hb.Rs) { try { $hb.Rs.Close() } catch {} }
        }

        # Startet ein externes Tool (sfc/dism/winget), streamt dessen Ausgabe live ins
        # Log UND ueberwacht die Laufzeit. Reagiert das Tool laenger als $TimeoutSec
        # nicht (klassischer DISM-/Download-Hang), wird der Prozessbaum hart beendet
        # und die Wartung laeuft mit dem naechsten Modul weiter, statt ewig zu haengen.
        #
        # Bewusst KEIN .NET-Event-Delegate (add_OutputDataReceived) - PS5.1 stuerzt in
        # Runspaces damit kommentarlos ab (Exit 2). Stattdessen die synchrone Original-
        # Leseschleife + ein separater Watchdog-Runspace (gleiches bewaehrtes Muster
        # wie Start-Heartbeat): der killt den Prozess nach Timeout, dadurch endet der
        # StandardOutput-Stream und die Leseschleife laeuft von selbst aus.
        function Invoke-MonitoredProcess {
            param(
                [string]$FileName,
                [string]$Arguments,
                [int]$TimeoutSec,
                [System.Text.Encoding]$OutEncoding = $null,
                [string]$Indent = "    "
            )
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName               = $FileName
            $psi.Arguments              = $Arguments
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError  = $true
            $psi.UseShellExecute        = $false
            $psi.CreateNoWindow         = $true
            if ($OutEncoding) {
                $psi.StandardOutputEncoding = $OutEncoding
                $psi.StandardErrorEncoding  = $OutEncoding
            }
            $proc = [System.Diagnostics.Process]::Start($psi)

            $wd = [hashtable]::Synchronized(@{ Killed = $false })
            $wdRs = [runspacefactory]::CreateRunspace()
            $wdRs.ApartmentState = 'STA'; $wdRs.Open()
            $wdRs.SessionStateProxy.SetVariable('sync', $sync)
            $wdRs.SessionStateProxy.SetVariable('wd', $wd)
            $wdRs.SessionStateProxy.SetVariable('wdPid', $proc.Id)
            $wdRs.SessionStateProxy.SetVariable('wdTimeout', $TimeoutSec)
            $wdPs = [powershell]::Create(); $wdPs.Runspace = $wdRs
            [void]$wdPs.AddScript({
                $waited = 0
                $userStop = $false
                while ($waited -lt $wdTimeout) {
                    Start-Sleep -Seconds 1
                    $waited++
                    if (-not (Get-Process -Id $wdPid -ErrorAction SilentlyContinue)) { return }
                    if ($sync.Stop -eq $true) { $userStop = $true; break }
                }
                # Prozessbaum hart beenden — bei echtem Timeout ODER User-Stop (sonst
                # laeuft der Installer verwaist weiter). ABER nur ein echter Timeout
                # wird als Killed/TimedOut markiert. Ein User-Stop darf NICHT als
                # "nach X Min abgebrochen" gemeldet werden, sonst zeigen Winget/SFC/
                # DISM faelschlich eine Timeout-Warnung obwohl der User selbst stoppte.
                if (-not $userStop) { $wd.Killed = $true }
                try { Start-Process taskkill.exe -ArgumentList "/PID $wdPid /T /F" -WindowStyle Hidden -Wait -ErrorAction Stop } catch {}
            })
            $wdHandle = $wdPs.BeginInvoke()

            # stderr PARALLEL in einem eigenen Runspace leeren, BEVOR wir synchron
            # stdout lesen. Sonst Deadlock-Risiko: fuellt das Tool (DISM/winget) den
            # stderr-Puffer (~4 KB) WAEHREND es weiter auf stdout schreibt, blockiert
            # der Kindprozess am stderr-Write und wir am stdout-ReadLine - bis der
            # Watchdog nach Timeout killt (und es faelschlich als Timeout zaehlt).
            # Gleiches bewaehrtes Runspace-Muster wie der Watchdog (kein .NET-Event-
            # Delegate add_ErrorDataReceived - das stuerzt PS5.1 in Runspaces ab).
            $errBuf = [hashtable]::Synchronized(@{ Text = "" })
            $erRs = [runspacefactory]::CreateRunspace()
            $erRs.ApartmentState = 'STA'; $erRs.Open()
            $erRs.SessionStateProxy.SetVariable('proc', $proc)
            $erRs.SessionStateProxy.SetVariable('errBuf', $errBuf)
            $erPs = [powershell]::Create(); $erPs.Runspace = $erRs
            [void]$erPs.AddScript({ try { $errBuf.Text = $proc.StandardError.ReadToEnd() } catch {} })
            $erHandle = $erPs.BeginInvoke()

            $allLines = New-Object System.Collections.Generic.List[string]
            try {
                while (-not $proc.StandardOutput.EndOfStream) {
                    $l = $proc.StandardOutput.ReadLine()
                    if ($l -and $l.Trim().Length -gt 0) {
                        $allLines.Add($l.Trim())
                        if ($l.Trim().Length -gt 3 -and -not (IsProgressNoise $l)) { L "$Indent$($l.Trim())" }
                    }
                }
            } catch {}
            # stderr-Reader einsammeln (spaetestens mit Prozess-Ende fertig) + aufraeumen
            try { [void]$erPs.EndInvoke($erHandle) } catch {}
            $errOut = $errBuf.Text
            try { $erPs.Dispose() } catch {}
            try { $erRs.Close() } catch {}
            try { $proc.WaitForExit() } catch {}
            if ($errOut -and $errOut.Trim().Length -gt 0) {
                $errOut.Split("`n") | ForEach-Object {
                    $t = $_.Trim()
                    if ($t.Length -gt 0) { $allLines.Add($t); if ($t.Length -gt 3 -and -not (IsProgressNoise $t)) { L "$Indent$t" } }
                }
            }
            $timedOut = ($wd.Killed -eq $true)
            $exit = if ($timedOut) { -999 } else { try { $proc.ExitCode } catch { -1 } }
            try { $wdPs.Stop() } catch {}
            try { $wdPs.Dispose() } catch {}
            try { $wdRs.Close() } catch {}
            try { $proc.Dispose() } catch {}
            return [pscustomobject]@{ ExitCode = $exit; TimedOut = $timedOut; Lines = $allLines }
        }

        $moduleOrder = @("Restore","Defender","WinUpdate","Drivers","Winget","Store","Repair","Network","Cleanup")
        $active = $moduleOrder | Where-Object { $cfg[$_] }
        $total = @($active).Count
        if ($total -eq 0) { L "Keine Module ausgewaehlt."; P 100; $sync.Done = $true; return }
        $i = 0

        L ""
        L "============================================"
        L "  SYSTEM WARTUNG PRO - Sitzung gestartet"
        L "  Version:  v$($sync.AppVersion)"
        L "  Host:     $env:COMPUTERNAME ($env:USERNAME)"
        L "  Zeit:     $(Get-Date -F 'dd.MM.yyyy HH:mm:ss')"
        L "  Module:   $total ausgewaehlt"
        L "============================================"
        L ""
        if ($null -ne $sync.ClosedAppCount) {
            if ($sync.ClosedAppCount -ge 0) {
                $names = @($sync.ClosedAppNames)
                if ($sync.ClosedAppCount -eq 0) {
                    L "  Vor-Update-Schritt: keine laufenden Programme zum Schliessen gefunden"
                } else {
                    L "  Vor-Update-Schritt: $($sync.ClosedAppCount) Programm(e) geschlossen"
                    if ($names.Count -gt 0) {
                        L "    -> $($names -join ', ')"
                    }
                }
            } elseif ($sync.ClosedAppCount -eq -2) {
                L "  Vor-Update-Schritt: Automatik-Modus - laufende Programme werden bewusst NICHT geschlossen"
            } else {
                L "  Vor-Update-Schritt: User hat das Schliessen abgelehnt - Updates koennen an gesperrten Dateien scheitern"
            }
            L ""
        }
        if ($sync.AutoMode) {
            L "  Modus: AUTOMATIK (geplante Wartung - keine Rueckfragen, kein Abschluss-Dialog)"
            L ""
        }

        # ── Connectivity-Precheck ── klare Offline-Meldung EINMAL, statt spaeter
        # mehrere kryptische Timeouts in Defender/WinUpdate/Winget/Store.
        # Robust: 1) Windows NLM (was Windows selbst nutzt fuer die Internet-
        # Anzeige), 2) mehrere Hosts probieren, 3) ausreichend Timeout. v2.6.4
        # hatte einen Single-HEAD auf microsoft.com mit 5s -> bei DNS-Lag oder
        # IPv6-Wackelei kam faelschlich "Offline".
        $online = $false
        # 1) NetworkListManager (COM) — sagt was Windows als verbunden sieht.
        try {
            $nlmType = [Type]::GetTypeFromCLSID([Guid]"DCB00C01-570F-4A9B-8D69-199FDBA5723B")
            if ($nlmType) {
                $nlm = [Activator]::CreateInstance($nlmType)
                # IsConnectedToInternet — boolean
                if ($nlm.IsConnectedToInternet) { $online = $true }
                try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($nlm) | Out-Null } catch {}
            }
        } catch {}
        # 2) HTTP-Test als zweite Meinung gegen mehrere Hosts (gibt true bei
        #    EINEM Treffer). 8s Timeout pro Host, jeder Host sequentiell aber
        #    Abbruch sobald einer antwortet -> max ~8s, meist <1s.
        if (-not $online) {
            foreach ($host_ in @("https://www.microsoft.com","https://github.com","https://www.cloudflare.com")) {
                try {
                    $req = [System.Net.WebRequest]::Create($host_)
                    $req.Method = "HEAD"; $req.Timeout = 8000
                    $resp = $req.GetResponse(); $resp.Close()
                    $online = $true; break
                } catch {}
            }
        }
        if ($online) {
            L "  Internet-Verbindung: OK"
        } else {
            L "  [WARNUNG] Keine Internet-Verbindung erkannt."
            L "  Online-Module (Defender, Windows Update, Apps, Store) koennen"
            L "  fehlschlagen oder nichts finden - das ist dann KEIN Geraetefehler."
            L "  Offline-Module (Reparatur, Netzwerk, Bereinigung) laufen normal."
        }
        L ""

        # ── System-Vorabcheck ── Pending-Reboot / Akku / Plattenplatz.
        # Bricht NICHTS ab - aber der User versteht Folgewarnungen (z.B. SFC
        # "Neustart erforderlich" oder zaehe Downloads am Akku) sofort.
        try {
            $pendingReboot = (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") -or
                             (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired")
            if ($pendingReboot) {
                $sync.RebootRequired = $true
                L "  [HINWEIS] Windows wartet bereits auf einen NEUSTART (fruehere Updates)."
                L "  Einzelne Module (SFC, Windows Update) koennen deshalb Warnungen melden."
                L "  Am besten den PC nach der Wartung neu starten."
                L ""
            }
        } catch {}
        try {
            $bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($bat -and $bat.BatteryStatus -eq 1) {
                L "  [HINWEIS] Geraet laeuft auf AKKU ($($bat.EstimatedChargeRemaining)% geladen)."
                L "  Bitte Netzteil anschliessen - Updates koennen lange dauern."
                L ""
            }
        } catch {}
        try {
            $sysDisk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'" -ErrorAction SilentlyContinue
            if ($sysDisk -and $sysDisk.FreeSpace -lt 10GB) {
                $freeGb = [Math]::Round($sysDisk.FreeSpace / 1GB, 1)
                L "  [WARNUNG] Wenig Speicherplatz auf $($env:SystemDrive) - nur $freeGb GB frei."
                L "  Grosse Windows-Updates brauchen oft 10+ GB. Die Bereinigung schafft etwas Platz."
                L ""
            }
        } catch {}

