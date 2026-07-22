using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;

namespace JustUpdate.Module;

/// <summary>
/// Systemdateien pruefen (SFC/DISM)
/// </summary>
internal static class SystemReparatur
{
    public const string Name = "reparatur";
    public const string Schnellbeschreibung = "SFC/DISM-Systemdateien prüfen";

    public static void Ausfuehren()
    {
        Console.WriteLine("[F] Systemdateien werden überprüft ...");

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

        (
            int ExitCode,
            bool TimedOut,
            string Output
        ) ProzessAusfuehren(
            string dateiname,
            string argumente,
            int zeitlimitSekunden,
            System.Text.Encoding ausgabeKodierung,
            string statusText)
        {
            var startInfo =
                new System.Diagnostics.ProcessStartInfo
                {
                    FileName = dateiname,
                    Arguments = argumente,
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    CreateNoWindow = true,
                    StandardOutputEncoding = ausgabeKodierung,
                    StandardErrorEncoding = ausgabeKodierung
                };

            using var prozess =
                new System.Diagnostics.Process
                {
                    StartInfo = startInfo
                };

            if (!prozess.Start())
            {
                throw new InvalidOperationException(
                    $"{dateiname} konnte nicht gestartet werden.");
            }

            var standardAusgabe =
                prozess.StandardOutput.ReadToEndAsync();

            var fehlerAusgabe =
                prozess.StandardError.ReadToEndAsync();

            var startzeit = DateTime.UtcNow;
            var naechsterStatus = startzeit.AddSeconds(30);
            bool zeitUeberschritten = false;

            while (!prozess.WaitForExit(1000))
            {
                TimeSpan laufzeit =
                    DateTime.UtcNow - startzeit;

                if (DateTime.UtcNow >= naechsterStatus)
                {
                    Console.WriteLine(
                        $"  {statusText} läuft seit " +
                        $"{(int)laufzeit.TotalMinutes:D2}:" +
                        $"{laufzeit.Seconds:D2} Minuten ...");

                    naechsterStatus =
                        DateTime.UtcNow.AddSeconds(30);
                }

                if (laufzeit.TotalSeconds >= zeitlimitSekunden)
                {
                    zeitUeberschritten = true;

                    try
                    {
                        prozess.Kill(entireProcessTree: true);
                    }
                    catch
                    {
                        // Der Prozess wurde möglicherweise bereits beendet.
                    }

                    break;
                }
            }

            prozess.WaitForExit();

            string ausgabe =
                standardAusgabe.GetAwaiter().GetResult();

            string fehler =
                fehlerAusgabe.GetAwaiter().GetResult();

            string kombiniert =
                string.Join(
                    Environment.NewLine,
                    new[] { ausgabe, fehler }
                        .Where(text => !string.IsNullOrWhiteSpace(text)));

            return (
                zeitUeberschritten ? -1 : prozess.ExitCode,
                zeitUeberschritten,
                kombiniert);
        }

        string LetzteZeilen(string text, int anzahl = 8)
        {
            if (string.IsNullOrWhiteSpace(text))
            {
                return "Keine zusätzliche Fehlermeldung verfügbar.";
            }

            string[] zeilen =
                text.Split(
                    new[] { "\r\n", "\n" },
                    StringSplitOptions.RemoveEmptyEntries);

            return string.Join(
                Environment.NewLine,
                zeilen.TakeLast(anzahl));
        }

        try
        {
            System.Text.Encoding dismKodierung;

            try
            {
                int oemCodepage =
                    System.Globalization.CultureInfo
                        .CurrentCulture
                        .TextInfo
                        .OEMCodePage;

                dismKodierung =
                    System.Text.Encoding.GetEncoding(oemCodepage);
            }
            catch
            {
                dismKodierung =
                    System.Text.Encoding.Default;
            }

            Console.WriteLine();
            Console.WriteLine("--------------------------------------------");
            Console.WriteLine("  Schritt 1/2: System File Checker");
            Console.WriteLine("--------------------------------------------");
            Console.WriteLine("  Windows-Systemdateien werden überprüft.");
            Console.WriteLine("  Zeitlimit ohne Abschluss: 30 Minuten.");
            Console.WriteLine();

            var sfcErgebnis =
                ProzessAusfuehren(
                    "sfc.exe",
                    "/scannow",
                    1800,
                    System.Text.Encoding.Unicode,
                    "SFC");

            string sfcText =
                sfcErgebnis.Output.ToLowerInvariant();

            bool sfcNeustartAusstehend =
                !sfcErgebnis.TimedOut &&
                sfcErgebnis.ExitCode != 0 &&
                (
                    sfcText.Contains("systemreparatur aus") ||
                    sfcText.Contains("neustart erfordert") ||
                    sfcText.Contains("pending system repair") ||
                    sfcText.Contains("system repair pending") ||
                    sfcText.Contains("requires a restart") ||
                    sfcText.Contains("requires reboot")
                );

            bool sfcErfolgreich =
                !sfcErgebnis.TimedOut &&
                sfcErgebnis.ExitCode == 0;

            if (sfcErfolgreich)
            {
                Console.WriteLine("[OK] SFC wurde erfolgreich abgeschlossen.");
            }
            else if (sfcErgebnis.TimedOut)
            {
                Console.WriteLine(
                    "[WARNUNG] SFC wurde nach 30 Minuten abgebrochen.");
            }
            else if (sfcNeustartAusstehend)
            {
                Console.WriteLine(
                    "[WARNUNG] SFC konnte wegen einer ausstehenden " +
                    "Systemreparatur nicht ausgeführt werden.");

                Console.WriteLine(
                    "[NEUSTART ERFORDERLICH] Windows neu starten und " +
                    "die Wartung danach erneut ausführen.");
            }
            else
            {
                Console.WriteLine(
                    $"[FEHLER] SFC ist fehlgeschlagen. " +
                    $"Exit-Code: {sfcErgebnis.ExitCode}");

                Console.WriteLine(
                    LetzteZeilen(sfcErgebnis.Output));
            }

            Console.WriteLine();
            Console.WriteLine("--------------------------------------------");
            Console.WriteLine("  Schritt 2/2: DISM");
            Console.WriteLine("--------------------------------------------");
            Console.WriteLine("  Der Windows-Komponentenspeicher wird repariert.");
            Console.WriteLine("  Zeitlimit ohne Abschluss: 45 Minuten.");
            Console.WriteLine();

            var dismErgebnis =
                ProzessAusfuehren(
                    "dism.exe",
                    "/Online /Cleanup-Image /RestoreHealth",
                    2700,
                    dismKodierung,
                    "DISM");

            if (
                !dismErgebnis.TimedOut &&
                dismErgebnis.ExitCode == 32)
            {
                Console.WriteLine(
                    "[HINWEIS] DISM meldet einen Datei-Konflikt.");

                Console.WriteLine(
                    "Ein Virenschutz oder ein anderer Prozess könnte " +
                    "eine benötigte Datei verwenden.");

                Console.WriteLine(
                    "Es wird 45 Sekunden gewartet und einmal erneut versucht.");

                System.Threading.Thread.Sleep(
                    TimeSpan.FromSeconds(45));

                dismErgebnis =
                    ProzessAusfuehren(
                        "dism.exe",
                        "/Online /Cleanup-Image /RestoreHealth",
                        2700,
                        dismKodierung,
                        "DISM-Wiederholung");
            }

            bool dismErfolgreich =
                !dismErgebnis.TimedOut &&
                (
                    dismErgebnis.ExitCode == 0 ||
                    dismErgebnis.ExitCode == 3010
                );

            bool dismNeustartErforderlich =
                dismErgebnis.ExitCode == 3010;

            if (dismErfolgreich)
            {
                Console.WriteLine("[OK] DISM wurde erfolgreich abgeschlossen.");

                if (dismNeustartErforderlich)
                {
                    Console.WriteLine(
                        "[NEUSTART ERFORDERLICH] Windows muss neu gestartet " +
                        "werden, um die Reparatur abzuschließen.");
                }
            }
            else if (dismErgebnis.TimedOut)
            {
                Console.WriteLine(
                    "[WARNUNG] DISM wurde nach 45 Minuten abgebrochen.");
            }
            else if (dismErgebnis.ExitCode == 32)
            {
                Console.WriteLine(
                    "[FEHLER] DISM meldet weiterhin einen Datei-Konflikt.");

                Console.WriteLine(
                    "Virenschutz vorübergehend pausieren, Windows neu starten " +
                    "und die Reparatur erneut ausführen.");
            }
            else
            {
                Console.WriteLine(
                    $"[FEHLER] DISM ist fehlgeschlagen. " +
                    $"Exit-Code: {dismErgebnis.ExitCode}");

                Console.WriteLine(
                    LetzteZeilen(dismErgebnis.Output));
            }

            Console.WriteLine();

            if (sfcErfolgreich && dismErfolgreich)
            {
                Console.WriteLine(
                    "[OK] System-Reparatur vollständig abgeschlossen.");
            }
            else if (sfcNeustartAusstehend && dismErfolgreich)
            {
                Console.WriteLine(
                    "[WARNUNG] DISM war erfolgreich, SFC benötigt jedoch " +
                    "zuerst einen Windows-Neustart.");
            }
            else if (
                sfcErgebnis.TimedOut ||
                dismErgebnis.TimedOut)
            {
                Console.WriteLine(
                    "[WARNUNG] Die System-Reparatur wurde teilweise wegen " +
                    "einer Zeitüberschreitung abgebrochen.");
            }
            else if (sfcErfolgreich || dismErfolgreich)
            {
                Console.WriteLine(
                    "[WARNUNG] Die System-Reparatur war nur teilweise erfolgreich.");
            }
            else
            {
                Console.WriteLine(
                    "[FEHLER] SFC und DISM konnten nicht erfolgreich " +
                    "abgeschlossen werden.");
            }
        }
        catch (Exception fehler)
        {
            Console.WriteLine(
                "[FEHLER] System-Reparatur fehlgeschlagen: " +
                fehler.Message);
        }
    }
}
