using System.ComponentModel;
using System.Diagnostics;
using System.Text;

namespace JustUpdate.Module;

/// <summary>
/// Installierte Apps ueber winget aktualisieren.
/// Winget wird direkt gestartet - kein PowerShell-Zwischenschritt.
/// </summary>
internal static class Apps
{
    public const string Name = "apps";
    public const string Schnellbeschreibung = "Apps über Winget aktualisieren";

    private static readonly TimeSpan QuellenTimeout = TimeSpan.FromMinutes(10);
    private static readonly TimeSpan UpgradeTimeout = TimeSpan.FromMinutes(60);

    public static void Ausfuehren()
    {
        Console.WriteLine("[A] Installierte Apps werden aktualisiert ...");

        if (!OperatingSystem.IsWindows())
        {
            Console.WriteLine("[FEHLER] Diese Funktion ist nur unter Windows verfügbar.");
            return;
        }

        try
        {
            string wingetPfad = ErmittleWingetPfad();

            Console.WriteLine($"Winget wird verwendet: {wingetPfad}");
            Console.WriteLine("Winget-Quellen werden aktualisiert ...");

            ProzessErgebnis quellen = FuehreProzessAus(
                wingetPfad,
                ["source", "update", "--disable-interactivity"],
                QuellenTimeout);

            bool quellenWarnung = quellen.Zeitueberschreitung || quellen.ExitCode != 0;

            if (quellen.Zeitueberschreitung)
            {
                Console.WriteLine(
                    "[WARNUNG] Das Aktualisieren der Winget-Quellen wurde nach " +
                    "10 Minuten abgebrochen.");
            }
            else if (quellen.ExitCode != 0)
            {
                Console.WriteLine(
                    "[WARNUNG] Die Winget-Quellen konnten nicht vollständig " +
                    "aktualisiert werden.");

                Console.WriteLine(
                    $"Winget-Rückgabecode: {FormatiereExitCode(quellen.ExitCode)}");
            }
            else
            {
                Console.WriteLine("[OK] Winget-Quellen wurden aktualisiert.");
            }

            if (quellenWarnung)
            {
                Console.WriteLine(
                    "Die App-Aktualisierung wird mit dem vorhandenen Paketindex " +
                    "fortgesetzt.");
            }

            Console.WriteLine();
            Console.WriteLine("Verfügbare App-Updates werden installiert ...");
            Console.WriteLine(
                "Das kann mehrere Minuten dauern. Bitte das Programm nicht beenden.");

            // --silent reicht den Silent-Schalter an den Installer *unter* winget
            // weiter. --disable-interactivity unterdrueckt nur wingets eigene
            // Rueckfragen, nicht die des MSI/Setups darunter.
            ProzessErgebnis upgrade = FuehreProzessAus(
                wingetPfad,
                [
                    "upgrade",
                    "--all",
                    "--include-unknown",
                    "--silent",
                    "--disable-interactivity",
                    "--accept-source-agreements",
                    "--accept-package-agreements"
                ],
                UpgradeTimeout);

            Console.WriteLine();

            if (upgrade.Zeitueberschreitung)
            {
                Console.WriteLine(
                    "[FEHLER] Die App-Aktualisierung wurde nach 60 Minuten abgebrochen.");
                return;
            }

            if (upgrade.ExitCode != 0)
            {
                Console.WriteLine("[FEHLER] Die App-Aktualisierung ist fehlgeschlagen.");

                Console.WriteLine(
                    $"Winget-Rückgabecode: {FormatiereExitCode(upgrade.ExitCode)}");

                Console.WriteLine(
                    "[HINWEIS] Einzelne Pakete können bereits aktualisiert worden " +
                    "sein. Massgebend ist die Winget-Ausgabe weiter oben.");

                return;
            }

            if (quellenWarnung)
            {
                Console.WriteLine(
                    "[WARNUNG] App-Aktualisierung abgeschlossen, aber die " +
                    "Winget-Quellen konnten zuvor nicht vollständig aktualisiert " +
                    "werden.");
            }
            else
            {
                Console.WriteLine("[OK] App-Aktualisierungsmodul abgeschlossen.");
            }
        }
        catch (Win32Exception fehler) when (fehler.NativeErrorCode is 2 or 3)
        {
            Console.WriteLine("[FEHLER] Winget konnte nicht gestartet werden.");
            Console.WriteLine(
                "Installiere im Microsoft Store die Anwendung \"App-Installer\".");
        }
        catch (Win32Exception fehler) when (fehler.NativeErrorCode == 5)
        {
            Console.WriteLine("[FEHLER] Der Zugriff auf Winget wurde verweigert.");
            Console.WriteLine(
                "Prüfe die Windows-App-Ausführungsaliase und die Berechtigungen " +
                "des aktuellen Benutzers.");
        }
        catch (Exception fehler)
        {
            Console.WriteLine("[FEHLER] Unerwarteter Fehler bei der App-Aktualisierung:");
            Console.WriteLine(fehler.Message);
        }
    }

