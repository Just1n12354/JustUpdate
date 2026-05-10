# Version: 2.3.5
# Determine script/exe path first
$ScriptPath = if ($PSCommandPath) { $PSCommandPath }
              elseif ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path }
              else { [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName }

# Ensure Windows PowerShell + STA + Admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($PSVersionTable.PSEdition -eq "Core" -or
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
if ($env:JUSTUPDATE_NO_SELFUPDATE -ne "1") {
    try {
        $remoteUrl = "https://raw.githubusercontent.com/Just1n12354/JustUpdate/main/MaintenanceProGUI_MODERN.ps1"
        $tempFile  = Join-Path $env:TEMP "JustUpdate_remote.ps1"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $remoteUrl -OutFile $tempFile -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        if ((Get-Item $tempFile).Length -gt 1000) {
            $localVerLine  = Get-Content $ScriptPath -TotalCount 1
            $remoteVerLine = Get-Content $tempFile  -TotalCount 1
            $localVer  = if ($localVerLine  -match '#\s*Version:\s*([\d\.]+)') { [version]$Matches[1] } else { [version]'0.0.0' }
            $remoteVer = if ($remoteVerLine -match '#\s*Version:\s*([\d\.]+)') { [version]$Matches[1] } else { $null }
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
                    Copy-Item -Path $tempFile -Destination $ScriptPath -Force
                    Remove-Item $tempFile -ErrorAction SilentlyContinue
                    $env:JUSTUPDATE_NO_SELFUPDATE = "1"
                    Start-Process powershell.exe -Verb RunAs `
                        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -File `"$ScriptPath`""
                    exit
                }
            }
        }
        Remove-Item $tempFile -ErrorAction SilentlyContinue
    } catch {
        # Offline / GitHub unreachable / keine Schreibrechte -> Fallback auf lokale Version
    }
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# =====================================================================
# PATHS
# =====================================================================
$BaseDir = Split-Path -Parent $ScriptPath
$LogDir  = Join-Path $env:APPDATA "JustUpdate\logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$script:LogPath = Join-Path $LogDir ("Maintenance_{0}.log" -f (Get-Date -Format "yyyy-MM-dd_HH-mm-ss"))
"" | Out-File -FilePath $script:LogPath -Encoding utf8

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
        <SolidColorBrush x:Key="BgMain"    Color="#05090E"/>
        <SolidColorBrush x:Key="BgPanel"   Color="#0A1018"/>
        <SolidColorBrush x:Key="BgCard"    Color="#0F1923"/>
        <SolidColorBrush x:Key="BgInput"   Color="#0B1219"/>
        <SolidColorBrush x:Key="Bdr"       Color="#1A2E42"/>
        <SolidColorBrush x:Key="Fg"        Color="#E8EDF3"/>
        <SolidColorBrush x:Key="FgDim"     Color="#8899AA"/>
        <SolidColorBrush x:Key="FgMute"    Color="#4A6075"/>
        <SolidColorBrush x:Key="Blu"       Color="#3B82F6"/>
        <SolidColorBrush x:Key="Grn"       Color="#22C55E"/>
        <SolidColorBrush x:Key="Rd"        Color="#EF4444"/>
        <SolidColorBrush x:Key="Amb"       Color="#F59E0B"/>

        <Style x:Key="Sw" TargetType="ToggleButton">
            <Setter Property="Width" Value="40"/>
            <Setter Property="Height" Value="22"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ToggleButton">
                        <Border x:Name="BgBd" CornerRadius="11" Background="#182838">
                            <Ellipse x:Name="Dot" Width="16" Height="16" Fill="#4A6075" HorizontalAlignment="Left" Margin="3,0,0,0"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="BgBd" Property="Background" Value="{StaticResource Blu}"/>
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
                                <Setter TargetName="B" Property="Background" Value="#1A2E42"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Border CornerRadius="16" Background="{StaticResource BgMain}" BorderBrush="#0D1520" BorderThickness="1.5">
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
                    <Ellipse Width="10" Height="10" Fill="{StaticResource Blu}" Margin="0,0,8,0"/>
                    <TextBlock x:Name="xTitleBar" Text="System Maintenance Pro" Foreground="{StaticResource Fg}" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center"/>
                </StackPanel>
                <DockPanel Grid.Column="1" LastChildFill="False">
                    <Button x:Name="xClose" DockPanel.Dock="Right" Style="{StaticResource WinBtn}" Content="X" FontSize="12"/>
                    <Button x:Name="xMax" DockPanel.Dock="Right" Style="{StaticResource WinBtn}" Content="☐" FontSize="12"/>
                    <Button x:Name="xMin" DockPanel.Dock="Right" Style="{StaticResource WinBtn}" Content="_" FontSize="14"/>
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
                                        <TextBlock x:Name="xIcoRestore" Text="R" Foreground="{StaticResource Blu}" FontSize="14" FontWeight="Bold" VerticalAlignment="Center"/>
                                        <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="6,0,0,0"><TextBlock x:Name="xRestore" Foreground="{StaticResource Fg}" FontSize="12"/><TextBlock x:Name="xRestoreD" Foreground="{StaticResource FgMute}" FontSize="9.5"/></StackPanel>
                                        <ToggleButton x:Name="xTglRestore" Grid.Column="2" Style="{StaticResource Sw}" IsChecked="True" VerticalAlignment="Center"/>
                                    </Grid>
                                </Border>
                                <Border Background="{StaticResource BgCard}" CornerRadius="10" Padding="12,10" Margin="0,0,0,5" BorderBrush="{StaticResource Bdr}" BorderThickness="1">
                                    <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="28"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                                        <TextBlock x:Name="xIcoDefender" Text="D" Foreground="{StaticResource Blu}" FontSize="14" FontWeight="Bold" VerticalAlignment="Center"/>
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
                                        <TextBlock x:Name="xIcoWinget" Text="A" Foreground="{StaticResource Blu}" FontSize="14" FontWeight="Bold" VerticalAlignment="Center"/>
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

                        <Border Grid.Row="2" Background="#070C12" CornerRadius="10" Padding="10" Margin="0,6,0,0" BorderBrush="{StaticResource Bdr}" BorderThickness="1">
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
                                <GradientStop Color="#0A1420" Offset="0"/>
                                <GradientStop Color="#101E30" Offset="0.5"/>
                                <GradientStop Color="#0A1828" Offset="1"/>
                            </LinearGradientBrush>
                        </Border.Background>
                        <StackPanel>
                            <TextBlock x:Name="xTag" Foreground="{StaticResource Blu}" FontSize="10.5" FontWeight="SemiBold" Margin="0,0,0,3"/>
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
                                                <GradientStop Color="#3B82F6" Offset="0"/>
                                                <GradientStop Color="#2563EB" Offset="1"/>
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
                                    <Border x:Name="B" CornerRadius="12" Background="#7F1D1D">
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
                        <Border CornerRadius="4" Background="#0F1923" Height="6">
                            <Border x:Name="xBar" CornerRadius="4" HorizontalAlignment="Left" Width="0">
                                <Border.Background>
                                    <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                                        <GradientStop Color="#3B82F6" Offset="0"/>
                                        <GradientStop Color="#06B6D4" Offset="1"/>
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
                    <Border Grid.Row="3" Background="#070C12" CornerRadius="14" BorderBrush="{StaticResource Bdr}" BorderThickness="1" MinHeight="200">
                        <Grid Margin="14">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>
                            <TextBlock x:Name="xLogHdr" Foreground="{StaticResource Fg}" FontSize="12" FontWeight="SemiBold" Margin="0,0,0,8"/>
                            <TextBox x:Name="xLogBox" Grid.Row="1"
                                     Background="Transparent" Foreground="#98B0C8"
                                     FontFamily="Consolas" FontSize="10.5"
                                     IsReadOnly="True" BorderThickness="0"
                                     VerticalScrollBarVisibility="Auto" TextWrapping="Wrap"/>
                        </Grid>
                    </Border>
                </Grid>
            </Grid>
            </ScrollViewer>

            <!-- FOOTER -->
            <TextBlock x:Name="xFooter" Grid.Row="2" Foreground="#3A4E62" FontSize="9" Margin="20,0" VerticalAlignment="Center"/>
        </Grid>
    </Border>
