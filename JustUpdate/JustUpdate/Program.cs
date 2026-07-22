using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;

using JustUpdate.Infrastruktur;
using JustUpdate.Module;

// Die Module geben Umlaute aus; ohne das rendert die Konsole sie als Muell.
Console.OutputEncoding = Encoding.UTF8;

// ──────────────────────────────────────────────────────────────────────────────
// Konfiguration laden
// ──────────────────────────────────────────────────────────────────────────────

var config = KonfigurationLaden();

// Module definieren — zentraler Ort, leicht erweiterbar
var moduleListe = new[]
{
    (Wiederherstellungspunkt.Name, Wiederherstellungspunkt.Ausfuehren, Wiederherstellungspunkt.Schnellbeschreibung),
    (Defender.Name,                Defender.Ausfuehren,                Defender.Schnellbeschreibung),
    (WindowsUpdate.Name,           WindowsUpdate.Ausfuehren,           WindowsUpdate.Schnellbeschreibung),
    (Treiber.Name,                 Treiber.Ausfuehren,                 Treiber.Schnellbeschreibung),
    (Apps.Name,                    Apps.Ausfuehren,                    Apps.Schnellbeschreibung),
    (Store.Name,                   Store.Ausfuehren,                   Store.Schnellbeschreibung),
    (SystemReparatur.Name,         SystemReparatur.Ausfuehren,         SystemReparatur.Schnellbeschreibung),
    (Netzwerk.Name,                Netzwerk.Ausfuehren,                Netzwerk.Schnellbeschreibung),
    (Bereinigung.Name,             Bereinigung.Ausfuehren,             Bereinigung.Schnellbeschreibung),
};

// Standard-Module: aus config oder alles
var standardModule = config.DefaultModule?.Length > 0
    ? config.DefaultModule
    : moduleListe.Select(m => m.Name).ToArray();

var auswahl = moduleListe;

// ──────────────────────────────────────────────────────────────────────────────
// CLI-Argumente auswerten
// ──────────────────────────────────────────────────────────────────────────────

var args = Environment.GetCommandLineArgs().Skip(1).ToArray();

var optionen = new Dictionary<string, string>();
var moduleArgumente = new List<string>();

foreach (var arg in args)
{
    if (arg.StartsWith("--"))
    {
        var teil = arg[2..];
        var equalIndex = teil.IndexOf('=');
        if (equalIndex >= 0)
        {
            optionen[teil[..equalIndex]] = teil[(equalIndex + 1)..];
        }
        else
        {
            optionen[teil] = ""; // Flag ohne Wert
        }
    }
    else
    {
        moduleArgumente.Add(arg);
    }
}

var istDryRun = optionen.ContainsKey("dry-run");

if (optionen.ContainsKey("help") || optionen.ContainsKey("h") || optionen.ContainsKey("?"))
{
    DruckenHilfe();
    return 0;
}

// Mit --modules kann die Modul-Auswahl überschrieben werden
if (optionen.TryGetValue("modules", out var moduleString))
{
    moduleArgumente.Clear();
    moduleArgumente.AddRange(moduleString.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries));
}

// Ohne Argumente: Standard-Module aus config oder alles
if (moduleArgumente.Count == 0)
{
    moduleArgumente.AddRange(standardModule);
}

if (moduleArgumente.Any(a => a is "alle" or "all"))
{
    moduleArgumente.Clear();
    moduleArgumente.AddRange(moduleListe.Select(m => m.Name));
}

// Unbekannte Module prüfen
if (moduleArgumente.Count > 0)
{
    var unbekannt = moduleArgumente
        .Where(a => !moduleListe.Any(m => string.Equals(m.Name, a, StringComparison.OrdinalIgnoreCase)))
        .ToArray();

    if (unbekannt.Length > 0)
    {
        Console.WriteLine("[FEHLER] Unbekanntes Modul: " + string.Join(", ", unbekannt));
        Console.WriteLine("Verfügbare Module: " + string.Join(", ", moduleListe.Select(m => m.Name)));
        return 1;
    }

    auswahl = moduleListe
        .Where(m => moduleArgumente.Any(a => string.Equals(m.Name, a, StringComparison.OrdinalIgnoreCase)))
        .ToArray();
}

// ──────────────────────────────────────────────────────────────────────────────
// Logging aufsetzen
// ──────────────────────────────────────────────────────────────────────────────

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

// ──────────────────────────────────────────────────────────────────────────────
// Header ausgeben
// ──────────────────────────────────────────────────────────────────────────────

var ergebnisse = new List<(string Name, string Status, TimeSpan Dauer, string Detail)>();

bool istAdministrator;

using (var identitaet = System.Security.Principal.WindowsIdentity.GetCurrent())
{
    istAdministrator =
        new System.Security.Principal.WindowsPrincipal(identitaet)
            .IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
}

