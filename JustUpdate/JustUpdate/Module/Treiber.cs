using System;
using JustUpdate.Infrastruktur;

namespace JustUpdate.Module;

/// <summary>
/// Treiber ueber Microsoft Update aktualisieren
/// </summary>
internal static class Treiber
{
    public const string Name = "treiber";
    public const string Schnellbeschreibung = "Treiber-Updates installieren";

    public static void Ausfuehren()
    {
        Console.WriteLine("[T] Treiber-Updates werden geprüft ...");

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
                    default { return "Unbekannter Status: $ResultCode" }
                }
            }

            try {
                Write-Output 'Windows Update wird für die Treibersuche initialisiert ...'

                $session = New-Object -ComObject Microsoft.Update.Session
                $session.ClientApplicationID = 'MaintenancePro-Treiber'

                $searcher = $session.CreateUpdateSearcher()

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

                        Write-Output 'Microsoft Update wurde eingebunden.'
                    }

                    # 3 = ssOthers
                    $searcher.ServerSelection = 3
                    $searcher.ServiceID = $microsoftUpdateServiceId

                    Write-Output (
                        'Suche über Microsoft Update, ' +
                        'einschließlich optionaler Treiber ...'
                    )
                }
                catch {
                    Write-Output (
                        '[WARNUNG] Microsoft Update konnte nicht ' +
                        'eingebunden werden.'
                    )

                    Write-Output (
                        'Die normale Windows-Update-Quelle wird verwendet.'
                    )

                    Write-Output "Grund: $($_.Exception.Message)"
                }

                $searchResult = $searcher.Search(
                    "IsInstalled=0 AND IsHidden=0 AND Type='Driver'"
                )

                $availableDrivers = @($searchResult.Updates)

                if ($availableDrivers.Count -eq 0) {
                    Write-Output '[OK] Alle Treiber sind auf dem neuesten Stand.'
                    exit 0
                }

                Write-Output ''
                Write-Output "$($availableDrivers.Count) Treiber-Update(s) gefunden:"
                Write-Output ''

                $downloadCollection =
                    New-Object -ComObject Microsoft.Update.UpdateColl

                $driverInformation = @{}

                $driverNumber = 1

                foreach ($driver in $availableDrivers) {
                    $updateId = $null

                    try {
                        $updateId = [string]$driver.Identity.UpdateID
                    }
                    catch {}

                    if ($updateId) {
                        $driverInformation[$updateId] = $driver.Title
                    }

                    Write-Output (
                        "  [$driverNumber/$($availableDrivers.Count)] " +
                        "$($driver.Title)"
                    )

                    try {
                        if ($driver.DriverManufacturer) {
                            Write-Output (
                                "       Hersteller: $($driver.DriverManufacturer)"
                            )
                        }

                        if ($driver.DriverModel) {
                            Write-Output "       Modell: $($driver.DriverModel)"
                        }

                        if ($driver.DriverVerDate) {
                            Write-Output (
                                '       Treiberdatum: ' +
                                $driver.DriverVerDate.ToString('dd.MM.yyyy')
                            )
                        }
                    }
                    catch {}

                    if (-not $driver.EulaAccepted) {
                        try {
                            $driver.AcceptEula()
                        }
                        catch {
                            Write-Output (
                                '       [WARNUNG] Lizenzbedingungen konnten ' +
                                'nicht automatisch akzeptiert werden.'
                            )
                        }
                    }

                    [void]$downloadCollection.Add($driver)
                    $driverNumber++
                }

                Write-Output ''
                Write-Output 'Treiber werden heruntergeladen ...'
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
                    Write-Output '[OK] Treiber-Download erfolgreich abgeschlossen.'
                }
                elseif ($downloadResult.ResultCode -eq 3) {
                    Write-Output (
                        '[WARNUNG] Treiber-Download wurde mit ' +
                        'Warnungen abgeschlossen.'
                    )
                }
                else {
                    Write-Output "[FEHLER] Downloadstatus: $downloadStatus"

                    Write-Output (
                        'HRESULT: 0x{0:X8}' -f
                        ([uint32]$downloadResult.HResult)
                    )

                    exit 1
                }

                $installCollection =
                    New-Object -ComObject Microsoft.Update.UpdateColl

                $downloadFailures = 0

                foreach ($driver in $availableDrivers) {
                    if ($driver.IsDownloaded) {
                        [void]$installCollection.Add($driver)
                    }
                    else {
                        $downloadFailures++

                        Write-Output (
                            '[WARNUNG] Nicht vollständig heruntergeladen: ' +
                            $driver.Title
                        )
                    }
                }

                if ($installCollection.Count -eq 0) {
                    Write-Output (
                        '[FEHLER] Keiner der gefundenen Treiber konnte ' +
                        'vollständig heruntergeladen werden.'
                    )

                    exit 1
                }

                Write-Output ''
                Write-Output (
                    "$($installCollection.Count) Treiber-Update(s) " +
                    'werden installiert ...'
                )

                Write-Output (
                    'Die Installation kann mehrere Minuten dauern. ' +
                    'Den Computer nicht ausschalten.'
                )

                $installer = $session.CreateUpdateInstaller()
                $installer.Updates = $installCollection

                try {
                    $installer.AllowSourcePrompts = $false
                }
                catch {}

                $installationResult = $installer.Install()

                $successfulDrivers = 0
                $failedDrivers = $downloadFailures
                $reportedSuccessfulIds = @{}

                Write-Output ''
                Write-Output 'Installationsergebnisse:'

                for (
                    $index = 0;
                    $index -lt $installCollection.Count;
                    $index++
                ) {
                    $driver = $installCollection.Item($index)

                    $driverResult =
                        $installationResult.GetUpdateResult($index)

                    $resultText =
                        Get-ResultText $driverResult.ResultCode

                    if (
                        $driverResult.ResultCode -eq 2 -or
                        $driverResult.ResultCode -eq 3
                    ) {
                        $successfulDrivers++

                        try {
                            $updateId =
                                [string]$driver.Identity.UpdateID

                            if ($updateId) {
                                $reportedSuccessfulIds[$updateId] =
                                    $driver.Title
                            }
                        }
                        catch {}

                        if ($driverResult.ResultCode -eq 3) {
                            Write-Output (
                                "  [OK MIT WARNUNG] $($driver.Title)"
                            )
                        }
                        else {
                            Write-Output "  [OK] $($driver.Title)"
                        }
                    }
                    else {
                        $failedDrivers++

                        Write-Output "  [FEHLER] $($driver.Title)"
                        Write-Output "           Status: $resultText"

                        Write-Output (
                            '           HRESULT: 0x{0:X8}' -f
                            ([uint32]$driverResult.HResult)
                        )
                    }
                }

                if ($installationResult.RebootRequired) {
                    Write-Output ''
                    Write-Output (
                        '[NEUSTART ERFORDERLICH] Der Computer muss ' +
                        'neu gestartet werden.'
                    )
                }

                if ($reportedSuccessfulIds.Count -gt 0) {
                    Write-Output ''
                    Write-Output 'Die Treiberinstallation wird verifiziert ...'

                    try {
                        $verificationSearcher =
                            $session.CreateUpdateSearcher()

                        if (
                            $searcher.ServerSelection -eq 3 -and
                            $searcher.ServiceID
                        ) {
                            $verificationSearcher.ServerSelection = 3
                            $verificationSearcher.ServiceID =
                                $searcher.ServiceID
                        }

                        $verificationResult =
                            $verificationSearcher.Search(
                                "IsInstalled=0 AND Type='Driver'"
                            )

                        $stillPending = @()

                        foreach ($pendingDriver in $verificationResult.Updates) {
                            $isHidden = $false

                            try {
                                $isHidden = [bool]$pendingDriver.IsHidden
                            }
                            catch {}

                            if ($isHidden) {
                                continue
                            }

                            $pendingId = $null

                            try {
                                $pendingId =
                                    [string]$pendingDriver.Identity.UpdateID
                            }
                            catch {}

                            if (
                                $pendingId -and
                                $reportedSuccessfulIds.ContainsKey($pendingId)
                            ) {
                                $stillPending += $pendingDriver.Title
                            }
                        }

                        if ($stillPending.Count -eq 0) {
                            Write-Output (
                                '[OK] Alle erfolgreich gemeldeten ' +
                                'Treiber wurden verifiziert.'
                            )
                        }
                        else {
                            Write-Output (
                                '[WARNUNG] Folgende Treiber werden weiterhin ' +
                                'als nicht installiert angezeigt:'
                            )

                            foreach ($title in $stillPending) {
                                Write-Output "  - $title"
                            }

                            $failedDrivers += $stillPending.Count

                            $successfulDrivers =
                                [Math]::Max(
                                    0,
                                    $successfulDrivers - $stillPending.Count
                                )
                        }
                    }
                    catch {
                        Write-Output (
                            '[WARNUNG] Die abschließende Verifikation ' +
                            'ist fehlgeschlagen.'
                        )

                        Write-Output "Grund: $($_.Exception.Message)"
                    }
                }

                Write-Output ''
                Write-Output (
                    "$successfulDrivers Treiber erfolgreich installiert."
                )

                if ($failedDrivers -eq 0) {
                    Write-Output (
                        '[OK] Alle Treiber-Updates wurden erfolgreich ' +
                        'abgeschlossen.'
                    )

                    exit 0
                }

                if ($successfulDrivers -gt 0) {
                    Write-Output (
                        "[WARNUNG] $failedDrivers Treiber-Update(s) " +
                        'konnten nicht vollständig installiert werden.'
                    )

                    Write-Output (
                        'Prüfe gegebenenfalls Windows Update unter ' +
                        '„Optionale Updates“.'
                    )

                    exit 2
                }

                Write-Output (
                    '[FEHLER] Die Treiber-Updates konnten nicht ' +
                    'installiert werden.'
                )

                exit 1
            }
            catch {
                Write-Error (
                    'Fehler bei den Treiber-Updates: ' +
                    $_.Exception.Message
                )

                exit 1
            }
            """;

        try
        {
            // 60 Minuten Timeout — Gleiche Falle wie bei Windows Update:
            // die WUA-COM-Aufrufe konnen unbegrenzt hangen. Ein Treiberpaket
            // ist selten gross - 60 Minuten sind reichlich.
            var erfolgreich = PowerShellHelper.Ausfuehren(script, 3600, out var ausgabe, out var fehler, out var exitCode, out var timedOut);

            if (!erfolgreich)
            {
                Console.WriteLine(
                    "[FEHLER] PowerShell konnte nicht gestartet werden.");
                return;
            }

            if (timedOut)
            {
                Console.WriteLine(
                    "[FEHLER] Zeitlimit: Die Treibersuche wurde nach 60 Minuten " +
                    "abgebrochen.");
                return;
            }

            if (!string.IsNullOrWhiteSpace(ausgabe))
            {
                Console.WriteLine(ausgabe.Trim());
            }

            if (exitCode == 0)
            {
                Console.WriteLine(
                    "[OK] Treiber-Modul erfolgreich abgeschlossen.");
            }
            else if (exitCode == 2)
            {
                Console.WriteLine(
                    "[WARNUNG] Treiber-Modul mit Warnungen abgeschlossen.");
            }
            else
            {
                Console.WriteLine(
                    "[FEHLER] Treiber-Modul ist fehlgeschlagen.");
            }
        }
        catch (Exception fehler)
        {
            Console.WriteLine("[FEHLER] " + fehler.Message);
        }
    }
}
