# =====================================================================
# UPDATE-PRUEFUNG: Vergleicht lokale Version (Header in Zeile 1) mit der
# Version auf GitHub. Bei neuerer Remote-Version fragt eine MessageBox
# den Nutzer ob er das Update jetzt installieren will.
# Deaktivierbar via Umgebungsvariable JUSTUPDATE_NO_SELFUPDATE=1.
# =====================================================================
# Im Automatik-Modus KEIN Self-Update: der braucht eine MessageBox-Bestaetigung
# und wuerde den unbeaufsichtigten Lauf blockieren. Der naechste manuelle Start
# holt das Update nach.
if (-not $isExe -and $env:JUSTUPDATE_NO_SELFUPDATE -ne "1" -and -not $script:AutoMode) {
    # ProgressPreference fuer den Download unterdruecken — sonst rendert Windows PowerShell
    # die deutsche Fortschrittsanzeige ("Webanforderung wird geschrieben / Anzahl geschriebener Bytes")
    # ueber das WPF-Window und macht Invoke-WebRequest ausserdem ~10x langsamer.
    $savedProgressPreference = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        $remoteUrl = "https://raw.githubusercontent.com/Just1n12354/JustUpdate/main/MaintenanceProGUI_MODERN.ps1"
        $tempFile  = Join-Path $env:TEMP "JustUpdate_remote.ps1"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $remoteUrl -OutFile $tempFile -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        # v2.6.4: -ErrorAction Stop auf Get-Item/Get-Content. Sonst kann ein
        # Antivirus (z.B. HP Wolf Security) die heruntergeladene Datei sofort
        # in Quarantaene stellen - Get-Content wirft non-terminating
        # UnauthorizedAccessException, faellt NICHT in den catch unten und
        # landet als roter Stacktrace auf dem Bildschirm. Mit Stop bleibt der
        # Fluss intakt, der catch fasst den AV-Block als bekannten Fall ab.
        if ((Get-Item $tempFile -ErrorAction Stop).Length -gt 1000) {
            $localVerLine  = Get-Content $ScriptPath -TotalCount 1 -ErrorAction Stop
            $remoteVerLine = Get-Content $tempFile  -TotalCount 1 -ErrorAction Stop
            $localVer = [version]'0.0.0'
            if ($localVerLine -match '#\s*Version:\s*([\d\.]+)') { try { $localVer = [version]$Matches[1] } catch {} }
            $remoteVer = $null
            if ($remoteVerLine -match '#\s*Version:\s*([\d\.]+)') { try { $remoteVer = [version]$Matches[1] } catch {} }
            if ($remoteVer -and $remoteVer -gt $localVer) {
                Add-Type -AssemblyName PresentationFramework
                $msg = "Eine neue Version von JustUpdate ist verfuegbar:`n`n" +
                       "  Installiert:  v$localVer`n" +
                       "  Verfuegbar:   v$remoteVer`n`n" +
                       "Jetzt herunterladen und installieren?"
                $answer = [System.Windows.MessageBox]::Show(
                    $msg,
                    "JustUpdate - Update verfuegbar",
                    [System.Windows.MessageBoxButton]::YesNo,
                    [System.Windows.MessageBoxImage]::Question)
                if ($answer -eq [System.Windows.MessageBoxResult]::Yes) {
                    # INTEGRITAET: heruntergeladenes Skript MUSS sich sauber parsen
                    # lassen, bevor es das laufende ueberschreibt. Sonst koennte ein
                    # abgebrochener/korrupter Download (TLS-Reset, Proxy-HTML, halbe
                    # Datei > 1000 Byte) die Installation unstartbar machen.
                    $parseErr = $null
                    [void][System.Management.Automation.Language.Parser]::ParseFile(
                        $tempFile, [ref]$null, [ref]$parseErr)
                    if ($parseErr -and $parseErr.Count -gt 0) {
                        [System.Windows.MessageBox]::Show(
                            "Das heruntergeladene Update ist beschaedigt und wurde " +
                            "NICHT installiert.`nDie vorhandene Version bleibt " +
                            "unveraendert. Bitte spaeter erneut versuchen.",
                            "JustUpdate - Update abgebrochen",
                            [System.Windows.MessageBoxButton]::OK,
                            [System.Windows.MessageBoxImage]::Warning) | Out-Null
                    } else {
                        # --- Versions-bewusster Changelog (BEST EFFORT) ----------
                        # Zeigt ALLE Changelog-Abschnitte mit Version > installiert.
                        # 2.5.0 -> 2.6.2: zeigt 2.5.x/2.6.0/2.6.1/2.6.2.
                        # 2.6.1 -> 2.6.2: zeigt nur 2.6.2.
                        # Darf das Update unter KEINEN Umstaenden blockieren.
                        try {
                            $clUrl = "https://raw.githubusercontent.com/Just1n12354/JustUpdate/main/CHANGELOG.md"
                            $clTmp = Join-Path $env:TEMP "JustUpdate_changelog.md"
                            Invoke-WebRequest -Uri $clUrl -OutFile $clTmp -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                            $clRaw = Get-Content $clTmp -Raw -ErrorAction Stop
                            Remove-Item $clTmp -ErrorAction SilentlyContinue
                            $secs = [regex]::Matches($clRaw,
                                '(?ms)^##\s*v?(\d+\.\d+\.\d+).*?\r?\n(.*?)(?=^##\s*v?\d+\.\d+\.\d+|\z)')
                            $rel = @()
                            foreach ($m in $secs) {
                                $sv = $null
                                try { $sv = [version]$m.Groups[1].Value } catch { continue }
                                if ($sv -gt $localVer) {
                                    $rel += [pscustomobject]@{
                                        V = $sv
                                        Txt = ("=== v{0} ===`r`n{1}" -f $m.Groups[1].Value, $m.Groups[2].Value.Trim())
                                    }
                                }
                            }
                            if ($rel.Count -gt 0) {
                                $body = (($rel | Sort-Object V -Descending | ForEach-Object { $_.Txt }) -join "`r`n`r`n")
                                Show-JUChangelog "JustUpdate v$remoteVer - Was ist neu seit v$localVer" $body
                            }
                        } catch { }
                        # ---------------------------------------------------------
                        # v2.6.4: -ErrorAction Stop, sonst koennte ein AV-Lock auf
                        # tempFile das Copy zerlegen und einen roten Crash erzeugen
                        # statt den catch-Pfad zu nehmen.
                        Copy-Item -Path $tempFile -Destination $ScriptPath -Force -ErrorAction Stop
                        Remove-Item $tempFile -ErrorAction SilentlyContinue
                        $env:JUSTUPDATE_NO_SELFUPDATE = "1"
                        Release-JUMutex   # sonst weist diese Instanz die frisch gestartete ab
                        Start-Process powershell.exe -Verb RunAs `
                            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -File `"$ScriptPath`""
                        exit
                    }
                }
            }
        }
        Remove-Item $tempFile -ErrorAction SilentlyContinue
    } catch {
        # Offline / GitHub unreachable / keine Schreibrechte -> Fallback auf lokale Version
    } finally {
        $ProgressPreference = $savedProgressPreference
    }
}

