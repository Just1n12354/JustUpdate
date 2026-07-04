# Version: 2.7.3
# Copyright (c) 2026 Itin TechSolutions / Justin Itin
# Alle Rechte vorbehalten - info@itintechsolutions.ch
# https://itintechsolutions.ch

# -Auto: Automatik-Modus fuer geplante Wartung (Task Scheduler / Zeitplan-
# Button in der Titelleiste). Startet die Wartung ohne Klick mit den
# gespeicherten Modulen, zeigt keine Dialoge, schliesst keine laufenden
# Programme, beendet sich selbst und liefert einen Exit-Code fuers
# Fleet-Monitoring (0=OK, 1=Warnungen, 2=Fehler).
# Alternativ aktivierbar via Umgebungsvariable JUSTUPDATE_AUTO=1.
param([switch]$Auto)

# Determine script/exe path first
$ScriptPath = if ($PSCommandPath) { $PSCommandPath }
              elseif ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path }
              else { [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName }

# Laeuft das hier als kompilierte JustUpdate.exe (PS2EXE) statt als .ps1 ueber
# powershell.exe? Dann duerfen Self-Elevation (powershell -File <exe> ist ungueltig)
# und Self-Update (wuerde die laufende .exe mit einer .ps1 ueberschreiben) NICHT
# den .ps1-Pfad gehen. Die EXE aktualisiert sich spaeter ueber GitHub-Releases.
$isExe = $ScriptPath -match '\.exe$'

# Automatik-Modus aktiv? (Parameter ODER Umgebungsvariable, z.B. fuer
# bestehende geplante Aufgaben, die keinen Parameter mitgeben koennen)
$script:AutoMode = [bool]$Auto -or ($env:JUSTUPDATE_AUTO -eq '1')

# Eine einzige Laufzeit-Versionsquelle fuer das ganze Skript (Footer, Report, ...).
# .ps1: Header in Zeile 1.  .exe: aus den FileVersionInfo-Metadaten (von build.ps1
# via PS2EXE -version gesetzt) - in der Binaerdatei gibt es keine lesbare "Zeile 1",
# darum zeigte die EXE vorher "v?".
$script:JUVersion = $null
if ($isExe) {
    try {
        $pv = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($ScriptPath).ProductVersion
        if ($pv) {
            # "2.6.0.0" -> sauber auf x.y.z (erste 3 Teile), NICHT Nullen strippen
            $parts = ([string]$pv).Trim() -split '\.'
            $script:JUVersion = (@($parts + '0' + '0')[0..2]) -join '.'
        }
    } catch {}
} else {
    try {
        if ((Get-Content $ScriptPath -TotalCount 1) -match '#\s*Version:\s*([\d\.]+)') { $script:JUVersion = $Matches[1] }
    } catch {}
}
if (-not $script:JUVersion) { $script:JUVersion = '2.7.3' }   # letzter Fallback statt "?"

# =====================================================================
# Changelog-Fenster (scrollbar). Wird beim Self-Update gezeigt: "Was ist
# neu seit deiner Version". Komplett gekapselt - ein Fehler hier darf das
# Update NIE blockieren (Aufrufer ist zusaetzlich in try/catch).
# =====================================================================
function Show-JUChangelog([string]$title, [string]$bodyText) {
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
        $w = New-Object System.Windows.Window
        $w.Title = $title
        $w.Width = 660; $w.Height = 580
        $w.WindowStartupLocation = 'CenterScreen'
        $w.ResizeMode = 'CanResizeWithGrip'
        $grid = New-Object System.Windows.Controls.Grid
        $grid.Margin = '16'
        foreach ($h in @('Auto','*','Auto')) {
            $rd = New-Object System.Windows.Controls.RowDefinition
            $rd.Height = [System.Windows.GridLength]::Auto
            if ($h -eq '*') { $rd.Height = New-Object System.Windows.GridLength(1,'Star') }
            $grid.RowDefinitions.Add($rd)
        }
        $hdr = New-Object System.Windows.Controls.TextBlock
        $hdr.Text = $title; $hdr.FontSize = 15; $hdr.FontWeight = 'Bold'
        $hdr.Margin = '0,0,0,10'; $hdr.TextWrapping = 'Wrap'
        [System.Windows.Controls.Grid]::SetRow($hdr,0)
        $tb = New-Object System.Windows.Controls.TextBox
        $tb.Text = $bodyText; $tb.IsReadOnly = $true; $tb.TextWrapping = 'Wrap'
        $tb.VerticalScrollBarVisibility = 'Auto'
        $tb.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas')
        $tb.FontSize = 12; $tb.BorderThickness = New-Object System.Windows.Thickness(0)
        $tb.Padding = New-Object System.Windows.Thickness(4)
        [System.Windows.Controls.Grid]::SetRow($tb,1)
        $btn = New-Object System.Windows.Controls.Button
        $btn.Content = 'Update jetzt installieren'
        $btn.Width = 200; $btn.Height = 36
        $btn.HorizontalAlignment = 'Right'; $btn.Margin = '0,14,0,0'
        $btn.IsDefault = $true
        $btn.Add_Click({ $w.Close() })
        [System.Windows.Controls.Grid]::SetRow($btn,2)
        $grid.Children.Add($hdr) | Out-Null
        $grid.Children.Add($tb)  | Out-Null
        $grid.Children.Add($btn) | Out-Null
        $w.Content = $grid
        $w.ShowDialog() | Out-Null
    } catch { }
}

# Ensure Windows PowerShell + STA + Admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isExe) {
    # EXE: nur fehlende Admin-Rechte sind relevant (STA/Edition setzt PS2EXE selbst).
    if (-not $isAdmin) {
        # -Auto MUSS die Selbst-Elevation ueberleben, sonst bleibt der
        # geplante Lauf nach dem UAC-Hop im interaktiven Modus haengen.
        if ($script:AutoMode) { Start-Process -FilePath $ScriptPath -ArgumentList "-Auto" -Verb RunAs }
        else                  { Start-Process -FilePath $ScriptPath -Verb RunAs }
        exit
    }
} elseif ($PSVersionTable.PSEdition -eq "Core" -or
    [System.Threading.Thread]::CurrentThread.ApartmentState -ne "STA" -or
    -not $isAdmin) {
    $elevArgs = "-NoProfile -ExecutionPolicy Bypass -STA -File `"$ScriptPath`""
    if ($script:AutoMode) { $elevArgs += " -Auto" }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $elevArgs
    exit
}

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

# =====================================================================
# EXE-MIGRATION (Bestandskunden .ps1 -> JustUpdate.exe, ohne Reinstall)
# Holt die EXE aus dem GitHub-Release, legt sie in den App-Ordner, biegt
# die Verknuepfungen um und startet die EXE. Einmalig (Marker-Datei).
#
# SICHERHEIT: standardmaessig AUS. Erst wenn eine (spaeter SIGNIERTE) EXE
# bereit ist, wird scharf geschaltet via Umgebungsvariable
#   JUSTUPDATE_MIGRATE_EXE = 1
# So koennen wir die Mechanik testen, ohne Produktiv-Kunden anzufassen.
# Die .ps1 bleibt liegen (Fallback) - die Migration ist reversibel.
# =====================================================================
if (-not $isExe -and $env:JUSTUPDATE_MIGRATE_EXE -eq "1") {
    try {
        $appDir   = Split-Path -Parent $ScriptPath
        $exePath  = Join-Path $appDir "JustUpdate.exe"
        $marker   = Join-Path $appDir ".exe_migrated"
        if (-not (Test-Path $marker)) {
            $tmpExe = Join-Path $env:TEMP "JustUpdate_new.exe"
            # Test-Override: lokale Datei / Test-URL, ohne das oeffentliche Release
            # anzufassen. z.B.  $env:JUSTUPDATE_EXE_URL = "C:\...\JustUpdate.exe"
            $exeUrl = if ($env:JUSTUPDATE_EXE_URL) { $env:JUSTUPDATE_EXE_URL }
                      else { "https://github.com/Just1n12354/JustUpdate/releases/latest/download/JustUpdate.exe" }
            if ($exeUrl -notmatch '^https?://') {
                Copy-Item $exeUrl $tmpExe -Force -ErrorAction Stop   # lokaler Pfad
            } else {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                $sp = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
                try {
                    Invoke-WebRequest -Uri $exeUrl -OutFile $tmpExe -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
                } finally { $ProgressPreference = $sp }
            }

            # Integritaet: echte PE-Datei (MZ-Header) + plausible Groesse?
            $okPe = $false
            if ((Test-Path $tmpExe) -and (Get-Item $tmpExe).Length -gt 100KB) {
                $fs = [IO.File]::OpenRead($tmpExe)
                try { $b = New-Object byte[] 2; [void]$fs.Read($b,0,2) } finally { $fs.Close() }
                $okPe = ($b[0] -eq 0x4D -and $b[1] -eq 0x5A)   # 'MZ'
            }
            if ($okPe) {
                Copy-Item $tmpExe $exePath -Force
                Remove-Item $tmpExe -ErrorAction SilentlyContinue

                # Verknuepfungen umbiegen: Desktop (Public/User) + Startmenue.
                $sh = New-Object -ComObject WScript.Shell
                $lnkDirs = @(
                    "$env:PUBLIC\Desktop", "$env:USERPROFILE\Desktop",
                    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
                    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
                )
                $changed = 0
                foreach ($d in $lnkDirs) {
                    if (-not (Test-Path $d)) { continue }
                    Get-ChildItem $d -Filter "JustUpdate*.lnk" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                        try {
                            $lnk = $sh.CreateShortcut($_.FullName)
                            $lnk.TargetPath       = $exePath
                            $lnk.Arguments        = ""
                            $lnk.WorkingDirectory = $appDir
                            $lnk.IconLocation     = "$exePath,0"
                            $lnk.Save()
                            $changed++
                        } catch {}
                    }
                }
                # Marker mit Revert-Info (falls je zurueck auf .ps1 noetig).
                @(
                    "migrated=$(Get-Date -Format o)",
                    "exe=$exePath",
                    "revert_target=powershell.exe",
                    "revert_args=-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$ScriptPath`"",
                    "shortcuts_changed=$changed"
                ) | Out-File -FilePath $marker -Encoding utf8 -Force

                # In die frische EXE wechseln.
                Start-Process -FilePath $exePath
                exit
            }
        }
    } catch {
        # Migration fehlgeschlagen -> .ps1 laeuft normal weiter (kein Bruch).
    }
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# =====================================================================
# PATHS
# =====================================================================
$BaseDir = Split-Path -Parent $ScriptPath
# Log-Ordner liegt neben dem Script/Exe (relativ, nicht hardcoded auf Program Files).
# Fallback auf APPDATA falls App-Ordner schreibgeschuetzt ist (z.B. portable von Read-Only-Medium).
$LogDir = Join-Path $BaseDir "logs"
try {
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force -ErrorAction Stop | Out-Null }
    # Schreibtest
    $probe = Join-Path $LogDir ".write_probe"
    "" | Out-File -FilePath $probe -Encoding utf8 -ErrorAction Stop
    Remove-Item $probe -Force -ErrorAction SilentlyContinue
} catch {
    $LogDir = Join-Path $env:APPDATA "JustUpdate\logs"
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
}
$script:LogPath = Join-Path $LogDir ("Maintenance_{0}_v{1}.log" -f (Get-Date -Format "yyyy-MM-dd_HH-mm-ss"), $script:JUVersion)
# Metadaten-Kopf in die neue Logdatei schreiben — fuer den Support sofort
# sichtbar welche Version, welcher Host, wann gelaufen.
$logHeader = @"
=================================================
JustUpdate Logdatei
=================================================
Version:    v$($script:JUVersion)
Host:       $($env:COMPUTERNAME)
Benutzer:   $($env:USERNAME)
Erstellt:   $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')
Skript:     $ScriptPath
Log-Datei:  $script:LogPath
=================================================

"@
$logHeader | Out-File -FilePath $script:LogPath -Encoding utf8

# Log-Rotation: max 10 Logs behalten, aeltere loeschen
try {
    Get-ChildItem -Path $LogDir -Filter "Maintenance_*.log" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip 10 |
        ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
} catch {}

# =====================================================================
# TRANSLATIONS
# =====================================================================
$script:TR = @{
    "de" = @{
        Title="System Wartung Pro"; Tag="All-in-One PC Wartung"
        Desc="Ein Klick - alles aktuell. Windows Updates, Treiber, Apps, Sicherheit und Bereinigung."
        Start="WARTUNG STARTEN"; Stop="ABBRECHEN"; OpenLog="LOG OEFFNEN"
        Modules="Wartungs-Module"; LiveLog="Live-Protokoll"
        Ready="Bereit"; Running="Laeuft..."; Done="Abgeschlossen!"; Stopped="Abgebrochen"
        Footer="Administratorrechte aktiv"
        Restore="Wiederherstellungspunkt"; RestoreD="Sicherung vor Aenderungen"
        Defender="Defender aktualisieren"; DefenderD="Viren-Signaturen updaten"
        WinUpdate="Windows Updates"; WinUpdateD="OS-Updates installieren"
        Drivers="Treiber aktualisieren"; DriversD="Geraete-Treiber updaten"
        Winget="Apps aktualisieren"; WingetD="Alle Apps via Winget"
        StoreApps="Store Apps updaten"; StoreAppsD="Microsoft Store Apps"
        Repair="System-Reparatur"; RepairD="SFC und DISM Pruefung"
        Network="Netzwerk reparieren"; NetworkD="DNS, Winsock, IP Reset"
        Cleanup="Bereinigung"; CleanupD="Temp, Cache, Papierkorb"
        Env="System"
        CloseAppsTitle="Apps vor Update schliessen?"
        CloseAppsMsg="Vor Windows-Updates und Store-Updates sollten alle offenen Programme geschlossen werden, damit sich keine Update-Installation an gesperrten Dateien aufhaengt.`n`nJetzt alle laufenden Programme schliessen?`n`nWICHTIG: Ungespeicherte Daten gehen verloren!"
    }
    "en" = @{
        Title="System Maintenance Pro"; Tag="All-in-One PC Maintenance"
        Desc="One click - everything up to date. Windows Updates, drivers, apps, security, and cleanup."
        Start="START MAINTENANCE"; Stop="CANCEL"; OpenLog="OPEN LOG"
        Modules="Maintenance Modules"; LiveLog="Live Log"
        Ready="Ready"; Running="Running..."; Done="Complete!"; Stopped="Cancelled"
        Footer="Administrator privileges active"
        Restore="Restore Point"; RestoreD="Safety checkpoint"
        Defender="Update Defender"; DefenderD="Update virus signatures"
        WinUpdate="Windows Updates"; WinUpdateD="Install OS updates"
        Drivers="Update Drivers"; DriversD="Device driver updates"
        Winget="Update Apps"; WingetD="All apps via Winget"
        StoreApps="Update Store Apps"; StoreAppsD="Microsoft Store apps"
        Repair="System Repair"; RepairD="SFC and DISM check"
        Network="Repair Network"; NetworkD="DNS, Winsock, IP reset"
        Cleanup="Cleanup"; CleanupD="Temp, cache, recycle bin"
        Env="System"
        CloseAppsTitle="Close apps before updating?"
        CloseAppsMsg="Before Windows Updates and Store updates, all open applications should be closed so update installations don't get stuck on locked files.`n`nClose all running applications now?`n`nWARNING: Unsaved data will be lost!"
    }
    "fr" = @{
        Title="Maintenance Systeme Pro"; Tag="Maintenance PC tout-en-un"
        Desc="Un clic - tout a jour. Mises a jour Windows, pilotes, apps, securite et nettoyage."
        Start="DEMARRER"; Stop="ANNULER"; OpenLog="OUVRIR LOG"
        Modules="Modules"; LiveLog="Journal en direct"
        Ready="Pret"; Running="En cours..."; Done="Termine!"; Stopped="Annule"
        Footer="Privileges administrateur actifs"
        Restore="Point de restauration"; RestoreD="Sauvegarde avant modifications"
        Defender="Mettre a jour Defender"; DefenderD="Signatures antivirus"
        WinUpdate="Mises a jour Windows"; WinUpdateD="Installer les MAJ OS"
        Drivers="Mettre a jour pilotes"; DriversD="Pilotes via Windows Update"
        Winget="Mettre a jour apps"; WingetD="Toutes les apps via Winget"
        StoreApps="Mettre a jour Store"; StoreAppsD="Apps Microsoft Store"
        Repair="Reparation systeme"; RepairD="Verification SFC et DISM"
        Network="Reparer reseau"; NetworkD="Reset DNS, Winsock, IP"
        Cleanup="Nettoyage"; CleanupD="Temp, cache, corbeille"
        Env="Systeme"
        CloseAppsTitle="Fermer les apps avant la mise a jour?"
        CloseAppsMsg="Avant les mises a jour Windows et Store, toutes les applications ouvertes doivent etre fermees pour eviter les blocages sur des fichiers verrouilles.`n`nFermer toutes les applications en cours maintenant?`n`nATTENTION: Les donnees non enregistrees seront perdues!"
    }
}
$script:Lang = "de"
function T([string]$k) { return $script:TR[$script:Lang][$k] }

