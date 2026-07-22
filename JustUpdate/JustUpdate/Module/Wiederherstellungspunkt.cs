using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;

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
            var startInfo = new System.Diagnostics.ProcessStartInfo
            {
                FileName = "powershell.exe",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
                // Fehlte hier als einzigem Modul - ohne UTF-8 kommen die Umlaute
                // aus dem PowerShell-Skript verstuemmelt zurueck.
                StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8
            };

            startInfo.ArgumentList.Add("-NoProfile");
            startInfo.ArgumentList.Add("-NonInteractive");
            startInfo.ArgumentList.Add("-ExecutionPolicy");
            startInfo.ArgumentList.Add("Bypass");
            startInfo.ArgumentList.Add("-Command");
            startInfo.ArgumentList.Add(script);

            var ausgabe = new StringBuilder();
            var fehlerAusgabe = new StringBuilder();

            using var process =
                new System.Diagnostics.Process { StartInfo = startInfo };

            // ReadToEnd() blockiert ohne Zeitlimit: haengt Checkpoint-Computer
            // (kaputtes VSS, blockierter Volumeschattenkopie-Dienst), haengt die
            // gesamte Wartung fuer immer. Darum asynchron lesen + Zeitlimit.
            process.OutputDataReceived += (_, e) =>
            {
                if (e.Data != null)
                {
                    lock (ausgabe) { ausgabe.AppendLine(e.Data); }
                }
            };

            process.ErrorDataReceived += (_, e) =>
            {
                if (e.Data != null)
                {
                    lock (fehlerAusgabe) { fehlerAusgabe.AppendLine(e.Data); }
                }
            };

            if (!process.Start())
            {
                Console.WriteLine("[FEHLER] PowerShell konnte nicht gestartet werden.");
                return;
            }

            process.BeginOutputReadLine();
            process.BeginErrorReadLine();

            if (!process.WaitForExit(10 * 60 * 1000))
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
                    "[FEHLER] Zeitlimit: Der Wiederherstellungspunkt wurde nach " +
                    "10 Minuten abgebrochen. Pruefe den Dienst " +
                    "\"Volumeschattenkopie\" (VSS).");

                return;
            }

            process.WaitForExit();

            if (process.ExitCode == 0)
            {
                Console.WriteLine("[OK] " + ausgabe.ToString().Trim());
            }
            else
            {
                Console.WriteLine("[FEHLER] Wiederherstellungspunkt fehlgeschlagen.");
                Console.WriteLine(fehlerAusgabe.ToString().Trim());
            }
        }
        catch (Exception fehler)
        {
            Console.WriteLine("[FEHLER] " + fehler.Message);
        }
    }
}
