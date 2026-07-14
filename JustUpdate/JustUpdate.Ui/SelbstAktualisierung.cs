using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Reflection;
using System.Text.Json;
using System.Windows;

namespace JustUpdate.Ui;

/// <summary>
/// Holt neue Versionen aus dem GitHub-Release und ersetzt die laufende EXE.
///
/// Das ist der Kanal, ueber den die Bestandskunden erreichbar bleiben. Ohne ihn
/// waere die Migration von der PowerShell-Version auf diese EXE eine
/// Einbahnstrasse: einmal migriert, nie wieder erreichbar.
///
/// Abschaltbar wie in v1 ueber JUSTUPDATE_NO_SELFUPDATE=1.
/// </summary>
internal static class SelbstAktualisierung
{
    private const string ReleaseApi =
        "https://api.github.com/repos/Just1n12354/JustUpdate/releases/latest";

    /// <summary>Der Name, unter dem die EXE im Release haengen muss.</summary>
    private const string AssetName = "JustUpdate.exe";

    /// <summary>Eine self-contained WPF-EXE ist zweistellig MB gross. Alles darunter ist kaputt.</summary>
    private const long MindestGroesseBytes = 20L * 1024 * 1024;

    private static readonly TimeSpan Zeitlimit = TimeSpan.FromSeconds(20);

    public static Version EigeneVersion =>
        Assembly.GetExecutingAssembly().GetName().Version ?? new Version(0, 0, 0);

    /// <summary>
    /// Versionstext fuer die Anzeige. NICHT einfach ToString(3): eine
    /// Testversion 2.7.8.1 wuerde damit als "2.7.8" erscheinen - der Kunde
    /// haette keine Chance zu sehen, welcher Stand wirklich laeuft.
    /// </summary>
    public static string VersionText =>
        EigeneVersion.Revision > 0
            ? EigeneVersion.ToString(4)
            : EigeneVersion.ToString(3);

    /// <summary>
    /// Prueft auf ein Update und installiert es nach Rueckfrage. Liefert true,
    /// wenn die App sich gerade beendet, weil der Nachfolger startet.
    ///
    /// leise=true beim automatischen Start (kein Kunde will beim Oeffnen
    /// weggeklickt werden, wenn ohnehin alles aktuell ist).
    /// leise=false, wenn der Kunde selbst auf "nach Updates suchen" geklickt
    /// hat - dann MUSS eine Antwort kommen, sonst wirkt der Knopf kaputt.
    /// </summary>
    public static async Task<bool> PruefenUndAnbieten(
        Window besitzer,
        Einzelinstanz sperre,
        bool leise = true)
    {
        if (leise && Environment.GetEnvironmentVariable("JUSTUPDATE_NO_SELFUPDATE") == "1")
        {
            return false;
        }

        try
        {
            (Version version, string url)? neu = await NeuesteVersionErmitteln();

            if (neu is null || neu.Value.version <= EigeneVersion)
            {
                if (!leise)
                {
                    MessageBox.Show(
                        besitzer,
                        $"JustUpdate ist aktuell (v{EigeneVersion.ToString(3)}).",
                        "JustUpdate",
                        MessageBoxButton.OK,
                        MessageBoxImage.Information);
                }

                return false;
            }

            var antwort = MessageBox.Show(
                besitzer,
                $"Eine neue Version von JustUpdate ist verfügbar:\n\n" +
                $"    Installiert:  v{EigeneVersion.ToString(3)}\n" +
                $"    Verfügbar:    v{neu.Value.version.ToString(3)}\n\n" +
                "Jetzt herunterladen und installieren?",
                "JustUpdate - Update verfügbar",
                MessageBoxButton.YesNo,
                MessageBoxImage.Question);

            if (antwort != MessageBoxResult.Yes)
            {
                return false;
            }

            string temporaer = Path.Combine(
                Path.GetTempPath(),
                $"JustUpdate_neu_{Guid.NewGuid():N}.exe");

            await Herunterladen(neu.Value.url, temporaer);

            if (!IstPlausibleExe(temporaer))
            {
                Loeschen(temporaer);

                MessageBox.Show(
                    besitzer,
                    "Das heruntergeladene Update ist beschädigt und wurde NICHT " +
                    "installiert. Die vorhandene Version bleibt unverändert.",
                    "JustUpdate - Update abgebrochen",
                    MessageBoxButton.OK,
                    MessageBoxImage.Warning);

                return false;
            }

            Austauschen(temporaer, sperre);
            return true;
        }
        catch (Exception fehler)
        {
            // Offline, GitHub nicht erreichbar, keine Schreibrechte: die
            // vorhandene Version laeuft normal weiter. Ein fehlgeschlagener
            // Update-Versuch darf die Wartung nie blockieren - beim
            // automatischen Start also stillschweigend.
            if (!leise)
            {
                MessageBox.Show(
                    besitzer,
                    "Es konnte nicht nach Updates gesucht werden.\n\n" +
                    $"Grund: {fehler.Message}\n\n" +
                    $"Die installierte Version v{EigeneVersion.ToString(3)} läuft normal weiter.",
                    "JustUpdate",
                    MessageBoxButton.OK,
                    MessageBoxImage.Warning);
            }

            return false;
        }
    }

