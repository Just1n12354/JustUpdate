using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.CompilerServices;
using System.Security.Principal;
using System.Text;
using System.Windows;
using System.Windows.Input;
using System.Windows.Threading;

using JustUpdate.Infrastruktur;
using JustUpdate.Module;

namespace JustUpdate.Ui;

public partial class MainWindow : Window, INotifyPropertyChanged
{
    private readonly ObservableCollection<ModulEintrag> _module;
    private readonly DispatcherTimer _uhrAnzeige = new() { Interval = TimeSpan.FromSeconds(1) };
    private readonly Stopwatch _uhr = new();

    private volatile bool _abbruchGewuenscht;
    private bool _kannStarten = true;
    private bool _automatik;
    private string? _logDatei;

    public MainWindow()
    {
        InitializeComponent();

        // Reihenfolge wie in Program.cs: Wiederherstellungspunkt zuerst (damit
        // es einen Rueckweg gibt), Bereinigung zuletzt. Farben wie in v1.
        _module =
        [
            new(Wiederherstellungspunkt.Name, "R", "Wiederherstellungspunkt",
                "Rückweg anlegen, bevor etwas verändert wird", "#A3243B",
                "Legt einen Windows-Systemwiederherstellungspunkt an, damit du den " +
                "gesamten Wartungslauf zurückdrehen kannst.",
                "Sichert KEINE persönlichen Dateien. Ein Wiederherstellungspunkt " +
                "ist kein Backup.",
                Wiederherstellungspunkt.Ausfuehren),

            new(Defender.Name, "D", "Microsoft Defender",
                "Signaturen aktualisieren und prüfen", "#A3243B",
                "Aktualisiert die Virensignaturen des in Windows eingebauten Defenders " +
                "und startet eine Prüfung.",
                "Installiert kein zusätzliches Virenprogramm und schaltet ein " +
                "vorhandenes Fremdprodukt nicht ab.",
                Defender.Ausfuehren),

            new(WindowsUpdate.Name, "W", "Windows Update",
                "Updates suchen und installieren", "#22C55E",
                "Sucht über Windows Update nach Sicherheits- und Systemupdates und " +
                "installiert sie.",
                "Startet den Rechner NICHT von selbst neu. Ein nötiger Neustart wird " +
                "am Ende nur gemeldet.",
                WindowsUpdate.Ausfuehren),

            new(Treiber.Name, "T", "Treiber",
                "Treiber-Updates prüfen", "#e8a020",
                "Prüft die von Windows Update angebotenen Treiber und installiert sie.",
                "Lädt keine Treiber von Herstellerseiten. Grafiktreiber holst du " +
                "weiterhin besser direkt bei NVIDIA oder AMD.",
                Treiber.Ausfuehren),

            new(Apps.Name, "A", "Apps (winget)",
                "Installierte Programme aktualisieren", "#A3243B",
                "Aktualisiert alle installierten Programme, die winget kennt " +
                "(Browser, Tools, Treiberprogramme ...).",
                "Installiert nichts Neues und deinstalliert nichts. Es werden nur " +
                "vorhandene Programme aktualisiert.",
                Apps.Ausfuehren),

            new(Store.Name, "S", "Microsoft Store",
                "Store-Apps aktualisieren", "#A855F7",
                "Stösst die Aktualisierung der über den Microsoft Store installierten " +
                "Apps an.",
                "Öffnet den Store nicht und kauft nichts.",
                Store.Ausfuehren),

            new(SystemReparatur.Name, "F", "Systemreparatur",
                "SFC und DISM — dauert lange", "#EF4444",
                "Prüft die Windows-Systemdateien (SFC) und repariert das " +
                "Systemabbild (DISM). Kann 20 bis 40 Minuten dauern.",
                "Fasst deine eigenen Dateien und Programme nicht an.",
                SystemReparatur.Ausfuehren),

            new(Netzwerk.Name, "N", "Netzwerk",
                "DNS-Flush, Winsock- und TCP/IP-Reset", "#06B6D4",
                "Leert den DNS-Zwischenspeicher und setzt Winsock und TCP/IP zurück — " +
                "hilft bei hartnäckigen Verbindungsproblemen.",
                "ACHTUNG: Die Netzwerkverbindung bricht dabei kurz ab und der Reset " +
                "wirkt erst nach einem Neustart. Deshalb standardmässig AUS.",
                Netzwerk.Ausfuehren),

            new(Bereinigung.Name, "C", "Bereinigung",
                "Temp-Dateien älter als sieben Tage", "#22C55E",
                "Löscht temporäre Dateien, die älter als sieben Tage sind.",
                "Räumt keine Registry auf, löscht keine Downloads, keinen Papierkorb " +
                "und keine Browserdaten.",
                Bereinigung.Ausfuehren),
        ];

        // Netzwerk-Reset reisst die Verbindung ab und verlangt einen Neustart -
        // das gehoert nicht in einen Standardlauf. War in v1 genauso.
        _module.First(m => m.Schluessel == Netzwerk.Name).Ausgewaehlt = false;

        DataContext = this;
        xModule.ItemsSource = _module;

        xVersion.Text = $"v{SelbstAktualisierung.VersionText}";
        xRechner.Text = Environment.MachineName;

        bool istAdministrator = IstAdministrator();

        xAdmin.Text = istAdministrator
            ? "Administrator: ja"
            : "Administrator: NEIN — mehrere Module brechen ab";

        xAdmin.Foreground = istAdministrator
            ? (System.Windows.Media.Brush)FindResource("Grn")
            : (System.Windows.Media.Brush)FindResource("Rd");

        _uhrAnzeige.Tick += (_, _) => xZeit.Text = Dauer(_uhr.Elapsed);

        Loaded += BeimOeffnen;
    }

