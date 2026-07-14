using System;
using System.Diagnostics;
using System.IO;
using System.Text;

namespace JustUpdate.Module;

/// <summary>
/// Aktualisiert installierte Windows-Anwendungen über Winget.
/// </summary>
internal static class Apps
{
    public const string Name = "apps";

    private const int TimeoutMilliseconds = 3_600_000;
    private const int ProcessTerminationTimeoutMilliseconds = 10_000;

    private const string WingetScript = @"
$ErrorActionPreference = 'Stop'

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding

$hadWarnings = $false

function Write-Line {
    param(
        [AllowEmptyString()]
        [string]$Text = ''
    )

    [Console]::Out.WriteLine($Text)
    [Console]::Out.Flush()
}

function Find-Winget {
    $command = Get-Command winget.exe -ErrorAction SilentlyContinue

    if ($command -and $command.Source) {
        return $command.Source
    }

    $candidates = New-Object System.Collections.Generic.List[string]

    if ($env:LOCALAPPDATA) {
        $currentUserWinget = Join-Path `
            $env:LOCALAPPDATA `
            'Microsoft\WindowsApps\winget.exe'

        [void]$candidates.Add($currentUserWinget)
    }

    try {
        $appInstallerPackages =
            Get-AppxPackage `
                -Name Microsoft.DesktopAppInstaller `
                -ErrorAction SilentlyContinue |
            Sort-Object Version -Descending

        foreach ($package in $appInstallerPackages) {
            if ($package.InstallLocation) {
                [void]$candidates.Add(
                    (Join-Path $package.InstallLocation 'winget.exe')
                )
            }
        }
    }
    catch {
        # Appx-Abfrage ist nicht auf jedem System verfügbar.
    }

    foreach ($candidate in $candidates) {
        if (
            $candidate -and
            (Test-Path -LiteralPath $candidate -PathType Leaf)
        ) {
            return $candidate
        }
    }

    return $null
}

try {
    Write-Line 'Winget wird gesucht ...'

    $winget = Find-Winget

    if (-not $winget) {
        Write-Line '[FEHLER] Winget wurde nicht gefunden.'
        Write-Line (
            'Installiere oder aktualisiere im Microsoft Store ' +
            'die Anwendung „App-Installer“.'
        )

        exit 1
    }

    Write-Line ""[OK] Winget gefunden: $winget""

    # Winget-Version ermitteln – robust gegen Warnungen
    $wingetVersionOutput = @(& $winget --version 2>&1)
    $wingetVersionExitCode = $LASTEXITCODE

    $wingetVersion =
        $wingetVersionOutput |
        ForEach-Object { ""$_"".Trim() } |
        Where-Object { $_ -match '^v?\d+(\.\d+){1,3}' } |
        Select-Object -First 1

    if ($wingetVersionExitCode -eq 0 -and $wingetVersion) {
        Write-Line ""Winget-Version: $wingetVersion""
    }
    else {
        Write-Line '[WARNUNG] Die Winget-Version konnte nicht ermittelt werden.'
        $hadWarnings = $true
    }

    $currentIdentity =
        [Security.Principal.WindowsIdentity]::GetCurrent()

    $windowsPrincipal =
        [Security.Principal.WindowsPrincipal]::new($currentIdentity)

    $isAdministrator =
        $windowsPrincipal.IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator
        )

    if (-not $isAdministrator) {
        Write-Line ''
        Write-Line (
            '[HINWEIS] JustUpdate wurde nicht als Administrator gestartet.'
        )

        Write-Line (
            'Updates mit Administratorrechten können deshalb ' +
            'möglicherweise nicht installiert werden.'
        )
    }

    Write-Line ''
    Write-Line 'Winget-Quellen werden aktualisiert ...'

    & $winget `
        source update `
        --disable-interactivity 2>&1 |
        ForEach-Object {
            Write-Line ""$_""
        }

    $sourceExitCode = $LASTEXITCODE

    if ($sourceExitCode -eq 0) {
        Write-Line '[OK] Winget-Quellen wurden aktualisiert.'
    }
    else {
        $hadWarnings = $true

        Write-Line (
            '[WARNUNG] Die Winget-Quellen konnten nicht vollständig ' +
            'aktualisiert werden.'
        )

        Write-Line ""Winget-Rückgabecode: $sourceExitCode""

        Write-Line (
            'Die App-Aktualisierung wird mit dem vorhandenen ' +
            'Paketindex fortgesetzt.'
        )
    }

    Write-Line ''
    Write-Line 'Verfügbare App-Updates werden installiert ...'

    Write-Line (
        'Dieser Vorgang kann mehrere Minuten dauern. ' +
        'Bitte JustUpdate nicht beenden.'
    )

    Write-Line ''

    $outputLines =
        New-Object System.Collections.Generic.List[string]

