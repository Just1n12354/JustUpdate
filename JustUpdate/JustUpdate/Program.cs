using System;
using System.Diagnostics;
using System.IO;
using System.Text;

using JustUpdate.Infrastruktur;
using JustUpdate.Module;

// Die Module geben Umlaute aus; ohne das rendert die Konsole sie als Muell.
Console.OutputEncoding = Encoding.UTF8;

// Jedes Modul liegt in Module\<Name>.cs. Neues Modul = neue Datei + eine Zeile
// hier. Der Compiler setzt das Projekt selbst zusammen - anders als bei der
// PowerShell-Version braucht es dafuer kein Build-Skript.
var module = new (string Name, Action Ausfuehren)[]
{
    (Wiederherstellungspunkt.Name, Wiederherstellungspunkt.Ausfuehren),
    (Defender.Name,                Defender.Ausfuehren),
    (WindowsUpdate.Name,           WindowsUpdate.Ausfuehren),
    (Treiber.Name,                 Treiber.Ausfuehren),
    (Apps.Name,                    Apps.Ausfuehren),
    (Store.Name,                   Store.Ausfuehren),
    (SystemReparatur.Name,         SystemReparatur.Ausfuehren),
    (Netzwerk.Name,                Netzwerk.Ausfuehren),
    (Bereinigung.Name,             Bereinigung.Ausfuehren),
};

var auswahl = module;

if (args.Any(a => a is "--help" or "-h" or "/?"))
{
    Console.WriteLine("JustUpdate - Windows-Wartung");
    Console.WriteLine();
    Console.WriteLine("  JustUpdate.exe                 volle Wartung (alle Module)");
    Console.WriteLine("  JustUpdate.exe <modul> [...]   nur die genannten Module");
    Console.WriteLine();
    Console.WriteLine("Module:");

    foreach (var m in module)
    {
        Console.WriteLine($"  {m.Name}");
    }

    Console.WriteLine();
    Console.WriteLine("Exit-Codes: 0 = OK, 1 = Warnungen, 2 = Fehler");
    return 0;
}

// Ohne Argumente laeuft die volle Wartung. Mit Argumenten nur die genannten
// Module - noetig, um einzelne Module zu testen, ohne eine Stunde lang
// Updates, Treiber und einen Netzwerk-Reset ueber den PC zu jagen.
//   JustUpdate.exe bereinigung
//   JustUpdate.exe defender windowsupdate
if (args.Length > 0)
{
    var unbekannt = args
        .Where(a => !module.Any(m => string.Equals(m.Name, a, StringComparison.OrdinalIgnoreCase)))
        .ToArray();

    if (unbekannt.Length > 0)
    {
        Console.WriteLine("[FEHLER] Unbekanntes Modul: " + string.Join(", ", unbekannt));
        Console.WriteLine("Verfuegbar: " + string.Join(", ", module.Select(m => m.Name)));
        return 1;
    }

    auswahl = module
        .Where(m => args.Any(a => string.Equals(m.Name, a, StringComparison.OrdinalIgnoreCase)))
        .ToArray();
}

// Jeder Lauf bekommt seine eigene Logdatei. Ohne Log ist jede Support-Frage
// ("was ist da passiert?") nach dem Schliessen der Konsole unbeantwortbar.
string logOrdner = Path.Combine(
    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
    "JustUpdate",
    "logs");

Directory.CreateDirectory(logOrdner);

string logDatei = Path.Combine(
    logOrdner,
    $"Maintenance_{DateTime.Now:yyyy-MM-dd_HH-mm-ss}.log");

TextWriter konsole = Console.Out;

using var logSchreiber =
    new StreamWriter(logDatei, append: false, new UTF8Encoding(true))
    {
        AutoFlush = true
    };

var mitschnitt = new Mitschnitt(konsole, logSchreiber);
Console.SetOut(mitschnitt);

bool istAdministrator;

using (var identitaet = System.Security.Principal.WindowsIdentity.GetCurrent())
{
    istAdministrator =
        new System.Security.Principal.WindowsPrincipal(identitaet)
            .IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
}

Console.WriteLine("============================================");
Console.WriteLine($"  JustUpdate - Start {DateTime.Now:dd.MM.yyyy HH:mm:ss}");
Console.WriteLine("============================================");
Console.WriteLine($"  Rechner:       {Environment.MachineName}");
Console.WriteLine($"  Administrator: {(istAdministrator ? "ja" : "NEIN")}");
Console.WriteLine($"  Module:        {string.Join(", ", auswahl.Select(m => m.Name))}");
Console.WriteLine($"  Log:           {logDatei}");
Console.WriteLine();

if (!istAdministrator)
{
    Console.WriteLine(
        "[WARNUNG] Ohne Administratorrechte werden mehrere Module uebersprungen.");
    Console.WriteLine();
}

var ergebnisse = new List<(string Name, string Status, TimeSpan Dauer)>();

foreach (var m in auswahl)
{
    var uhr = Stopwatch.StartNew();
    mitschnitt.ModulBeginnen();

    try
    {
        m.Ausfuehren();
    }
    catch (Exception fehler)
    {
        // Ein abstuerzendes Modul darf die restliche Wartung nicht mitreissen.
        // Vorher hat eine UnauthorizedAccessException aus der Bereinigung den
        // gesamten Prozess beendet.
        Console.WriteLine(
            $"[FEHLER] Modul '{m.Name}' ist abgestuerzt: {fehler.Message}");
    }

    uhr.Stop();
    ergebnisse.Add((m.Name, mitschnitt.ModulStatus(), uhr.Elapsed));
    Console.WriteLine();
}

Console.WriteLine("============================================");
Console.WriteLine("  ZUSAMMENFASSUNG");
Console.WriteLine("============================================");

foreach (var (name, status, dauer) in ergebnisse)
{
    string symbol = status switch
    {
        "FEHLER"  => "[X]",
        "WARNUNG" => "[!]",
        _         => "[OK]"
    };

    Console.WriteLine($"  {symbol,-4} {name,-24} {Dauer(dauer)}");
}

Console.WriteLine();

if (mitschnitt.NeustartErforderlich)
{
    Console.WriteLine(
        "[NEUSTART ERFORDERLICH] Mindestens ein Modul verlangt einen Neustart.");
    Console.WriteLine();
}

// Exit-Code wie in der PowerShell-Version: 0 = OK, 1 = Warnungen, 2 = Fehler.
// Ein geplanter Lauf ist sonst nicht auswertbar - vorher kam immer 0 zurueck,
// selbst wenn das Programm abgestuerzt ist.
int exitCode =
    ergebnisse.Any(e => e.Status == "FEHLER")  ? 2 :
    ergebnisse.Any(e => e.Status == "WARNUNG") ? 1 :
    0;

Console.WriteLine($"Ergebnis: Exit-Code {exitCode} " +
                  $"(0 = OK, 1 = Warnungen, 2 = Fehler)");
Console.WriteLine($"Log: {logDatei}");

Console.Out.Flush();
Console.SetOut(konsole);

// Nur warten, wenn wirklich jemand vor der Konsole sitzt - sonst haengt ein
// geplanter Lauf ewig an ReadKey().
if (!Console.IsInputRedirected)
{
    Console.WriteLine();
    Console.WriteLine("Zum Beenden eine Taste druecken ...");
    Console.ReadKey();
}

return exitCode;

static string Dauer(TimeSpan spanne) =>
    spanne.TotalMinutes >= 1
        ? $"{(int)spanne.TotalMinutes} min {spanne.Seconds} s"
        : $"{spanne.TotalSeconds:F1} s";