</Window>
"@

# =====================================================================
# LOAD WINDOW
# =====================================================================
$reader = New-Object System.Xml.XmlNodeReader $xamlXml
$Window = [Windows.Markup.XamlReader]::Load($reader)

# Get elements
$e = @{}
$allNames = @(
    "TitleBar","xLang","xMin","xMax","xClose","xTitleBar",
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
    $e.xFooter.Text    = T "Footer"
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

function Set-ModIcon([string]$id, [string]$state) {
    $ico = $script:IconElements[$id]
    if (-not $ico) { return }
    $ico.Dispatcher.Invoke([Action]{
        switch ($state) {
            "run"  { $ico.Text = "..."; $ico.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#F59E0B") }
            "ok"   { $ico.Text = [string][char]0x2713; $ico.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#22C55E") }
            "err"  { $ico.Text = "X"; $ico.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#EF4444") }
            default {
                $ico.Text = $script:Icons[$id]
                $ico.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#3B82F6")
            }
        }
    })
}

function Reset-AllIcons {
    foreach ($k in $script:Icons.Keys) {
        $ico = $script:IconElements[$k]
        if ($ico) {
            $ico.Text = $script:Icons[$k]
            $ico.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#3B82F6")
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

function Start-Maintenance {
    Reset-AllIcons
    $e.xLogBox.Clear()
    $e.xBar.Width = 0
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
        Config   = $cfg
        LogPath  = $script:LogPath
        Stop     = $false
        Done     = $false
        Lines    = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
        Progress = 0
        Module   = ""
        Results  = [hashtable]::Synchronized(@{})
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

        function L($m) {
            $line = "[$(Get-Date -F 'HH:mm:ss')] $m"
            try { $line | Out-File $logFile -Append -Encoding utf8 } catch {}
            $sync.Lines.Add($line) | Out-Null
        }
        function P($v) { $sync.Progress = [Math]::Min(100, [int]$v) }
        function M($id,$s) { $sync.Module = "$id|$s" }
        function IsStopped { $sync.Stop -eq $true }
        # Mark result: status = ok|warn|err, details = free-text summary
        function Mark($id, $status, $details) {
            $sync.Results[$id] = @{ Status = $status; Details = $details }
            $uiState = switch ($status) { "ok" { "ok" } "warn" { "ok" } default { "err" } }
            M $id $uiState
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

        # ── RESTORE POINT ──
        if ($cfg.Restore) {
            if (IsStopped) { $sync.Done = $true; return }
            M "Restore" "run"
            L "--------------------------------------------"
            L "  MODUL 1: Wiederherstellungspunkt"
            L "--------------------------------------------"
            L "  Systemschutz aktivieren auf C:\..."
            try {
                try { Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue } catch {}
                L "  Erstelle Wiederherstellungspunkt..."
                L "  Name: MaintenancePro_$(Get-Date -F 'yyyyMMdd_HHmm')"
                Checkpoint-Computer -Description "MaintenancePro_$(Get-Date -F 'yyyyMMdd_HHmm')" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
                L "  [OK] Wiederherstellungspunkt erfolgreich erstellt"
                Mark "Restore" "ok" "erstellt"
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
                if (Get-Command Update-MpSignature -ErrorAction SilentlyContinue) {
                    # Aktuelle Version anzeigen
                    try {
                        $defStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue
                        if ($defStatus) {
                            L "  Aktueller Status:"
                            L "    Antivirus-Version:  $($defStatus.AntivirusSignatureVersion)"
                            L "    Letztes Update:     $($defStatus.AntivirusSignatureLastUpdated)"
                            L "    Echtzeit-Schutz:    $(if($defStatus.RealTimeProtectionEnabled){'Aktiv'}else{'Inaktiv'})"
                        }
                    } catch {}
                    L "  Lade neueste Signaturen herunter..."
                    Update-MpSignature -ErrorAction Stop
                    # Neue Version anzeigen
                    try {
                        $defNew = Get-MpComputerStatus -ErrorAction SilentlyContinue
                        if ($defNew) {
                            L "  Neue Version:         $($defNew.AntivirusSignatureVersion)"
                        }
                    } catch {}
                    L "  [OK] Defender-Signaturen erfolgreich aktualisiert"
                    Mark "Defender" "ok" "Signaturen aktualisiert"
                } else {
                    L "  [WARNUNG] Windows Defender ist auf diesem System nicht verfuegbar"
                    Mark "Defender" "warn" "Defender nicht verfuegbar"
                }
            } catch {
                L "  [FEHLER] $($_.Exception.Message)"
                Mark "Defender" "err" $_.Exception.Message
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
                        try { $size = " ($([Math]::Round($u.MaxDownloadSize / 1MB, 1)) MB)" } catch {}
                        L "    [$updateNum/$($softwareUpdates.Count)] $($u.Title)$size"
                        if (-not $u.EulaAccepted) { try { $u.AcceptEula() | Out-Null } catch {} }
                        if (-not $u.IsDownloaded) { $dlColl.Add($u) | Out-Null }
                        $updateNum++
                    }
                    L ""

                    $dlFailed = $false
                    if ($dlColl.Count -gt 0) {
                        L "  Lade $($dlColl.Count) Update(s) herunter..."
                        $dl = $session.CreateUpdateDownloader()
                        $dl.Updates = $dlColl
                        $dlResult = $dl.Download()
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
                        $inst = $session.CreateUpdateInstaller()
                        $inst.Updates = $instColl
                        $r = $inst.Install()

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
                    $dl = $session.CreateUpdateDownloader()
                    $dl.Updates = $dColl
                    $dlRes = $dl.Download()
                    if ($dlRes.ResultCode -eq 2) {
                        L "  [OK] Download abgeschlossen"
                    } else {
                        L "  [FEHLER] Treiber-Download fehlgeschlagen (Status: $($dlRes.ResultCode), HResult: 0x$('{0:X}' -f $dlRes.HResult))"
                        L "         Typischer Grund: fehlende Admin-Rechte"
                        Mark "Drivers" "err" "Treiber-Download fehlgeschlagen"
                        throw "Download failed"
                    }
                    L "  Installiere Treiber..."
                    $inst = $session.CreateUpdateInstaller()
                    $inst.Updates = $dColl
                    $r = $inst.Install()

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
                $wg = (Get-Command winget -ErrorAction SilentlyContinue).Source
                if ($wg) {
                    L "  Winget gefunden: $wg"
                    L "  Pruefe verfuegbare Updates..."
                    L ""

                    # Zuerst zeigen was verfuegbar ist
                    $listOut = & $wg upgrade --accept-source-agreements 2>&1
                    $listOut | ForEach-Object {
                        $l = "$_".Trim()
                        if ($l.Length -gt 2) { L "    $l" }
                    }
                    L ""
                    L "  Starte Upgrade aller Apps..."
                    L ""

                    # Process starten und Output Zeile fuer Zeile streamen
                    $psi = New-Object System.Diagnostics.ProcessStartInfo
                    $psi.FileName = $wg
                    $psi.Arguments = "upgrade --all --include-unknown --disable-interactivity --accept-source-agreements --accept-package-agreements"
                    $psi.RedirectStandardOutput = $true
                    $psi.RedirectStandardError = $true
                    $psi.UseShellExecute = $false
                    $psi.CreateNoWindow = $true
                    $proc = [System.Diagnostics.Process]::Start($psi)

                    while (-not $proc.StandardOutput.EndOfStream) {
                        $l = $proc.StandardOutput.ReadLine()
                        if ($l -and $l.Trim().Length -gt 1) {
                            L "    $($l.Trim())"
                        }
                    }
                    $proc.WaitForExit()

                    $exitCode = $proc.ExitCode
                    L ""
                    if ($exitCode -eq 0) {
                        L "  [OK] Alle Apps erfolgreich aktualisiert"
                        Mark "Winget" "ok" "Apps aktualisiert"
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
                L "  Verbinde mit MDM App Management..."
                $ns = "root\cimv2\mdm\dmmap"
                $cls = "MDM_EnterpriseModernAppManagement_AppManagement01"
                $obj = Get-CimInstance -Namespace $ns -ClassName $cls -ErrorAction Stop
                L "  Starte Update-Scan fuer alle Store Apps..."
                Invoke-CimMethod -InputObject $obj -MethodName "UpdateScanMethod" -ErrorAction Stop | Out-Null
                L "  [OK] Store-Update Scan erfolgreich gestartet"
                L "  Updates werden im Hintergrund heruntergeladen und installiert"
                Mark "Store" "ok" "Scan im Hintergrund gestartet"
            } catch {
                L "  MDM nicht verfuegbar: $($_.Exception.Message)"
                L "  Oeffne Microsoft Store Updates-Seite..."
                try {
                    Start-Process "ms-windows-store://downloadsandupdates" -ErrorAction Stop
                    L "  [WARNUNG] Store-Seite geoeffnet - bitte manuell 'Alle aktualisieren' klicken"
                    Mark "Store" "warn" "manueller Klick in Store noetig"
                } catch {
                    L "  [FEHLER] Store konnte nicht geoeffnet werden"
                    Mark "Store" "err" "Store nicht erreichbar"
                }
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
                L ""

                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = "sfc.exe"
                $psi.Arguments = "/scannow"
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError = $true
                $psi.UseShellExecute = $false
                $psi.CreateNoWindow = $true
                # SFC gibt UTF-16 LE aus — sonst bekommen wir Gibberish
                $psi.StandardOutputEncoding = [System.Text.Encoding]::Unicode
                $psi.StandardErrorEncoding  = [System.Text.Encoding]::Unicode
                $proc = [System.Diagnostics.Process]::Start($psi)
                while (-not $proc.StandardOutput.EndOfStream) {
                    $l = $proc.StandardOutput.ReadLine()
                    if ($l -and $l.Trim().Length -gt 3) { L "    $($l.Trim())" }
                }
                $sfcErr = $proc.StandardError.ReadToEnd()
                $proc.WaitForExit()
                $sfcExit = $proc.ExitCode
                if ($sfcErr -and $sfcErr.Trim().Length -gt 0) {
                    $sfcErr.Split("`n") | ForEach-Object { $l = $_.Trim(); if ($l.Length -gt 0) { L "    $l" } }
                }
                $sfcOk = ($sfcExit -eq 0)
                if ($sfcOk) {
                    L "  [OK] SFC abgeschlossen"
                } else {
                    L "  [FEHLER] SFC fehlgeschlagen (Exit-Code: $sfcExit)"
                }

                L ""
                L "  Schritt 2/2: DISM (Deployment Image Servicing)"
                L "  Repariere Windows-Komponentenspeicher..."
                L ""

                $psi2 = New-Object System.Diagnostics.ProcessStartInfo
                $psi2.FileName = "dism.exe"
                $psi2.Arguments = "/online /cleanup-image /restorehealth"
                $psi2.RedirectStandardOutput = $true
                $psi2.RedirectStandardError = $true
                $psi2.UseShellExecute = $false
                $psi2.CreateNoWindow = $true
                $proc2 = [System.Diagnostics.Process]::Start($psi2)
                while (-not $proc2.StandardOutput.EndOfStream) {
                    $l = $proc2.StandardOutput.ReadLine()
                    if ($l -and $l.Trim().Length -gt 3) { L "    $($l.Trim())" }
                }
                $dismErr = $proc2.StandardError.ReadToEnd()
                $proc2.WaitForExit()
                $dismExit = $proc2.ExitCode
                if ($dismErr -and $dismErr.Trim().Length -gt 0) {
                    $dismErr.Split("`n") | ForEach-Object { $l = $_.Trim(); if ($l.Length -gt 0) { L "    $l" } }
                }
                $dismOk = ($dismExit -eq 0)
                if ($dismOk) {
                    L "  [OK] DISM abgeschlossen"
                } else {
                    L "  [FEHLER] DISM fehlgeschlagen (Exit-Code: $dismExit)"
                }

                L ""
                if ($sfcOk -and $dismOk) {
                    L "  [OK] System-Reparatur abgeschlossen"
                    Mark "Repair" "ok" "SFC + DISM erfolgreich"
                } elseif ($sfcOk -or $dismOk) {
                    $who = if ($sfcOk) { "DISM fehlgeschlagen" } else { "SFC fehlgeschlagen" }
                    L "  [WARNUNG] Teilweise erfolgreich - $who"
                    Mark "Repair" "warn" $who
                } else {
                    L "  [FEHLER] SFC und DISM fehlgeschlagen - Admin-Rechte pruefen"
                    Mark "Repair" "err" "SFC und DISM fehlgeschlagen"
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

                L "  Schritt 1/5: DNS-Cache leeren..."
                $dnsOut = & ipconfig /flushdns 2>&1
                $dnsOut | ForEach-Object { $l = "$_".Trim(); if ($l.Length -gt 1) { L "    $l" } }
                if ($LASTEXITCODE -ne 0) { $netFailures += "DNS-Flush" }

                L "  Schritt 2/5: Winsock-Katalog zuruecksetzen..."
                $wsOut = & netsh winsock reset 2>&1
                $wsOut | ForEach-Object { $l = "$_".Trim(); if ($l.Length -gt 1) { L "    $l" } }
                if ($LASTEXITCODE -ne 0) {
                    $netFailures += "Winsock-Reset"
                }

                L "  Schritt 3/5: IP-Adresse freigeben..."
                & ipconfig /release 2>&1 | Out-Null

                L "  Schritt 4/5: Neue IP-Adresse beziehen..."
                $renewOut = & ipconfig /renew 2>&1
                $renewOut | ForEach-Object { $l = "$_".Trim(); if ($l.Length -gt 1) { L "    $l" } }

                L "  Schritt 5/5: TCP/IP-Stack zuruecksetzen..."
                $tcpOut = & netsh int ip reset 2>&1
                $tcpOut | ForEach-Object { $l = "$_".Trim(); if ($l.Length -gt 1) { L "    $l" } }
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

                # Temp Dateien
                L "  Schritt 3/5: Temporaere Dateien entfernen..."
                $removed = 0
                $freedMB = 0
                @($env:TEMP, "C:\Windows\Temp") | ForEach-Object {
                    $dir = $_
                    if (Test-Path $dir) {
                        L "    Durchsuche: $dir"
                        Get-ChildItem $dir -Recurse -Force -ErrorAction SilentlyContinue |
                            Where-Object { -not $_.PSIsContainer -and $_.LastWriteTime -lt (Get-Date).AddDays(-3) } |
                            ForEach-Object {
                                try {
                                    $freedMB += $_.Length / 1MB
                                    Remove-Item $_.FullName -Force -ErrorAction Stop
                                    $removed++
                                } catch {}
                            }
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

                # Thumbnail Cache
                L "  Schritt 5/5: Thumbnail-Cache..."
                try {
                    $thumbDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Explorer"
                    if (Test-Path $thumbDir) {
                        $thumbFiles = Get-ChildItem $thumbDir -Filter "thumbcache_*.db" -Force -ErrorAction SilentlyContinue
                        $thumbSize = [Math]::Round(($thumbFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 1)
                        $thumbFiles | ForEach-Object { try { Remove-Item $_.FullName -Force } catch {} }
                        L "    [OK] $($thumbFiles.Count) Cache-Dateien ($thumbSize MB)"
                    }
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
        $okCount = 0; $warnCount = 0; $errCount = 0
        foreach ($modId in $active) {
            if ($sync.Results.ContainsKey($modId)) {
                $r = $sync.Results[$modId]
                $prefix = switch ($r.Status) {
                    "ok"   { $okCount++;   "[OK]  " }
                    "warn" { $warnCount++; "[!]   " }
                    "err"  { $errCount++;  "[FAIL]" }
                    default { "[?]   " }
                }
                L "  $prefix $modId - $($r.Details)"
            } else {
                L "  [?]    $modId - kein Ergebnis"
                $errCount++
            }
        }
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
        if ($pw -gt 0) { $e.xBar.Width = [Math]::Max(0, $pw * $pct / 100) }
        if ($s.Module -and $s.Module.Contains("|")) {
            $parts = $s.Module -split "\|", 2
            $s.Module = ""
            Set-ModIcon $parts[0] $parts[1]
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
        $msg    = "$ok erfolgreich, $warn Warnungen, $err Fehler"
        $icon   = if ($err -gt 0) { "Error" } elseif ($warn -gt 0) { "Warning" } else { "Information" }
        $header = if ($err -gt 0) { "Wartung mit Fehlern beendet" }
                  elseif ($warn -gt 0) { "Wartung mit Warnungen beendet" }
                  else { T "Done" }
        if ($err -gt 0 -or $warn -gt 0) {
            $msg += "`n`nDetails findest du im Log (Button 'LOG OEFFNEN')."
        }
        [System.Windows.MessageBox]::Show($msg, $header, "OK", $icon) | Out-Null
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
    # Dann PowerShell-Konsole verstecken
    $consoleHwnd = [Native.Win32]::GetConsoleWindow()
    if ($consoleHwnd -ne [IntPtr]::Zero) {
        [Native.Win32]::ShowWindow($consoleHwnd, 0) | Out-Null
    }
})
$Window.ShowDialog() | Out-Null