    & $winget `
        upgrade `
        --all `
        --include-unknown `
        --disable-interactivity `
        --accept-source-agreements `
        --accept-package-agreements 2>&1 |
        ForEach-Object {
            $line = ""$_""

            [void]$outputLines.Add($line)
            Write-Line $line
        }

    $upgradeExitCode = $LASTEXITCODE
    $combinedOutput = $outputLines -join [Environment]::NewLine

    $nothingToUpdate =
        $combinedOutput -match (
            'No installed package found|' +
            'No available upgrade|' +
            'No applicable upgrade|' +
            'No newer package versions are available|' +
            'No newer versions available|' +
            'kein installiertes Paket gefunden|' +
            'keine verfügbaren Upgrades|' +
            'kein anwendbares Upgrade|' +
            'keine neuere Paketversion verfügbar|' +
            'Aucun package installé|' +
            'Aucune mise à niveau disponible|' +
            'Aucune version plus récente'
        )

    $successfulUpdate =
        $combinedOutput -match (
            'Successfully installed|' +
            'Installation was successful|' +
            'Successfully upgraded|' +
            'Erfolgreich installiert|' +
            'Die Installation war erfolgreich|' +
            'Erfolgreich aktualisiert|' +
            'Installation réussie|' +
            'Mise à niveau réussie'
        )

    $applicationRestartRequired =
        $combinedOutput -match (
            'Restart the application to complete|' +
            'Restart the application|' +
            'Starten Sie die Anwendung neu|' +
            'Anwendung neu starten|' +
            'Redémarrez l.application'
        )

    $computerRestartRequired =
        $combinedOutput -match (
            'Restart your PC to finish|' +
            'Restart your computer|' +
            'reboot is required|' +
            'Starten Sie (Ihren|den) PC neu|' +
            'Windows-Neustart erforderlich|' +
            'Neustart des Computers erforderlich|' +
            'Redémarrez (votre|le) PC'
        )

    Write-Line ''

    if ($applicationRestartRequired) {
        Write-Line (
            '[HINWEIS] Mindestens eine aktualisierte Anwendung ' +
            'muss neu gestartet werden.'
        )
    }

    if ($computerRestartRequired) {
        Write-Line (
            '[NEUSTART ERFORDERLICH] Mindestens ein Update wird ' +
            'erst nach einem Windows-Neustart abgeschlossen.'
        )
    }

    if ($nothingToUpdate -and -not $successfulUpdate) {
        Write-Line '[OK] Alle installierten Apps sind aktuell.'

        if ($hadWarnings) {
            exit 2
        }

        exit 0
    }

    if ($upgradeExitCode -eq 0) {
        if ($successfulUpdate) {
            Write-Line (
                '[OK] Die installierten Apps wurden erfolgreich ' +
                'aktualisiert.'
            )
        }
        else {
            Write-Line '[OK] Winget-Aktualisierung abgeschlossen.'
        }

        if ($hadWarnings) {
            exit 2
        }

        exit 0
    }

    if ($successfulUpdate) {
        Write-Line (
            '[WARNUNG] Einige Apps wurden aktualisiert, mindestens ' +
            'ein Update ist jedoch fehlgeschlagen.'
        )

        Write-Line ""Winget-Rückgabecode: $upgradeExitCode""
        exit 2
    }

    Write-Line '[FEHLER] Die App-Aktualisierung ist fehlgeschlagen.'
    Write-Line ""Winget-Rückgabecode: $upgradeExitCode""