# =====================================================================
# XAML
# =====================================================================
[xml]$xamlXml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="System Maintenance Pro" Width="900" Height="620"
        MinWidth="750" MinHeight="500"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None" ResizeMode="CanResize"
        AllowsTransparency="True" Background="Transparent">

    <Window.Resources>
        <SolidColorBrush x:Key="BgMain"    Color="#111118"/>
        <SolidColorBrush x:Key="BgPanel"   Color="#18181f"/>
        <SolidColorBrush x:Key="BgCard"    Color="#1f1f28"/>
        <SolidColorBrush x:Key="BgInput"   Color="#25252f"/>
        <SolidColorBrush x:Key="Bdr"       Color="#2a2a35"/>
        <SolidColorBrush x:Key="Fg"        Color="#ededf2"/>
        <SolidColorBrush x:Key="FgDim"     Color="#8888a0"/>
        <SolidColorBrush x:Key="FgMute"    Color="#52526a"/>
        <SolidColorBrush x:Key="Acc"       Color="#A3243B"/>
        <SolidColorBrush x:Key="AccH"      Color="#bd2b46"/>
        <SolidColorBrush x:Key="Blu"       Color="#3B82F6"/>
        <SolidColorBrush x:Key="Grn"       Color="#22C55E"/>
        <SolidColorBrush x:Key="Rd"        Color="#EF4444"/>
        <SolidColorBrush x:Key="Amb"       Color="#e8a020"/>

        <Style x:Key="Sw" TargetType="ToggleButton">
            <Setter Property="Width" Value="40"/>
            <Setter Property="Height" Value="22"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ToggleButton">
                        <Border x:Name="BgBd" CornerRadius="11" Background="#2a2a35">
                            <Ellipse x:Name="Dot" Width="16" Height="16" Fill="#52526a" HorizontalAlignment="Left" Margin="3,0,0,0"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="BgBd" Property="Background" Value="{StaticResource Acc}"/>
                                <Setter TargetName="Dot" Property="Fill" Value="White"/>
                                <Setter TargetName="Dot" Property="HorizontalAlignment" Value="Right"/>
                                <Setter TargetName="Dot" Property="Margin" Value="0,0,3,0"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="WinBtn" TargetType="Button">
            <Setter Property="Foreground" Value="{StaticResource FgDim}"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Width" Value="34"/>
            <Setter Property="Height" Value="28"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="B" Background="Transparent" CornerRadius="6">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="B" Property="Background" Value="#25252f"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Border CornerRadius="16" Background="{StaticResource BgMain}" BorderBrush="#0a0a10" BorderThickness="1.5">
        <Border.Effect>
            <DropShadowEffect BlurRadius="50" ShadowDepth="0" Opacity="0.55" Color="#000"/>
        </Border.Effect>
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="42"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="28"/>
            </Grid.RowDefinitions>

            <!-- TITLEBAR -->
            <Grid x:Name="TitleBar" Grid.Row="0" Margin="16,0" Background="Transparent">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <Ellipse Width="10" Height="10" Fill="{StaticResource Acc}" Margin="0,0,8,0"/>
                    <TextBlock x:Name="xTitleBar" Text="System Maintenance Pro" Foreground="{StaticResource Fg}" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center"/>
                </StackPanel>
                <DockPanel Grid.Column="1" LastChildFill="False">
                    <Button x:Name="xClose" DockPanel.Dock="Right" Style="{StaticResource WinBtn}" Content="X" FontSize="12"/>
                    <Button x:Name="xMax" DockPanel.Dock="Right" Style="{StaticResource WinBtn}" Content="☐" FontSize="12"/>
                    <Button x:Name="xMin" DockPanel.Dock="Right" Style="{StaticResource WinBtn}" Content="_" FontSize="14"/>
                    <Button x:Name="xInfo" DockPanel.Dock="Right" Style="{StaticResource WinBtn}" Content="i" FontSize="14" FontWeight="Bold" Foreground="{StaticResource Acc}" Margin="0,0,4,0"/>
                    <Button x:Name="xPatch" DockPanel.Dock="Right" Style="{StaticResource WinBtn}" Content="?" FontSize="14" FontWeight="Bold" Foreground="{StaticResource Fg}" Margin="0,0,4,0" ToolTip="Patch-Notes / Versions-Historie"/>
                    <Button x:Name="xSched" DockPanel.Dock="Right" Style="{StaticResource WinBtn}" Content="&#x23F0;" FontSize="13" Foreground="{StaticResource Fg}" Margin="0,0,4,0" ToolTip="Automatische Wartung planen (woechentlich)"/>
                    <ComboBox x:Name="xLang" DockPanel.Dock="Right" Width="90" Height="26" Margin="0,0,8,0"
                              Background="{StaticResource BgCard}" Foreground="{StaticResource FgDim}"
                              BorderBrush="{StaticResource Bdr}" BorderThickness="1" FontSize="11">
                        <ComboBoxItem Content="Deutsch" Tag="de" IsSelected="True"/>
                        <ComboBoxItem Content="English" Tag="en"/>
                        <ComboBoxItem Content="Francais" Tag="fr"/>
                    </ComboBox>
                </DockPanel>
            </Grid>

            <!-- MAIN -->
            <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
            <Grid Margin="14,2,14,6">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*" MinWidth="250" MaxWidth="380"/>
                    <ColumnDefinition Width="12"/>
                    <ColumnDefinition Width="2*"/>
                </Grid.ColumnDefinitions>

                <!-- LEFT: MODULES -->
                <Border Grid.Column="0" Background="{StaticResource BgPanel}" CornerRadius="14" BorderBrush="{StaticResource Bdr}" BorderThickness="1">
                    <Grid Margin="14">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>

                        <TextBlock x:Name="xModHdr" Foreground="{StaticResource Fg}" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,10"/>

                        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
                            <StackPanel x:Name="xMods">
                                <!-- Each module card -->
                                <Border Background="{StaticResource BgCard}" CornerRadius="10" Padding="12,10" Margin="0,0,0,5" BorderBrush="{StaticResource Bdr}" BorderThickness="1">
                                    <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="28"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                                        <TextBlock x:Name="xIcoRestore" Text="R" Foreground="{StaticResource Acc}" FontSize="14" FontWeight="Bold" VerticalAlignment="Center"/>
                                        <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="6,0,0,0"><TextBlock x:Name="xRestore" Foreground="{StaticResource Fg}" FontSize="12"/><TextBlock x:Name="xRestoreD" Foreground="{StaticResource FgMute}" FontSize="9.5"/></StackPanel>
                                        <ToggleButton x:Name="xTglRestore" Grid.Column="2" Style="{StaticResource Sw}" IsChecked="True" VerticalAlignment="Center"/>
                                    </Grid>
                                </Border>
                                <Border Background="{StaticResource BgCard}" CornerRadius="10" Padding="12,10" Margin="0,0,0,5" BorderBrush="{StaticResource Bdr}" BorderThickness="1">
                                    <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="28"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                                        <TextBlock x:Name="xIcoDefender" Text="D" Foreground="{StaticResource Acc}" FontSize="14" FontWeight="Bold" VerticalAlignment="Center"/>
                                        <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="6,0,0,0"><TextBlock x:Name="xDefender" Foreground="{StaticResource Fg}" FontSize="12"/><TextBlock x:Name="xDefenderD" Foreground="{StaticResource FgMute}" FontSize="9.5"/></StackPanel>
                                        <ToggleButton x:Name="xTglDefender" Grid.Column="2" Style="{StaticResource Sw}" IsChecked="True" VerticalAlignment="Center"/>
                                    </Grid>
                                </Border>
                                <Border Background="{StaticResource BgCard}" CornerRadius="10" Padding="12,10" Margin="0,0,0,5" BorderBrush="{StaticResource Bdr}" BorderThickness="1">
                                    <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="28"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                                        <TextBlock x:Name="xIcoWinUpdate" Text="W" Foreground="{StaticResource Grn}" FontSize="14" FontWeight="Bold" VerticalAlignment="Center"/>
                                        <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="6,0,0,0"><TextBlock x:Name="xWinUpdate" Foreground="{StaticResource Fg}" FontSize="12"/><TextBlock x:Name="xWinUpdateD" Foreground="{StaticResource FgMute}" FontSize="9.5"/></StackPanel>
                                        <ToggleButton x:Name="xTglWinUpdate" Grid.Column="2" Style="{StaticResource Sw}" IsChecked="True" VerticalAlignment="Center"/>
                                    </Grid>
                                </Border>
                                <Border Background="{StaticResource BgCard}" CornerRadius="10" Padding="12,10" Margin="0,0,0,5" BorderBrush="{StaticResource Bdr}" BorderThickness="1">
                                    <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="28"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                                        <TextBlock x:Name="xIcoDrivers" Text="T" Foreground="{StaticResource Amb}" FontSize="14" FontWeight="Bold" VerticalAlignment="Center"/>
                                        <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="6,0,0,0"><TextBlock x:Name="xDrivers" Foreground="{StaticResource Fg}" FontSize="12"/><TextBlock x:Name="xDriversD" Foreground="{StaticResource FgMute}" FontSize="9.5"/></StackPanel>
                                        <ToggleButton x:Name="xTglDrivers" Grid.Column="2" Style="{StaticResource Sw}" IsChecked="True" VerticalAlignment="Center"/>
                                    </Grid>
                                </Border>
                                <Border Background="{StaticResource BgCard}" CornerRadius="10" Padding="12,10" Margin="0,0,0,5" BorderBrush="{StaticResource Bdr}" BorderThickness="1">
                                    <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="28"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                                        <TextBlock x:Name="xIcoWinget" Text="A" Foreground="{StaticResource Acc}" FontSize="14" FontWeight="Bold" VerticalAlignment="Center"/>
                                        <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="6,0,0,0"><TextBlock x:Name="xWinget" Foreground="{StaticResource Fg}" FontSize="12"/><TextBlock x:Name="xWingetD" Foreground="{StaticResource FgMute}" FontSize="9.5"/></StackPanel>
                                        <ToggleButton x:Name="xTglWinget" Grid.Column="2" Style="{StaticResource Sw}" IsChecked="True" VerticalAlignment="Center"/>
                                    </Grid>
                                </Border>
                                <Border Background="{StaticResource BgCard}" CornerRadius="10" Padding="12,10" Margin="0,0,0,5" BorderBrush="{StaticResource Bdr}" BorderThickness="1">
                                    <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="28"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                                        <TextBlock x:Name="xIcoStore" Text="S" Foreground="#A855F7" FontSize="14" FontWeight="Bold" VerticalAlignment="Center"/>
                                        <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="6,0,0,0"><TextBlock x:Name="xStoreApps" Foreground="{StaticResource Fg}" FontSize="12"/><TextBlock x:Name="xStoreAppsD" Foreground="{StaticResource FgMute}" FontSize="9.5"/></StackPanel>
                                        <ToggleButton x:Name="xTglStore" Grid.Column="2" Style="{StaticResource Sw}" IsChecked="True" VerticalAlignment="Center"/>
                                    </Grid>
                                </Border>
                                <Border Background="{StaticResource BgCard}" CornerRadius="10" Padding="12,10" Margin="0,0,0,5" BorderBrush="{StaticResource Bdr}" BorderThickness="1">
                                    <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="28"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                                        <TextBlock x:Name="xIcoRepair" Text="F" Foreground="{StaticResource Rd}" FontSize="14" FontWeight="Bold" VerticalAlignment="Center"/>
                                        <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="6,0,0,0"><TextBlock x:Name="xRepair" Foreground="{StaticResource Fg}" FontSize="12"/><TextBlock x:Name="xRepairD" Foreground="{StaticResource FgMute}" FontSize="9.5"/></StackPanel>
                                        <ToggleButton x:Name="xTglRepair" Grid.Column="2" Style="{StaticResource Sw}" IsChecked="True" VerticalAlignment="Center"/>
                                    </Grid>
                                </Border>
                                <Border Background="{StaticResource BgCard}" CornerRadius="10" Padding="12,10" Margin="0,0,0,5" BorderBrush="{StaticResource Bdr}" BorderThickness="1">
                                    <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="28"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                                        <TextBlock x:Name="xIcoNetwork" Text="N" Foreground="#06B6D4" FontSize="14" FontWeight="Bold" VerticalAlignment="Center"/>
                                        <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="6,0,0,0"><TextBlock x:Name="xNetwork" Foreground="{StaticResource Fg}" FontSize="12"/><TextBlock x:Name="xNetworkD" Foreground="{StaticResource FgMute}" FontSize="9.5"/></StackPanel>
                                        <ToggleButton x:Name="xTglNetwork" Grid.Column="2" Style="{StaticResource Sw}" IsChecked="False" VerticalAlignment="Center"/>
                                    </Grid>
                                </Border>
                                <Border Background="{StaticResource BgCard}" CornerRadius="10" Padding="12,10" Margin="0,0,0,5" BorderBrush="{StaticResource Bdr}" BorderThickness="1">
                                    <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="28"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                                        <TextBlock x:Name="xIcoCleanup" Text="C" Foreground="{StaticResource Grn}" FontSize="14" FontWeight="Bold" VerticalAlignment="Center"/>
                                        <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="6,0,0,0"><TextBlock x:Name="xCleanup" Foreground="{StaticResource Fg}" FontSize="12"/><TextBlock x:Name="xCleanupD" Foreground="{StaticResource FgMute}" FontSize="9.5"/></StackPanel>
                                        <ToggleButton x:Name="xTglCleanup" Grid.Column="2" Style="{StaticResource Sw}" IsChecked="True" VerticalAlignment="Center"/>
                                    </Grid>
                                </Border>
                            </StackPanel>
                        </ScrollViewer>

                        <Border Grid.Row="2" Background="#0c0c12" CornerRadius="10" Padding="10" Margin="0,6,0,0" BorderBrush="{StaticResource Bdr}" BorderThickness="1">
                            <StackPanel>
                                <TextBlock x:Name="xEnvLbl" Foreground="{StaticResource FgDim}" FontSize="10" FontWeight="SemiBold"/>
                                <TextBlock x:Name="xEnvInfo" Foreground="{StaticResource FgMute}" FontSize="9" TextWrapping="Wrap" Margin="0,3,0,0"/>
                            </StackPanel>
                        </Border>
                    </Grid>
                </Border>

                <!-- RIGHT -->
                <Grid Grid.Column="2">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <!-- Header -->
                    <Border Grid.Row="0" CornerRadius="14" Margin="0,0,0,8" BorderBrush="{StaticResource Bdr}" BorderThickness="1" Padding="22,18">
                        <Border.Background>
                            <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                                <GradientStop Color="#1a1018" Offset="0"/>
                                <GradientStop Color="#241522" Offset="0.5"/>
                                <GradientStop Color="#1a1018" Offset="1"/>
                            </LinearGradientBrush>
                        </Border.Background>
                        <StackPanel>
                            <TextBlock x:Name="xTag" Foreground="{StaticResource Acc}" FontSize="10.5" FontWeight="SemiBold" Margin="0,0,0,3"/>
                            <TextBlock x:Name="xTitle" Foreground="{StaticResource Fg}" FontSize="22" FontWeight="Bold"/>
                            <TextBlock x:Name="xDesc" Foreground="{StaticResource FgDim}" FontSize="11.5" TextWrapping="Wrap" Margin="0,5,0,0"/>
                        </StackPanel>
                    </Border>

                    <!-- Buttons -->
                    <Grid Grid.Row="1" Margin="0,0,0,8">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="2*"/>
                            <ColumnDefinition Width="6"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="6"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Button x:Name="xStart" Grid.Column="0" Height="48" Foreground="White" FontSize="13" FontWeight="Bold" Cursor="Hand">
                            <Button.Template>
                                <ControlTemplate TargetType="Button">
                                    <Border x:Name="B" CornerRadius="12">
                                        <Border.Background>
                                            <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                                                <GradientStop Color="#A3243B" Offset="0"/>
                                                <GradientStop Color="#bd2b46" Offset="1"/>
                                            </LinearGradientBrush>
                                        </Border.Background>
                                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                    </Border>
                                    <ControlTemplate.Triggers>
                                        <Trigger Property="IsEnabled" Value="False">
                                            <Setter TargetName="B" Property="Opacity" Value="0.3"/>
                                        </Trigger>
                                    </ControlTemplate.Triggers>
                                </ControlTemplate>
                            </Button.Template>
                        </Button>
                        <Button x:Name="xStop" Grid.Column="2" Height="48" Foreground="White" FontSize="12" FontWeight="SemiBold" IsEnabled="False" Cursor="Hand">
                            <Button.Template>
                                <ControlTemplate TargetType="Button">
                                    <Border x:Name="B" CornerRadius="12" Background="#5a1521">
                                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                    </Border>
                                    <ControlTemplate.Triggers>
                                        <Trigger Property="IsEnabled" Value="False">
                                            <Setter TargetName="B" Property="Opacity" Value="0.25"/>
                                        </Trigger>
                                    </ControlTemplate.Triggers>
                                </ControlTemplate>
                            </Button.Template>
                        </Button>
                        <Button x:Name="xLog" Grid.Column="4" Height="48" Foreground="{StaticResource FgDim}" FontSize="11" FontWeight="SemiBold" Cursor="Hand">
                            <Button.Template>
                                <ControlTemplate TargetType="Button">
                                    <Border CornerRadius="12" Background="{StaticResource BgCard}" BorderBrush="{StaticResource Bdr}" BorderThickness="1">
                                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                    </Border>
                                </ControlTemplate>
                            </Button.Template>
                        </Button>
                    </Grid>

                    <!-- Progress -->
                    <Grid Grid.Row="2" Margin="0,0,0,8">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>
                        <Border CornerRadius="4" Background="#1f1f28" Height="6">
                            <Border x:Name="xBar" CornerRadius="4" HorizontalAlignment="Left" Width="0">
                                <Border.Background>
                                    <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                                        <GradientStop Color="#A3243B" Offset="0"/>
                                        <GradientStop Color="#bd2b46" Offset="1"/>
                                    </LinearGradientBrush>
                                </Border.Background>
                            </Border>
                        </Border>
                        <Grid Grid.Row="1" Margin="0,5,0,0">
                            <TextBlock x:Name="xStatus" Foreground="{StaticResource FgMute}" FontSize="10.5"/>
                            <TextBlock x:Name="xTime" Foreground="{StaticResource FgMute}" FontSize="10.5" HorizontalAlignment="Right"/>
                        </Grid>
                    </Grid>

                    <!-- Log -->
                    <Border Grid.Row="3" Background="#0c0c12" CornerRadius="14" BorderBrush="{StaticResource Bdr}" BorderThickness="1" MinHeight="200">
                        <Grid Margin="14">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>
                            <TextBlock x:Name="xLogHdr" Foreground="{StaticResource Fg}" FontSize="12" FontWeight="SemiBold" Margin="0,0,0,8"/>
                            <TextBox x:Name="xLogBox" Grid.Row="1"
                                     Background="Transparent" Foreground="#b8b8d0"
                                     FontFamily="Consolas" FontSize="10.5"
                                     IsReadOnly="True" BorderThickness="0"
                                     VerticalScrollBarVisibility="Auto" TextWrapping="Wrap"/>
                        </Grid>
                    </Border>
                </Grid>
            </Grid>
            </ScrollViewer>

            <!-- FOOTER -->
            <TextBlock x:Name="xFooter" Grid.Row="2" Foreground="#52526a" FontSize="9" Margin="20,0" VerticalAlignment="Center"/>
        </Grid>
    </Border>
