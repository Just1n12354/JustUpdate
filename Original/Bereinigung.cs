using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;

namespace JustUpdate.Module;

/// <summary>
/// Temporaere Dateien loeschen
/// </summary>
internal static class Bereinigung
{
    public const string Name = "bereinigung";

    public static void Ausfuehren()
    {
        Console.WriteLine("[C] Bereinigung wird gestartet ...");

        string tempOrdner = Path.GetTempPath();
        DateTime grenzdatum = DateTime.Now.AddDays(-7);

        int geloeschteDateien = 0;
        long freigegebeneBytes = 0;

        Console.WriteLine($"Temp-Ordner: {tempOrdner}");
        Console.WriteLine("Dateien, die älter als sieben Tage sind, werden gelöscht.");

        // SearchOption.AllDirectories wirft, sobald der Enumerator auf einen
        // Ordner ohne Zugriff stoesst (z.B. Temp\nx) - und zwar AUSSERHALB des
        // try/catch in der Schleife, das Programm stirbt also komplett.
        // EnumerationOptions mit IgnoreInaccessible ueberspringt solche Ordner.
        // ReparsePoint uebersprungen: sonst folgt die Suche Junctions aus dem
        // Temp-Ordner heraus und loescht Dateien ausserhalb.
        var suchOptionen = new EnumerationOptions
        {
            RecurseSubdirectories = true,
            IgnoreInaccessible = true,
            AttributesToSkip = FileAttributes.ReparsePoint
        };

        try
        {
            foreach (string datei in Directory.EnumerateFiles(
                         tempOrdner,
                         "*",
                         suchOptionen))
            {
                try
                {
                    FileInfo dateiInfo = new FileInfo(datei);

                    if (dateiInfo.LastWriteTime < grenzdatum)
                    {
                        long dateigroesse = dateiInfo.Length;

                        dateiInfo.Delete();

                        geloeschteDateien++;
                        freigegebeneBytes += dateigroesse;

                        Console.WriteLine($"Gelöscht: {datei}");
                    }
                }
                catch (UnauthorizedAccessException)
                {
                    Console.WriteLine($"Kein Zugriff: {datei}");
                }
                catch (IOException)
                {
                    Console.WriteLine($"Datei wird verwendet: {datei}");
                }
                catch (Exception fehler)
                {
                    Console.WriteLine($"Fehler bei {datei}: {fehler.Message}");
                }
            }
        }
        catch (Exception fehler)
        {
            // Der Enumerator selbst kann werfen (gesperrter Ordner, verschwundenes
            // Verzeichnis). Das darf die Wartung nicht abbrechen.
            Console.WriteLine(
                "[WARNUNG] Die Temp-Suche wurde vorzeitig beendet: " +
                fehler.Message);
        }

        double freigegebeneMegabytes =
            freigegebeneBytes / 1024.0 / 1024.0;

        Console.WriteLine();
        Console.WriteLine("Bereinigung abgeschlossen.");
        Console.WriteLine($"Gelöschte Dateien: {geloeschteDateien}");
        Console.WriteLine(
            $"Freigegebener Speicher: {freigegebeneMegabytes:F2} MB");
    }
}
