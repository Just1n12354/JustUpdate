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
