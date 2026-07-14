using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;

namespace JustUpdate.Module;

/// <summary>
/// Microsoft-Defender-Signaturen aktualisieren
/// </summary>
internal static class Defender
{
    public const string Name = "defender";

    public static void Ausfuehren()
    {
        Console.WriteLine("[D] Microsoft Defender wird aktualisiert ...");

        if (!OperatingSystem.IsWindows())
        {
            Console.WriteLine("[FEHLER] Diese Funktion ist nur unter Windows verfügbar.");
            return;
        }

        string script = """
            $ErrorActionPreference = 'Stop'

            function Test-PendingReboot {
                $rebootPending = $false

                if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
                    $rebootPending = $true
                }

                if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
                    $rebootPending = $true
                }

                try {
                    $sessionManager = Get-ItemProperty `
                        -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
                        -Name 'PendingFileRenameOperations' `
                        -ErrorAction SilentlyContinue

                    if ($sessionManager.PendingFileRenameOperations) {
                        $rebootPending = $true
                    }
                }
                catch {}

                return $rebootPending
            }

            $otherAntivirus = $null
            $pendingReboot = Test-PendingReboot

            try {
                $antivirusProducts = Get-CimInstance `
                    -Namespace 'root\SecurityCenter2' `
                    -ClassName 'AntiVirusProduct' `
                    -ErrorAction SilentlyContinue

                $otherAntivirus = $antivirusProducts |
                    Where-Object {
                        $_.displayName -and
                        $_.displayName -notmatch 'Windows Defender|Microsoft Defender'
                    } |
                    Select-Object -ExpandProperty displayName -First 1
            }
            catch {}

            if (-not (Get-Command Update-MpSignature -ErrorAction SilentlyContinue)) {
                if ($otherAntivirus) {
                    Write-Output "[OK] Microsoft Defender ist passiv."
                    Write-Output "Aktiver Drittanbieter-Virenschutz: $otherAntivirus"
                    Write-Output "Dieser Virenschutz verwaltet seine Updates selbst."
                    exit 0
                }

                Write-Output "[WARNUNG] Microsoft Defender ist auf diesem System nicht verfügbar."
                exit 0
            }

            $oldVersion = $null
            $oldUpdateTime = $null

            try {
                $oldStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue

                if ($oldStatus) {
                    $oldVersion = $oldStatus.AntivirusSignatureVersion
                    $oldUpdateTime = $oldStatus.AntivirusSignatureLastUpdated

                    Write-Output "Aktueller Status:"
                    Write-Output "  Antivirus-Version: $oldVersion"
                    Write-Output "  Letztes Update:    $oldUpdateTime"

                    if ($oldStatus.RealTimeProtectionEnabled) {
                        Write-Output "  Echtzeit-Schutz:   Aktiv"
                    }
                    else {
                        Write-Output "  Echtzeit-Schutz:   Inaktiv"
                    }
                }
            }
            catch {}

            try {
                Write-Output "Neueste Defender-Signaturen werden heruntergeladen ..."

                Update-MpSignature -ErrorAction Stop

                $newStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue
                $newVersion = $null
                $newUpdateTime = $null

                if ($newStatus) {
                    $newVersion = $newStatus.AntivirusSignatureVersion
                    $newUpdateTime = $newStatus.AntivirusSignatureLastUpdated

                    Write-Output "Neue Version:      $newVersion"
                    Write-Output "Neues Updatedatum: $newUpdateTime"
                }

                if ($newVersion -and $oldVersion -and $newVersion -ne $oldVersion) {
                    Write-Output "[OK] Defender-Signaturen wurden erfolgreich aktualisiert."
                    exit 0
                }

                if ($newUpdateTime -and $oldUpdateTime -and $newUpdateTime -gt $oldUpdateTime) {
                    Write-Output "[OK] Defender-Signaturen wurden erfolgreich aktualisiert."
                    exit 0
                }

                if ($newVersion -and $oldVersion -and $newVersion -eq $oldVersion) {
                    Write-Output "[OK] Microsoft Defender war bereits aktuell."
                    exit 0
                }

                Write-Output "[WARNUNG] Das Update wurde ausgeführt, konnte aber nicht vollständig verifiziert werden."
                exit 0
            }
            catch {
                $updateError = $_.Exception.Message

                if ($otherAntivirus) {
                    Write-Output "[OK] Defender-Update nicht erforderlich."
                    Write-Output "Aktiver Drittanbieter-Virenschutz: $otherAntivirus"
                    exit 0
                }

                $mpCmdRun = $null
                $platformDirectory = Join-Path `
                    $env:ProgramData `
                    'Microsoft\Windows Defender\Platform'

                if (Test-Path $platformDirectory) {
                    $mpCmdRun = Get-ChildItem `
                        -Path $platformDirectory `
                        -Directory `
                        -ErrorAction SilentlyContinue |
                        Sort-Object Name -Descending |
                        ForEach-Object {
                            Join-Path $_.FullName 'MpCmdRun.exe'
                        } |
                        Where-Object {
                            Test-Path $_
                        } |
                        Select-Object -First 1
                }

                if (-not $mpCmdRun) {
                    $fallbackPath = Join-Path `
                        $env:ProgramFiles `
                        'Windows Defender\MpCmdRun.exe'

                    if (Test-Path $fallbackPath) {
                        $mpCmdRun = $fallbackPath
                    }
                }

                if ($mpCmdRun) {
                    Write-Output "PowerShell-Update fehlgeschlagen."
                    Write-Output "Fallback über MpCmdRun.exe wird gestartet ..."

                    try {
                        $fallbackProcess = Start-Process `
                            -FilePath $mpCmdRun `
                            -ArgumentList '-SignatureUpdate' `
                            -Wait `
                            -PassThru `
                            -WindowStyle Hidden

                        if ($fallbackProcess.ExitCode -eq 0) {
                            Write-Output "[OK] Defender-Signaturen wurden über MpCmdRun aktualisiert."
                            exit 0
                        }

                        Write-Output "MpCmdRun-Rückgabecode: $($fallbackProcess.ExitCode)"
                    }
                    catch {
                        Write-Output "MpCmdRun konnte nicht ausgeführt werden: $($_.Exception.Message)"
                    }
                }

                $isRpcError =
                    $updateError -match 'Remoteprozeduraufruf|800706BE|RPC server'

                if ($isRpcError -or $pendingReboot) {
                    Write-Output "[WARNUNG] Das Defender-Update ist momentan nicht möglich."
                    Write-Output "Ein Neustart ist möglicherweise erforderlich."
                    Write-Output "Microsoft Defender aktualisiert sich nach dem Neustart automatisch."
                    exit 0
                }

                Write-Error "Defender-Update fehlgeschlagen: $updateError"
                exit 1
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

            // Update-MpSignature haengt bei blockiertem Defender-Dienst oder
            // toter Netzwerkverbindung unbegrenzt. 20 Minuten sind grosszuegig -
            // ein Signatur-Update dauert normalerweise unter einer Minute.
            if (!process.WaitForExit(20 * 60 * 1000))
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
                    "[FEHLER] Zeitlimit: Das Defender-Update wurde nach " +
                    "20 Minuten abgebrochen.");

                return;
            }

            process.WaitForExit();

            string ausgabeText = ausgabe.ToString();

            if (!string.IsNullOrWhiteSpace(ausgabeText))
            {
                Console.WriteLine(ausgabeText.Trim());
            }

            if (process.ExitCode != 0)
            {
                Console.WriteLine("[FEHLER] Microsoft Defender konnte nicht aktualisiert werden.");

                string fehlerText = fehlerAusgabe.ToString();

                if (!string.IsNullOrWhiteSpace(fehlerText))
                {
                    Console.WriteLine(fehlerText.Trim());
                }
            }
        }
        catch (Exception fehler)
        {
            Console.WriteLine("[FEHLER] " + fehler.Message);
        }
    }
}