</Window>
"@

# =====================================================================
# LOAD WINDOW
# =====================================================================
$reader = New-Object System.Xml.XmlNodeReader $xamlXml
$Window = [Windows.Markup.XamlReader]::Load($reader)

# App-Icon zur Laufzeit erzeugen (rotes Quadrat mit weissem J).
# Kein .ico-File noetig - wird in-memory gerendert und an $Window.Icon gehaengt.
try {
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap 64,64
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode    = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $bg = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(163,36,59))
    $g.FillRectangle($bg, 0, 0, 64, 64)
    $font = New-Object System.Drawing.Font ("Segoe UI", 36, [System.Drawing.FontStyle]::Bold)
    $fg   = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
    $sf   = New-Object System.Drawing.StringFormat
    $sf.Alignment     = [System.Drawing.StringAlignment]::Center
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
    $rect = New-Object System.Drawing.RectangleF 0,2,64,64
    $g.DrawString("J", $font, $fg, $rect, $sf)
    $g.Dispose(); $font.Dispose(); $bg.Dispose(); $fg.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $ms.Position = 0
    $bi = New-Object System.Windows.Media.Imaging.BitmapImage
    $bi.BeginInit()
    $bi.CacheOption  = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bi.StreamSource = $ms
    $bi.EndInit()
    $bi.Freeze()
    $Window.Icon = $bi
    $bmp.Dispose()
} catch {}

# Get elements
$e = @{}
$allNames = @(
    "TitleBar","xLang","xMin","xMax","xClose","xInfo","xPatch","xSched","xTitleBar",
    "xTag","xTitle","xDesc","xModHdr",
    "xRestore","xRestoreD","xIcoRestore","xTglRestore",
    "xDefender","xDefenderD","xIcoDefender","xTglDefender",
    "xWinUpdate","xWinUpdateD","xIcoWinUpdate","xTglWinUpdate",
    "xDrivers","xDriversD","xIcoDrivers","xTglDrivers",
    "xWinget","xWingetD","xIcoWinget","xTglWinget",
    "xStoreApps","xStoreAppsD","xIcoStore","xTglStore",
    "xRepair","xRepairD","xIcoRepair","xTglRepair",
    "xNetwork","xNetworkD","xIcoNetwork","xTglNetwork",
    "xCleanup","xCleanupD","xIcoCleanup","xTglCleanup",
    "xStart","xStop","xLog",
    "xBar","xStatus","xTime",
    "xLogHdr","xLogBox",
    "xEnvLbl","xEnvInfo","xFooter"
)
foreach ($n in $allNames) { $e[$n] = $Window.FindName($n) }

# =====================================================================
# LANGUAGE
# =====================================================================
function Update-UI {
    $e.xTitleBar.Text = T "Title"
    $e.xTag.Text      = T "Tag"
    $e.xTitle.Text     = T "Title"
    $e.xDesc.Text      = T "Desc"
    $e.xModHdr.Text    = T "Modules"
    $e.xStart.Content  = T "Start"
    $e.xStop.Content   = T "Stop"
    $e.xLog.Content    = T "OpenLog"
    $e.xLogHdr.Text    = T "LiveLog"
    $e.xEnvLbl.Text    = T "Env"
    $e.xFooter.Text    = "v$($script:JUVersion)  -  " + (T "Footer")
    $e.xStatus.Text    = T "Ready"
    $e.xRestore.Text   = T "Restore";   $e.xRestoreD.Text   = T "RestoreD"
    $e.xDefender.Text  = T "Defender";  $e.xDefenderD.Text  = T "DefenderD"
    $e.xWinUpdate.Text = T "WinUpdate"; $e.xWinUpdateD.Text = T "WinUpdateD"
    $e.xDrivers.Text   = T "Drivers";  $e.xDriversD.Text   = T "DriversD"
    $e.xWinget.Text    = T "Winget";   $e.xWingetD.Text    = T "WingetD"
    $e.xStoreApps.Text = T "StoreApps"; $e.xStoreAppsD.Text = T "StoreAppsD"
    $e.xRepair.Text    = T "Repair";   $e.xRepairD.Text    = T "RepairD"
    $e.xNetwork.Text   = T "Network";  $e.xNetworkD.Text   = T "NetworkD"
    $e.xCleanup.Text   = T "Cleanup";  $e.xCleanupD.Text   = T "CleanupD"
}

# Icon map
$script:Icons = @{
    Restore="R"; Defender="D"; WinUpdate="W"; Drivers="T"
    Winget="A"; Store="S"; Repair="F"; Network="N"; Cleanup="C"
}
$script:IconElements = @{
    Restore=$e.xIcoRestore; Defender=$e.xIcoDefender; WinUpdate=$e.xIcoWinUpdate; Drivers=$e.xIcoDrivers
    Winget=$e.xIcoWinget; Store=$e.xIcoStore; Repair=$e.xIcoRepair; Network=$e.xIcoNetwork; Cleanup=$e.xIcoCleanup
}
# Text-Elemente der Module (links im Panel) - werden zusammen mit dem Icon umgefaerbt,
# damit der User den Status auch am Wort und nicht nur am Buchstaben sieht.
$script:TextElements = @{
    Restore=$e.xRestore; Defender=$e.xDefender; WinUpdate=$e.xWinUpdate; Drivers=$e.xDrivers
    Winget=$e.xWinget; Store=$e.xStoreApps; Repair=$e.xRepair; Network=$e.xNetwork; Cleanup=$e.xCleanup
}
# Modul-ID -> Toggle-Schalter. Grundlage fuer Settings-Persistenz und Auto-Modus.
$script:ToggleMap = @{
    Restore=$e.xTglRestore; Defender=$e.xTglDefender; WinUpdate=$e.xTglWinUpdate; Drivers=$e.xTglDrivers
    Winget=$e.xTglWinget; Store=$e.xTglStore; Repair=$e.xTglRepair; Network=$e.xTglNetwork; Cleanup=$e.xTglCleanup
}

# =====================================================================
# SETTINGS-PERSISTENZ: Modul-Auswahl + Sprache ueberleben den Neustart.
# Liegt im (verifiziert beschreibbaren) Log-Ordner als settings.json.
# Komplett gekapselt - ein Defekt hier darf den App-Start NIE verhindern.
# =====================================================================
$script:SettingsPath = Join-Path $LogDir "settings.json"
function Save-JUSettings {
    try {
        $mods = @{}
        foreach ($k in $script:ToggleMap.Keys) { $mods[$k] = [bool]$script:ToggleMap[$k].IsChecked }
        $s = [pscustomobject]@{ lang = $script:Lang; modules = [pscustomobject]$mods }
        [IO.File]::WriteAllText($script:SettingsPath, ($s | ConvertTo-Json -Depth 4),
            (New-Object System.Text.UTF8Encoding($false)))
    } catch {}
}
function Restore-JUSettings {
    try {
        if (-not (Test-Path $script:SettingsPath)) { return }
        $s = Get-Content $script:SettingsPath -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($s.lang -and $script:TR.ContainsKey([string]$s.lang)) {
            foreach ($item in $e.xLang.Items) {
                if ($item.Tag -eq [string]$s.lang) { $e.xLang.SelectedItem = $item; break }
            }
            $script:Lang = [string]$s.lang
        }
        if ($s.modules) {
            foreach ($k in @($script:ToggleMap.Keys)) {
                $p = $s.modules.PSObject.Properties[$k]
                if ($null -ne $p) { $script:ToggleMap[$k].IsChecked = [bool]$p.Value }
            }
        }
    } catch {}
}

function Set-ModIcon([string]$id, [string]$state) {
    $ico = $script:IconElements[$id]
    $txt = $script:TextElements[$id]
    if (-not $ico) { return }
    $ico.Dispatcher.Invoke([Action]{
        $brush = $null
        switch ($state) {
            "run"  {
                $ico.Text = "..."
                $brush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#A3243B")
            }
            "ok"   {
                $ico.Text = [string][char]0x2713
                $brush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#22C55E")
            }
            "warn" {
                $ico.Text = "!"
                $brush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#e8a020")
            }
            "err"  {
                $ico.Text = "X"
                $brush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#EF4444")
            }
            default {
                $ico.Text = $script:Icons[$id]
                $brush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#A3243B")
            }
        }
        $ico.Foreground = $brush
        # Bei "default" bleibt der Text-Block in Standard-Fg (weiss/grau), sonst Status-Farbe:
        if ($txt) {
            if ($state -eq "default" -or [string]::IsNullOrEmpty($state)) {
                $txt.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#ededf2")
            } else {
                $txt.Foreground = $brush
            }
        }
    })
}

function Reset-AllIcons {
    foreach ($k in $script:Icons.Keys) {
        $ico = $script:IconElements[$k]
        $txt = $script:TextElements[$k]
        if ($ico) {
            $ico.Text = $script:Icons[$k]
            $ico.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#A3243B")
        }
        if ($txt) {
            $txt.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#ededf2")
        }
    }
}

# =====================================================================
# INIT
# =====================================================================
Update-UI
# Gespeicherte Modul-Auswahl + Sprache wiederherstellen (settings.json).
# Nach Update-UI, damit ein Sprach-Wechsel die Texte gleich mit umstellt.
Restore-JUSettings

try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $cpu = (Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1).Name
    $ram = [Math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $e.xEnvInfo.Text = "$($os.Caption) | $($os.Version) | $([Environment]::MachineName) | $cpu | $($ram) GB RAM"
} catch {
    $e.xEnvInfo.Text = "$([Environment]::OSVersion.VersionString) | $([Environment]::MachineName)"
}

# Window chrome
$e.TitleBar.Add_MouseLeftButtonDown({
    if ($_.ClickCount -eq 2) {
        if ($Window.WindowState -eq "Maximized") {
            $Window.WindowState = "Normal"
            $e.xMax.Content = [char]0x2610
        } else {
            $Window.WindowState = "Maximized"
            $e.xMax.Content = [char]0x2397
        }
    } elseif ($_.ChangedButton -eq "Left") {
        $Window.DragMove()
    }
})
$e.xClose.Add_Click({ $Window.Close() })
$e.xMax.Add_Click({
    if ($Window.WindowState -eq "Maximized") {
        $Window.WindowState = "Normal"
        $e.xMax.Content = [char]0x2610
    } else {
        $Window.WindowState = "Maximized"
        $e.xMax.Content = [char]0x2397
    }
})
$e.xMin.Add_Click({ $Window.WindowState = "Minimized" })
# Schliessen-Schutz: X-Klick/Alt-F4 waehrend laufender Wartung killte den Lauf
# bisher kommentarlos (Runspace mitten in einer Update-Installation weg).
# Jetzt: nachfragen, bei Ja sauber stoppen. Settings werden immer gespeichert.
$Window.Add_Closing({
    param($sender2, $ev)
    $running = ($script:SyncHash -and -not $script:SyncHash.Done -and -not $script:SessionEnded)
    if ($running -and -not $script:AutoMode) {
        $a = [System.Windows.MessageBox]::Show(
            "Die Wartung laeuft noch - ein Abbruch kann eine Update-Installation mittendrin stoppen.`n`nWirklich abbrechen und beenden?",
            "JustUpdate - Wartung laeuft",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning)
        if ($a -ne [System.Windows.MessageBoxResult]::Yes) { $ev.Cancel = $true; return }
        try { End-Session } catch {}
    }
    try { Save-JUSettings } catch {}
})
$e.xLang.Add_SelectionChanged({
    $tag = $this.SelectedItem.Tag
    if ($tag) { $script:Lang = $tag; Update-UI }
})

# =====================================================================
# MAINTENANCE ENGINE
# =====================================================================
$script:SyncHash   = $null
$script:Pipeline   = $null
$script:Runspace   = $null
$script:UITimer    = $null
$script:ClockTimer = $null
$script:StartTime  = $null

# Update-Blocker: oft als Tray/Helper aktiv, sperren Installer-Dateien.
# Wildcards (-like) erlaubt — wichtig fuer App-Familien wie OBS, die
# mehrere Helper-Prozesse mitlaufen lassen (obs-ffmpeg-mux, obs-amf-test,
# OBS-Studio-Updater etc.), die der User nicht sieht aber den Winget-
# Installer mit "Datei in Verwendung" / Exit 1603/6 blockieren.
# EINE Quelle fuer Haupt-Thread UND Worker-Runspace (geht via $sync mit) -
# vorher stand die Liste doppelt im Code und konnte auseinanderlaufen.
$script:TrayBlockers = @(
    "obs*",                                                 # alle OBS-Familien-Prozesse
    "EpicGamesLauncher","EpicWebHelper","UnrealCEFSubProcess",
    "Steam","steamwebhelper","GameOverlayUI",
    "Discord","DiscordPTB","DiscordCanary",
    "Spotify","SpotifyWebHelper",
    "Teams","ms-teams","msedgewebview2",
    "OneDrive","FileCoAuth","FileSyncHelper",
    "Slack",
    "Code","Code - Insiders",
    "Cursor",
    "Zoom","ZoomLauncher",
    "WhatsApp",
    "Telegram"
)

function Close-RunningUserApps {
    # Schliesst GUI-Prozesse mit Hauptfenster — sanft via CloseMainWindow().
    # Zusaetzlich: bekannte Update-Blocker, die im Tray OHNE MainWindow laufen
    # (OBS-Helper, Epic-Launcher etc.) — die sperren ihre Installer-Dateien und
    # liessen v2.6.4 mit winget Exit 1603/6 (file-in-use) auflaufen.
    # Ausgenommen: System-Prozesse, Shell, JustUpdate selbst.
    $whitelist = @(
        "explorer","dwm","conhost","powershell","pwsh","cmd","WindowsTerminal",
        "wininit","winlogon","csrss","smss","services","lsass","svchost",
        "fontdrvhost","SearchHost","StartMenuExperienceHost","ShellExperienceHost",
        "TextInputHost","RuntimeBroker","ApplicationFrameHost","SecurityHealthSystray"
    )
    $trayBlockers = $script:TrayBlockers
    $myPid = $PID
    $closedNames = New-Object System.Collections.Generic.HashSet[string]
    # 1) Apps mit sichtbarem Fenster sanft schliessen (CloseMainWindow -> "Speichern?")
    Get-Process | Where-Object {
        $_.Id -ne $myPid -and
        $_.MainWindowHandle -ne 0 -and
        $whitelist -notcontains $_.ProcessName
    } | ForEach-Object {
        try {
            [void]$_.CloseMainWindow()
            [void]$closedNames.Add($_.ProcessName)
        } catch {}
    }
    # 2) Tray-only Update-Blocker hart beenden — sie haben kein MainWindow,
    #    halten aber Installer-Dateien gelockt. Stop-Process ohne Confirm.
    #    -like-Match unterstuetzt Wildcards (z.B. 'obs*' fuer OBS-Familie).
    Get-Process | Where-Object {
        $pn = $_.ProcessName
        $_.Id -ne $myPid -and
        (@($trayBlockers | Where-Object { $pn -like $_ }).Count -gt 0)
    } | ForEach-Object {
        try {
            Stop-Process -Id $_.Id -Force -ErrorAction Stop
            [void]$closedNames.Add($_.ProcessName)
        } catch {}
    }
    # Kurz warten, damit Apps ihre "Speichern?"-Dialoge anzeigen koennen und
    # File-Handles freigegeben werden.
    Start-Sleep -Seconds 3
    # Names-Liste sortiert zurueck, damit der User im Log sieht WAS geschlossen
    # wurde (statt nur eine Zahl). PSCustomObject fuer alte Aufrufer kompatibel:
    # [int] cast greift auf .Count zu (impliziet via PowerShell-Coercion bleibt
    # aber unsauber) — daher explizit beides bereitstellen.
    return [pscustomobject]@{
        Count = $closedNames.Count
        Names = @($closedNames | Sort-Object)
    }
}

