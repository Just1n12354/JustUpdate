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