Console.WriteLine("============================================");
Console.WriteLine($"  JustUpdate {config.Version ?? "unknown"} - Start {DateTime.Now:dd.MM.yyyy HH:mm:ss}");
Console.WriteLine("============================================");
Console.WriteLine($"  Rechner:       {Environment.MachineName}");
Console.WriteLine($"  Benutzer:      {Environment.UserName}");
Console.WriteLine($"  Administrator: {(istAdministrator ? "ja" : "NEIN")}");
Console.WriteLine($"  Dry-Run:       {(istDryRun ? "ja" : "nein")}");
Console.WriteLine($"  Module:        {string.Join(", ", auswahl.Select(m => m.Name))}");
Console.WriteLine($"  Log:           {logDatei}");
Console.WriteLine();

if (!istAdministrator)
{
    Console.WriteLine(
        "[WARNUNG] Ohne Administratorrechte werden mehrere Module übersprungen.");
    Console.WriteLine();
}

if (istDryRun)
{
    Console.WriteLine("[HINWEIS] Dry-Run-Modus — keine echten Änderungen.");
    Console.WriteLine();
}

// ──────────────────────────────────────────────────────────────────────────────
// Module ausführen
// ──────────────────────────────────────────────────────────────────────────────

foreach (var (name, ausfuehren, beschreibung) in auswahl)
{
    var uhr = Stopwatch.StartNew();
    mitschnitt.ModulBeginnen();

    string status = "OK";
    string detail = "";

    try
    {
        if (istDryRun)
        {
            Console.WriteLine($"[DRY-RUN] Modul '{name}' würde ausgeführt werden.");
            if (!string.IsNullOrWhiteSpace(beschreibung))
            {
                Console.WriteLine($"  {beschreibung}");
            }
        }
        else
        {
            ausfuehren();
        }

        status = mitschnitt.ModulStatus();
        detail = "";
    }
    catch (Exception fehler)
    {
        status = "FEHLER";
        detail = fehler.Message;
        Console.WriteLine(
            $"[FEHLER] Modul '{name}' ist abgestürzt: {fehler.Message}");
    }

    uhr.Stop();
    ergebnisse.Add((name, status, uhr.Elapsed, detail));
    Console.WriteLine();
}

// ──────────────────────────────────────────────────────────────────────────────
// Zusammenfassung
// ──────────────────────────────────────────────────────────────────────────────

Console.WriteLine("============================================");
Console.WriteLine("  ZUSAMMENFASSUNG");
Console.WriteLine("============================================");

int fehlerAnzahl = 0;
int warnungAnzahl = 0;

foreach (var (name, status, dauer, detail) in ergebnisse)
{
    string symbol = status switch
    {
        "FEHLER"  => "✗",
        "WARNUNG" => "!",
        _         => "✓"
    };

    if (status == "FEHLER") fehlerAnzahl++;
    if (status == "WARNUNG") warnungAnzahl++;

    Console.WriteLine($"  {symbol,-2} {name,-24} {Dauer(dauer)}");

    if (!string.IsNullOrWhiteSpace(detail))
    {
        Console.WriteLine($"       Detail: {detail}");
    }
}

Console.WriteLine();
Console.WriteLine($"  Ergebnis: {ergebnisse.Count - fehlerAnzahl - warnungAnzahl}/{ergebnisse.Count} OK, " +
                   $"{warnungAnzahl} Warnung, {fehlerAnzahl} Fehler");

if (mitschnitt.NeustartErforderlich)
{
    Console.WriteLine();
    Console.WriteLine("[NEUSTART ERFORDERLICH] Mindestens ein Modul verlangt einen Neustart.");
}

// ──────────────────────────────────────────────────────────────────────────────
// JSON-Metadaten für automatische Auswertung schreiben
// ──────────────────────────────────────────────────────────────────────────────

string jsonPfad = Path.ChangeExtension(logDatei, ".json");

try
{
    var jsonOptionen = new JsonSerializerOptions
    {
        WriteIndented = false,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping
    };

    var lauf = new Dictionary<string, object>
    {
        ["version"] = config.Version ?? "unknown",
        ["datum"] = DateTime.Now.ToString("o"),
        ["rechner"] = Environment.MachineName,
        ["benutzer"] = Environment.UserName,
        ["administrator"] = istAdministrator,
        ["dryrun"] = istDryRun,
        ["module"] = auswahl.Select(m => m.Name).ToArray(),
        ["ergebnisse"] = ergebnisse.Select(e => new Dictionary<string, object>
        {
            ["name"] = e.Name,
            ["status"] = e.Status,
            ["dauer"] = e.Dauer.TotalSeconds,
            ["detail"] = e.Detail
        }).ToArray(),
        ["neustart_erforderlich"] = mitschnitt.NeustartErforderlich,
        ["fehler"] = fehlerAnzahl,
        ["warnungen"] = warnungAnzahl
    };

    var eintraege = new List<Dictionary<string, object>> { lauf };

    // Anhängen an bestehende JSON-Datei (mehrere Läufe)
    if (File.Exists(jsonPfad))
    {
        try
        {
            var bestandeneEintraege = JsonSerializer.Deserialize<List<Dictionary<string, object>>>(
                File.ReadAllText(jsonPfad)) ?? new List<Dictionary<string, object>>();

            bestandeneEintraege.Add(lauf);
            eintraege = bestandeneEintraege;

            // Nur letzte 50 Einträge behalten (Platz nicht sprengen)
            if (eintraege.Count > 50)
            {
                eintraege = eintraege.Skip(eintraege.Count - 50).ToList();
            }
        }
        catch
        {
            // Alte Datei war beschädigt — neu erstellen
        }
    }

    // Temporär schreiben + umbenennen = atomar
    string tempPfad = jsonPfad + ".tmp";
    try
    {
        File.WriteAllText(tempPfad, JsonSerializer.Serialize(eintraege, jsonOptionen));
        File.Delete(jsonPfad);
        File.Move(tempPfad, jsonPfad);
    }
    catch
    {
        // Wenn umbenennen fehlschlägt, temporäre Datei löschen
        try { File.Delete(tempPfad); } catch { }
    }
}
catch (Exception ex)
{
    // JSON-Fehler sind nicht kritisch — nicht stören
    mitschnitt.WriteLine($"[HINWEIS] Metadaten konnten nicht gespeichert werden: {ex.Message}");
}