function Start-Maintenance {
    # Vor Update-Modulen: User fragen, ob laufende Apps geschlossen werden sollen.
    # Verhindert dass Update-Installer sich an gesperrten Dateien aufhaengen.
    # Winget mit reingenommen: Hauptursache fuer file-in-use sind Tray-Apps wie
    # OBS/Epic, die ueber winget aktualisiert werden.
    # Aktuelle Auswahl direkt sichern - so laeuft der naechste (auch geplante)
    # Lauf garantiert mit dem, was der User zuletzt eingestellt hat.
    Save-JUSettings

    $needsClose = ([bool]$e.xTglWinUpdate.IsChecked) -or `
                  ([bool]$e.xTglStore.IsChecked) -or `
                  ([bool]$e.xTglWinget.IsChecked)
    if ($needsClose -and $script:AutoMode) {
        # Automatik-Modus: NIEMALS ungefragt Programme schliessen (ungespeicherte
        # Daten!). Updates, die an gesperrten Dateien scheitern, holt der
        # naechste manuelle Lauf nach. -2 = Marker "Auto-Modus, nicht gefragt".
        $script:ClosedAppCount = -2
        $script:ClosedAppNames = @()
    } elseif ($needsClose) {
        $answer = [System.Windows.MessageBox]::Show(
            (T "CloseAppsMsg"),
            (T "CloseAppsTitle"),
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning)
        if ($answer -eq [System.Windows.MessageBoxResult]::Yes) {
            $closeResult = Close-RunningUserApps
            $script:ClosedAppCount = [int]$closeResult.Count
            $script:ClosedAppNames = @($closeResult.Names)
        } else {
            $script:ClosedAppCount = -1
            $script:ClosedAppNames = @()
        }
    } else {
        $script:ClosedAppCount = $null
        $script:ClosedAppNames = $null
    }

    Reset-AllIcons
    $e.xLogBox.Clear()
    try { $e.xBar.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty, $null) } catch {}
    $e.xBar.Width = 0
    $script:LastBarTarget = 0
    $e.xTime.Text = "00:00"
    $script:StartTime = Get-Date
    $script:SessionEnded = $false   # Reentrancy-Guard fuer End-Session zuruecksetzen

    $e.xStart.IsEnabled = $false
    $e.xStop.IsEnabled  = $true
    $e.xStatus.Text = T "Running"

    $cfg = @{
        Restore   = [bool]$e.xTglRestore.IsChecked
        Defender  = [bool]$e.xTglDefender.IsChecked
        WinUpdate = [bool]$e.xTglWinUpdate.IsChecked
        Drivers   = [bool]$e.xTglDrivers.IsChecked
        Winget    = [bool]$e.xTglWinget.IsChecked
        Store     = [bool]$e.xTglStore.IsChecked
        Repair    = [bool]$e.xTglRepair.IsChecked
        Network   = [bool]$e.xTglNetwork.IsChecked
        Cleanup   = [bool]$e.xTglCleanup.IsChecked
    }

    $sync = [hashtable]::Synchronized(@{
        Config         = $cfg
        LogPath        = $script:LogPath
        Stop           = $false
        Done           = $false
        Lines          = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
        Progress       = 0
        ModuleQueue    = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
        Results        = [hashtable]::Synchronized(@{})
        ClosedAppCount = $script:ClosedAppCount
        ClosedAppNames = $script:ClosedAppNames
        AppVersion     = $script:JUVersion
        TrayBlockers   = @($script:TrayBlockers)
        AutoMode       = $script:AutoMode
        RebootRequired = $false
    })
    $script:SyncHash = $sync

    $rs = [RunspaceFactory]::CreateRunspace()
    $rs.ApartmentState = "STA"
    $rs.Open()
    $rs.SessionStateProxy.SetVariable("sync", $sync)
    $script:Runspace = $rs

    $ps = [PowerShell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({
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
            $m2 = [int]($secs / 60); $s2 = $secs % 60
            $dTxt = if ($m2 -gt 0) { "${m2}m ${s2}s" } else { "${s2}s" }
            L "  (Modul-Dauer: $dTxt)"
            try {
                if ($sync.Results.ContainsKey($script:CurModule)) {
                    $sync.Results[$script:CurModule].DurationSeconds = $secs
                }
            } catch {}
            $script:CurModule = $null
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
                    $min = [int]($elapsed / 60); $sec = $elapsed % 60
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
                    $isDriver = $false
                    foreach ($cat in $_.Categories) { if ($cat.Type -eq "Driver") { $isDriver = $true; break } }
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
                $drvResult = $searcher.Search("IsInstalled=0 AND Type='Driver'")

                if ($drvResult.Updates.Count -eq 0) {
                    L "  [OK] Alle Treiber sind auf dem neuesten Stand"
                    Mark "Drivers" "ok" "keine Treiber-Updates verfuegbar"
                } else {
                    L "  $($drvResult.Updates.Count) Treiber-Update(s) gefunden:"
                    L ""
                    $dColl = New-Object -ComObject Microsoft.Update.UpdateColl
                    $drvNum = 1
                    foreach ($d in $drvResult.Updates) {
                        L "    [$drvNum/$($drvResult.Updates.Count)] $($d.Title)"
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
                    if ($dlRes.ResultCode -eq 2) {
                        L "  [OK] Download abgeschlossen"
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

                    $drvOk = 0; $drvFail = 0
                    $reportedOk = @()  # Treiber, die WUA als OK meldet — die werden gleich verifiziert
                    for ($idx = 0; $idx -lt $dColl.Count; $idx++) {
                        $uResult = $r.GetUpdateResult($idx)
                        $status = switch ($uResult.ResultCode) { 2 {"OK"} 3 {"OK (Warnung)"} 4 {"FEHLGESCHLAGEN"} default {"Status $($uResult.ResultCode)"} }
                        L "    [$status] $($dColl.Item($idx).Title)"
                        if ($uResult.ResultCode -eq 2 -or $uResult.ResultCode -eq 3) {
                            $drvOk++
                            $reportedOk += $dColl.Item($idx).Title
                        } else { $drvFail++ }
                    }
                    if ($r.RebootRequired) { L "  >>> NEUSTART ERFORDERLICH <<<"; $sync.RebootRequired = $true }

                    # FIX v2.3.3: Verifikation - WUA-ResultCode=2 luegt bei optionalen/superseded Treibern.
                    # Re-Search; was immer noch IsInstalled=0 ist, wurde NICHT wirklich installiert.
                    # Fallback: pnputil mit den heruntergeladenen Treiber-Dateien (Microsoft-signiert).
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
                                        $reallyPending = @($reResult.Updates | Where-Object { $stillPending -contains $_.Title } | ForEach-Object { $_.Title })
                                    } catch {
                                        L "  [WARNUNG] Re-Verifikation nach pnputil fehlgeschlagen - werte haengende Treiber als offen"
                                    }
                                    # Inkrementell gegen die WUA-Zaehler verrechnen (wie der
                                    # No-Cache-Zweig) - NICHT mit $dColl.Count ueberschreiben,
                                    # sonst gingen echte WUA-Fehlschlaege aus der Install-Schleife
                                    # verloren.
                                    $drvFail += @($reallyPending).Count
                                    $drvOk    = [Math]::Max(0, $drvOk - @($reallyPending).Count)
                                    if (@($reallyPending).Count -gt 0) {
                                        L "  [WARNUNG] $(@($reallyPending).Count) Treiber haengen weiterhin (auch nach pnputil):"
                                        foreach ($t in $reallyPending) { L "    - $t" }
                                    }
                                } else {
                                    L "  [WARNUNG] Kein Treiber-Cache fuer pnputil-Fallback vorhanden"
                                    $drvFail += $stillPending.Count
                                    $drvOk = [Math]::Max(0, $drvOk - $stillPending.Count)
                                }
                            }
                        } catch {
                            L "  [WARNUNG] Verifikation fehlgeschlagen: $($_.Exception.Message)"
                        }
                    }

                    if ($drvFail -eq 0) {
                        Mark "Drivers" "ok" "$drvOk Treiber installiert (verifiziert)"
                    } elseif ($drvOk -gt 0) {
                        Mark "Drivers" "warn" "$drvOk von $($dColl.Count) Treibern installiert, $drvFail haengen (siehe Optionale Updates)"
                    } else {
                        Mark "Drivers" "err" "Alle $($dColl.Count) Treiber-Updates fehlgeschlagen"
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
                    $null = Invoke-MonitoredProcess -FileName $wg `
                              -Arguments "source update --disable-interactivity" -TimeoutSec 120

                    L "  Pruefe verfuegbare Updates..."
                    L ""

                    # Zuerst zeigen was verfuegbar ist
                    $listOut = & $wg upgrade --accept-source-agreements 2>&1
                    $listOut | ForEach-Object {
                        $l = "$_".Trim()
                        if ($l.Length -gt 2 -and -not (IsProgressNoise $l)) { L "    $l" }
                    }
                    L ""
                    L "  Starte Upgrade aller Apps..."
                    L ""

                    # Erfolgs-Erkennung. NEBEN dem klaren "Erfolgreich installiert" gibt
                    # es Pakete (z.B. Claude, Microsoft Teams, Edge-basierte Apps), die
                    # melden "Die Installation war erfolgreich. Starten Sie die Anwendung
                    # neu, um das Upgrade abzuschliessen." - das ist KEIN Fehler, sondern
                    # ein erfolgreicher Update der nur noch einen App-Neustart braucht.
                    # Frueher fiel dieser Satz durch alle Parser-Branches, das Paket blieb
                    # in $cur haengen und wurde beim naechsten "(N/M) Gefunden" faelschlich
                    # als fehlgeschlagen verbucht. Beide Phrasen zaehlen jetzt als Erfolg.
                    $okRx = 'Successfully installed|Erfolgreich installiert|Installation reussie|Die Installation war erfolgreich|installation was successful|Restart the application to complete|Starten Sie die Anwendung neu|Redemarrez l.application'
                    # Untermenge von $okRx: erfolgreich, aber App-Neustart noch offen.
                    $restartRx = 'Restart the application to complete|Starten Sie die Anwendung neu|Redemarrez l.application'

                    # Inline-Parser: Output-Stream auswerten und pro Paket Status sammeln.
                    # Wichtig fuer in-use-Retry: wir muessen wissen WELCHE Apps wegen
                    # "Datei in Verwendung" gescheitert sind (Exit 1603/6 oder Klartext).
                    $parseWg = {
                        param([string[]]$Lines)
                        $fail = @(); $ok = @(); $cur = $null
                        $inUseRx = 'einer anderen Anwendung verwendet|in use by another|currently being used|being used by another'
                        foreach ($raw in $Lines) {
                            $t = "$raw".Trim()
                            if ($t -match '^\(\d+/\d+\)\s+(?:Gefunden|Found|Trouve)\s+(.+?)\s+\[([^\]]+)\]') {
                                if ($cur) { $fail += $cur }
                                $cur = @{ Name = $Matches[1].Trim(); Id = $Matches[2].Trim(); Exit = $null; InUse = $false; Restart = $false }
                            }
                            elseif ($t -match $inUseRx) {
                                if ($cur) { $cur.InUse = $true }
                            }
                            elseif ($t -match '(?:Installation fehlgeschlagen mit Exitcode|Installer failed with exit code|Installation echouee avec le code de sortie)\D*(-?\d+)') {
                                if ($cur) {
                                    $cur.Exit = [int]$Matches[1]
                                    if ($cur.Exit -in 1603,6,1618,1638) { $cur.InUse = $true }
                                    $fail += $cur; $cur = $null
                                }
                            }
                            elseif ($t -match $okRx) {
                                if ($cur) {
                                    if ($t -match $restartRx) { $cur.Restart = $true }
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
                               -TimeoutSec 3600
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
                        Get-Process -ErrorAction SilentlyContinue | Where-Object {
                            $pn = $_.ProcessName
                            (@($retryBlockers | Where-Object { $pn -like $_ }).Count -gt 0)
                        } | ForEach-Object {
                            try { Stop-Process -Id $_.Id -Force -ErrorAction Stop } catch {}
                        }

                        # AGGRESSIVER 2. PASS: pro fehlgeschlagenes Paket auch
                        # alle Prozesse killen, deren EXE-Pfad zum Paket-Namen
                        # passt. Behebt den Fall aus dem User-Log: OBS-Studio
                        # hatte Helper laufen, die NICHT mit "obs" beginnen
                        # (Auto-Update-Service, Streamlabs-Plugin, etc.) - die
                        # tauchten nicht in der Wildcard-Liste auf, blockierten
                        # den Installer aber trotzdem.
                        foreach ($pkg in $inUseFails) {
                            # Paket-Schluesselwort raus: "OBSProject.OBSStudio"
                            # -> Suchbegriffe "OBSStudio", "OBSProject", "OBS"
                            $kw = @()
                            if ($pkg.Name) { $kw += ($pkg.Name -split '\W+' | Where-Object { $_.Length -ge 3 }) }
                            if ($pkg.Id)   { $kw += ($pkg.Id   -split '[\W_]+' | Where-Object { $_.Length -ge 3 }) }
                            $kw = @($kw | Sort-Object -Unique)
                            $killed = New-Object System.Collections.Generic.List[string]
                            foreach ($p in Get-Process -ErrorAction SilentlyContinue) {
                                try {
                                    $path = $p.Path
                                    if (-not $path) { continue }
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
                            # Windows-Services mit passendem Namen stoppen — OBS-
                            # Studio installiert keinen Service standardmaessig,
                            # aber Plugins/Updater-Tools tun es manchmal.
                            foreach ($k in $kw) {
                                try {
                                    Get-Service -ErrorAction SilentlyContinue |
                                        Where-Object { $_.Name -like "*$k*" -or $_.DisplayName -like "*$k*" } |
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
                                   -TimeoutSec 1800
                            $rOut = $r.Lines -join " "
                            if ($r.ExitCode -eq 0 -and ($rOut -match $okRx)) {
                                L "    [OK] $($pkg.Name) im Retry aktualisiert"
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
                        $null = $svcMgr.AddService2($storeServiceId, 7, "")
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
                            if ($installedCount -eq $storeInst.Count) { $storeOk = $true }
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

        # ── REPAIR ──
        if ($cfg.Repair) {
            if (IsStopped) { $sync.Done = $true; return }
            M "Repair" "run"
            L "--------------------------------------------"
            L "  MODUL $($i+1)/${total}: System-Reparatur"
            L "--------------------------------------------"
            try {
                L "  Schritt 1/2: SFC (System File Checker)"
                L "  Pruefe Integritaet der Systemdateien..."
                L "  (Bricht nach 30 Min ohne Reaktion automatisch ab)"
                L ""

                # SFC gibt UTF-16 LE aus - sonst bekommen wir Gibberish.
                # Ueberwacht mit 30-Min-Timeout, damit ein haengendes sfc.exe die
                # Wartung nicht endlos blockiert (Bug: 145 Min ohne Reaktion).
                $sfcRun = Invoke-MonitoredProcess -FileName "sfc.exe" -Arguments "/scannow" `
                            -TimeoutSec 1800 -OutEncoding ([System.Text.Encoding]::Unicode)
                $sfcExit     = $sfcRun.ExitCode
                $sfcTimedOut = $sfcRun.TimedOut
                # Pending-Reboot wird von sfc.exe mit Exit-Code 1 + Meldung "Systemreparatur aus" /
                # "Neustart erfordert" / "pending system repair" gemeldet. Das ist kein Fehler — SFC
                # konnte legitim nicht laufen, weil ein vorheriger CBS-Vorgang noch nicht durch ist.
                $sfcCombined = ($sfcRun.Lines -join " ")
                $sfcPending = (-not $sfcTimedOut) -and ($sfcExit -ne 0) -and ($sfcCombined -match 'Systemreparatur aus|Neustart erfordert|pending system repair|requires a restart')
                $sfcOk = (-not $sfcTimedOut) -and ($sfcExit -eq 0)
                if ($sfcOk) {
                    L "  [OK] SFC abgeschlossen"
                } elseif ($sfcTimedOut) {
                    L "  [WARNUNG] SFC reagierte 30 Min nicht - abgebrochen und uebersprungen"
                } elseif ($sfcPending) {
                    L "  [WARNUNG] SFC uebersprungen - Neustart erforderlich, dann erneut ausfuehren"
                    $sync.RebootRequired = $true
                } else {
                    L "  [FEHLER] SFC fehlgeschlagen (Exit-Code: $sfcExit)"
                }

                L ""
                L "  Schritt 2/2: DISM (Deployment Image Servicing)"
                L "  Repariere Windows-Komponentenspeicher..."
                L "  (Bricht nach 45 Min ohne Reaktion automatisch ab)"
                L ""

                # DISM emittiert OEM-Codepage (CP850 auf DE-Locale), nicht UTF-8.
                # 45-Min-Timeout: DISM /restorehealth haengt sich klassisch auf, wenn
                # der Komponentenspeicher beschaedigt ist oder Windows Update nicht
                # erreichbar ist - genau die Ursache fuer den 145-Min-Hang.
                # Heartbeat: DISM gibt KEINE Progress-Zeilen aus (anders als WUA/winget) —
                # ohne Heartbeat sieht der User 45 Min lang absolut nichts.
                $dismHb = Start-Heartbeat "    DISM-Repair " 30
                $dismRun = Invoke-MonitoredProcess -FileName "dism.exe" `
                             -Arguments "/online /cleanup-image /restorehealth" `
                             -TimeoutSec 2700 -OutEncoding $oemEnc
                Stop-Heartbeat $dismHb
                $dismExit     = $dismRun.ExitCode
                $dismTimedOut = $dismRun.TimedOut

                # v2.6.4: Retry bei Exit 32 (ERROR_SHARING_VIOLATION). Klassische
                # Ursache: ein Antivirus (HP Wolf, Defender Real-Time, Drittanbieter)
                # scannt parallel eine Datei aus dem Komponentenspeicher und hat sie
                # gelockt. 45 Sekunden reichen meistens, damit der Scan fertig ist.
                # Wir versuchen es genau einmal nochmal - laenger zu warten lohnt
                # nicht, dann ist's vermutlich kein vorvoruebergehender Lock mehr.
                if (-not $dismTimedOut -and $dismExit -eq 32) {
                    L "  [HINWEIS] DISM meldet Datei-Konflikt (Exit 32) - typisch bei aktivem Antivirus."
                    L "           Warte 45 Sekunden und versuche es nochmal..."
                    Start-Sleep -Seconds 45
                    $dismRun = Invoke-MonitoredProcess -FileName "dism.exe" `
                                 -Arguments "/online /cleanup-image /restorehealth" `
                                 -TimeoutSec 2700 -OutEncoding $oemEnc
                    $dismExit     = $dismRun.ExitCode
                    $dismTimedOut = $dismRun.TimedOut
                }

                $dismOk = (-not $dismTimedOut) -and ($dismExit -eq 0)
                if ($dismOk) {
                    L "  [OK] DISM abgeschlossen"
                } elseif ($dismTimedOut) {
                    L "  [WARNUNG] DISM reagierte 45 Min nicht - abgebrochen und uebersprungen"
                } elseif ($dismExit -eq 32) {
                    L "  [FEHLER] DISM auch nach Retry mit Datei-Konflikt (Exit 32)"
                    L "         Tipp: Antivirus voruebergehend pausieren und JustUpdate erneut starten"
                } else {
                    L "  [FEHLER] DISM fehlgeschlagen (Exit-Code: $dismExit)"
                }

                L ""
                if ($sfcOk -and $dismOk) {
                    L "  [OK] System-Reparatur abgeschlossen"
                    Mark "Repair" "ok" "SFC + DISM erfolgreich"
                } elseif ($sfcPending -and $dismOk) {
                    L "  [WARNUNG] DISM OK - SFC braucht Neustart, dann erneut ausfuehren"
                    Mark "Repair" "warn" "Kein echter Fehler: Eine fruehere Windows-Reparatur ist noch offen. Bitte den PC neu starten und JustUpdate danach nochmal ausfuehren."
                } elseif ($sfcTimedOut -or $dismTimedOut) {
                    $slow = @(); if ($sfcTimedOut) { $slow += "SFC" }; if ($dismTimedOut) { $slow += "DISM" }
                    L "  [WARNUNG] System-Reparatur abgebrochen (Zeitueberschreitung: $($slow -join ' + '))"
                    Mark "Repair" "warn" "$($slow -join ' + ') hat zu lange nicht reagiert und wurde nach dem Zeitlimit abgebrochen. Meist nur voruebergehend - bitte den PC neu starten und JustUpdate spaeter erneut ausfuehren."
                } elseif ($sfcOk -or $dismOk) {
                    $who = if ($sfcOk) { "DISM" } else { "SFC" }
                    L "  [WARNUNG] Teilweise erfolgreich - $who fehlgeschlagen"
                    Mark "Repair" "warn" "$who konnte nicht abgeschlossen werden (der andere Teil war erfolgreich). Bitte JustUpdate als Administrator erneut ausfuehren."
                } else {
                    L "  [FEHLER] SFC und DISM fehlgeschlagen - Admin-Rechte pruefen"
                    Mark "Repair" "err" "SFC und DISM fehlgeschlagen - bitte JustUpdate als Administrator starten (Rechtsklick > Als Administrator ausfuehren)."
                }
            } catch {
                L "  [FEHLER] $($_.Exception.Message)"
                Mark "Repair" "err" $_.Exception.Message
            }
            Finish-Module
            $i++; P ($i / $total * 100)
            L ""
        }

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
                        Get-ChildItem $wuCache -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                            if (-not $_.PSIsContainer -and $_.LastWriteTime -gt $cutoff) {
                                $skipped++
                            } else {
                                try { Remove-Item $_.FullName -Force -Recurse -ErrorAction Stop } catch {}
                            }
                        }
                        foreach ($svcName in $stoppedSvcs) {
                            try { Start-Service -Name $svcName -ErrorAction Stop } catch {}
                        }
                        if ($skipped -gt 0) {
                            L "    [OK] $sz MB bereinigt ($skipped frische Dateien geschont fuer laufende Downloads)"
                        } else {
                            L "    [OK] $sz MB freigegeben"
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

        P 100
        L "============================================"
        L "  ZUSAMMENFASSUNG"
        L "============================================"
        # Klartext-Namen fuers Abschluss-Popup - der Kunde soll auf einen Blick sehen
        # WELCHES Modul WARUM gewarnt/fehlgeschlagen ist, ohne erst das Log zu oeffnen.
        $friendlyName = @{
            Restore="Wiederherstellungspunkt"; Defender="Defender aktualisieren"
            WinUpdate="Windows Updates";       Drivers="Treiber aktualisieren"
            Winget="Apps aktualisieren";       Store="Microsoft Store Apps"
            Repair="System-Reparatur";         Network="Netzwerk reparieren"
            Cleanup="Bereinigung"
        }
        $okCount = 0; $warnCount = 0; $errCount = 0
        $issueLines = New-Object System.Collections.Generic.List[string]
        foreach ($modId in $active) {
            $fn = if ($friendlyName.ContainsKey($modId)) { $friendlyName[$modId] } else { $modId }
            if ($sync.Results.ContainsKey($modId)) {
                $r = $sync.Results[$modId]
                $prefix = switch ($r.Status) {
                    "ok"   { $okCount++;   "[OK]  " }
                    "warn" { $warnCount++; "[!]   " }
                    "err"  { $errCount++;  "[FAIL]" }
                    default { "[?]   " }
                }
                L "  $prefix $modId - $($r.Details)"
                if ($r.Status -eq "warn") { $issueLines.Add("WARNUNG - ${fn}:`n   $($r.Details)") }
                elseif ($r.Status -eq "err") { $issueLines.Add("FEHLER - ${fn}:`n   $($r.Details)") }
            } else {
                L "  [?]    $modId - kein Ergebnis"
                $issueLines.Add("FEHLER - ${fn}:`n   Kein Ergebnis - das Modul wurde nicht sauber beendet.")
                $errCount++
            }
        }
        $sync.SummaryDetails = ($issueLines -join "`n`n")
        L "============================================"
        L "  $okCount OK, $warnCount Warnungen, $errCount Fehler"
        if ($sync.RebootRequired) {
            L "  >>> NEUSTART ERFORDERLICH - bitte den PC zeitnah neu starten <<<"
        }
        L "  $(Get-Date -F 'dd.MM.yyyy HH:mm:ss')"
        L "============================================"
        $sync.SummaryOk   = $okCount
        $sync.SummaryWarn = $warnCount
        $sync.SummaryErr  = $errCount
        $sync.Done = $true
    })

    $script:Pipeline = $ps
    $script:AsyncResult = $ps.BeginInvoke()

    # Clock
    $script:ClockTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:ClockTimer.Interval = [TimeSpan]::FromSeconds(1)
    $script:ClockTimer.Add_Tick({
        if ($script:StartTime) {
            $el = (Get-Date) - $script:StartTime
            # Floor statt [int]-Cast: der rundet kaufmaennisch (1.5 -> 2) und
            # liess die Uhr ab Sekunde 30 jeder Minute eine Minute vorgehen.
            $e.xTime.Text = "{0:D2}:{1:D2}" -f [int][Math]::Floor($el.TotalMinutes), $el.Seconds
        }
    })
    $script:ClockTimer.Start()

    # Display-Aufbereitung NUR fuer die Live-Ansicht (xLogBox). Die Logdatei
    # bleibt 1:1 erhalten (Zeitstempel, Trennlinien, [OK]/[FEHLER] - perfekt
    # zum Auswerten). Auf dem Bildschirm soll der Mensch dagegen gefuehrt dem
    # Ablauf folgen koennen: Zeitstempel raus, Trennlinien raus, Modul-Koepfe
    # als klare "Schritt X von N"-Ueberschriften, Status-Marker als Symbole.
    # Rueckgabe $null = Zeile auf dem Bildschirm ueberspringen.
    # WICHTIG: script:-Scope. Der UI-Timer-Tick feuert ERST nachdem
    # Start-Maintenance zurueckgekehrt ist - eine nur lokal definierte Funktion
    # ist dann weg, der Aufruf wirft "nicht erkannt", und weil die Zeile oben
    # schon aus $s.Lines entfernt wurde, schluckt 'catch { break }' jede Zeile
    # -> Live-Protokoll bleibt leer. (Regression v2.7.1)
    function script:Format-LiveLine($raw) {
        if ($null -eq $raw) { return $null }
        # 1) "[HH:mm:ss] "-Praefix entfernen (live nur Rauschen).
        $t = $raw -replace '^\[\d{2}:\d{2}:\d{2}\]\s?', ''
        $trim = $t.Trim()
        # 2) Reine Trennlinien (----- / =====) ausblenden.
        if ($trim -match '^[-=]{4,}$') { return $null }
        # 3) Modul-Kopf "MODUL x/total: Name" -> gefuehrte Schritt-Ueberschrift.
        if ($trim -match '^MODUL\s+(\d+)/(\d+):\s*(.+)$') {
            return "`r`n>> Schritt $($Matches[1]) von $($Matches[2]):  $($Matches[3])`r`n"
        }
        # 4) Status-Marker am Zeilenanfang als deutliche Symbole.
        $t = $t -replace '^(\s*)\[OK\]\s*',      '$1   [ok]  '
        $t = $t -replace '^(\s*)\[FEHLER\]\s*',  '$1  [X] FEHLER:  '
        $t = $t -replace '^(\s*)\[WARNUNG\]\s*', '$1  [!] HINWEIS:  '
        $t = $t -replace '^(\s*)\[HINWEIS\]\s*', '$1  [i] '
        return $t
    }

    # UI poll
    $script:UITimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:UITimer.Interval = [TimeSpan]::FromMilliseconds(150)
    $script:UITimer.Add_Tick({
        $s = $script:SyncHash
        while ($s.Lines.Count -gt 0) {
            try {
                $line = $s.Lines[0]
                $s.Lines.RemoveAt(0)
                # Bildschirm: menschenfreundlich aufbereitet (kann Zeilen schlucken).
                $disp = Format-LiveLine $line
                if ($null -ne $disp) {
                    $e.xLogBox.AppendText("$disp`r`n")
                    $e.xLogBox.ScrollToEnd()
                }
                # Status-Zeile unter dem Balken: einzeilig, ohne Zeitstempel.
                $st = ($line -replace '^\[\d{2}:\d{2}:\d{2}\]\s?', '').Trim()
                if ($st) { $e.xStatus.Text = $st }
            } catch { break }
        }
        $pct = $s.Progress
        $pw = $e.xBar.Parent.ActualWidth
        if ($pw -gt 0) {
            $target = [Math]::Max(0, $pw * $pct / 100)
            # Nur animieren wenn sich das Ziel spuerbar aendert (sonst Re-Trigger
            # jeden 150ms-Tick -> Ruckeln). Sanftes EaseOut statt harter Sprung.
            if ($null -eq $script:LastBarTarget -or [Math]::Abs($target - $script:LastBarTarget) -gt 0.5) {
                $script:LastBarTarget = $target
                try {
                    $anim = New-Object System.Windows.Media.Animation.DoubleAnimation
                    $anim.To = $target
                    $anim.Duration = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds(450))
                    $ease = New-Object System.Windows.Media.Animation.CubicEase
                    $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
                    $anim.EasingFunction = $ease
                    $e.xBar.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty, $anim)
                } catch {
                    $e.xBar.Width = $target
                }
            }
        }
        # Queue komplett abarbeiten - jeder Status wird angezeigt, kein Update geht verloren
        while ($s.ModuleQueue.Count -gt 0) {
            try {
                $msg = [string]$s.ModuleQueue[0]
                $s.ModuleQueue.RemoveAt(0)
                if ([string]::IsNullOrEmpty($msg) -or -not $msg.Contains("|")) { continue }
                $parts = $msg -split "\|", 2
                Set-ModIcon $parts[0] $parts[1]
            } catch { break }
        }
        if ($s.Done) { End-Session -completed }
    })
    $script:UITimer.Start()
}