    /// <summary>
    /// Raeumt die beim letzten Update beiseitegelegte alte EXE weg. Die kann
    /// erst geloescht werden, wenn sie nicht mehr laeuft - also beim naechsten
    /// Start, nicht beim Austausch selbst.
    /// </summary>
    public static void AltlastenEntfernen()
    {
        try
        {
            string? eigenerPfad = Environment.ProcessPath;

            if (eigenerPfad is null)
            {
                return;
            }

            string alt = eigenerPfad + ".alt";

            if (File.Exists(alt))
            {
                File.Delete(alt);
            }
        }
        catch (Exception)
        {
            // Bleibt die alte Datei liegen, stoert sie niemanden.
        }
    }

    private static async Task<(Version version, string url)?> NeuesteVersionErmitteln()
    {
        using var klient = new HttpClient { Timeout = Zeitlimit };

        // Ohne User-Agent antwortet die GitHub-API mit 403.
        klient.DefaultRequestHeaders.UserAgent.Add(
            new ProductInfoHeaderValue("JustUpdate", EigeneVersion.ToString(3)));

        klient.DefaultRequestHeaders.Accept.Add(
            new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));

        string antwort = await klient.GetStringAsync(ReleaseApi);

        using JsonDocument dokument = JsonDocument.Parse(antwort);
        JsonElement wurzel = dokument.RootElement;

        if (!wurzel.TryGetProperty("tag_name", out JsonElement marke))
        {
            return null;
        }

        string markenText = (marke.GetString() ?? string.Empty).TrimStart('v', 'V');

        if (!Version.TryParse(markenText, out Version? version))
        {
            return null;
        }

        if (!wurzel.TryGetProperty("assets", out JsonElement anhaenge))
        {
            return null;
        }

        foreach (JsonElement anhang in anhaenge.EnumerateArray())
        {
            string? name = anhang.TryGetProperty("name", out JsonElement n)
                ? n.GetString()
                : null;

            if (!string.Equals(name, AssetName, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            string? url = anhang.TryGetProperty("browser_download_url", out JsonElement u)
                ? u.GetString()
                : null;

            if (!string.IsNullOrWhiteSpace(url))
            {
                return (version, url);
            }
        }

        return null;
    }

    private static async Task Herunterladen(string url, string ziel)
    {
        using var klient = new HttpClient { Timeout = TimeSpan.FromMinutes(10) };

        klient.DefaultRequestHeaders.UserAgent.Add(
            new ProductInfoHeaderValue("JustUpdate", EigeneVersion.ToString(3)));

        await using Stream quelle = await klient.GetStreamAsync(url);
        await using var datei = new FileStream(ziel, FileMode.Create, FileAccess.Write);

        await quelle.CopyToAsync(datei);
    }

    /// <summary>
    /// Gleiche Pruefung wie die EXE-Migration in v1: echte PE-Datei (MZ-Header)
    /// und plausible Groesse. Faengt abgebrochene Downloads und Proxy-HTML ab,
    /// die sonst als unstartbare "EXE" installiert wuerden.
    /// </summary>
    private static bool IstPlausibleExe(string pfad)
    {
        try
        {
            var info = new FileInfo(pfad);

            if (!info.Exists || info.Length < MindestGroesseBytes)
            {
                return false;
            }

            using FileStream strom = File.OpenRead(pfad);

            return strom.ReadByte() == 0x4D && strom.ReadByte() == 0x5A;   // 'MZ'
        }
        catch (Exception)
        {
            return false;
        }
    }

    /// <summary>
    /// Windows laesst eine laufende EXE nicht ueberschreiben - aber umbenennen.
    /// Also: alte EXE beiseite, neue an ihren Platz, neue starten, selbst enden.
    /// Die beiseitegelegte Datei raeumt der naechste Start weg.
    /// </summary>
    private static void Austauschen(string neueExe, Einzelinstanz sperre)
    {
        string? eigenerPfad = Environment.ProcessPath
            ?? throw new InvalidOperationException("Der eigene Pfad ist nicht ermittelbar.");

        string alt = eigenerPfad + ".alt";

        Loeschen(alt);
        File.Move(eigenerPfad, alt);

        try
        {
            File.Copy(neueExe, eigenerPfad, overwrite: true);
        }
        catch (Exception)
        {
            // Der Austausch ist gescheitert - die alte EXE zurueckholen, sonst
            // bleibt der Kunde ohne Programm zurueck.
            File.Move(alt, eigenerPfad, overwrite: true);
            throw;
        }

        Loeschen(neueExe);

        // Sonst weist die noch laufende Instanz die frisch gestartete ab.
        sperre.Freigeben();

        Process.Start(new ProcessStartInfo(eigenerPfad) { UseShellExecute = true });

        Application.Current.Shutdown();
    }

    private static void Loeschen(string pfad)
    {
        try
        {
            if (File.Exists(pfad))
            {
                File.Delete(pfad);
            }
        }
        catch (Exception)
        {
            // Nicht kritisch.
        }
    }
}
