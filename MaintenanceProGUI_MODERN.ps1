# Version: 2.6.2
# Copyright (c) 2026 Itin TechSolutions / Justin Itin
# Alle Rechte vorbehalten - info@itintechsolutions.ch
# https://itintechsolutions.ch
# Determine script/exe path first
$ScriptPath = if ($PSCommandPath) { $PSCommandPath }
              elseif ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path }
              else { [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName }

# Laeuft das hier als kompilierte JustUpdate.exe (PS2EXE) statt als .ps1 ueber
# powershell.exe? Dann duerfen Self-Elevation (powershell -File <exe> ist ungueltig)
# und Self-Update (wuerde die laufende .exe mit einer .ps1 ueberschreiben) NICHT
# den .ps1-Pfad gehen. Die EXE aktualisiert sich spaeter ueber GitHub-Releases.
$isExe = $ScriptPath -match '\.exe$'

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
if (-not $script:JUVersion) { $script:JUVersion = '2.6.2' }   # letzter Fallback statt "?"

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
        Start-Process -FilePath $ScriptPath -Verb RunAs
        exit
    }
} elseif ($PSVersionTable.PSEdition -eq "Core" -or
    [System.Threading.Thread]::CurrentThread.ApartmentState -ne "STA" -or
    -not $isAdmin) {
    Start-Process powershell.exe -Verb RunAs `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -File `"$ScriptPath`""
    exit
}