    exit 1
}
catch {
    Write-Line (
        '[FEHLER] Unerwarteter Fehler bei der App-Aktualisierung: ' +
        $_.Exception.Message
    )

    exit 1
}
";

    /// <summary>
    /// Führt die Aktualisierung der installierten Anwendungen aus.
    /// </summary>
    public static void Ausfuehren()
    {
        Console.WriteLine(); // Leerzeile am Anfang

        Console.WriteLine("==================================================");
        Console.WriteLine("[A] Installierte Apps werden aktualisiert");
        Console.WriteLine("==================================================");

        if (!OperatingSystem.IsWindows())
        {
            Console.WriteLine(
                "[FEHLER] Dieses Modul kann nur unter Windows ausgeführt werden.");
            Console.WriteLine(); // Leerzeile vor Rückkehr
            return;
        }

        string? powerShellPath = ErmittlePowerShellPfad();

        if (powerShellPath is null)
        {
            Console.WriteLine(
                "[FEHLER] Windows PowerShell wurde nicht gefunden.");
            Console.WriteLine(); // Leerzeile vor Rückkehr
            return;
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = powerShellPath,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
            WorkingDirectory = Environment.SystemDirectory
        };

        startInfo.ArgumentList.Add("-NoLogo");
        startInfo.ArgumentList.Add("-NoProfile");
        startInfo.ArgumentList.Add("-NonInteractive");
        startInfo.ArgumentList.Add("-ExecutionPolicy");
        startInfo.ArgumentList.Add("Bypass");
        startInfo.ArgumentList.Add("-Command");
        startInfo.ArgumentList.Add(WingetScript);

        using var process = new Process { StartInfo = startInfo };

        process.OutputDataReceived += (_, eventArgs) =>
        {
            if (eventArgs.Data is not null)
            {
                Console.WriteLine(eventArgs.Data);
            }
        };

        process.ErrorDataReceived += (_, eventArgs) =>
        {
            if (eventArgs.Data is not null)
            {
                Console.Error.WriteLine(eventArgs.Data);
            }
        };

        var stopwatch = Stopwatch.StartNew();

        try
        {
            if (!process.Start())
            {
                Console.WriteLine(
                    "[FEHLER] Windows PowerShell konnte nicht gestartet werden.");
                return;
            }

            process.BeginOutputReadLine();
            process.BeginErrorReadLine();

            bool abgeschlossen =
                process.WaitForExit(TimeoutMilliseconds);

            if (!abgeschlossen)
            {
                Console.WriteLine();
                Console.WriteLine(
                    $"[FEHLER] Die App-Aktualisierung hat das Zeitlimit von " +
                    $"{TimeoutMilliseconds / 60_000} Minuten überschritten.");

                ProzessBeenden(process);
                return;
            }

            // Stellt sicher, dass alle asynchron empfangenen Ausgabedaten
            // vollständig verarbeitet wurden.
            process.WaitForExit();

            stopwatch.Stop();

            string dauer = stopwatch.Elapsed.TotalMinutes >= 1
                ? $"{stopwatch.Elapsed.TotalMinutes:F1} Minuten"
                : $"{stopwatch.Elapsed.TotalSeconds:F1} Sekunden";

            Console.WriteLine();

            switch (process.ExitCode)
            {
                case 0:
                    Console.WriteLine(
                        $"[OK] App-Aktualisierungsmodul erfolgreich abgeschlossen ({dauer}).");
                    break;

                case 2:
                    Console.WriteLine(
                        $"[WARNUNG] App-Aktualisierungsmodul mit Warnungen abgeschlossen ({dauer}).");
                    break;

                default:
                    Console.WriteLine(
                        $"[FEHLER] App-Aktualisierungsmodul fehlgeschlagen " +
                        $"(ExitCode {process.ExitCode}, Dauer: {dauer}).");
                    break;
            }
        }
        catch (Exception ex)
        {
            stopwatch.Stop();

            Console.WriteLine();
            Console.WriteLine(
                $"[FEHLER] PowerShell konnte nicht korrekt ausgeführt werden: " +
                $"{ex.Message}");
        }
        finally
        {
            Console.WriteLine(); // Leerzeile am Ende
        }
    }

    /// <summary>
    /// Ermittelt den sicheren Pfad zu Windows PowerShell.
    /// </summary>
    private static string? ErmittlePowerShellPfad()
    {
        string windowsDirectory =
            Environment.GetFolderPath(Environment.SpecialFolder.Windows);

        if (string.IsNullOrWhiteSpace(windowsDirectory))
        {
            return null;
        }

        string systemDirectoryName =
            Environment.Is64BitOperatingSystem &&
            !Environment.Is64BitProcess
                ? "Sysnative"
                : "System32";

        string powerShellPath = Path.Combine(
            windowsDirectory,
            systemDirectoryName,
            "WindowsPowerShell",
            "v1.0",
            "powershell.exe");

        if (File.Exists(powerShellPath))
        {
            return powerShellPath;
        }

        string fallbackPath = Path.Combine(
            Environment.SystemDirectory,
            "WindowsPowerShell",
            "v1.0",
            "powershell.exe");

        return File.Exists(fallbackPath)
            ? fallbackPath
            : null;
    }

    /// <summary>
    /// Beendet PowerShell und alle von PowerShell gestarteten Prozesse.
    /// </summary>
    private static void ProzessBeenden(Process process)
    {
        try
        {
            if (process.HasExited)
            {
                return;
            }

            process.Kill(entireProcessTree: true);

            if (!process.WaitForExit(ProcessTerminationTimeoutMilliseconds))
            {
                Console.WriteLine(
                    "[WARNUNG] Der Aktualisierungsprozess konnte nicht " +
                    "vollständig beendet werden.");
            }
        }
        catch (InvalidOperationException)
        {
            // Der Prozess wurde zwischenzeitlich bereits beendet.
        }
        catch (Exception ex)
        {
            Console.WriteLine(
                $"[WARNUNG] Fehler beim Beenden des " +
                $"Aktualisierungsprozesses: {ex.Message}");
        }
    }
}