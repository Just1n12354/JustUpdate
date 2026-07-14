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

