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
                    <Button x:Name="xMax" DockPanel.Dock="Right" Style="{StaticResource WinBtn}" Content="&#x2610;" FontSize="12"/>
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

