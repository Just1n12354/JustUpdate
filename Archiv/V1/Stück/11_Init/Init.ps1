# =====================================================================
# INIT
# =====================================================================
# Gespeicherte Modul-Auswahl + Sprache wiederherstellen (settings.json) -
# und zwar VOR Update-UI (Bug-Fix v2.7.5): der SelectionChanged-Handler von
# xLang ist an dieser Stelle noch nicht registriert, das Setzen von
# SelectedItem loest also KEIN Update-UI aus. Lief Update-UI zuerst (wie bis
# v2.7.4), blieben die UI-Texte nach einem Neustart auf Deutsch, obwohl die
# Sprach-ComboBox die gespeicherte Sprache (z.B. English) anzeigte.
Restore-JUSettings
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