    /// <summary>
    /// Steuert, ob die Modulauswahl bedienbar ist. Waehrend eines Laufs nicht -
    /// sonst schaltet jemand mitten im Durchlauf ein Modul an, das gar nicht
    /// mehr drankommt.
    /// </summary>
    public bool KannStarten
    {
        get => _kannStarten;
        private set
        {
            if (_kannStarten == value)
            {
                return;
            }

            _kannStarten = value;
            Melde();
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private async void BeimOeffnen(object sender, RoutedEventArgs e)
    {
        // Die beim letzten Update beiseitegelegte EXE laeuft jetzt nicht mehr
        // und kann weg.
        SelbstAktualisierung.AltlastenEntfernen();

        var app = (App)Application.Current;

        if (app.Automatik)
        {
            // Geplanter Lauf: KEIN Self-Update (das braucht eine Rueckfrage und
            // wuerde den unbeaufsichtigten Lauf blockieren) - genau wie in v1.
            // Der naechste manuelle Start holt das Update nach.
            StarteAutomatik(app.AutomatikModule);
            return;
        }

        // Vor dem Lauf pruefen, nicht danach: sonst faehrt der Kunde eine Stunde
        // Wartung mit der alten Version und darf danach nochmal.
        await SelbstAktualisierung.PruefenUndAnbieten(this, app.Sperre);
    }

    /// <summary>
    /// Startet die Wartung ohne Klick und schliesst das Fenster danach. Der
    /// Exit-Code macht den geplanten Lauf auswertbar: 0 = OK, 1 = Warnungen,
    /// 2 = Fehler.
    /// </summary>
    private void StarteAutomatik(string[] module)
    {
        if (module.Length > 0)
        {
            foreach (ModulEintrag eintrag in _module)
            {
                eintrag.Ausgewaehlt = module.Contains(
                    eintrag.Schluessel,
                    StringComparer.OrdinalIgnoreCase);
            }
        }

        _automatik = true;
        Starten(this, new RoutedEventArgs());
    }

    // ---- Fensterrahmen (WindowStyle=None, also selbst gebaut) --------------

    private void TitelleisteGezogen(object sender, MouseButtonEventArgs e)
    {
        if (e.ClickCount == 2)
        {
            FensterMaximieren(sender, e);
            return;
        }

        DragMove();
    }

    private void FensterMinimieren(object sender, RoutedEventArgs e) =>
        WindowState = WindowState.Minimized;

    private void FensterMaximieren(object sender, RoutedEventArgs e) =>
        WindowState = WindowState == WindowState.Maximized
            ? WindowState.Normal
            : WindowState.Maximized;

    private void FensterSchliessen(object sender, RoutedEventArgs e)
    {
        if (!KannStarten)
        {
            var antwort = MessageBox.Show(
                this,
                "Es läuft gerade eine Wartung.\n\n" +
                "Wird das Fenster jetzt geschlossen, bricht ein laufendes Update " +
                "oder eine laufende Reparatur mittendrin ab. Trotzdem schliessen?",
                "JustUpdate",
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning);

            if (antwort != MessageBoxResult.Yes)
            {
                return;
            }
        }

        Close();
    }

    // ---- Modulauswahl -----------------------------------------------------

    private static bool IstAdministrator()
    {
        using var identitaet = WindowsIdentity.GetCurrent();

        return new WindowsPrincipal(identitaet)
            .IsInRole(WindowsBuiltInRole.Administrator);
    }

    private void AlleWaehlen(object sender, RoutedEventArgs e) => SetzeAuswahl(true);

    private void KeineWaehlen(object sender, RoutedEventArgs e) => SetzeAuswahl(false);

    private void SetzeAuswahl(bool wert)
    {
        if (!KannStarten)
        {
            return;
        }

        foreach (ModulEintrag eintrag in _module)
        {
            eintrag.Ausgewaehlt = wert;
        }
    }

    private void Abbrechen(object sender, RoutedEventArgs e)
    {
        // Die Module sind synchrone void-Methoden ohne CancellationToken. Ein
        // laufendes Modul laesst sich also NICHT sauber stoppen - ein halb
        // abgebrochenes DISM oder ein gekillter Installer waere schlimmer als
        // zu Ende zu warten. Deshalb: nach dem aktuellen Modul ist Schluss.
        _abbruchGewuenscht = true;
        xAbbrechen.IsEnabled = false;
        xStatus.Text = "Abbruch angefordert — das laufende Modul wird noch zu Ende geführt ...";
    }

    private void LogOeffnen(object sender, RoutedEventArgs e)
    {
        if (_logDatei is null || !File.Exists(_logDatei))
        {
            return;
        }

        Process.Start(new ProcessStartInfo(_logDatei) { UseShellExecute = true });
    }

    // ---- Titelleisten-Knoepfe ---------------------------------------------

    private void InfoZeigen(object sender, RoutedEventArgs e)
    {
        new InfoFenster(_module) { Owner = this }.ShowDialog();
    }

    private void PatchNotizenZeigen(object sender, RoutedEventArgs e)
    {
        new ChangelogFenster { Owner = this }.ShowDialog();
    }

    private async void NachUpdatesSuchen(object sender, RoutedEventArgs e)
    {
        if (!KannStarten)
        {
            MessageBox.Show(this,
                "Während einer laufenden Wartung wird nicht aktualisiert.",
                "JustUpdate", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        var app = (App)Application.Current;

        // leise: false - der Kunde hat selbst geklickt und will eine Antwort,
        // auch wenn alles aktuell ist.
        await SelbstAktualisierung.PruefenUndAnbieten(this, app.Sperre, leise: false);
    }

    private void ZeitplanZeigen(object sender, RoutedEventArgs e)
    {
        string[] auswahl = _module
            .Where(m => m.Ausgewaehlt)
            .Select(m => m.Schluessel)
            .ToArray();

        new ZeitplanFenster(auswahl) { Owner = this }.ShowDialog();
    }

    // ---- Wartungslauf -----------------------------------------------------

    private async void Starten(object sender, RoutedEventArgs e)
    {
        ModulEintrag[] auswahl = _module.Where(m => m.Ausgewaehlt).ToArray();

        if (auswahl.Length == 0)
        {
            MessageBox.Show(this, "Es ist kein Modul ausgewählt.", "JustUpdate",
                MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        _abbruchGewuenscht = false;
        KannStarten = false;
        xStart.IsEnabled = false;
        xAbbrechen.IsEnabled = true;
        xLog.Clear();
        xFortschritt.Value = 0;

        foreach (ModulEintrag eintrag in _module)
        {
            eintrag.Status = eintrag.Ausgewaehlt ? "wartet" : "aus";
            eintrag.Dauer = string.Empty;
        }

        // Jeder Lauf bekommt seine eigene Logdatei - gleicher Ort wie bei der
        // Konsolen-Variante, damit ein Supportfall nur an EINER Stelle sucht.
        string logOrdner = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "JustUpdate",
            "logs");

        Directory.CreateDirectory(logOrdner);

        _logDatei = Path.Combine(
            logOrdner,
            $"Maintenance_{DateTime.Now:yyyy-MM-dd_HH-mm-ss}.log");

        xLogOeffnen.IsEnabled = true;

        _uhr.Restart();
        _uhrAnzeige.Start();

        bool neustartNoetig = false;

        try
        {
            neustartNoetig = await Task.Run(() => Durchlauf(auswahl, _logDatei));
        }
        catch (Exception fehler)
        {
            AnhaengenAmUiThread($"[FEHLER] Der Wartungslauf ist abgestürzt: {fehler.Message}");
        }

        _uhr.Stop();
        _uhrAnzeige.Stop();
        xZeit.Text = Dauer(_uhr.Elapsed);

        KannStarten = true;
        xStart.IsEnabled = true;
        xAbbrechen.IsEnabled = false;
        xFortschritt.Value = 1;

        int fehlerAnzahl = _module.Count(m => m.Status == "FEHLER");
        int warnungen = _module.Count(m => m.Status == "WARNUNG");

        string ergebnis =
            fehlerAnzahl > 0 ? $"Abgeschlossen mit {fehlerAnzahl} Fehler(n)" :
            warnungen > 0 ? $"Abgeschlossen mit {warnungen} Warnung(en)" :
            "Alles in Ordnung";

        if (_abbruchGewuenscht)
        {
            ergebnis = "Abgebrochen — " + ergebnis;
        }

        xStatus.Text = ergebnis + ".";

        if (neustartNoetig)
        {
            xStatus.Text += " NEUSTART ERFORDERLICH.";
        }

        // Exit-Code wie in v1 und in der Konsolen-Variante: 0 = OK,
        // 1 = Warnungen, 2 = Fehler. Sonst ist ein geplanter Lauf nicht
        // auswertbar.
        int exitCode = fehlerAnzahl > 0 ? 2 : warnungen > 0 ? 1 : 0;

        if (_automatik)
        {
            // Geplanter Lauf: kein Dialog, niemand sitzt davor. Fenster zu,
            // Exit-Code raus.
            Application.Current.Shutdown(exitCode);
            return;
        }

        if (neustartNoetig)
        {
            MessageBox.Show(this,
                "Mindestens ein Modul verlangt einen Neustart, damit die Änderungen " +
                "wirksam werden.",
                "JustUpdate — Neustart erforderlich",
                MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    /// <summary>
    /// Laeuft im Hintergrund-Thread. Haengt den Mitschnitt (Logdatei +
    /// Statusauswertung) an Console.Out ein - genau wie Program.cs. Die Module
    /// selbst bleiben dadurch unveraendert: sie schreiben weiter nach
    /// Console.WriteLine und wissen nichts von der Oberflaeche.
    /// </summary>
    private bool Durchlauf(ModulEintrag[] auswahl, string logDatei)
    {
        TextWriter vorherigeAusgabe = Console.Out;

        using var logSchreiber =
            new StreamWriter(logDatei, append: false, new UTF8Encoding(true))
            {
                AutoFlush = true
            };

        var uiSchreiber = new UiSchreiber(AnhaengenAmUiThread);
        var mitschnitt = new Mitschnitt(uiSchreiber, logSchreiber);

        Console.SetOut(mitschnitt);

        try
        {
            Console.WriteLine("============================================");
            Console.WriteLine($"  JustUpdate - Start {DateTime.Now:dd.MM.yyyy HH:mm:ss}");
            Console.WriteLine("============================================");
            Console.WriteLine($"  Rechner:       {Environment.MachineName}");
            Console.WriteLine($"  Administrator: {(IstAdministrator() ? "ja" : "NEIN")}");
            Console.WriteLine($"  Module:        {string.Join(", ", auswahl.Select(m => m.Schluessel))}");
            Console.WriteLine($"  Log:           {logDatei}");
            Console.WriteLine();

            for (int i = 0; i < auswahl.Length; i++)
            {
                ModulEintrag eintrag = auswahl[i];

                if (_abbruchGewuenscht)
                {
                    AmUiThread(() => eintrag.Status = "abgebrochen");
                    continue;
                }

                AmUiThread(() =>
                {
                    eintrag.Status = "läuft";
                    xStatus.Text = $"{eintrag.Anzeige} läuft ... ({i + 1}/{auswahl.Length})";
                    xFortschritt.Value = (double)i / auswahl.Length;
                });

                var modulUhr = Stopwatch.StartNew();
                mitschnitt.ModulBeginnen();

                try
                {
                    eintrag.Ausfuehren();
                }
                catch (Exception fehler)
                {
                    // Ein abstuerzendes Modul darf die restliche Wartung nicht
                    // mitreissen - gleiche Regel wie in Program.cs.
                    Console.WriteLine(
                        $"[FEHLER] Modul '{eintrag.Schluessel}' ist abgestürzt: {fehler.Message}");
                }

                modulUhr.Stop();

                string status = mitschnitt.ModulStatus();

                AmUiThread(() =>
                {
                    eintrag.Status = status;
                    eintrag.Dauer = Dauer(modulUhr.Elapsed);
                });

                Console.WriteLine();
            }

            Console.WriteLine("============================================");
            Console.WriteLine("  ZUSAMMENFASSUNG");
            Console.WriteLine("============================================");

            foreach (ModulEintrag eintrag in auswahl)
            {
                Console.WriteLine($"  {eintrag.Status,-12} {eintrag.Anzeige,-26} {eintrag.Dauer}");
            }

            if (mitschnitt.NeustartErforderlich)
            {
                Console.WriteLine();
                Console.WriteLine(
                    "[NEUSTART ERFORDERLICH] Mindestens ein Modul verlangt einen Neustart.");
            }

            Console.Out.Flush();

            return mitschnitt.NeustartErforderlich;
        }
        finally
        {
            Console.SetOut(vorherigeAusgabe);
        }
    }

    private void AnhaengenAmUiThread(string zeile)
    {
        Dispatcher.BeginInvoke(() =>
        {
            xLog.AppendText(zeile + Environment.NewLine);
            xLog.ScrollToEnd();
        });
    }

    private void AmUiThread(Action aktion)
    {
        Dispatcher.Invoke(aktion);
    }

    private static string Dauer(TimeSpan spanne) =>
        spanne.TotalMinutes >= 1
            ? $"{(int)spanne.TotalMinutes} min {spanne.Seconds} s"
            : $"{spanne.TotalSeconds:F1} s";

    private void Melde([CallerMemberName] string? name = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }
}
