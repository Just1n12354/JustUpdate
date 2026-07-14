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
                # Aufbereitung einzeln abgesichert: wirft Format-LiveLine (war schon
                # einmal Regressions-Quelle, v2.7.2), zeigen wir die Zeile ROH statt
                # sie zu verlieren - 'catch { break }' unten schluckte sonst alles.
                $disp = $null
                try { $disp = Format-LiveLine $line } catch { $disp = $line }
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

