using System;
using JustUpdate.Infrastruktur;

namespace JustUpdate.Module;

/// <summary>
/// Microsoft-Store-Apps aktualisieren
/// </summary>
internal static class Store
{
    public const string Name = "store";
    public const string Schnellbeschreibung = "Store-Apps aktualisieren";

    public static void Ausfuehren()
    {
        Console.WriteLine("[S] Microsoft-Store-Apps werden aktualisiert ...");

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

            function Write-Line {
                param([string]$Text)

                [Console]::Out.WriteLine($Text)
                [Console]::Out.Flush()
            }

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
                Write-Line 'Schritt 1/2: Store-Updatescan wird ausgelöst ...'

                $mdmScanSuccessful = $false

                try {
                    $namespace =
                        'root\cimv2\mdm\dmmap'

                    $className =
                        'MDM_EnterpriseModernAppManagement_AppManagement01'

                    $managementObject =
                        Get-CimInstance `
                            -Namespace $namespace `
                            -ClassName $className `
                            -ErrorAction Stop

                    Invoke-CimMethod `
                        -InputObject $managementObject `
                        -MethodName 'UpdateScanMethod' `
                        -ErrorAction Stop |
                        Out-Null

                    $mdmScanSuccessful = $true

                    Write-Line '[OK] Microsoft-Store-Updatescan wurde ausgelöst.'
                }
                catch {
                    Write-Line (
                        '[WARNUNG] Der MDM-Updatescan ist nicht verfügbar: ' +
                        $_.Exception.Message
                    )
                }

                Write-Line ''
                Write-Line 'Schritt 2/2: Store-Updates werden gesucht ...'

                $storeServiceId =
                    '855E8A7C-ECB4-4CA3-B045-1DFA50104289'

                $session =
                    New-Object -ComObject Microsoft.Update.Session

                $session.ClientApplicationID =
                    'MaintenancePro-Store'

                try {
                    $serviceManager =
                        New-Object -ComObject Microsoft.Update.ServiceManager

                    $serviceManager.ClientApplicationID =
                        'MaintenancePro-Store'

                    $serviceRegistered = $false

                    foreach ($service in $serviceManager.Services) {
                        if ($service.ServiceID -eq $storeServiceId) {
                            $serviceRegistered = $true
                            break
                        }
                    }

                    if (-not $serviceRegistered) {
                        $serviceManager.AddService2(
                            $storeServiceId,
                            3,
                            ''
                        ) | Out-Null

                        Write-Line 'Microsoft-Store-Updatedienst wurde eingebunden.'
                    }
                }
                catch {
                    Write-Line (
                        '[HINWEIS] Der Store-Updatedienst ist möglicherweise ' +
                        'bereits registriert.'
                    )
                }

                $searcher =
                    $session.CreateUpdateSearcher()

                $searcher.ServiceID =
                    $storeServiceId

                # 3 = Andere registrierte Updatequelle verwenden.
                $searcher.ServerSelection = 3

                try {
                    # 1 = Updates für Computer und aktuellen Benutzer.
                    $searcher.SearchScope = 1
                }
                catch {}

                $searchResult =
                    $searcher.Search('IsInstalled=0 AND IsHidden=0')

                $availableUpdates =
                    @($searchResult.Updates)

                $availableCount =
                    $availableUpdates.Count

                if ($availableCount -eq 0) {
                    Write-Line ''
                    Write-Line '[OK] Alle Microsoft-Store-Apps sind aktuell.'
                    exit 0
                }

                Write-Line ''
                Write-Line "$availableCount Store-Update(s) gefunden:"
                Write-Line ''

                $downloadCollection =
                    New-Object -ComObject Microsoft.Update.UpdateColl

                $updateNumber = 1

                foreach ($update in $availableUpdates) {
                    Write-Line (
                        "  [$updateNumber/$availableCount] " +
                        $update.Title
                    )

                    if (-not $update.EulaAccepted) {
                        try {
                            $update.AcceptEula()
                        }
                        catch {
                            Write-Line (
                                '       [WARNUNG] Lizenzbedingungen konnten ' +
                                'nicht automatisch akzeptiert werden.'
                            )
                        }
                    }

                    if (-not $update.IsDownloaded) {
                        [void]$downloadCollection.Add($update)
                    }

                    $updateNumber++
                }

                $downloadFailed = $false

                if ($downloadCollection.Count -gt 0) {
                    Write-Line ''
                    Write-Line (
                        "$($downloadCollection.Count) Store-Update(s) " +
                        'werden heruntergeladen ...'
                    )

                    Write-Line (
                        'Der Download kann mehrere Minuten dauern. ' +
                        'Bitte das Programm nicht beenden.'
                    )

                    $downloader =
                        $session.CreateUpdateDownloader()

                    $downloader.Updates =
                        $downloadCollection

                    $downloadResult =
                        $downloader.Download()

                    $downloadStatus =
                        Get-ResultText $downloadResult.ResultCode

                    if ($downloadResult.ResultCode -eq 2) {
                        Write-Line '[OK] Store-Download erfolgreich abgeschlossen.'
                    }
                    elseif ($downloadResult.ResultCode -eq 3) {
                        Write-Line (
                            '[WARNUNG] Store-Download wurde mit ' +
                            'Warnungen abgeschlossen.'
                        )
                    }
                    else {
                        $downloadFailed = $true

                        Write-Line (
                            "[FEHLER] Store-Download: $downloadStatus"
                        )

                        Write-Line (
                            'HRESULT: 0x{0:X8}' -f
                            ([uint32]$downloadResult.HResult)
                        )
                    }
                }
                else {
                    Write-Line ''
                    Write-Line (
                        'Alle gefundenen Store-Updates sind bereits ' +
                        'heruntergeladen.'
                    )
                }

                $installCollection =
                    New-Object -ComObject Microsoft.Update.UpdateColl

                foreach ($update in $availableUpdates) {
                    if ($update.IsDownloaded) {
                        [void]$installCollection.Add($update)
                    }
                }

                if ($installCollection.Count -eq 0) {
                    Write-Line ''
                    Write-Line (
                        '[WARNUNG] Es wurden Store-Updates gefunden, aber ' +
                        'keines konnte zur Installation vorbereitet werden.'
                    )

                    if ($mdmScanSuccessful) {
                        Write-Line (
                            'Der Store-Updatescan läuft möglicherweise noch ' +
                            'im Hintergrund weiter.'
                        )

                        exit 2
                    }

                    exit 1
                }

                Write-Line ''
                Write-Line (
                    "$($installCollection.Count) Store-Update(s) " +
                    'werden installiert ...'
                )

                Write-Line (
                    'Die Installation kann mehrere Minuten dauern. ' +
                    'Bitte das Programm nicht beenden.'
                )

                $installer =
                    $session.CreateUpdateInstaller()

                $installer.Updates =
                    $installCollection

                try {
                    $installer.AllowSourcePrompts = $false
                }
                catch {}

                $installationResult =
                    $installer.Install()

                $successfulUpdates = 0
                $failedUpdates = 0

                Write-Line ''
                Write-Line 'Installationsergebnisse:'

                for (
                    $index = 0;
                    $index -lt $installCollection.Count;
                    $index++
                ) {
                    $update =
                        $installCollection.Item($index)

                    $updateResult =
                        $installationResult.GetUpdateResult($index)

                    $resultText =
                        Get-ResultText $updateResult.ResultCode

                    if ($updateResult.ResultCode -eq 2) {
                        $successfulUpdates++

                        Write-Line "  [OK] $($update.Title)"
                    }
                    elseif ($updateResult.ResultCode -eq 3) {
                        $successfulUpdates++

                        Write-Line (
                            "  [OK MIT WARNUNG] $($update.Title)"
                        )
                    }
                    else {
                        $failedUpdates++

                        Write-Line "  [FEHLER] $($update.Title)"
                        Write-Line "           Status: $resultText"

                        Write-Line (
                            '           HRESULT: 0x{0:X8}' -f
                            ([uint32]$updateResult.HResult)
                        )
                    }
                }

                # Auch Updates berücksichtigen, deren Download fehlgeschlagen ist.
                $notInstalledCount =
                    $availableCount - $successfulUpdates

                if ($notInstalledCount -gt $failedUpdates) {
                    $failedUpdates = $notInstalledCount
                }

                Write-Line ''
                Write-Line (
                    "$successfulUpdates von $availableCount " +
                    'Store-Update(s) erfolgreich installiert.'
                )

                if ($installationResult.RebootRequired) {
                    Write-Line ''
                    Write-Line (
                        '[NEUSTART ERFORDERLICH] Mindestens ein Store-Update ' +
                        'benötigt einen Windows-Neustart.'
                    )
                }

                if (
                    $successfulUpdates -eq $availableCount -and
                    -not $downloadFailed
                ) {
                    Write-Line (
                        '[OK] Alle Microsoft-Store-Apps wurden erfolgreich ' +
                        'aktualisiert.'
                    )

                    exit 0
                }

                if ($successfulUpdates -gt 0) {
                    Write-Line (
                        "[WARNUNG] $failedUpdates Store-Update(s) konnten " +
                        'nicht vollständig installiert werden.'
                    )

                    exit 2
                }

                Write-Line (
                    '[FEHLER] Keines der gefundenen Store-Updates konnte ' +
                    'installiert werden.'
                )

                exit 1
            }
            catch {
                Write-Line (
                    '[FEHLER] Fehler bei den Microsoft-Store-Updates: ' +
                    $_.Exception.Message
                )

                exit 1
            }
            """;

        try
        {
            // 60 Minuten Timeout — Store-Updates konnen bei grossen App-Updates
            // mehrere Minuten dauern.
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
                    "[FEHLER] Die Store-Aktualisierung wurde nach 60 Minuten abgebrochen.");
                return;
            }

            if (!string.IsNullOrWhiteSpace(ausgabe))
            {
                Console.WriteLine(ausgabe.Trim());
            }

            if (exitCode == 0)
            {
                Console.WriteLine(
                    "[OK] Microsoft-Store-Modul abgeschlossen.");
            }
            else if (exitCode == 2)
            {
                Console.WriteLine(
                    "[WARNUNG] Microsoft-Store-Modul mit Warnungen abgeschlossen.");
            }
            else
            {
                Console.WriteLine(
                    "[FEHLER] Microsoft-Store-Modul ist fehlgeschlagen.");
            }
        }
        catch (Exception fehler)
        {
            Console.WriteLine("[FEHLER] " + fehler.Message);
        }
    }
}