function Get-PatchHistoryText {
    # Versucht zuerst lokales CHANGELOG.md (neben Skript/EXE), dann GitHub raw.
    # Gibt String oder $null zurueck.
    $cands = @()
    try { $cands += (Join-Path $PSScriptRoot "CHANGELOG.md") } catch {}
    try {
        $exeDir = Split-Path -Parent $ScriptPath -ErrorAction SilentlyContinue
        if ($exeDir) { $cands += (Join-Path $exeDir "CHANGELOG.md") }
    } catch {}
    foreach ($c in $cands) {
        try {
            if ($c -and (Test-Path $c)) {
                $txt = [IO.File]::ReadAllText($c)
                if ($txt -and $txt.Length -gt 50) { return $txt }
            }
        } catch {}
    }
    # Fallback GitHub raw — beim Kunden ist meistens nur die EXE installiert,
    # nicht das CHANGELOG. Online holen, kurzer Timeout.
    try {
        $savedPP = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $resp = Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Just1n12354/JustUpdate/main/CHANGELOG.md" `
                   -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
        $ProgressPreference = $savedPP
        if ($resp -and $resp.Content) { return [string]$resp.Content }
    } catch {
        try { $ProgressPreference = $savedPP } catch {}
    }
    return $null
}

function Add-PatchInlines {
    # Fuegt einer TextBlock-Instanz formatierte Runs hinzu. Erkennt:
    #   **bold**   -> fett, helle Akzent-Farbe
    #   `code`     -> Consolas, Akzent-Hintergrund
    # Alles andere -> normaler Text.
    param([System.Windows.Controls.TextBlock]$Tb, [string]$Txt)
    if (-not $Txt) { return }
    $rx = [regex]'\*\*(.+?)\*\*|`([^`]+)`'
    $pos = 0
    foreach ($m in $rx.Matches($Txt)) {
        if ($m.Index -gt $pos) {
            $r = New-Object System.Windows.Documents.Run
            $r.Text = $Txt.Substring($pos, $m.Index - $pos)
            [void]$Tb.Inlines.Add($r)
        }
        if ($m.Groups[1].Success) {
            $r = New-Object System.Windows.Documents.Run
            $r.Text = $m.Groups[1].Value
            $r.FontWeight = 'Bold'
            $r.Foreground = New-Object System.Windows.Media.SolidColorBrush(
                [System.Windows.Media.Color]::FromRgb(0xed,0xed,0xf2))
            [void]$Tb.Inlines.Add($r)
        } elseif ($m.Groups[2].Success) {
            $r = New-Object System.Windows.Documents.Run
            $r.Text = $m.Groups[2].Value
            $r.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas')
            $r.FontSize = 11.5
            $r.Foreground = New-Object System.Windows.Media.SolidColorBrush(
                [System.Windows.Media.Color]::FromRgb(0xff,0xc0,0x90))
            [void]$Tb.Inlines.Add($r)
        }
        $pos = $m.Index + $m.Length
    }
    if ($pos -lt $Txt.Length) {
        $r = New-Object System.Windows.Documents.Run
        $r.Text = $Txt.Substring($pos)
        [void]$Tb.Inlines.Add($r)
    }
}