# =====================================================================
# UPDATE-PRUEFUNG: Vergleicht lokale Version (Header in Zeile 1) mit der
# Version auf GitHub. Bei neuerer Remote-Version fragt eine MessageBox
# den Nutzer ob er das Update jetzt installieren will.
# Deaktivierbar via Umgebungsvariable JUSTUPDATE_NO_SELFUPDATE=1.
# =====================================================================
if (-not $isExe -and $env:JUSTUPDATE_NO_SELFUPDATE -ne "1") {
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
        if ((Get-Item $tempFile).Length -gt 1000) {
            $localVerLine  = Get-Content $ScriptPath -TotalCount 1
            $remoteVerLine = Get-Content $tempFile  -TotalCount 1
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
                        Copy-Item -Path $tempFile -Destination $ScriptPath -Force
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
$script:LogPath = Join-Path $LogDir ("Maintenance_{0}.log" -f (Get-Date -Format "yyyy-MM-dd_HH-mm-ss"))
"" | Out-File -FilePath $script:LogPath -Encoding utf8

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
    "TitleBar","xLang","xMin","xMax","xClose","xInfo","xTitleBar",
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

function Close-RunningUserApps {
    # Schliesst alle GUI-Prozesse mit Hauptfenster — sanft via CloseMainWindow().
    # Ausgenommen: System-Prozesse, Shell, JustUpdate selbst.
    $whitelist = @(
        "explorer","dwm","conhost","powershell","pwsh","cmd","WindowsTerminal",
        "wininit","winlogon","csrss","smss","services","lsass","svchost",
        "fontdrvhost","SearchHost","StartMenuExperienceHost","ShellExperienceHost",
        "TextInputHost","RuntimeBroker","ApplicationFrameHost","SecurityHealthSystray"
    )
    $myPid = $PID
    $closed = 0
    Get-Process | Where-Object {
        $_.Id -ne $myPid -and
        $_.MainWindowHandle -ne 0 -and
        $whitelist -notcontains $_.ProcessName
    } | ForEach-Object {
        try {
            [void]$_.CloseMainWindow()
            $closed++
        } catch {}
    }
    # Kurz warten, damit Apps ihre "Speichern?"-Dialoge anzeigen koennen
    Start-Sleep -Seconds 2
    return $closed
}

function Start-Maintenance {
    # Vor Update-Modulen: User fragen, ob laufende Apps geschlossen werden sollen.
    # Verhindert dass Update-Installer sich an gesperrten Dateien aufhaengen.
    $needsClose = ([bool]$e.xTglWinUpdate.IsChecked) -or ([bool]$e.xTglStore.IsChecked)
    if ($needsClose) {
        $answer = [System.Windows.MessageBox]::Show(
            (T "CloseAppsMsg"),
            (T "CloseAppsTitle"),
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning)
        if ($answer -eq [System.Windows.MessageBoxResult]::Yes) {
            $script:ClosedAppCount = Close-RunningUserApps
        } else {
            $script:ClosedAppCount = -1
        }
    } else {
        $script:ClosedAppCount = $null
    }

    Reset-AllIcons
    $e.xLogBox.Clear()
    try { $e.xBar.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty, $null) } catch {}
    $e.xBar.Width = 0
    $script:LastBarTarget = 0
    $e.xTime.Text = "00:00"
    $script:StartTime = Get-Date

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
        function M($id,$s) { [void]$sync.ModuleQueue.Add("$id|$s") }
        function IsStopped { $sync.Stop -eq $true }
        # Mark result: status = ok|warn|err, details = free-text summary
        # UI: ok -> Gruen, warn -> Orange ("!"), err -> Rot+X
        function Mark($id, $status, $details) {
            $sync.Results[$id] = @{ Status = $status; Details = $details }
            $uiState = switch ($status) { "ok" { "ok" } "warn" { "warn" } default { "err" } }
            M $id $uiState
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

        # Microsoft Update Service registrieren + ServiceID zurueckgeben (oder $null).
        # Warum: Die "Optionalen Updates" aus Windows-Einstellungen > Windows Update >
        # Erweiterte Optionen > Optionale Updates (v.a. Treiber, manchmal Vorschau-CU)
        # liegen im Microsoft Update Service - der Standard WUA-Searcher (ssDefault)
        # sucht nur im Windows Update Service und uebersieht sie deshalb komplett.
        # Loesung: Service via IUpdateServiceManager anhaengen, Searcher dann mit
        # ServerSelection=ssOthers + dieser ServiceID darauf zeigen lassen.
        # AddService2 ist idempotent - bei bereits registriertem Service wirft es,
        # das fangen wir und akzeptieren es.
        function Enable-MicrosoftUpdateService {
            $muId = '7971f918-a847-4430-9279-4a52d1efe18d'
            try {
                $svcMgr = New-Object -ComObject Microsoft.Update.ServiceManager
                try { $svcMgr.AddService2($muId, 7, '') | Out-Null } catch {}
                foreach ($svc in $svcMgr.Services) {
                    if ($svc.ServiceID -eq $muId) { return $muId }
                }
            } catch {}
            return $null
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
                while ($waited -lt $wdTimeout) {
                    Start-Sleep -Seconds 1
                    $waited++
                    if (-not (Get-Process -Id $wdPid -ErrorAction SilentlyContinue)) { return }
                    if ($sync.Stop -eq $true) { break }
                }
                $wd.Killed = $true
                try { Start-Process taskkill.exe -ArgumentList "/PID $wdPid /T /F" -WindowStyle Hidden -Wait -ErrorAction Stop } catch {}
            })
            $wdHandle = $wdPs.BeginInvoke()

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
            $errOut = ""
            try { $errOut = $proc.StandardError.ReadToEnd() } catch {}
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
        L "  $total Module ausgewaehlt"
        L "  $(Get-Date -F 'dd.MM.yyyy HH:mm:ss')"
        L "============================================"
        L ""
        if ($null -ne $sync.ClosedAppCount) {
            if ($sync.ClosedAppCount -ge 0) {
                L "  Vor-Update-Schritt: $($sync.ClosedAppCount) laufende Programm(e) geschlossen"
            } else {
                L "  Vor-Update-Schritt: User hat das Schliessen abgelehnt - Updates koennen an gesperrten Dateien scheitern"
            }
            L ""
        }

        # ── Connectivity-Precheck ── klare Offline-Meldung EINMAL, statt spaeter
        # mehrere kryptische Timeouts in Defender/WinUpdate/Winget/Store.
        $online = $false
        try {
            $req = [System.Net.WebRequest]::Create("https://www.microsoft.com")
            $req.Method = "HEAD"; $req.Timeout = 5000
            $resp = $req.GetResponse(); $resp.Close(); $online = $true
        } catch { $online = $false }
        if ($online) {
            L "  Internet-Verbindung: OK"
        } else {
            L "  [WARNUNG] Keine Internet-Verbindung erkannt."
            L "  Online-Module (Defender, Windows Update, Apps, Store) koennen"
            L "  fehlschlagen oder nichts finden - das ist dann KEIN Geraetefehler."
            L "  Offline-Module (Reparatur, Netzwerk, Bereinigung) laufen normal."
        }
        L ""

        # ── RESTORE POINT ──
        if ($cfg.Restore) {
            if (IsStopped) { $sync.Done = $true; return }
            M "Restore" "run"
            L "--------------------------------------------"
            L "  MODUL 1: Wiederherstellungspunkt"
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
            $i++; P ($i / $total * 100)
            L ""
        }

        # ── DEFENDER ──
        if ($cfg.Defender) {
            if (IsStopped) { $sync.Done = $true; return }
            M "Defender" "run"
            L "--------------------------------------------"
            L "  MODUL 2: Windows Defender"
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
                    L "  [FEHLER] $($_.Exception.Message)"
                    Mark "Defender" "err" $_.Exception.Message
                }
            }
            $i++; P ($i / $total * 100)
            L ""
        }

        # ── WINDOWS UPDATE ──
        if ($cfg.WinUpdate) {
            if (IsStopped) { $sync.Done = $true; return }
            M "WinUpdate" "run"
            L "--------------------------------------------"
            L "  MODUL 3: Windows Updates"
            L "--------------------------------------------"
            try {
                L "  Windows Update Service initialisieren..."
                $session = New-Object -ComObject Microsoft.Update.Session
                $searcher = $session.CreateUpdateSearcher()
                # Microsoft Update Service anhaengen + Searcher darauf umstellen, sonst
                # fehlen die "Optionalen Updates" aus den Win-Einstellungen.
                $muId = Enable-MicrosoftUpdateService
                if ($muId) {
                    $searcher.ServerSelection = 3   # ssOthers
                    $searcher.ServiceID = $muId
                    L "  Microsoft Update Service aktiv - optionale Updates werden einbezogen"
                } else {
                    L "  [HINWEIS] Microsoft Update Service nicht verfuegbar - nur Standard Windows Update"
                }
                L "  Suche nach verfuegbaren Updates (inkl. Vorschau/optional)..."
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
                        if ($r.RebootRequired) { L "  >>> NEUSTART ERFORDERLICH <<<" }

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
            $i++; P ($i / $total * 100)
            L ""
        }

        # ── DRIVERS ──
        if ($cfg.Drivers) {
            if (IsStopped) { $sync.Done = $true; return }
            M "Drivers" "run"
            L "--------------------------------------------"
            L "  MODUL 4: Treiber-Updates"
            L "--------------------------------------------"
            try {
                L "  Windows Update Service fuer Treiber initialisieren..."
                $session = New-Object -ComObject Microsoft.Update.Session
                $searcher = $session.CreateUpdateSearcher()
                # Treiber-Updates "Optionale Updates" liegen im Microsoft Update Service
                # (BrowseOnly=true). Ohne diesen Service-Switch findet WUA hier oft nur
                # einen Bruchteil der tatsaechlich verfuegbaren Treiber.
                $muId = Enable-MicrosoftUpdateService
                if ($muId) {
                    $searcher.ServerSelection = 3   # ssOthers
                    $searcher.ServiceID = $muId
                    L "  Microsoft Update Service aktiv - optionale Treiber werden einbezogen"
                } else {
                    L "  [HINWEIS] Microsoft Update Service nicht verfuegbar - nur Standard Windows Update"
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
                    if ($r.RebootRequired) { L "  >>> NEUSTART ERFORDERLICH <<<" }

                    # FIX v2.3.3: Verifikation - WUA-ResultCode=2 luegt bei optionalen/superseded Treibern.
                    # Re-Search; was immer noch IsInstalled=0 ist, wurde NICHT wirklich installiert.
                    # Fallback: pnputil mit den heruntergeladenen Treiber-Dateien (Microsoft-signiert).
                    if ($reportedOk.Count -gt 0) {
                        L ""
                        L "  Verifiziere Installation (Re-Scan)..."
                        try {
                            $verSearcher = $session.CreateUpdateSearcher()
                            if ($muId) {
                                $verSearcher.ServerSelection = 3
                                $verSearcher.ServiceID = $muId
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
                                    L "  [OK] pnputil-Fallback: $pnpInstalled Treiber-Pakete uebernommen"
                                    # echte erfolgsmenge neu berechnen
                                    $drvFail = [Math]::Max(0, $stillPending.Count - $pnpInstalled)
                                    $drvOk = $dColl.Count - $drvFail
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
            $i++; P ($i / $total * 100)
            L ""
        }

        # ── WINGET ──
        if ($cfg.Winget) {
            if (IsStopped) { $sync.Done = $true; return }
            M "Winget" "run"
            L "--------------------------------------------"
            L "  MODUL 5: Apps aktualisieren (Winget)"
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

                    # Process starten, Output live streamen UND Laufzeit ueberwachen.
                    # 60-Min-Timeout: ein einzelner Riesen-Download (z.B. Game-Engines
                    # / grosse Suites) oder ein haengender Installer darf die Wartung
                    # nicht endlos blockieren - dann lieber dieses Modul ueberspringen
                    # (Bug: 145 Min ohne Reaktion).
                    $wgRun = Invoke-MonitoredProcess -FileName $wg `
                               -Arguments "upgrade --all --include-unknown --disable-interactivity --accept-source-agreements --accept-package-agreements" `
                               -TimeoutSec 3600
                    # Result-Detection braucht alle Zeilen; Live-Log filtert nur Block-Progress.
                    $wgUpgradeOutput = $wgRun.Lines
                    $wgTimedOut = $wgRun.TimedOut
                    $exitCode   = $wgRun.ExitCode
                    # winget gibt bei "nichts zu tun" haeufig Exit 0 zurueck mit Sprach-Meldung
                    # "Es wurde kein installiertes Paket gefunden" (DE) / "No installed package" (EN) /
                    # "Aucun package installe" (FR). Dann ist nichts aktualisiert worden.
                    $combined = ($wgUpgradeOutput -join " ")
                    $nothingToDo = $combined -match 'kein installiertes Paket|No installed package|Aucun package install'
                    $installedAny = $combined -match 'Successfully installed|Erfolgreich installiert|Installation reussie'
                    L ""
                    if ($wgTimedOut) {
                        L "  [WARNUNG] App-Updates nach 60 Min ohne Reaktion abgebrochen"
                        L "  Wahrscheinlich ein sehr grosser Download oder haengender Installer"
                        Mark "Winget" "warn" "Nach 60 Min abgebrochen - eine App (vermutlich ein sehr grosser Download) hat zu lange gebraucht. Die uebrigen Apps wurden aktualisiert; bitte JustUpdate spaeter erneut ausfuehren."
                    } elseif ($exitCode -eq 0) {
                        if ($nothingToDo -and -not $installedAny) {
                            L "  [OK] Keine App-Updates verfuegbar - alle Apps aktuell"
                            Mark "Winget" "ok" "keine Updates verfuegbar"
                        } elseif ($installedAny) {
                            L "  [OK] Apps erfolgreich aktualisiert"
                            Mark "Winget" "ok" "Apps aktualisiert"
                        } else {
                            L "  [OK] Winget-Lauf abgeschlossen"
                            Mark "Winget" "ok" "Lauf abgeschlossen"
                        }
                    } elseif ($exitCode -eq -1978335189) {
                        L "  [OK] Keine Updates verfuegbar - alle Apps aktuell"
                        Mark "Winget" "ok" "alle Apps aktuell"
                    } else {
                        L "  [WARNUNG] Winget abgeschlossen mit Exit-Code: $exitCode"
                        L "  Einige Apps konnten moeglicherweise nicht aktualisiert werden"
                        Mark "Winget" "warn" "Exit-Code $exitCode - nicht alle Apps aktualisiert"
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
            $i++; P ($i / $total * 100)
            L ""
        }

        # ── STORE APPS ──
        if ($cfg.Store) {
            if (IsStopped) { $sync.Done = $true; return }
            M "Store" "run"
            L "--------------------------------------------"
            L "  MODUL 6: Microsoft Store Apps"
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
            $i++; P ($i / $total * 100)
            L ""
        }

        # ── REPAIR ──
        if ($cfg.Repair) {
            if (IsStopped) { $sync.Done = $true; return }
            M "Repair" "run"
            L "--------------------------------------------"
            L "  MODUL 7: System-Reparatur"
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
                $dismRun = Invoke-MonitoredProcess -FileName "dism.exe" `
                             -Arguments "/online /cleanup-image /restorehealth" `
                             -TimeoutSec 2700 -OutEncoding $oemEnc
                $dismExit     = $dismRun.ExitCode
                $dismTimedOut = $dismRun.TimedOut
                $dismOk = (-not $dismTimedOut) -and ($dismExit -eq 0)
                if ($dismOk) {
                    L "  [OK] DISM abgeschlossen"
                } elseif ($dismTimedOut) {
                    L "  [WARNUNG] DISM reagierte 45 Min nicht - abgebrochen und uebersprungen"
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
            $i++; P ($i / $total * 100)
            L ""
        }

        # ── NETWORK ──
        if ($cfg.Network) {
            if (IsStopped) { $sync.Done = $true; return }
            M "Network" "run"
            L "--------------------------------------------"
            L "  MODUL 8: Netzwerk reparieren"
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
                    $so = $pr.StandardOutput.ReadToEnd()
                    $se = $pr.StandardError.ReadToEnd()
                    $pr.WaitForExit()
                    return @{ Out = ($so + $se) -split "`r?`n"; Exit = $pr.ExitCode }
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
            $i++; P ($i / $total * 100)
            L ""
        }

        # ── CLEANUP ──
        if ($cfg.Cleanup) {
            if (IsStopped) { $sync.Done = $true; return }
            M "Cleanup" "run"
            L "--------------------------------------------"
            L "  MODUL 9: Bereinigung & Optimierung"
            L "--------------------------------------------"
            try {
                # Papierkorb
                L "  Schritt 1/5: Papierkorb leeren..."
                try {
                    Clear-RecycleBin -Force -ErrorAction Stop
                    L "    [OK] Papierkorb geleert"
                } catch {
                    L "    Papierkorb bereits leer oder Zugriff verweigert"
                }

                # DNS Cache
                L "  Schritt 2/5: DNS-Cache leeren..."
                & ipconfig /flushdns 2>&1 | Out-Null
                L "    [OK] DNS-Cache geleert"

                # Temp Dateien (alle User-Profile + System-Temp)
                # Iteriert C:\Users\*\AppData\Local\Temp dynamisch — keine Hardcoded-Usernames.
                L "  Schritt 3/5: Temporaere Dateien entfernen..."
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
                L "  Schritt 4/5: Windows Update Cache..."
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
                L "  Schritt 5/5: Thumbnail-Cache..."
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

                L ""
                L "  [OK] Bereinigung abgeschlossen"
                Mark "Cleanup" "ok" "$removed Dateien, $([Math]::Round($freedMB,1)) MB freigegeben"
            } catch {
                L "  [FEHLER] $($_.Exception.Message)"
                Mark "Cleanup" "err" $_.Exception.Message
            }
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
            $e.xTime.Text = "{0:D2}:{1:D2}" -f [int]$el.TotalMinutes, $el.Seconds
        }
    })
    $script:ClockTimer.Start()

    # UI poll
    $script:UITimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:UITimer.Interval = [TimeSpan]::FromMilliseconds(150)
    $script:UITimer.Add_Tick({
        $s = $script:SyncHash
        while ($s.Lines.Count -gt 0) {
            try {
                $line = $s.Lines[0]
                $s.Lines.RemoveAt(0)
                $e.xLogBox.AppendText("$line`r`n")
                $e.xLogBox.ScrollToEnd()
                $e.xStatus.Text = $line
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

function End-Session {
    param([switch]$completed)
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
                        module  = $k
                        status  = [string]$r.Status
                        details = [string]$r.Details
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
                modules         = $modules
            }
            $jsonPath = [IO.Path]::ChangeExtension($script:LogPath, $null).TrimEnd('.') -replace 'Maintenance_', 'result_'
            $jsonPath = "$jsonPath.json"
            $report | ConvertTo-Json -Depth 5 | Out-File -FilePath $jsonPath -Encoding utf8
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

        $msg    = "$ok erfolgreich, $warn Warnungen, $err Fehler"
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
            $msg += "`n`nBericht jetzt an den Support senden? (oeffnet E-Mail +"
            $msg += "`nden Log-Ordner zum Anhaengen)"
            $ans = [System.Windows.MessageBox]::Show($msg, $header,
                [System.Windows.MessageBoxButton]::YesNo, $icon)
            if ($ans -eq [System.Windows.MessageBoxResult]::Yes) {
                try {
                    $subj = "JustUpdate Bericht - $($env:COMPUTERNAME) - $ok OK / $warn Warn / $err Fehler"
                    $bodyTxt = "Automatischer JustUpdate-Bericht`r`n`r`n" +
                               "Host: $($env:COMPUTERNAME)`r`nBenutzer: $($env:USERNAME)`r`n" +
                               "Version: v$($script:JUVersion)`r`n" +
                               "Ergebnis: $ok OK, $warn Warnungen, $err Fehler`r`n`r`n" +
                               "Bitte die Log-Datei aus dem geoeffneten Ordner anhaengen."
                    $u = "mailto:info@itintechsolutions.ch?subject=$([uri]::EscapeDataString($subj))&body=$([uri]::EscapeDataString($bodyTxt))"
                    Start-Process $u
                    Start-Process explorer.exe "/select,`"$($script:LogPath)`""
                } catch {}
            }
        } else {
            [System.Windows.MessageBox]::Show($msg, $header, "OK", $icon) | Out-Null
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
})
$Window.ShowDialog() | Out-Null