// ──────────────────────────────────────────────────────────────────────────────
// Exit-Code setzen
// ──────────────────────────────────────────────────────────────────────────────

int exitCode =
    fehlerAnzahl > 0  ? 2 :
    warnungAnzahl > 0 ? 1 :
    0;

Console.WriteLine($"Ergebnis: Exit-Code {exitCode} " +
                  "(0 = OK, 1 = Warnungen, 2 = Fehler)");
Console.WriteLine($"Log: {logDatei}");
Console.WriteLine($"Metadaten: {jsonPfad}");

Console.Out.Flush();
Console.SetOut(konsole);

// ──────────────────────────────────────────────────────────────────────────────
// Warten wenn interaktiv
// ──────────────────────────────────────────────────────────────────────────────

if (!Console.IsInputRedirected && !istDryRun)
{
    Console.WriteLine();
    Console.WriteLine("Zum Beenden eine Taste drücken ...");
    Console.ReadKey();
}

return exitCode;

static string Dauer(TimeSpan spanne) =>
    spanne.TotalMinutes >= 1
        ? $"{(int)spanne.TotalMinutes:D2}:{spanne.Seconds:D2}"
        : $"{spanne.TotalSeconds:F1}s";

static void DruckenHilfe()
{
    Console.WriteLine("JustUpdate - Windows-Wartung");
    Console.WriteLine();
    Console.WriteLine("  JustUpdate.exe                 volle Wartung (alle Module)");
    Console.WriteLine("  JustUpdate.exe <modul> [...]   nur die genannten Module");
    Console.WriteLine();
    Console.WriteLine("Optionen:");
    Console.WriteLine("  --help                         diese Hilfe anzeigen");
    Console.WriteLine("  --dry-run                      nur zeigen, ohne auszuführen");
    Console.WriteLine("  --modules mod1,mod2,...        eigene Modulauswahl");
    Console.WriteLine();
    Console.WriteLine("Module:");

    var module = new[]
    {
        (Wiederherstellungspunkt.Name, Wiederherstellungspunkt.Schnellbeschreibung),
        (Defender.Name,                Defender.Schnellbeschreibung),
        (WindowsUpdate.Name,           WindowsUpdate.Schnellbeschreibung),
        (Treiber.Name,                 Treiber.Schnellbeschreibung),
        (Apps.Name,                    Apps.Schnellbeschreibung),
        (Store.Name,                   Store.Schnellbeschreibung),
        (SystemReparatur.Name,         SystemReparatur.Schnellbeschreibung),
        (Netzwerk.Name,                Netzwerk.Schnellbeschreibung),
        (Bereinigung.Name,             Bereinigung.Schnellbeschreibung),
    };

    foreach (var (name, beschreibung) in module)
    {
        Console.WriteLine($"  {name,-24} {beschreibung}");
    }

    Console.WriteLine();
    Console.WriteLine("Exit-Codes: 0 = OK, 1 = Warnungen, 2 = Fehler");
}

static Konfiguration KonfigurationLaden()
{
    // Konfigurationspfad: .justupdate.json im aktuellen Verzeichnis oder Home
    string[] pfade =
    {
        Path.Combine(AppContext.BaseDirectory, ".justupdate.json"),
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".justupdate.json"),
    };

    foreach (string pfad in pfade)
    {
        if (File.Exists(pfad))
        {
            try
            {
                var json = File.ReadAllText(pfad);
                var doc = JsonSerializer.Deserialize<Dictionary<string, object>>(json);

                if (doc is null) continue;

                return new Konfiguration
                {
                    Version = doc.TryGetValue("version", out var v) ? v?.ToString() : "unknown",
                    DefaultModule = doc.TryGetValue("defaultModules", out var d) && d is System.Collections.IEnumerable arr
                        ? arr.Cast<object?>().Select(x => x?.ToString()).Where(s => !string.IsNullOrWhiteSpace(s)).ToArray()
                        : null
                };
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[HINWEIS] Konfiguration {pfad} konnte nicht geladen werden: {ex.Message}");
            }
        }
    }

    return new Konfiguration { Version = "unknown", DefaultModule = null };
}

record Konfiguration(string? Version, string[]? DefaultModule);