function New-PatchTextBlock {
    # Standard-TextBlock-Factory fuer die Patchnotes-Cards: Wrap, Farben passen
    # zum Dark-Theme, optional eingerueckt fuer Listen-Items.
    param(
        [string]$Text,
        [int]$LeftIndent = 0,
        [bool]$Subheader = $false,
        [bool]$Quote = $false
    )
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.TextWrapping = 'Wrap'
    $tb.FontSize = 12
    $tb.LineHeight = 18
    $tb.Margin = New-Object System.Windows.Thickness($LeftIndent, 3, 0, 3)
    if ($Subheader) {
        $tb.Foreground = New-Object System.Windows.Media.SolidColorBrush(
            [System.Windows.Media.Color]::FromRgb(0xed,0xed,0xf2))
        $tb.FontSize = 13
        $tb.FontWeight = 'SemiBold'
        $tb.Margin = New-Object System.Windows.Thickness(0, 10, 0, 4)
    } elseif ($Quote) {
        $tb.Foreground = New-Object System.Windows.Media.SolidColorBrush(
            [System.Windows.Media.Color]::FromRgb(0x88,0x88,0xa0))
        $tb.FontStyle = 'Italic'
    } else {
        $tb.Foreground = New-Object System.Windows.Media.SolidColorBrush(
            [System.Windows.Media.Color]::FromRgb(0xb9,0xc0,0xcc))
    }
    Add-PatchInlines -Tb $tb -Txt $Text
    return $tb
}

function Show-PatchHistory {
    # Komplette Versions-Historie im App-Stil. Quelle: lokales CHANGELOG.md,
    # Fallback online vom Verteil-Repo. Layout: Sidebar mit Versions-Liste
    # links, Cards rechts. Markdown wird programmatisch in WPF-Elemente
    # uebersetzt (Bold/Code/Bullets/Quotes/Subheader).
    $text = Get-PatchHistoryText
    if (-not $text) {
        [System.Windows.MessageBox]::Show(
            "Patch-Notes konnten nicht geladen werden.`r`n`r`nKein lokales CHANGELOG.md gefunden und keine Internet-Verbindung zum Abruf.",
            "Patch-Notes", "OK", "Warning") | Out-Null
        return
    }
    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="JustUpdate - Patch-Notes" Width="980" Height="700"
        MinWidth="720" MinHeight="500"
        WindowStartupLocation="CenterOwner" ResizeMode="CanResizeWithGrip"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent">
    <Border CornerRadius="14" Background="#111118" BorderBrush="#2a2a35" BorderThickness="1.5">
        <Grid Margin="0">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <!-- HEADER -->
            <Border Grid.Row="0" Padding="22,16,22,14" Background="#0e0e15"
                    BorderBrush="#2a2a35" BorderThickness="0,0,0,1"
                    x:Name="xHdrBar">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <StackPanel Grid.Column="0" Orientation="Horizontal">
                        <Ellipse Width="10" Height="10" Fill="#A3243B" Margin="0,0,10,0" VerticalAlignment="Center"/>
                        <TextBlock Text="Patch-Notes" Foreground="#ededf2"
                                   FontSize="15" FontWeight="Bold" VerticalAlignment="Center"/>
                        <TextBlock x:Name="xSubtitle" Foreground="#8888a0"
                                   FontSize="12" VerticalAlignment="Center" Margin="12,2,0,0"/>
                    </StackPanel>
                    <Button x:Name="xX" Grid.Column="1" Content="X" Width="32" Height="28"
                            Background="Transparent" Foreground="#8888a0" BorderThickness="0"
                            FontWeight="Bold" Cursor="Hand">
                        <Button.Template>
                            <ControlTemplate TargetType="Button">
                                <Border x:Name="bd" Background="{TemplateBinding Background}"
                                        CornerRadius="6">
                                    <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                </Border>
                                <ControlTemplate.Triggers>
                                    <Trigger Property="IsMouseOver" Value="True">
                                        <Setter TargetName="bd" Property="Background" Value="#5a1521"/>
                                    </Trigger>
                                </ControlTemplate.Triggers>
                            </ControlTemplate>
                        </Button.Template>
                    </Button>
                </Grid>
            </Border>
            <!-- BODY: Sidebar + Cards -->
            <Grid Grid.Row="1">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="200"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Border Grid.Column="0" Background="#0c0c12" BorderBrush="#2a2a35" BorderThickness="0,0,1,0">
                    <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="10,12,10,12">
                        <StackPanel x:Name="xSidebar"/>
                    </ScrollViewer>
                </Border>
                <ScrollViewer x:Name="xMainScroll" Grid.Column="1" VerticalScrollBarVisibility="Auto" Padding="22,16,22,16">
                    <StackPanel x:Name="xMain"/>
                </ScrollViewer>
            </Grid>
            <!-- FOOTER -->
            <Border Grid.Row="2" Padding="22,12,22,14" Background="#0e0e15"
                    BorderBrush="#2a2a35" BorderThickness="0,1,0,0">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock x:Name="xSrc" Grid.Column="0" Foreground="#52526a" FontSize="10.5"
                               VerticalAlignment="Center"/>
                    <Button x:Name="xClose" Grid.Column="1" Content="Schliessen"
                            Background="#25252f" Foreground="#ededf2"
                            BorderBrush="#2a2a35" BorderThickness="1"
                            Padding="22,9" FontSize="12" Cursor="Hand"
                            IsDefault="True" IsCancel="True">
                        <Button.Template>
                            <ControlTemplate TargetType="Button">
                                <Border x:Name="bd" Background="{TemplateBinding Background}"
                                        BorderBrush="{TemplateBinding BorderBrush}"
                                        BorderThickness="{TemplateBinding BorderThickness}"
                                        CornerRadius="8" Padding="{TemplateBinding Padding}">
                                    <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                </Border>
                                <ControlTemplate.Triggers>
                                    <Trigger Property="IsMouseOver" Value="True">
                                        <Setter TargetName="bd" Property="Background" Value="#2a2a35"/>
                                    </Trigger>
                                </ControlTemplate.Triggers>
                            </ControlTemplate>
                        </Button.Template>
                    </Button>
                </Grid>
            </Border>
        </Grid>
    </Border>
</Window>
"@
    try {
        $reader = New-Object System.Xml.XmlNodeReader $xaml
        $dlg = [Windows.Markup.XamlReader]::Load($reader)
        $sidebar  = $dlg.FindName("xSidebar")
        $main     = $dlg.FindName("xMain")
        $sub      = $dlg.FindName("xSubtitle")
        $src      = $dlg.FindName("xSrc")
        $close    = $dlg.FindName("xClose")
        $closeX   = $dlg.FindName("xX")
        $hdrBar   = $dlg.FindName("xHdrBar")
        $curVer   = $script:JUVersion

        # --- Sections aus dem Markdown extrahieren ---
        $sections = New-Object System.Collections.ArrayList
        $cur = $null
        $lines = $text -split "(`r`n|`r|`n)"
        foreach ($raw in $lines) {
            $ln = "$raw"
            if ($ln -match '^\s*##\s+(.+?)\s*$') {
                if ($cur) { [void]$sections.Add([pscustomobject]$cur) }
                $cur = @{ Title = $Matches[1].Trim(); Lines = New-Object System.Collections.ArrayList }
            } elseif ($cur) {
                [void]$cur.Lines.Add($ln)
            }
        }
        if ($cur) { [void]$sections.Add([pscustomobject]$cur) }

        # --- Rendern: Cards rechts, Sidebar-Eintraege links ---
        foreach ($sec in $sections) {
            # Title parsen: "v2.6.10 (23.05.2026 22:42)" -> Version + Datum
            $vCore = $sec.Title
            $vDate = ""
            if ($sec.Title -match '^(.+?)\s*\((.+?)\)\s*$') {
                $vCore = $Matches[1].Trim()
                $vDate = $Matches[2].Trim()
            }

            # Card (Border + StackPanel)
            $card = New-Object System.Windows.Controls.Border
            $card.CornerRadius = New-Object System.Windows.CornerRadius(12)
            $card.Background = New-Object System.Windows.Media.SolidColorBrush(
                [System.Windows.Media.Color]::FromRgb(0x18,0x18,0x1f))
            $card.BorderBrush = New-Object System.Windows.Media.SolidColorBrush(
                [System.Windows.Media.Color]::FromRgb(0x2a,0x2a,0x35))
            $card.BorderThickness = New-Object System.Windows.Thickness(1)
            $card.Padding = New-Object System.Windows.Thickness(18, 14, 18, 16)
            $card.Margin = New-Object System.Windows.Thickness(0, 0, 0, 14)

            $cardSp = New-Object System.Windows.Controls.StackPanel
            $card.Child = $cardSp

            # Version-Header: Version (gross) + Datum (gedimmt daneben) + AKTUELL-Badge
            $hdrRow = New-Object System.Windows.Controls.StackPanel
            $hdrRow.Orientation = 'Horizontal'
            $hdrRow.Margin = New-Object System.Windows.Thickness(0, 0, 0, 8)

            $vTitle = New-Object System.Windows.Controls.TextBlock
            $vTitle.Text = $vCore
            $vTitle.FontSize = 17
            $vTitle.FontWeight = 'Bold'
            $vTitle.VerticalAlignment = 'Center'
            $vTitle.Foreground = New-Object System.Windows.Media.SolidColorBrush(
                [System.Windows.Media.Color]::FromRgb(0xed,0xed,0xf2))
            [void]$hdrRow.Children.Add($vTitle)

            # Datum-Pille neben der Version
            if ($vDate) {
                $vDateBox = New-Object System.Windows.Controls.Border
                $vDateBox.CornerRadius = New-Object System.Windows.CornerRadius(6)
                $vDateBox.Background = New-Object System.Windows.Media.SolidColorBrush(
                    [System.Windows.Media.Color]::FromRgb(0x25,0x25,0x2f))
                $vDateBox.Padding = New-Object System.Windows.Thickness(8, 2, 8, 3)
                $vDateBox.Margin = New-Object System.Windows.Thickness(12, 3, 0, 0)
                $vDateBox.VerticalAlignment = 'Center'
                $vDateTb = New-Object System.Windows.Controls.TextBlock
                $vDateTb.Text = $vDate
                $vDateTb.FontSize = 11
                $vDateTb.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas')
                $vDateTb.Foreground = New-Object System.Windows.Media.SolidColorBrush(
                    [System.Windows.Media.Color]::FromRgb(0xb9,0xc0,0xcc))
                $vDateBox.Child = $vDateTb
                [void]$hdrRow.Children.Add($vDateBox)
            }

            if ($vCore -match '^v?' + [regex]::Escape($curVer) + '\b') {
                $badge = New-Object System.Windows.Controls.Border
                $badge.CornerRadius = New-Object System.Windows.CornerRadius(8)
                $badge.Background = New-Object System.Windows.Media.SolidColorBrush(
                    [System.Windows.Media.Color]::FromRgb(0xA3,0x24,0x3B))
                $badge.Padding = New-Object System.Windows.Thickness(8, 2, 8, 3)
                $badge.Margin = New-Object System.Windows.Thickness(10, 2, 0, 0)
                $badge.VerticalAlignment = 'Center'
                $badgeTxt = New-Object System.Windows.Controls.TextBlock
                $badgeTxt.Text = "AKTUELL"
                $badgeTxt.FontSize = 9.5
                $badgeTxt.FontWeight = 'Bold'
                $badgeTxt.Foreground = New-Object System.Windows.Media.SolidColorBrush(
                    [System.Windows.Media.Color]::FromRgb(0xff,0xff,0xff))
                $badge.Child = $badgeTxt
                [void]$hdrRow.Children.Add($badge)
            }
            [void]$cardSp.Children.Add($hdrRow)

            # Trennlinie unter Version-Header
            $sep = New-Object System.Windows.Shapes.Rectangle
            $sep.Height = 1
            $sep.Fill = New-Object System.Windows.Media.SolidColorBrush(
                [System.Windows.Media.Color]::FromRgb(0x2a,0x2a,0x35))
            $sep.Margin = New-Object System.Windows.Thickness(0, 0, 0, 10)
            [void]$cardSp.Children.Add($sep)

            # Inhalt parsen: einzelne Markdown-Zeilen -> WPF-Elemente
            $arr = @($sec.Lines)
            for ($i = 0; $i -lt $arr.Count; $i++) {
                $l = $arr[$i]
                if (-not $l) { continue }
                $trim = $l.Trim()
                if ($trim.Length -eq 0) { continue }
                # Bullet (- foo) oder Sub-Bullet (  - foo)
                if ($trim -match '^[-*]\s+(.+)$') {
                    $rest = $Matches[1]
                    # Sub-bullet? (Whitespace vorne ueber 2 Spaces)
                    $indent = if ($l -match '^(\s+)') { ($Matches[1].Length) } else { 0 }
                    $left = if ($indent -ge 2) { 36 } else { 14 }
                    $row = New-Object System.Windows.Controls.Grid
                    $row.Margin = New-Object System.Windows.Thickness($left, 2, 0, 2)
                    $col1 = New-Object System.Windows.Controls.ColumnDefinition
                    $col1.Width = New-Object System.Windows.GridLength(14)
                    $col2 = New-Object System.Windows.Controls.ColumnDefinition
                    $col2.Width = New-Object System.Windows.GridLength(1, 'Star')
                    [void]$row.ColumnDefinitions.Add($col1)
                    [void]$row.ColumnDefinitions.Add($col2)
                    $dot = New-Object System.Windows.Controls.TextBlock
                    $dot.Text = [char]0x2022   # bullet •
                    $dot.Foreground = New-Object System.Windows.Media.SolidColorBrush(
                        [System.Windows.Media.Color]::FromRgb(0xA3,0x24,0x3B))
                    $dot.FontSize = 14
                    $dot.FontWeight = 'Bold'
                    $dot.VerticalAlignment = 'Top'
                    [System.Windows.Controls.Grid]::SetColumn($dot, 0)
                    [void]$row.Children.Add($dot)
                    $txt = New-PatchTextBlock -Text $rest
                    [System.Windows.Controls.Grid]::SetColumn($txt, 1)
                    [void]$row.Children.Add($txt)
                    [void]$cardSp.Children.Add($row)
                    continue
                }
                # Numbered list (1. foo) — als Bullet mit Nummer
                if ($trim -match '^(\d+)\.\s+(.+)$') {
                    $num = $Matches[1]
                    $rest = $Matches[2]
                    $indent = if ($l -match '^(\s+)') { ($Matches[1].Length) } else { 0 }
                    $left = if ($indent -ge 2) { 36 } else { 14 }
                    $row = New-Object System.Windows.Controls.Grid
                    $row.Margin = New-Object System.Windows.Thickness($left, 2, 0, 2)
                    $col1 = New-Object System.Windows.Controls.ColumnDefinition
                    $col1.Width = New-Object System.Windows.GridLength(20)
                    $col2 = New-Object System.Windows.Controls.ColumnDefinition
                    $col2.Width = New-Object System.Windows.GridLength(1, 'Star')
                    [void]$row.ColumnDefinitions.Add($col1)
                    [void]$row.ColumnDefinitions.Add($col2)
                    $numTb = New-Object System.Windows.Controls.TextBlock
                    $numTb.Text = "$num."
                    $numTb.Foreground = New-Object System.Windows.Media.SolidColorBrush(
                        [System.Windows.Media.Color]::FromRgb(0xA3,0x24,0x3B))
                    $numTb.FontSize = 12
                    $numTb.FontWeight = 'Bold'
                    $numTb.VerticalAlignment = 'Top'
                    [System.Windows.Controls.Grid]::SetColumn($numTb, 0)
                    [void]$row.Children.Add($numTb)
                    $txt = New-PatchTextBlock -Text $rest
                    [System.Windows.Controls.Grid]::SetColumn($txt, 1)
                    [void]$row.Children.Add($txt)
                    [void]$cardSp.Children.Add($row)
                    continue
                }
                # Quote (> foo)
                if ($trim -match '^>\s+(.+)$') {
                    $rest = $Matches[1]
                    $bq = New-Object System.Windows.Controls.Border
                    $bq.BorderBrush = New-Object System.Windows.Media.SolidColorBrush(
                        [System.Windows.Media.Color]::FromRgb(0xA3,0x24,0x3B))
                    $bq.BorderThickness = New-Object System.Windows.Thickness(3, 0, 0, 0)
                    $bq.Padding = New-Object System.Windows.Thickness(10, 4, 6, 4)
                    $bq.Margin = New-Object System.Windows.Thickness(0, 6, 0, 6)
                    $bq.Background = New-Object System.Windows.Media.SolidColorBrush(
                        [System.Windows.Media.Color]::FromArgb(0x33, 0xA3, 0x24, 0x3B))
                    $qTxt = New-PatchTextBlock -Text $rest -Quote $true
                    $bq.Child = $qTxt
                    [void]$cardSp.Children.Add($bq)
                    continue
                }
                # Subheader: ganze Zeile in **...** und endet auf '.' o.ae.
                if ($trim -match '^\*\*(.+?)\*\*\s*$') {
                    [void]$cardSp.Children.Add(
                        (New-PatchTextBlock -Text $Matches[1] -Subheader $true))
                    continue
                }
                # Default: normale Zeile
                [void]$cardSp.Children.Add(
                    (New-PatchTextBlock -Text $trim))
            }

            [void]$main.Children.Add($card)

            # --- Sidebar-Eintrag --- nur Version (kompakt), kein Datum
            $sbBtn = New-Object System.Windows.Controls.Button
            $sbBtn.Content = $vCore
            $sbBtn.HorizontalContentAlignment = 'Left'
            $sbBtn.Padding = New-Object System.Windows.Thickness(10, 7, 8, 7)
            $sbBtn.Margin = New-Object System.Windows.Thickness(0, 1, 0, 1)
            $sbBtn.FontSize = 11.5
            $sbBtn.Cursor = 'Hand'
            $sbBtn.BorderThickness = New-Object System.Windows.Thickness(0)
            $sbBtn.Background = New-Object System.Windows.Media.SolidColorBrush(
                [System.Windows.Media.Colors]::Transparent)
            $sbBtn.Foreground = New-Object System.Windows.Media.SolidColorBrush(
                [System.Windows.Media.Color]::FromRgb(0xb9,0xc0,0xcc))
            # Aktuelle Version optisch markieren
            if ($vCore -match '^v?' + [regex]::Escape($curVer) + '\b') {
                $sbBtn.Background = New-Object System.Windows.Media.SolidColorBrush(
                    [System.Windows.Media.Color]::FromRgb(0xA3,0x24,0x3B))
                $sbBtn.Foreground = New-Object System.Windows.Media.SolidColorBrush(
                    [System.Windows.Media.Color]::FromRgb(0xff,0xff,0xff))
                $sbBtn.FontWeight = 'SemiBold'
            }
            # Card-Referenz im Tag, fuer Klick-Scroll
            $sbBtn.Tag = $card
            $sbBtn.Add_Click({
                try { $this.Tag.BringIntoView() } catch {}
            })
            [void]$sidebar.Children.Add($sbBtn)
        }

        $sub.Text = "$($sections.Count) Versionen"
        $src.Text = "Aktuelle Version: v$curVer  -  Quelle: github.com/Just1n12354/JustUpdate"
        $close.Add_Click({ $dlg.Close() })
        $closeX.Add_Click({ $dlg.Close() })
        try { if ($Window) { $dlg.Owner = $Window } } catch {}
        # Drag-To-Move ueber die Header-Leiste
        $hdrBar.Add_MouseLeftButtonDown({ try { $dlg.DragMove() } catch {} })
        [void]$dlg.ShowDialog()
    } catch {
        Show-JUChangelog "Patch-Notes" $text
    }
}

