using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;

namespace JustUpdate.Module;

/// <summary>
/// Netzwerk zuruecksetzen
/// </summary>
internal static class Netzwerk
{
    public const string Name = "netzwerk";

    public static void Ausfuehren()
    {
        Console.WriteLine("[N] Netzwerk wird überprüft ...");

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
            string[] Lines
        ) ProzessAusfuehren(
            string dateiname,
            string argumente,
            int zeitlimitSekunden = 120)
        {
            System.Text.Encoding.RegisterProvider(
                System.Text.CodePagesEncodingProvider.Instance);

            System.Text.Encoding kodierung;

            try
            {
                int oemCodepage =
                    System.Globalization.CultureInfo
                        .CurrentCulture
                        .TextInfo
                        .OEMCodePage;

                kodierung =
                    System.Text.Encoding.GetEncoding(oemCodepage);
            }
            catch
            {
                kodierung = System.Text.Encoding.Default;
            }

            var startInfo =
                new System.Diagnostics.ProcessStartInfo
                {
                    FileName = dateiname,
                    Arguments = argumente,
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    CreateNoWindow = true,
                    StandardOutputEncoding = kodierung,
                    StandardErrorEncoding = kodierung
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

            bool abgeschlossen =
                prozess.WaitForExit(zeitlimitSekunden * 1000);

            if (!abgeschlossen)
            {
                try
                {
                    prozess.Kill(entireProcessTree: true);
                }
                catch
                {
                    try
                    {
                        prozess.Kill();
                    }
                    catch
                    {
                        // Prozess konnte nicht mehr beendet werden.
                    }
                }

                prozess.WaitForExit();

                return (
                    -1,
                    true,
                    new[]
                    {
                        $"[Timeout] {dateiname} {argumente} wurde nach " +
                        $"{zeitlimitSekunden} Sekunden abgebrochen."
                    });
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

            string[] zeilen =
                kombiniert.Split(
                    new[] { "\r\n", "\n" },
                    StringSplitOptions.RemoveEmptyEntries);

            return (
                prozess.ExitCode,
                false,
                zeilen);
        }

        void AusgabeAnzeigen(IEnumerable<string> zeilen)
        {
            foreach (string zeile in zeilen)
            {
                string text = zeile.Trim();

                if (text.Length > 1)
                {
                    Console.WriteLine($"    {text}");
                }
            }
        }

        try
        {
            var fehlgeschlageneSchritte =
                new List<string>();

            Console.WriteLine();
            Console.WriteLine("--------------------------------------------");
            Console.WriteLine("  Netzwerk reparieren");
            Console.WriteLine("--------------------------------------------");

            Console.WriteLine("  Schritt 1/5: DNS-Cache leeren ...");

            var dnsErgebnis =
                ProzessAusfuehren(
                    "ipconfig.exe",
                    "/flushdns");

            AusgabeAnzeigen(dnsErgebnis.Lines);

            if (dnsErgebnis.ExitCode != 0)
            {
                fehlgeschlageneSchritte.Add("DNS-Flush");
            }

            Console.WriteLine();
            Console.WriteLine("  Schritt 2/5: Winsock-Katalog zurücksetzen ...");

            var winsockErgebnis =
                ProzessAusfuehren(
                    "netsh.exe",
                    "winsock reset");

            AusgabeAnzeigen(winsockErgebnis.Lines);

            if (winsockErgebnis.ExitCode != 0)
            {
                fehlgeschlageneSchritte.Add("Winsock-Reset");
            }

            Console.WriteLine();
            Console.WriteLine("  Schritt 3/5: IP-Adresse freigeben ...");

            var releaseErgebnis =
                ProzessAusfuehren(
                    "ipconfig.exe",
                    "/release");

            if (releaseErgebnis.TimedOut)
            {
                AusgabeAnzeigen(releaseErgebnis.Lines);
                fehlgeschlageneSchritte.Add("IP-Freigabe");
            }

            Console.WriteLine();
            Console.WriteLine("  Schritt 4/5: Neue IP-Adresse beziehen ...");

            var renewErgebnis =
                ProzessAusfuehren(
                    "ipconfig.exe",
                    "/renew");

            AusgabeAnzeigen(renewErgebnis.Lines);

            if (renewErgebnis.ExitCode != 0)
            {
                fehlgeschlageneSchritte.Add("IP-Erneuerung");
            }

            Console.WriteLine();
            Console.WriteLine("  Schritt 5/5: TCP/IP-Stack zurücksetzen ...");

            var tcpErgebnis =
                ProzessAusfuehren(
                    "netsh.exe",
                    "int ip reset");

            int anonymeErfolge = 0;
            int anonymeFehler = 0;
            bool letzterEintragWarFehler = false;

            const string anonymesMuster =
                @"^(wird zurückgesetzt|Resetting)\.{0,3}\s*" +
                @"(OK|Fehler|Failed|Failed\.|denied|verweigert)?\s*$";

            foreach (string zeile in tcpErgebnis.Lines)
            {
                string text = zeile.Trim();

                if (text.Length < 2)
                {
                    letzterEintragWarFehler = false;
                    continue;
                }

                if (System.Text.RegularExpressions.Regex.IsMatch(
                        text,
                        anonymesMuster,
                        System.Text.RegularExpressions.RegexOptions.IgnoreCase))
                {
                    if (System.Text.RegularExpressions.Regex.IsMatch(
                            text,
                            @"OK\s*$",
                            System.Text.RegularExpressions.RegexOptions.IgnoreCase))
                    {
                        anonymeErfolge++;
                        letzterEintragWarFehler = false;
                    }
                    else
                    {
                        anonymeFehler++;
                        letzterEintragWarFehler = true;
                    }

                    continue;
                }

                if (
                    letzterEintragWarFehler &&
                    System.Text.RegularExpressions.Regex.IsMatch(
                        text,
                        @"^(Zugriff verweigert|Access is denied)\.?\s*$",
                        System.Text.RegularExpressions.RegexOptions.IgnoreCase))
                {
                    letzterEintragWarFehler = false;
                    continue;
                }

                letzterEintragWarFehler = false;
                Console.WriteLine($"    {text}");
            }

            if (anonymeErfolge + anonymeFehler > 0)
            {
                string fehlerText =
                    anonymeFehler > 0
                        ? $", {anonymeFehler} Fehler " +
                          "(gesperrte Registry-Schlüssel, meist harmlos)"
                        : string.Empty;

                Console.WriteLine(
                    $"    Weitere Reset-Schritte: " +
                    $"{anonymeErfolge} OK{fehlerText}");
            }

            bool tcpErfolgreich =
                tcpErgebnis.Lines.Any(
                    zeile =>
                        zeile.Contains(
                            "Starten Sie den Computer neu",
                            StringComparison.OrdinalIgnoreCase) ||
                        zeile.Contains(
                            "Restart the computer",
                            StringComparison.OrdinalIgnoreCase));

            int verweigerteZugriffe =
                tcpErgebnis.Lines.Count(
                    zeile =>
                        zeile.Contains(
                            "verweigert",
                            StringComparison.OrdinalIgnoreCase) ||
                        zeile.Contains(
                            "denied",
                            StringComparison.OrdinalIgnoreCase));

            if (!tcpErfolgreich)
            {
                fehlgeschlageneSchritte.Add("TCP/IP-Reset");
            }
            else if (verweigerteZugriffe > 0)
            {
                Console.WriteLine(
                    $"  [HINWEIS] {verweigerteZugriffe} gesperrte " +
                    "Registry-Schlüssel wurden übersprungen.");

                Console.WriteLine(
                    "  Das ist bei bestimmten Windows-Netzwerkeinträgen " +
                    "ein bekanntes Verhalten.");
            }

            Console.WriteLine();

            if (fehlgeschlageneSchritte.Count == 0)
            {
                Console.WriteLine(
                    "[OK] Netzwerk-Reset erfolgreich abgeschlossen.");

                Console.WriteLine(
                    "[NEUSTART EMPFOHLEN] Windows neu starten, damit alle " +
                    "Änderungen vollständig wirksam werden.");
            }
            else
            {
                Console.WriteLine(
                    "[WARNUNG] Folgende Schritte sind fehlgeschlagen: " +
                    string.Join(", ", fehlgeschlageneSchritte));

                Console.WriteLine(
                    "Prüfe die Netzwerkadapter, VPN-Software und " +
                    "Administratorrechte.");
            }
        }
        catch (Exception fehler)
        {
            Console.WriteLine(
                "[FEHLER] Netzwerk-Reparatur fehlgeschlagen: " +
                fehler.Message);
        }
    }
}