    /// <summary>
    /// Sucht winget.exe: erst der App-Ausfuehrungsalias im eigenen Profil,
    /// dann der PATH. Fremde Benutzerprofile werden bewusst NICHT durchsucht -
    /// ein winget aus einem anderen Profil ist fuer diesen Benutzer nicht
    /// registriert. Findet sich nichts, wird "winget.exe" zurueckgegeben; der
    /// fehlgeschlagene Start liefert dann eine aussagekraeftige Win32Exception.
    /// </summary>
    private static string ErmittleWingetPfad()
    {
        string lokalerAppPfad = Environment.GetFolderPath(
            Environment.SpecialFolder.LocalApplicationData);

        if (!string.IsNullOrWhiteSpace(lokalerAppPfad))
        {
            string alias = Path.Combine(
                lokalerAppPfad, "Microsoft", "WindowsApps", "winget.exe");

            if (File.Exists(alias))
            {
                return alias;
            }
        }

        string? pfadVariable = Environment.GetEnvironmentVariable("PATH");

        if (!string.IsNullOrWhiteSpace(pfadVariable))
        {
            foreach (string verzeichnis in pfadVariable.Split(
                Path.PathSeparator,
                StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            {
                try
                {
                    string kandidat = Path.Combine(verzeichnis.Trim('"'), "winget.exe");

                    if (File.Exists(kandidat))
                    {
                        return kandidat;
                    }
                }
                catch (Exception fehler) when (fehler is ArgumentException
                    or NotSupportedException
                    or PathTooLongException)
                {
                    // Ungueltiger einzelner PATH-Eintrag - ueberspringen.
                }
            }
        }

        return "winget.exe";
    }

    private static ProzessErgebnis FuehreProzessAus(
        string dateiname,
        IReadOnlyList<string> argumente,
        TimeSpan timeout)
    {
        return FuehreProzessAusAsync(dateiname, argumente, timeout)
            .GetAwaiter()
            .GetResult();
    }

    private static async Task<ProzessErgebnis> FuehreProzessAusAsync(
        string dateiname,
        IReadOnlyList<string> argumente,
        TimeSpan timeout)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = dateiname,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            StandardOutputEncoding = new UTF8Encoding(false),
            StandardErrorEncoding = new UTF8Encoding(false)
        };

        // ArgumentList quotet jedes Argument selbst - kein Command-Injection-Risiko.
        foreach (string argument in argumente)
        {
            startInfo.ArgumentList.Add(argument);
        }

        using var prozess = new Process { StartInfo = startInfo };

        prozess.Start();

        // Beide Streams gleichzeitig leeren, sonst blockiert winget, sobald eine
        // der beiden Pipes volllaeuft.
        // BEIDE Streams nach Console.Out - NICHT nach Console.Error. Program.cs
        // haengt den Mitschnitt (Log + Modul-Status) per Console.SetOut ein;
        // Console.Error laeuft daran vorbei und fehlte im Log.
        Task ausgabe = LeseStromAsync(prozess.StandardOutput);
        Task fehlerausgabe = LeseStromAsync(prozess.StandardError);

        using var timeoutQuelle = new CancellationTokenSource(timeout);

        try
        {
            await prozess.WaitForExitAsync(timeoutQuelle.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (timeoutQuelle.IsCancellationRequested)
        {
            try
            {
                prozess.Kill(entireProcessTree: true);
            }
            catch (Exception fehler) when (fehler is InvalidOperationException
                or Win32Exception)
            {
                // Prozess ist zwischenzeitlich schon beendet oder laesst sich nicht
                // beenden - in beiden Faellen ist hier nichts mehr zu retten.
            }

            await prozess.WaitForExitAsync().ConfigureAwait(false);
            await Task.WhenAll(ausgabe, fehlerausgabe).ConfigureAwait(false);

            return new ProzessErgebnis(ExitCode: -1, Zeitueberschreitung: true);
        }

        // Erst wenn beide Leser durch sind, ist die Ausgabe vollstaendig.
        await Task.WhenAll(ausgabe, fehlerausgabe).ConfigureAwait(false);

        return new ProzessErgebnis(prozess.ExitCode, Zeitueberschreitung: false);
    }

    private static async Task LeseStromAsync(StreamReader leser)
    {
        while (await leser.ReadLineAsync().ConfigureAwait(false) is { } zeile)
        {
            Console.WriteLine(zeile);

            if (VerlangtNeustart(zeile))
            {
                // Program.cs erkennt einen noetigen Neustart nur an diesem
                // Marker. Der Exit-Code von winget sagt darueber nichts.
                Console.WriteLine(
                    "[NEUSTART ERFORDERLICH] Mindestens ein Update wird erst nach " +
                    "einem Windows-Neustart abgeschlossen.");
            }
        }
    }

    /// <summary>
    /// Bewusst Textvergleich auf wingets lokalisierte Ausgabe - und bewusst NUR
    /// hier: Ob der Lauf erfolgreich war, entscheidet allein der Exit-Code.
    /// Dieser Marker ist nur ein Hinweis. Greift das Muster in einer nicht
    /// abgedeckten Sprache nicht, fehlt der Hinweis - es wird nichts falsch
    /// bewertet.
    /// </summary>
    private static bool VerlangtNeustart(string zeile)
    {
        return zeile.Contains("Restart your PC", StringComparison.OrdinalIgnoreCase)
            || zeile.Contains("reboot", StringComparison.OrdinalIgnoreCase)
            || zeile.Contains("Neustart", StringComparison.OrdinalIgnoreCase)
            || zeile.Contains("PC neu", StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// Winget-Fehlercodes stehen in der Doku hexadezimal (z. B. 0x8A150011),
    /// .NET liefert sie dezimal und vorzeichenbehaftet.
    /// </summary>
    private static string FormatiereExitCode(int exitCode)
    {
        return $"{exitCode} (0x{unchecked((uint)exitCode):X8})";
    }

    private readonly record struct ProzessErgebnis(int ExitCode, bool Zeitueberschreitung);
}