function Show-SupportPrompt {
    # Custom-Dialog statt MessageBox YesNo: explizit beschriftete Buttons,
    # damit niemand reflexhaft "Ja" klickt und sich wundert, warum eine
    # Mail-Vorschau aufgeht. "Schliessen" ist Default (Enter-Taste) -> ein
    # versehentliches Bestaetigen oeffnet NICHT die Mail.
    param(
        [string]$Title,
        [string]$Body,
        [string]$Level = "warn"   # "warn" | "err" | "ok"
    )
    $headerColor = if ($Level -eq "err") { "#EF4444" }
                   elseif ($Level -eq "warn") { "#e8a020" }
                   else { "#22C55E" }
    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="JustUpdate" Width="560" SizeToContent="Height"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ShowInTaskbar="False">
    <Border CornerRadius="14" Background="#18181f" BorderBrush="#2a2a35" BorderThickness="1.5">
        <Grid Margin="22,20,22,18">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <TextBlock x:Name="xHdr" Grid.Row="0" FontSize="15" FontWeight="Bold"
                       Margin="0,0,0,12"/>
            <ScrollViewer Grid.Row="1" MaxHeight="320" VerticalScrollBarVisibility="Auto"
                          Margin="0,0,0,18">
                <TextBlock x:Name="xBody" Foreground="#ededf2" FontSize="12"
                           TextWrapping="Wrap" LineHeight="18"/>
            </ScrollViewer>
            <Grid Grid.Row="2">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Button x:Name="xMail" Grid.Column="0" Content="Mail an Support senden"
                        Background="#A3243B" Foreground="#ffffff" BorderThickness="0"
                        Padding="18,9" FontWeight="SemiBold" FontSize="12"
                        Cursor="Hand">
                    <Button.Template>
                        <ControlTemplate TargetType="Button">
                            <Border x:Name="bd" Background="{TemplateBinding Background}"
                                    CornerRadius="8" Padding="{TemplateBinding Padding}">
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                            <ControlTemplate.Triggers>
                                <Trigger Property="IsMouseOver" Value="True">
                                    <Setter TargetName="bd" Property="Background" Value="#bd2b46"/>
                                </Trigger>
                            </ControlTemplate.Triggers>
                        </ControlTemplate>
                    </Button.Template>
                </Button>
                <Button x:Name="xClose" Grid.Column="2" Content="Schliessen"
                        Background="#25252f" Foreground="#ededf2" BorderThickness="1"
                        BorderBrush="#2a2a35" Padding="22,9" FontSize="12"
                        IsDefault="True" IsCancel="True" Cursor="Hand">
                    <Button.Template>
                        <ControlTemplate TargetType="Button">
                            <Border x:Name="bd" Background="{TemplateBinding Background}"
                                    BorderBrush="{TemplateBinding BorderBrush}"
                                    BorderThickness="{TemplateBinding BorderThickness}"
                                    CornerRadius="8" Padding="{TemplateBinding Padding}">
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                            <ControlTemplate.Triggers>
                                <Trigger Property="IsMouseOver" Value="True">
                                    <Setter TargetName="bd" Property="Background" Value="#2a2a35"/>
                                </Trigger>
                            </ControlTemplate.Triggers>
                        </ControlTemplate>
                    </Button.Template>
                </Button>
            </Grid>
        </Grid>
    </Border>
</Window>
"@
    try {
        $reader = New-Object System.Xml.XmlNodeReader $xaml
        $dlg = [Windows.Markup.XamlReader]::Load($reader)
        $hdr  = $dlg.FindName("xHdr")
        $body = $dlg.FindName("xBody")
        $mail = $dlg.FindName("xMail")
        $close = $dlg.FindName("xClose")
        $hdr.Text = $Title
        $hdr.Foreground = (New-Object System.Windows.Media.SolidColorBrush (
            [System.Windows.Media.ColorConverter]::ConvertFromString($headerColor)))
        $body.Text = $Body
        $script:_SupportChoice = $false
        $mail.Add_Click({ $script:_SupportChoice = $true; $dlg.Close() })
        $close.Add_Click({ $script:_SupportChoice = $false; $dlg.Close() })
        try { if ($Window) { $dlg.Owner = $Window } } catch {}
        [void]$dlg.ShowDialog()
        return $script:_SupportChoice
    } catch {
        # Fallback: WPF-Window OHNE Transparency/Custom-Chrome (robuster).
        # Trotzdem mit explizit beschrifteten Buttons - NIE wieder Ja/Nein.
        try {
            Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
            $w = New-Object System.Windows.Window
            $w.Title = $Title
            $w.Width = 560
            $w.SizeToContent = 'Height'
            $w.WindowStartupLocation = 'CenterScreen'
            $w.ResizeMode = 'NoResize'
            try { if ($Window) { $w.Owner = $Window } } catch {}
            $g = New-Object System.Windows.Controls.Grid
            $g.Margin = '18'
            foreach ($h in @('*','Auto')) {
                $rd = New-Object System.Windows.Controls.RowDefinition
                if ($h -eq 'Auto') { $rd.Height = [System.Windows.GridLength]::Auto }
                else { $rd.Height = New-Object System.Windows.GridLength(1,'Star') }
                [void]$g.RowDefinitions.Add($rd)
            }
            $tb = New-Object System.Windows.Controls.TextBlock
            $tb.Text = $Body
            $tb.TextWrapping = 'Wrap'
            $tb.FontSize = 12
            $tb.Margin = '0,0,0,16'
            [System.Windows.Controls.Grid]::SetRow($tb, 0)
            [void]$g.Children.Add($tb)
            $bp = New-Object System.Windows.Controls.DockPanel
            $bp.LastChildFill = $false
            [System.Windows.Controls.Grid]::SetRow($bp, 1)
            $btnMail = New-Object System.Windows.Controls.Button
            $btnMail.Content = 'Mail an Support senden'
            $btnMail.Padding = '14,7'
            $btnMail.MinWidth = 180
            [System.Windows.Controls.DockPanel]::SetDock($btnMail, 'Left')
            $btnClose = New-Object System.Windows.Controls.Button
            $btnClose.Content = 'Schliessen'
            $btnClose.Padding = '20,7'
            $btnClose.MinWidth = 110
            $btnClose.IsDefault = $true
            $btnClose.IsCancel = $true
            [System.Windows.Controls.DockPanel]::SetDock($btnClose, 'Right')
            [void]$bp.Children.Add($btnMail)
            [void]$bp.Children.Add($btnClose)
            [void]$g.Children.Add($bp)
            $w.Content = $g
            $script:_SupportChoice = $false
            $btnMail.Add_Click({ $script:_SupportChoice = $true; $w.Close() })
            $btnClose.Add_Click({ $script:_SupportChoice = $false; $w.Close() })
            [void]$w.ShowDialog()
            return $script:_SupportChoice
        } catch {
            # Absoluter Notfall: wenn auch WPF nicht geht -> kein Dialog,
            # einfach "false" zurueck (kein Mail-Versand). Niemals YesNo.
            return $false
        }
    }
}

