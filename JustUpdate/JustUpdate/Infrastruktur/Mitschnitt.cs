using System;
using System.IO;
using System.Text;

namespace JustUpdate.Infrastruktur;

/// <summary>
/// Schreibt jede Ausgabezeile gleichzeitig auf die Konsole und (mit Zeitstempel)
/// in die Logdatei, und merkt sich die Zeilen des laufenden Moduls.
///
/// Der Modul-Status wird aus genau den Markern abgeleitet, die die Module
/// ohnehin schon ausgeben ([OK] / [WARNUNG] / [FEHLER]). So bleibt der
/// bestehende Modul-Code unangetastet und liefert trotzdem einen Exit-Code.
/// </summary>
sealed class Mitschnitt : TextWriter
{
    // Die Module schreiben ihre Ausgabe aus den OutputDataReceived- und
    // ErrorDataReceived-Callbacks - das sind zwei Threadpool-Threads, nicht
    // der Hauptthread. Console.SetOut synchronisiert NICHT. Ohne dieses Lock
    // wuerden StringBuilder und StreamWriter nebenlaeufig beschrieben:
    // verstuemmelte Logzeilen bis hin zu Exceptions.
    private readonly object _schloss = new();

    private readonly TextWriter _konsole;
    private readonly TextWriter _log;
    private readonly StringBuilder _modulZeilen = new();

    public Mitschnitt(TextWriter konsole, TextWriter log)
    {
        _konsole = konsole;
        _log = log;
    }

    public override Encoding Encoding => Encoding.UTF8;

    private bool _neustartErforderlich;

    public bool NeustartErforderlich
    {
        get { lock (_schloss) { return _neustartErforderlich; } }
    }

    public override void Write(char zeichen)
    {
        lock (_schloss)
        {
            _konsole.Write(zeichen);
            _log.Write(zeichen);
            _modulZeilen.Append(zeichen);
        }
    }

    public override void WriteLine(string? zeile)
    {
        zeile ??= string.Empty;

        lock (_schloss)
        {
            _konsole.WriteLine(zeile);
            _log.WriteLine($"[{DateTime.Now:HH:mm:ss}] {zeile}");
            _modulZeilen.AppendLine(zeile);

            if (zeile.Contains("[NEUSTART", StringComparison.OrdinalIgnoreCase))
            {
                _neustartErforderlich = true;
            }
        }
    }

    public void ModulBeginnen()
    {
        lock (_schloss)
        {
            _modulZeilen.Clear();
        }
    }

    public string ModulStatus()
    {
        lock (_schloss)
        {
            string text = _modulZeilen.ToString();

            if (text.Contains("[FEHLER]", StringComparison.OrdinalIgnoreCase))
            {
                return "FEHLER";
            }

            if (text.Contains("[WARNUNG]", StringComparison.OrdinalIgnoreCase))
            {
                return "WARNUNG";
            }

            return "OK";
        }
    }
}
