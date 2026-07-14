using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;

namespace JustUpdate.Module;

/// <summary>
/// Installierte Apps ueber winget aktualisieren
/// </summary>
internal static class Apps
{
    public const string Name = "apps";

    public static void Ausfuehren()
    {
        Console.WriteLine("[A] Installierte Apps werden aktualisiert ...");

        if (!OperatingSystem.IsWindows())
        {
            Console.WriteLine("[FEHLER] Diese Funktion ist nur unter Windows verfügbar.");
            return;
        }

        string script = """
            $ErrorActionPreference = 'Stop'
            [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
            $OutputEncoding = [Console]::OutputEncoding

            function Write-Line {
                param([string]$Text)

                [Console]::Out.WriteLine($Text)
                [Console]::Out.Flush()
            }

            try {
                $winget = (Get-Command winget.exe -ErrorAction SilentlyContinue).Source

                if (-not $winget) {
                    $candidates = @(
                        "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"
                    )

                    try {
                        $packageDirectory =
                            Get-ChildItem `
                                -Path "$env:ProgramFiles\WindowsApps" `
                                -Directory `
                                -ErrorAction SilentlyContinue |
                            Where-Object {
                                $_.Name -like
                                'Microsoft.DesktopAppInstaller_*_8wekyb3d8bbwe'
                            } |
                            Sort-Object Name -Descending |
                            Select-Object -First 1

                        if ($packageDirectory) {
                            $candidates +=
                                Join-Path $packageDirectory.FullName 'winget.exe'
                        }
                    }
                    catch {}

                    try {
                        $candidates +=
                            Get-ChildItem `
                                -Path "$env:SystemDrive\Users" `
                                -Directory `
                                -ErrorAction SilentlyContinue |
                            ForEach-Object {
                                Join-Path `
                                    $_.FullName `
                                    'AppData\Local\Microsoft\WindowsApps\winget.exe'
                            }
                    }
                    catch {}

                    $winget =
                        $candidates |
                        Where-Object {
                            $_ -and (Test-Path -LiteralPath $_)
                        } |
                        Select-Object -First 1
                }

                if (-not $winget) {
                    Write-Line '[FEHLER] Winget ist nicht installiert.'
                    Write-Line (
                        'Installiere im Microsoft Store die Anwendung ' +
                        '„App-Installer“.'
                    )

                    exit 1
                }

                Write-Line "Winget gefunden: $winget"
                Write-Line 'Winget-Quellen werden aktualisiert ...'

                & $winget `
                    source update `
                    --disable-interactivity 2>&1 |
                    ForEach-Object {
                        Write-Line "$_"
                    }

                $sourceExitCode = $LASTEXITCODE

                if ($sourceExitCode -ne 0) {
                    Write-Line (
                        '[WARNUNG] Die Winget-Quellen konnten nicht ' +
                        'vollständig aktualisiert werden.'
                    )

                    Write-Line (
                        'Die App-Aktualisierung wird mit dem vorhandenen ' +
                        'Paketindex fortgesetzt.'
                    )
                }
                else {
                    Write-Line '[OK] Winget-Quellen wurden aktualisiert.'
                }

                Write-Line ''
                Write-Line 'Verfügbare App-Updates werden installiert ...'
                Write-Line (
                    'Das kann mehrere Minuten dauern. ' +
                    'Bitte das Programm nicht beenden.'
                )

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
                        $line = "$_"
                        [void]$outputLines.Add($line)
                        Write-Line $line
                    }

                $upgradeExitCode = $LASTEXITCODE
                $combinedOutput = $outputLines -join ' '

                $nothingToUpdate =
                    $combinedOutput -match (
                        'No installed package found|' +
                        'No available upgrade|' +
                        'No applicable upgrade|' +
                        'kein installiertes Paket|' +
                        'keine verfügbaren Upgrades|' +
                        'kein anwendbares Upgrade|' +
                        'Aucun package installé|' +
                        'Aucune mise à niveau disponible'
                    )

                $successfulUpdate =
                    $combinedOutput -match (
                        'Successfully installed|' +
                        'Installation was successful|' +
                        'Erfolgreich installiert|' +
                        'Die Installation war erfolgreich|' +
                        'Installation réussie'
                    )

                $applicationRestartRequired =
                    $combinedOutput -match (
                        'Restart the application to complete|' +
                        'Starten Sie die Anwendung neu|' +
                        'Redémarrez l.application'
                    )

                $computerRestartRequired =
                    $combinedOutput -match (
                        'Restart your PC to finish|' +
                        'Starten Sie (Ihren|den) PC neu|' +
                        'Redémarrez (votre|le) PC'
                    )

                Write-Line ''

                if ($nothingToUpdate -and -not $successfulUpdate) {
                    Write-Line '[OK] Alle installierten Apps sind aktuell.'
                    exit 0
                }

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

                    exit 0
                }

                if ($successfulUpdate) {
                    Write-Line (
                        '[WARNUNG] Einige Apps wurden aktualisiert, ' +
                        'mindestens ein Update ist jedoch fehlgeschlagen.'
                    )

                    Write-Line "Winget-Rückgabecode: $upgradeExitCode"
                    exit 2
                }

                Write-Line '[FEHLER] Die App-Aktualisierung ist fehlgeschlagen.'
                Write-Line "Winget-Rückgabecode: $upgradeExitCode"

                exit 1
            }
            catch {
                Write-Line (
                    '[FEHLER] Fehler bei der App-Aktualisierung: ' +
                    $_.Exception.Message
                )

                exit 1
            }
            """;

        try
        {
            var startInfo =
                new System.Diagnostics.ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    CreateNoWindow = true,
                    StandardOutputEncoding = System.Text.Encoding.UTF8,
                    StandardErrorEncoding = System.Text.Encoding.UTF8
                };

            startInfo.ArgumentList.Add("-NoProfile");
            startInfo.ArgumentList.Add("-NonInteractive");
            startInfo.ArgumentList.Add("-ExecutionPolicy");
            startInfo.ArgumentList.Add("Bypass");
            startInfo.ArgumentList.Add("-Command");
            startInfo.ArgumentList.Add(script);

            using var process =
                new System.Diagnostics.Process
                {
                    StartInfo = startInfo
                };

            process.OutputDataReceived += (_, eventArgs) =>
            {
                if (!string.IsNullOrWhiteSpace(eventArgs.Data))
                {
                    Console.WriteLine(eventArgs.Data);
                }
            };

            process.ErrorDataReceived += (_, eventArgs) =>
            {
                if (!string.IsNullOrWhiteSpace(eventArgs.Data))
                {
                    Console.WriteLine(eventArgs.Data);
                }
            };

            if (!process.Start())
            {
                Console.WriteLine(
                    "[FEHLER] PowerShell konnte nicht gestartet werden.");
                return;
            }

            process.BeginOutputReadLine();
            process.BeginErrorReadLine();

            bool abgeschlossen = process.WaitForExit(3_600_000);

            if (!abgeschlossen)
            {
                try
                {
                    process.Kill(entireProcessTree: true);
                }
                catch
                {
                    // Prozess wurde möglicherweise bereits beendet.
                }

                Console.WriteLine(
                    "[FEHLER] Die App-Aktualisierung wurde nach 60 Minuten abgebrochen.");
                return;
            }

            process.WaitForExit();

            if (process.ExitCode == 0)
            {
                Console.WriteLine(
                    "[OK] App-Aktualisierungsmodul abgeschlossen.");
            }
            else if (process.ExitCode == 2)
            {
                Console.WriteLine(
                    "[WARNUNG] App-Aktualisierungsmodul mit Warnungen abgeschlossen.");
            }
            else
            {
                Console.WriteLine(
                    "[FEHLER] App-Aktualisierungsmodul ist fehlgeschlagen.");
            }
        }
        catch (Exception fehler)
        {
            Console.WriteLine("[FEHLER] " + fehler.Message);
        }
    }
}
