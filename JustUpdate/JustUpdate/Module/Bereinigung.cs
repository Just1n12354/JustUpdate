using System.Security;

namespace JustUpdate.Module;

/// <summary>
/// Temporaere Dateien loeschen
/// </summary>
internal static class Bereinigung
{
    public const string Name = "bereinigung";

    private const int MaximalesAlterInTagen = 7;

    // ACHTUNG: AttributesToSkip ueberschreibt den Default (Hidden | System).
    // ReparsePoint: sonst folgt die Suche Junctions aus dem Temp-Ordner heraus
    //   und loescht Dateien ausserhalb.
    // System:       Windows-eigene Dateien fasst das Tool nicht an.
    // Hidden ist BEWUSST nicht dabei - versteckte Installer-Reste im Temp sind
    //   genau das, was hier weg soll.
    private const FileAttributes AuszulassendeAttribute =
        FileAttributes.System | FileAttributes.ReparsePoint;

    public static void Ausfuehren()
    {
        Console.WriteLine("[C] Bereinigung wird gestartet ...");

        string? tempOrdner = ErmittleTempOrdner();

        if (tempOrdner is null)
        {
            Console.WriteLine("Bereinigung abgebrochen.");
            return;
        }

        // UTC, damit die Sieben-Tage-Grenze bei der Zeitumstellung nicht
        // um eine Stunde springt.
        DateTime grenzdatumUtc = DateTime.UtcNow.AddDays(-MaximalesAlterInTagen);

        int geloeschteDateien = 0;
        int fehlerhafteDateien = 0;
        long freigegebeneBytes = 0;
        bool sucheVollstaendig = true;

        Console.WriteLine($"Temp-Ordner: {tempOrdner}");
        Console.WriteLine(
            $"Dateien, die älter als {MaximalesAlterInTagen} Tage sind, werden gelöscht.");

        var suchOptionen = new EnumerationOptions
        {
            RecurseSubdirectories = true,
            // Ein einzelner gesperrter Unterordner (z.B. Temp\nx) darf die
            // Wartung nicht abbrechen.
            IgnoreInaccessible = true,
            AttributesToSkip = AuszulassendeAttribute
        };

        try
        {
            foreach (string datei in Directory.EnumerateFiles(tempOrdner, "*", suchOptionen))
            {
                try
                {
                    var dateiInfo = new FileInfo(datei);

                    if (!dateiInfo.Exists ||
                        dateiInfo.LastWriteTimeUtc >= grenzdatumUtc)
                    {
                        continue;
                    }

                    long dateigroesse = dateiInfo.Length;

                    // Schreibgeschuetzte Reste von Installationen liegen oft im
                    // Temp. Delete() wuerde daran mit UnauthorizedAccessException
                    // scheitern, also Attribut vorher wegnehmen.
                    if ((dateiInfo.Attributes & FileAttributes.ReadOnly) != 0)
                    {
                        dateiInfo.Attributes &= ~FileAttributes.ReadOnly;
                    }

                    dateiInfo.Delete();

                    geloeschteDateien++;
                    freigegebeneBytes += dateigroesse;

                    Console.WriteLine($"Gelöscht: {datei}");
                }
                catch (Exception fehler) when (fehler is FileNotFoundException
                    or DirectoryNotFoundException)
                {
                    // Ein anderer Prozess war schneller. Im Temp-Ordner der
                    // Normalfall, keine Meldung wert.
                }
                catch (UnauthorizedAccessException fehler)
                {
                    fehlerhafteDateien++;
                    Console.WriteLine($"Kein Zugriff: {datei} ({fehler.Message})");
                }
                catch (IOException fehler)
                {
                    // NICHT pauschal "Datei wird verwendet" melden - eine
                    // IOException kann auch ein Datentraegerfehler oder ein zu
                    // langer Pfad sein.
                    fehlerhafteDateien++;
                    Console.WriteLine($"E/A-Fehler bei {datei}: {fehler.Message}");
                }
                catch (Exception fehler) when (fehler is ArgumentException
                    or NotSupportedException
                    or SecurityException)
                {
                    fehlerhafteDateien++;
                    Console.WriteLine($"Übersprungen: {datei} ({fehler.Message})");
                }
            }
        }
        catch (Exception fehler) when (fehler is IOException
            or UnauthorizedAccessException
            or SecurityException)
        {
            // Der Enumerator selbst kann werfen, z.B. wenn der Temp-Ordner
            // waehrend des Laufs verschwindet.
            sucheVollstaendig = false;

            Console.WriteLine(
                $"[WARNUNG] Die Temp-Suche wurde vorzeitig beendet: {fehler.Message}");
        }

        double freigegebeneMegabytes = freigegebeneBytes / 1024.0 / 1024.0;

        Console.WriteLine();

        Console.WriteLine(sucheVollstaendig && fehlerhafteDateien == 0
            ? "Bereinigung abgeschlossen."
            : "Bereinigung mit Warnungen abgeschlossen.");

        Console.WriteLine($"Gelöschte Dateien: {geloeschteDateien}");

        // FileInfo.Length ist die logische Groesse. Bei komprimierten oder
        // spaerlich belegten Dateien weicht der real freigegebene Platz ab.
        Console.WriteLine(
            $"Freigegebener Speicher (geschätzt): {freigegebeneMegabytes:F2} MB");

        if (fehlerhafteDateien > 0)
        {
            Console.WriteLine($"Nicht gelöschte Dateien: {fehlerhafteDateien}");
        }

        if (!sucheVollstaendig)
        {
            Console.WriteLine("Hinweis: Die Verzeichnissuche wurde vorzeitig beendet.");
        }
    }

