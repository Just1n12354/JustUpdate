using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;

namespace JustUpdate.Module;

/// <summary>
/// Windows-Updates installieren
/// </summary>
internal static class WindowsUpdate
{
    public const string Name = "windowsupdate";

    public static void Ausfuehren()
    {
        Console.WriteLine("[W] Windows-Updates werden geprüft ...");

        if (!OperatingSystem.IsWindows())
        {
            Console.WriteLine("[FEHLER] Diese Funktion ist nur unter Windows verfügbar.");
            return;
        }

        using var identity =
            System.Security.Principal.WindowsIdentity.GetCurrent();

        var principal =
            new System.Security.Principal.WindowsPrincipal(identity);

        if (!principal.IsInRole(
                System.Security.Principal.WindowsBuiltInRole.Administrator))
        {
            Console.WriteLine(
                "[FEHLER] Das Programm muss als Administrator gestartet werden.");
            return;
        }

        string script = """
            $ErrorActionPreference = 'Stop'
            [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
            $OutputEncoding = [Console]::OutputEncoding

            function Get-ResultText {
                param([int]$ResultCode)

                switch ($ResultCode) {
                    0 { return 'Nicht gestartet' }
                    1 { return 'In Bearbeitung' }
                    2 { return 'Erfolgreich' }
                    3 { return 'Erfolgreich mit Warnungen' }
                    4 { return 'Fehlgeschlagen' }
                    5 { return 'Abgebrochen' }
                    default { return "Unbekannter Status $ResultCode" }
                }
            }

            try {
                Write-Output 'Windows-Update-Dienst wird initialisiert ...'

                $session = New-Object -ComObject Microsoft.Update.Session
                $session.ClientApplicationID = 'MaintenancePro'

                $searcher = $session.CreateUpdateSearcher()

                # Microsoft Update einbinden, damit auch Updates für andere
                # Microsoft-Produkte und möglichst viele optionale Updates
                # gefunden werden.
                $microsoftUpdateServiceId =
                    '7971f918-a847-4430-9279-4a52d1efe18d'

                try {
                    $serviceManager =
                        New-Object -ComObject Microsoft.Update.ServiceManager

                    $serviceRegistered = $false

                    foreach ($service in $serviceManager.Services) {
                        if ($service.ServiceID -eq $microsoftUpdateServiceId) {
                            $serviceRegistered = $true
                            break
                        }
                    }

                    if (-not $serviceRegistered) {
                        $serviceManager.AddService2(
                            $microsoftUpdateServiceId,
                            2,
                            ''
                        ) | Out-Null

                        Write-Output 'Microsoft Update wurde temporär eingebunden.'
                    }

                    # 3 = ssOthers
                    $searcher.ServerSelection = 3
                    $searcher.ServiceID = $microsoftUpdateServiceId

                    Write-Output 'Suche über Microsoft Update ...'
                }
                catch {
                    Write-Output '[WARNUNG] Microsoft Update konnte nicht eingebunden werden.'
                    Write-Output 'Fallback auf die normale Windows-Update-Quelle.'
                    Write-Output "Grund: $($_.Exception.Message)"
                }

                Write-Output 'Verfügbare Updates werden gesucht ...'

                $searchResult =
                    $searcher.Search('IsInstalled=0 AND IsHidden=0')

                $softwareUpdates = @(
                    $searchResult.Updates |
                        Where-Object {
                            $isDriver = $false

                            try {
                                # IUpdate.Type:
                                # 1 = Software
                                # 2 = Treiber
                                if ($_.Type -eq 2) {
                                    $isDriver = $true
                                }
                            }
                            catch {}

                            if (-not $isDriver) {
                                try {
                                    foreach ($category in $_.Categories) {
                                        if ($category.Type -eq 'Driver') {
                                            $isDriver = $true
                                            break
                                        }
                                    }
                                }
                                catch {}
                            }

                            -not $isDriver
                        }
                )

                if ($softwareUpdates.Count -eq 0) {
                    Write-Output '[OK] Windows ist auf dem neuesten Stand.'
                    Write-Output 'Es wurden keine Software-Updates gefunden.'
                    exit 0
                }

                Write-Output ''
                Write-Output "$($softwareUpdates.Count) Update(s) gefunden:"
                Write-Output ''

                $downloadCollection =
                    New-Object -ComObject Microsoft.Update.UpdateColl

                $updateNumber = 1

                foreach ($update in $softwareUpdates) {
                    $sizeText = ''

                    try {
                        $sizeMegabytes =
                            [Math]::Round(
                                $update.MaxDownloadSize / 1MB,
                                1
                            )

                        if (
                            $sizeMegabytes -gt 0 -and
                            $sizeMegabytes -lt 50000
                        ) {
                            $sizeText = " ($sizeMegabytes MB)"
                        }
                    }
                    catch {}

                    Write-Output (
                        "  [$updateNumber/$($softwareUpdates.Count)] " +
                        "$($update.Title)$sizeText"
                    )

                    if (-not $update.EulaAccepted) {
                        try {
                            $update.AcceptEula()
                        }
                        catch {
                            Write-Output (
                                "    [WARNUNG] Lizenzbedingungen konnten " +
                                "nicht automatisch akzeptiert werden."
                            )
                        }
                    }

                    if (-not $update.IsDownloaded) {
                        [void]$downloadCollection.Add($update)
                    }

                    $updateNumber++
                }

                Write-Output ''

                $downloadFailed = $false

                if ($downloadCollection.Count -gt 0) {
                    Write-Output (
                        "$($downloadCollection.Count) Update(s) " +
                        'werden heruntergeladen ...'
                    )

                    Write-Output (
                        'Der Download kann mehrere Minuten dauern. ' +
                        'Bitte das Programm nicht beenden.'
                    )

                    $downloader = $session.CreateUpdateDownloader()
                    $downloader.Updates = $downloadCollection

                    $downloadResult = $downloader.Download()
                    $downloadStatus =
                        Get-ResultText $downloadResult.ResultCode

                    if ($downloadResult.ResultCode -eq 2) {
                        Write-Output '[OK] Download erfolgreich abgeschlossen.'
                    }
                    elseif ($downloadResult.ResultCode -eq 3) {
                        Write-Output (
                            '[WARNUNG] Download wurde mit Warnungen abgeschlossen.'
                        )
                    }
                    else {
                        $downloadFailed = $true

                        Write-Output (
                            "[FEHLER] Download: $downloadStatus"
                        )

                        Write-Output (
                            'HRESULT: 0x{0:X8}' -f
                            ([uint32]$downloadResult.HResult)
                        )
                    }
                }
                else {
                    Write-Output 'Alle gefundenen Updates sind bereits heruntergeladen.'
                }

                $installCollection =
                    New-Object -ComObject Microsoft.Update.UpdateColl

                foreach ($update in $softwareUpdates) {
                    if ($update.IsDownloaded) {
                        [void]$installCollection.Add($update)
                    }
                }

                if ($installCollection.Count -eq 0) {
                    if ($downloadFailed) {
                        Write-Output (
                            '[FEHLER] Es konnten keine Updates zur ' +
                            'Installation vorbereitet werden.'
                        )

                        exit 1
                    }

                    Write-Output (
                        '[WARNUNG] Updates wurden gefunden, aber keines ' +
                        'konnte installiert werden.'
                    )

                    exit 2
                }

                Write-Output ''
                Write-Output (
                    "$($installCollection.Count) Update(s) " +
                    'werden installiert ...'
                )

                Write-Output (
                    'Die Installation kann längere Zeit dauern. ' +
                    'Den Computer nicht ausschalten.'
                )

                $installer = $session.CreateUpdateInstaller()
                $installer.Updates = $installCollection

                $installationResult = $installer.Install()

                $successfulUpdates = 0
                $failedUpdates = 0

                Write-Output ''
                Write-Output 'Installationsergebnisse:'

                for (
                    $index = 0;
                    $index -lt $installCollection.Count;
                    $index++
                ) {
                    $update = $installCollection.Item($index)
                    $updateResult =
                        $installationResult.GetUpdateResult($index)

                    $status =
                        Get-ResultText $updateResult.ResultCode

                    if (
                        $updateResult.ResultCode -eq 2 -or
                        $updateResult.ResultCode -eq 3
                    ) {
                        $successfulUpdates++

                        Write-Output "  [OK] $($update.Title)"

                        if ($updateResult.ResultCode -eq 3) {
                            Write-Output '       Erfolgreich mit Warnungen'
                        }
                    }
                    else {
                        $failedUpdates++

                        Write-Output "  [FEHLER] $($update.Title)"
                        Write-Output "           Status: $status"

                        Write-Output (
                            '           HRESULT: 0x{0:X8}' -f
                            ([uint32]$updateResult.HResult)
                        )
                    }
                }

                Write-Output ''
                Write-Output (
                    "$successfulUpdates von $($installCollection.Count) " +
                    'Update(s) erfolgreich installiert.'
                )

                if ($installationResult.RebootRequired) {
                    Write-Output ''
                    Write-Output (
                        '[NEUSTART ERFORDERLICH] Der Computer muss ' +
                        'neu gestartet werden.'
                    )
                }

                if (
                    $failedUpdates -eq 0 -and
                    -not $downloadFailed
                ) {
                    Write-Output '[OK] Windows-Updates wurden erfolgreich abgeschlossen.'
                    exit 0
                }

                if ($successfulUpdates -gt 0) {
                    Write-Output (
                        '[WARNUNG] Einige Updates konnten nicht ' +
                        'vollständig installiert werden.'
                    )

                    exit 2
                }

                Write-Output '[FEHLER] Alle Update-Installationen sind fehlgeschlagen.'
                exit 1
            }
            catch {
                Write-Error (
                    'Windows-Update-Fehler: ' +
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

            // IUpdateDownloader.Download() und IUpdateInstaller.Install() sind
            // synchrone COM-Aufrufe ohne Timeout. Haengt der Windows-Update-Dienst
            // (klassisch nach einem abgebrochenen Update), wartet die Wartung sonst
            // bis in alle Ewigkeit. 2 Stunden decken auch grosse Feature-Updates ab.
            if (!process.WaitForExit(120 * 60 * 1000))
            {
                try
                {
                    process.Kill(entireProcessTree: true);
                }
                catch
                {
                    // Prozess war bereits beendet.
                }

                Console.WriteLine(
                    "[FEHLER] Zeitlimit: Windows Update wurde nach 2 Stunden " +
                    "abgebrochen. Der Windows-Update-Dienst haengt vermutlich.");

                return;
            }

            process.WaitForExit();

            if (process.ExitCode == 0)
            {
                Console.WriteLine(
                    "[OK] Windows-Update-Modul abgeschlossen.");
            }
            else if (process.ExitCode == 2)
            {
                Console.WriteLine(
                    "[WARNUNG] Windows-Update-Modul mit Warnungen abgeschlossen.");
            }
            else
            {
                Console.WriteLine(
                    "[FEHLER] Windows-Update-Modul ist fehlgeschlagen.");
            }
        }
        catch (Exception fehler)
        {
            Console.WriteLine("[FEHLER] " + fehler.Message);
        }
    }
}
