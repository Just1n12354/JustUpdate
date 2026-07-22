using System;
using JustUpdate.Infrastruktur;

namespace JustUpdate.Module;

/// <summary>
/// Systemwiederherstellungspunkt anlegen
/// </summary>
internal static class Wiederherstellungspunkt
{
    public const string Name = "wiederherstellungspunkt";
    public const string Schnellbeschreibung = "Wiederherstellungspunkt erstellen";

    public static void Ausfuehren()
    {
        Console.WriteLine("[R] Wiederherstellungspunkt wird erstellt ...");

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

            $drive = $env:SystemDrive + '\'
            $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
            $property = 'SystemRestorePointCreationFrequency'

            Enable-ComputerRestore -Drive $drive

            $oldProperty = Get-ItemProperty `
                -Path $key `
                -Name $property `
                -ErrorAction SilentlyContinue

            $hadOldValue = $null -ne $oldProperty

            if ($hadOldValue) {
                $oldValue = $oldProperty.$property
            }

            try {
                New-ItemProperty `
                    -Path $key `
                    -Name $property `
                    -Value 0 `
                    -PropertyType DWord `
                    -Force | Out-Null

                $restorePointName =
                    'MaintenancePro_' + (Get-Date -Format 'yyyyMMdd_HHmmss')

                Checkpoint-Computer `
                    -Description $restorePointName `
                    -RestorePointType 'MODIFY_SETTINGS'

                Write-Output "Wiederherstellungspunkt '$restorePointName' wurde erstellt."
            }
            finally {
                if ($hadOldValue) {
                    Set-ItemProperty `
                        -Path $key `
                        -Name $property `
                        -Value $oldValue
                }
                else {
                    Remove-ItemProperty `
                        -Path $key `
                        -Name $property `
                        -ErrorAction SilentlyContinue
                }
            }
            """;

        try
        {
            // 10 Minuten Timeout — Checkpoint-Computer kann bei kaputtem VSS ewig hangen
            var erfolgreich = PowerShellHelper.Ausfuehren(script, 600, out var ausgabe, out var fehler, out var exitCode, out var timedOut);

            if (!erfolgreich)
            {
                Console.WriteLine("[FEHLER] PowerShell konnte nicht gestartet werden.");
                return;
            }

            if (timedOut)
            {
                Console.WriteLine(
                    "[FEHLER] Zeitlimit: Der Wiederherstellungspunkt wurde nach " +
                    "10 Minuten abgebrochen. Prüfe den Dienst " +
                    "\"Volumeschattenkopie\" (VSS).");
                return;
            }

            if (exitCode == 0)
            {
                Console.WriteLine("[OK] " + ausgabe.Trim());
            }
            else
            {
                Console.WriteLine("[FEHLER] Wiederherstellungspunkt fehlgeschlagen.");
                if (!string.IsNullOrWhiteSpace(fehler))
                {
                    Console.WriteLine(fehler.Trim());
                }
            }
        }
        catch (Exception fehler)
        {
            Console.WriteLine("[FEHLER] " + fehler.Message);
        }
    }
}