function End-Session {
    param([switch]$completed)
    # Reentrancy-Guard: Stop-Klick (End-Session) und der Done-Tick des UI-Timers
    # (End-Session -completed) koennen fast gleichzeitig feuern - ein bereits in der
    # Dispatcher-Queue stehender Tick laeuft trotz $UITimer.Stop() noch durch. Ohne
    # Guard liefe der Report-/Mail-/Dialog-Block doppelt und griffe auf die schon
    # disposte Pipeline / genullte SyncHash-Werte zu.
    if ($script:SessionEnded) { return }
    $script:SessionEnded = $true
    if ($script:UITimer)    { $script:UITimer.Stop() }
    if ($script:ClockTimer) { $script:ClockTimer.Stop() }
    if (-not $completed -and $script:SyncHash) { $script:SyncHash.Stop = $true }
    if ($script:Pipeline) { try { $script:Pipeline.Stop() } catch {}; try { $script:Pipeline.Dispose() } catch {} }
    if ($script:Runspace)  { try { $script:Runspace.Close() } catch {} }
    $e.xStart.IsEnabled = $true
    $e.xStop.IsEnabled  = $false
    if ($completed) {
        $e.xStatus.Text = T "Done"
        $ok   = 0; $warn = 0; $err = 0
        if ($script:SyncHash) {
            $ok   = [int]$script:SyncHash.SummaryOk
            $warn = [int]$script:SyncHash.SummaryWarn
            $err  = [int]$script:SyncHash.SummaryErr
        }
        # --- Maschinenlesbarer Report (Fleet-Monitoring ueber mehrere Geraete) ---
        # Komplett gekapselt: ein Fehler hier darf den Abschluss-Dialog NIE stoppen.
        try {
            $modules = @()
            if ($script:SyncHash -and $script:SyncHash.Results) {
                foreach ($k in @($script:SyncHash.Results.Keys)) {
                    $r = $script:SyncHash.Results[$k]
                    $modules += [PSCustomObject]@{
                        module          = $k
                        status          = [string]$r.Status
                        details         = [string]$r.Details
                        durationSeconds = if ($r.ContainsKey('DurationSeconds')) { [int]$r.DurationSeconds } else { $null }
                    }
                }
            }
            $reportVer = $script:JUVersion
            $started = $script:StartTime
            $report = [PSCustomObject]@{
                tool            = "JustUpdate"
                version         = $reportVer
                host            = $env:COMPUTERNAME
                user            = $env:USERNAME
                startedUtc      = if ($started) { $started.ToUniversalTime().ToString("o") } else { $null }
                finishedUtc     = (Get-Date).ToUniversalTime().ToString("o")
                durationSeconds = if ($started) { [int]((Get-Date) - $started).TotalSeconds } else { $null }
                summary         = [PSCustomObject]@{ ok = $ok; warnings = $warn; errors = $err }
                overall         = if ($err -gt 0) { "error" } elseif ($warn -gt 0) { "warning" } else { "ok" }
                rebootRequired  = [bool]($script:SyncHash -and $script:SyncHash.RebootRequired)
                autoMode        = [bool]$script:AutoMode
                modules         = $modules
            }
            # Nur den DATEINAMEN umschreiben (verankert), nicht den ganzen Pfad per
            # ungeankertem Regex - sonst wuerde ein Ordnerpfad, der "Maintenance_"
            # enthaelt, mitumgeschrieben und das JSON landete im Nirgendwo.
            $logDir   = Split-Path $script:LogPath
            $logLeaf  = [IO.Path]::GetFileNameWithoutExtension($script:LogPath) -replace '^Maintenance_', 'result_'
            $jsonPath = Join-Path $logDir "$logLeaf.json"
            # BOM-frei schreiben: ConvertTo-Json | Out-File -Encoding utf8 setzt in
            # PS5.1 ein fuehrendes UTF-8-BOM (EF BB BF) VOR die '{' - strikte JSON-
            # Parser (Fleet-Auswertung, .NET System.Text.Json, Linux/NAS-Tools)
            # stolpern darueber. WriteAllText mit UTF8Encoding($false) = ohne BOM.
            [IO.File]::WriteAllText($jsonPath, ($report | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
            $script:LastResultJson = $jsonPath
            # Rotation: max. 20 Result-JSONs behalten (analog Log-Rotation)
            Get-ChildItem -Path (Split-Path $jsonPath) -Filter "result_*.json" -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -Skip 20 |
                ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }

            # Fleet-Monitoring: Report zusaetzlich zentral ablegen, wenn ein
            # Sammelpfad gesetzt ist ($env:JUSTUPDATE_REPORT_DIR, z.B. OneDrive/
            # NAS). Dateiname mit Host -> kollisionsfrei ueber viele Geraete.
            # fleet-report.ps1 -Path <dieser Ordner> wertet das aus.
            if ($env:JUSTUPDATE_REPORT_DIR) {
                try {
                    $fleetDir = $env:JUSTUPDATE_REPORT_DIR
                    if (-not (Test-Path $fleetDir)) { New-Item -ItemType Directory -Path $fleetDir -Force -ErrorAction Stop | Out-Null }
                    Copy-Item $jsonPath (Join-Path $fleetDir ("{0}__{1}" -f $env:COMPUTERNAME, (Split-Path $jsonPath -Leaf))) -Force -ErrorAction Stop
                } catch { }
            }
        } catch { }

        # Automatik-Modus: kein Dialog, kein Mail-Prompt - Report ist geschrieben,
        # Exit-Code gesetzt, Fenster zu. Task Scheduler sieht 0/1/2.
        if ($script:AutoMode) {
            $script:AutoExitCode = if ($err -gt 0) { 2 } elseif ($warn -gt 0) { 1 } else { 0 }
            try { $Window.Close() } catch {}
            return
        }

        # Dezenter Abschluss-Sound - der User darf waehrend der langen Wartung
        # woanders sein und hoert trotzdem, dass sie fertig ist.
        try { [System.Media.SystemSounds]::Asterisk.Play() } catch {}

        $msg    = "$ok erfolgreich, $warn Warnungen, $err Fehler"
        $rebootNeeded = [bool]($script:SyncHash -and $script:SyncHash.RebootRequired)
        # Neustart-Hinweis NICHT mehr als statischer Text in der Zusammenfassung -
        # er kommt weiter unten als eigener Ja/Nein-Vorschlag ("Jetzt neu starten?").
        $icon   = if ($err -gt 0) { "Error" } elseif ($warn -gt 0) { "Warning" } else { "Information" }
        $header = if ($err -gt 0) { "Wartung mit Fehlern beendet" }
                  elseif ($warn -gt 0) { "Wartung mit Warnungen beendet" }
                  else { T "Done" }
        if ($err -gt 0 -or $warn -gt 0) {
            $details = if ($script:SyncHash) { [string]$script:SyncHash.SummaryDetails } else { "" }
            if ($details.Trim().Length -gt 0) {
                $msg += "`n`n--- Was genau ---`n`n$details"
            }
            $msg += "`n`nVollstaendige Details: Button 'LOG OEFFNEN'."
            $msg += "`n`nMit 'Mail an Support senden' wird automatisch eine Mail "
            $msg += "`nmit Log + Diagnose vorbereitet - du musst nur noch auf "
            $msg += "`n'Senden' klicken. Mit 'Schliessen' passiert nichts."
            $lvl = if ($err -gt 0) { "err" } else { "warn" }
            $sendMail = Show-SupportPrompt -Title $header -Body $msg -Level $lvl
            if ($sendMail) {
                # Mail-Header / Body bauen — fuer BEIDE Wege (Outlook + mailto) identisch.
                $subj = "JustUpdate Bericht - $($env:COMPUTERNAME) - $ok OK / $warn Warn / $err Fehler"
                $head = "Automatischer JustUpdate-Bericht`r`n`r`n" +
                        "Host: $($env:COMPUTERNAME)`r`nBenutzer: $($env:USERNAME)`r`n" +
                        "Version: v$($script:JUVersion)`r`n" +
                        "Ergebnis: $ok OK, $warn Warnungen, $err Fehler`r`n" +
                        "Log-Datei: $($script:LogPath)`r`n"
                # Modul-Details (kompakte Liste der warn/err) aus dem SyncHash
                $modTxt = ""
                if ($script:SyncHash -and $script:SyncHash.Results) {
                    $bad = @()
                    foreach ($k in @($script:SyncHash.Results.Keys)) {
                        $r = $script:SyncHash.Results[$k]
                        if ($r.Status -eq "warn" -or $r.Status -eq "err") {
                            $bad += "  [$($r.Status.ToUpper())] $k - $($r.Details)"
                        }
                    }
                    if ($bad.Count -gt 0) {
                        $modTxt = "`r`n--- Module mit Problemen ---`r`n" + ($bad -join "`r`n") + "`r`n"
                    }
                }
                # Voller Log fuer die Zwischenablage zusammenbauen — Kunde
                # macht einmal Strg+V im Mail-Body und hat alles drin.
                $fullLog = ""
                try {
                    if (Test-Path $script:LogPath) {
                        $fullLog = [IO.File]::ReadAllText($script:LogPath)
                    }
                } catch {}
                $bodyFull = $head + $modTxt
                if ($fullLog) {
                    $bodyFull += "`r`n--- Log (vollstaendig) ---`r`n" + $fullLog + "`r`n"
                }

                # IMMER ueber Standard-Mail-Handler (mailto:) — respektiert die
                # Mail-App, die der Kunde in Windows als Default gesetzt hat
                # (Outlook, Thunderbird, Apple Mail, Web-Mail-Handler, ...).
                # Frueher (v2.6.5 - v2.6.9): direkte Outlook-COM-Automation
                # hat IMMER Outlook geoeffnet, auch wenn der Kunde lieber eine
                # andere App benutzt - jetzt entfernt.
                try {
                    # 1) Vollen Log + Diagnose in die Zwischenablage. mailto-
                    #    URLs sind laengen-limitiert (~2000 Bytes), aber der
                    #    Kunde kann mit einem Strg+V den gesamten Inhalt im
                    #    Mail-Body einfuegen.
                    try { Set-Clipboard -Value $bodyFull -ErrorAction Stop } catch {}

                    # 2) Kompakter Body in der mailto-URL: Header + Modul-
                    #    Stati + Klartext-Hinweis was zu tun ist.
                    $hint = "`r`n--- WICHTIG ---`r`n" +
                            "Der vollstaendige Log liegt bereits in der ZWISCHENABLAGE." +
                            "`r`nBitte hier im Mail-Body einmal Strg+V druecken, dann Senden." +
                            "`r`n" +
                            "`r`nAlternativ liegt die Log-Datei im gerade geoeffneten" +
                            "`r`nOrdner und kann als Anhang reingezogen werden.`r`n"
                    $bodyForUri = $head + $modTxt + $hint
                    if ($bodyForUri.Length -gt 1800) {
                        $bodyForUri = $bodyForUri.Substring(0, 1800) +
                                      "`r`n[gekuerzt - voller Log in Zwischenablage]"
                    }
                    $u = "mailto:info@itintechsolutions.ch?subject=$([uri]::EscapeDataString($subj))&body=$([uri]::EscapeDataString($bodyForUri))"
                    # Start-Process auf mailto-URL -> Windows fragt den
                    # registrierten Default-Mail-Handler. Hat der Kunde keinen
                    # Default gesetzt, kommt der "Eine App auswaehlen"-Dialog
                    # von Windows - genau richtig.
                    Start-Process $u
                    # Ordner mit Log + result_*.json oeffnen (Backup-Pfad fuer
                    # Anhang). Sicht statt /select, damit beide Dateien sichtbar.
                    Start-Process explorer.exe ("`"" + (Split-Path $script:LogPath) + "`"")
                } catch {}
            }
        } else {
            [System.Windows.MessageBox]::Show($msg, $header, "OK", $icon) | Out-Null
        }

        # ── Neustart-Nachfrage ──────────────────────────────────────────────
        # Liegt ein Neustart an, kommt NACH der Zusammenfassung ein eigener
        # Ja/Nein-Dialog. Reiner Vorschlag: bei "Nein" passiert nichts (der
        # Hinweis bleibt im Log + result-JSON erhalten). Im Automatik-Modus
        # erscheint er nicht (dort oben bereits per return verlassen).
        if ($rebootNeeded) {
            $rb = [System.Windows.MessageBox]::Show(
                "Einige Aenderungen wirken erst nach einem Neustart vollstaendig`n" +
                "(z.B. Defender-Signaturen, Windows-Updates, SFC, Netzwerk-Reset).`n`n" +
                "Moechtest du den PC JETZT neu starten?`n`n" +
                "(Bei 'Nein' kannst du jederzeit spaeter selbst neu starten.)",
                "JustUpdate - Neustart empfohlen",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Question)
            $rbMsg = if ($rb -eq [System.Windows.MessageBoxResult]::Yes) {
                "Neustart vom Benutzer bestaetigt - PC wird in 20s neu gestartet (Abbruch: 'shutdown /a')."
            } else {
                "Neustart vom Benutzer verschoben (Vorschlag mit 'Nein' abgelehnt)."
            }
            try { [IO.File]::AppendAllText($script:LogPath, "[$(Get-Date -F 'HH:mm:ss')]   [INFO] $rbMsg`r`n", (New-Object System.Text.UTF8Encoding($false))) } catch {}
            if ($rb -eq [System.Windows.MessageBoxResult]::Yes) {
                # Geplanter Neustart mit 20s Karenz - Windows zeigt seine eigene
                # Vorwarnung, der User kann mit 'shutdown /a' noch abbrechen.
                try {
                    Start-Process shutdown.exe -ArgumentList @('/r','/t','20','/c','JustUpdate: Neustart nach Wartung') -WindowStyle Hidden
                } catch {
                    try { Restart-Computer -Force } catch {}
                }
            }
        }
    } else {
        $e.xStatus.Text = T "Stopped"
    }
}

# =====================================================================
# EVENTS
# =====================================================================
$e.xStart.Add_Click({ Start-Maintenance })
$e.xStop.Add_Click({ End-Session })
$e.xLog.Add_Click({ Start-Process notepad.exe "`"$($script:LogPath)`"" })
$e.xPatch.Add_Click({ Show-PatchHistory })

# Zeitplan-Button: legt eine woechentliche geplante Aufgabe an (Sonntag 11:00),
# die JustUpdate im Automatik-Modus (-Auto) startet - oder entfernt sie wieder.
# Laeuft als angemeldeter User mit hoechsten Rechten (RunLevel Highest), damit
# kein UAC-Prompt den unbeaufsichtigten Lauf blockiert. Bewusst Interactive:
# als SYSTEM koennte das WPF-Fenster in Session 0 nicht zuverlaessig laufen.
$e.xSched.Add_Click({
    $taskName = "JustUpdate Auto-Wartung"
    try {
        $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($existing) {
            $a = [System.Windows.MessageBox]::Show(
                "Die automatische Wartung ist bereits eingeplant:`n`n" +
                "  Aufgabe: $taskName`n  Rhythmus: woechentlich, Sonntag 11:00`n`n" +
                "Geplante Aufgabe ENTFERNEN?",
                "JustUpdate - Zeitplan",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Question)
            if ($a -eq [System.Windows.MessageBoxResult]::Yes) {
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
                [System.Windows.MessageBox]::Show("Die geplante Aufgabe wurde entfernt.",
                    "JustUpdate - Zeitplan", "OK", "Information") | Out-Null
            }
            return
        }
        $a = [System.Windows.MessageBox]::Show(
            "JustUpdate kann die komplette Wartung automatisch ausfuehren:`n`n" +
            "  - jeden Sonntag um 11:00 Uhr (PC muss an + User angemeldet sein)`n" +
            "  - mit den aktuell gespeicherten Modulen`n" +
            "  - ohne Nachfragen und ohne Abschluss-Dialog`n" +
            "  - laufende Programme werden NICHT geschlossen`n`n" +
            "Jetzt einplanen?",
            "JustUpdate - Zeitplan",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Question)
        if ($a -ne [System.Windows.MessageBoxResult]::Yes) { return }
        Save-JUSettings
        if ($isExe) {
            $action = New-ScheduledTaskAction -Execute $ScriptPath -Argument "-Auto"
        } else {
            $action = New-ScheduledTaskAction -Execute "powershell.exe" `
                        -Argument "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$ScriptPath`" -Auto"
        }
        $trigger   = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "11:00"
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
                        -RunLevel Highest -LogonType Interactive
        $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
                        -DontStopIfGoingOnBatteries -StartWhenAvailable `
                        -ExecutionTimeLimit (New-TimeSpan -Hours 4)
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
            -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
        [System.Windows.MessageBox]::Show(
            "Eingeplant: '$taskName' laeuft jeden Sonntag um 11:00 Uhr.`n`n" +
            "Verpasste Termine werden nachgeholt, sobald der PC wieder an ist.`n" +
            "Entfernen: einfach nochmal auf das Uhr-Symbol klicken.",
            "JustUpdate - Zeitplan", "OK", "Information") | Out-Null
    } catch {
        [System.Windows.MessageBox]::Show(
            "Zeitplan konnte nicht angelegt/geaendert werden:`n`n$($_.Exception.Message)",
            "JustUpdate - Zeitplan", "OK", "Warning") | Out-Null
    }
})

$e.xInfo.Add_Click({
    $infoMsg = @"
JustUpdate haelt Ihren PC sauber und aktuell - mit einem einzigen Klick.

WAS DIESE ANWENDUNG MACHT:

1. Wiederherstellungspunkt
   Erstellt vor allen Aenderungen einen Sicherungspunkt von Windows.
   So koennen Sie bei Problemen wieder zum vorherigen Zustand zurueck.

2. Defender aktualisieren
   Laedt die neuesten Viren-Signaturen fuer den Windows-Virenschutz herunter.

3. Windows Updates
   Sucht nach offiziellen Microsoft-Updates fuer Windows und installiert diese.
   (Treiber-Updates werden separat in Schritt 4 behandelt.)

4. Treiber aktualisieren
   Sucht ueber Windows Update nach neueren Geraete-Treibern (Drucker, Grafik, etc.)
   und installiert diese.

5. Apps aktualisieren (Winget)
   Aktualisiert alle installierten Programme, die ueber den Windows-Paketmanager
   (winget) bekannt sind - z.B. Browser, Office-Tools, Entwickler-Programme.

6. Microsoft Store Apps
   Stoesst die Aktualisierung aller Apps aus dem Microsoft Store an.
   (Laeuft im Hintergrund weiter, deshalb als 'Warnung' markiert.)

7. System-Reparatur
   Pruefen die Systemdateien (SFC) und reparieren beschaedigte Komponenten (DISM).
   Das ist die offizielle Microsoft-Methode bei Windows-Problemen.

8. Netzwerk reparieren
   Setzt DNS-Cache, Winsock und IP-Konfiguration zurueck.
   Hilft bei Internet-Problemen. Standardmaessig deaktiviert.

9. Bereinigung
   Leert Papierkorb, DNS-Cache und temporaere Dateien aller Benutzer auf diesem PC.
   Setzt den Thumbnail-Cache zurueck und gibt Speicher im Windows-Update-Ordner frei.

ZUSAETZLICHE FUNKTIONEN:

- Vor Updates fragt JustUpdate, ob alle offenen Programme geschlossen werden
  sollen, damit sich Update-Installationen nicht an gesperrten Dateien aufhaengen.
- Die Modul-Bezeichnungen links wechseln waehrend der Wartung die Farbe:
  WEISS = noch nicht gestartet, ROT = laeuft gerade, GRUEN = erfolgreich abgeschlossen.
- Alle Aktionen werden mitprotokolliert. Den letzten Log oeffnen Sie ueber 'LOG OEFFNEN'.
- Es werden maximal die 10 neuesten Logs aufbewahrt, aeltere werden automatisch geloescht.
- Ihre Modul-Auswahl und Sprache werden gespeichert und beim naechsten Start
  automatisch wiederhergestellt.
- Ueber das Uhr-Symbol oben rechts laesst sich eine woechentliche automatische
  Wartung einplanen (Sonntag 11:00). Sie laeuft ohne Nachfragen, schliesst keine
  Programme und beendet sich selbst. Erneuter Klick entfernt den Zeitplan.
- Vor der Wartung prueft JustUpdate automatisch: Internet-Verbindung, offener
  Windows-Neustart, Akku-Betrieb und freier Speicherplatz - und sagt klar,
  wenn etwas davon die Wartung beeintraechtigen koennte.

WAS DIESE ANWENDUNG NICHT MACHT:

- JustUpdate installiert keine Programme, die noch nicht auf Ihrem PC sind.
- JustUpdate verschickt keine Daten ins Internet (ausser fuer den Update-Download
  von Microsoft direkt) und sammelt keine persoenlichen Informationen.
- JustUpdate aendert keine persoenlichen Dateien (Dokumente, Bilder, Videos).
- JustUpdate ueberschreibt keine eigenen Einstellungen wie Hintergrundbild,
  Browser-Favoriten oder installierte Programme.
- Die Bereinigung loescht nur temporaere Dateien, die aelter als drei Tage sind -
  keine eigenen Dokumente, Downloads oder Programmdaten.

WICHTIGE HINWEISE:

- Bitte lassen Sie den PC waehrend der Wartung eingeschaltet.
- Manche Updates verlangen einen Neustart - JustUpdate weist Sie darauf hin.
- Fuer alle Module sind Administratorrechte noetig (wird automatisch angefragt).
- Bei Fragen oder Problemen oeffnen Sie das Log und schicken den Inhalt an Ihre
  IT-Person oder an Justin (info@itintechsolutions.ch).

Vielen Dank, dass Sie JustUpdate verwenden!
"@
    [System.Windows.MessageBox]::Show($infoMsg, "Info - Was macht JustUpdate?", "OK", "Information") | Out-Null
})

# =====================================================================
# RUN
# =====================================================================
# PowerShell-Konsolenfenster verstecken, WPF-Fenster in den Vordergrund
Add-Type -Name Win32 -Namespace Native -MemberDefinition @"
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
"@
$Window.Add_Loaded({
    # Erst WPF-Fenster sichtbar machen
    $helper = New-Object System.Windows.Interop.WindowInteropHelper $Window
    [Native.Win32]::ShowWindow($helper.Handle, 5) | Out-Null
    [Native.Win32]::SetForegroundWindow($helper.Handle) | Out-Null
    $Window.Activate()
    # Sanftes Fade-In (280ms, EaseOut) - hochwertiger Ersteindruck statt Hartschnitt.
    try {
        $Window.Opacity = 0
        $fade = New-Object System.Windows.Media.Animation.DoubleAnimation
        $fade.From = 0; $fade.To = 1
        $fade.Duration = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds(280))
        $fe = New-Object System.Windows.Media.Animation.CubicEase
        $fe.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
        $fade.EasingFunction = $fe
        $Window.BeginAnimation([System.Windows.Window]::OpacityProperty, $fade)
    } catch { $Window.Opacity = 1 }
    # Dann PowerShell-Konsole verstecken
    $consoleHwnd = [Native.Win32]::GetConsoleWindow()
    if ($consoleHwnd -ne [IntPtr]::Zero) {
        [Native.Win32]::ShowWindow($consoleHwnd, 0) | Out-Null
    }
    # Automatik-Modus: Wartung ohne Klick starten - erst wenn das Fenster
    # fertig gerendert ist (ApplicationIdle), sonst fehlen ActualWidth & Co.
    if ($script:AutoMode) {
        $Window.Dispatcher.BeginInvoke(
            [Action]{ Start-Maintenance },
            [System.Windows.Threading.DispatcherPriority]::ApplicationIdle) | Out-Null
    }
})
$Window.ShowDialog() | Out-Null

# Automatik-Modus: Exit-Code an den Task Scheduler / das Fleet-Monitoring
# durchreichen (0 = alles OK, 1 = Warnungen, 2 = Fehler).
if ($script:AutoMode -and $null -ne $script:AutoExitCode) { exit $script:AutoExitCode }
