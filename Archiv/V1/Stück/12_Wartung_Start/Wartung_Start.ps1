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
    # Bug-Fix v2.7.6 (K1): Reentrancy-Guard GANZ am Anfang. Der "Apps
    # schliessen?"-Dialog unten ist eine MessageBox ohne Owner - ihr Message-
    # Pump stellt Klicks aufs Hauptfenster weiter zu. Ein Doppelklick auf
    # START konnte so ZWEI Worker im selben Prozess starten (der Global-Mutex
    # schuetzt nur prozessUEBERgreifend); der verwaiste Worker war danach
    # nicht mehr stoppbar, weil seine Pipeline-Referenz ueberschrieben wurde.
    if ($script:MaintRunning) { return }
    $script:MaintRunning = $true
    $e.xStart.IsEnabled = $false

    # Vor Update-Modulen: User fragen, ob laufende Apps geschlossen werden sollen.
    # Verhindert dass Update-Installer sich an gesperrten Dateien aufhaengen.
    # Winget mit reingenommen: Hauptursache fuer file-in-use sind Tray-Apps wie
    # OBS/Epic, die ueber winget aktualisiert werden.
    # Aktuelle Auswahl direkt sichern - so laeuft der naechste (auch geplante)
    # Lauf garantiert mit dem, was der User zuletzt eingestellt hat.
    Save-JUSettings

    # Bug-Fix v2.7.5: Jeder Wartungslauf bekommt seine EIGENE Logdatei. Beim
    # zweiten Start in derselben Sitzung haengte das Log vorher an Lauf 1 an
    # und das result_*.json von Lauf 1 wurde ueberschrieben (gleicher Name).
    if ($script:SyncHash) { New-JULogFile }

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