    /// <summary>
    /// Liefert den Temp-Ordner oder null, wenn er nicht sicher bereinigt werden
    /// kann. Path.GetTempPath() folgt TMP/TEMP aus der Umgebung - zeigt das auf
    /// eine Laufwerkswurzel oder eine Junction, wuerde ein als Administrator
    /// laufendes Loeschen weit ueber den Temp-Ordner hinausgreifen.
    /// </summary>
    private static string? ErmittleTempOrdner()
    {
        string tempOrdner;

        try
        {
            tempOrdner = Path.GetFullPath(Path.GetTempPath());
        }
        catch (Exception fehler) when (fehler is IOException
            or ArgumentException
            or NotSupportedException
            or SecurityException)
        {
            Console.WriteLine(
                $"[FEHLER] Der Temp-Ordner konnte nicht ermittelt werden: {fehler.Message}");
            return null;
        }

        if (!Directory.Exists(tempOrdner))
        {
            Console.WriteLine($"[FEHLER] Der Temp-Ordner existiert nicht: {tempOrdner}");
            return null;
        }

        string? wurzel = Path.GetPathRoot(tempOrdner);

        bool istWurzel = string.IsNullOrEmpty(wurzel) || string.Equals(
            Path.TrimEndingDirectorySeparator(tempOrdner),
            Path.TrimEndingDirectorySeparator(wurzel),
            StringComparison.OrdinalIgnoreCase);

        if (istWurzel)
        {
            Console.WriteLine(
                $"[FEHLER] Der Temp-Pfad ist eine Laufwerkswurzel: {tempOrdner}");
            Console.WriteLine("Bereinigung aus Sicherheitsgründen abgebrochen.");
            return null;
        }

        try
        {
            if ((File.GetAttributes(tempOrdner) & FileAttributes.ReparsePoint) != 0)
            {
                Console.WriteLine(
                    $"[FEHLER] Der Temp-Ordner ist eine Junction/ein Symlink: {tempOrdner}");
                Console.WriteLine("Bereinigung aus Sicherheitsgründen abgebrochen.");
                return null;
            }
        }
        catch (Exception fehler) when (fehler is IOException
            or UnauthorizedAccessException
            or SecurityException)
        {
            Console.WriteLine(
                $"[FEHLER] Der Temp-Ordner konnte nicht geprüft werden: {fehler.Message}");
            return null;
        }

        return tempOrdner;
    }
}
