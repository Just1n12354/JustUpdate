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

