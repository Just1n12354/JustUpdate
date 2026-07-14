using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Media;

namespace JustUpdate.Ui;

/// <summary>
/// Ein Wartungsmodul, wie es die Oberflaeche sieht: an/aus, Anzeigename,
/// Farbe und laufender Status. Die eigentliche Arbeit steckt weiterhin in
/// JustUpdate.Module - hier wird nur darauf gezeigt.
/// </summary>
internal sealed class ModulEintrag : INotifyPropertyChanged
{
    private bool _ausgewaehlt = true;
    private string _status = "bereit";
    private string _dauer = string.Empty;

    public ModulEintrag(
        string schluessel,
        string kuerzel,
        string anzeige,
        string beschreibung,
        string farbe,
        string macht,
        string machtNicht,
        Action ausfuehren)
    {
        Schluessel = schluessel;
        Kuerzel = kuerzel;
        Anzeige = anzeige;
        Beschreibung = beschreibung;
        Macht = macht;
        MachtNicht = machtNicht;
        Ausfuehren = ausfuehren;

        var pinsel = new SolidColorBrush((Color)ColorConverter.ConvertFromString(farbe));
        pinsel.Freeze();   // wird aus mehreren Threads gelesen
        Farbe = pinsel;
    }

    /// <summary>Der Name, den auch die Konsolen-Variante als Argument nimmt.</summary>
    public string Schluessel { get; }

    /// <summary>Der Buchstabe, den das Modul selbst in seine Ausgabe schreibt ([R], [D], ...).</summary>
    public string Kuerzel { get; }

    public string Anzeige { get; }

    public string Beschreibung { get; }

    /// <summary>Was das Modul konkret ausfuehrt - fuers Info-Fenster.</summary>
    public string Macht { get; }

    /// <summary>
    /// Was das Modul ausdruecklich NICHT tut. Genauso wichtig wie das, was es
    /// tut: der Kunde soll nicht raten muessen, ob JustUpdate ihm eben die
    /// Registry aufgeraeumt oder Programme deinstalliert hat.
    /// </summary>
    public string MachtNicht { get; }

    /// <summary>Modulfarbe wie in v1 - die Karten sollen auf einen Blick unterscheidbar sein.</summary>
    public Brush Farbe { get; }

    public Action Ausfuehren { get; }

    public bool Ausgewaehlt
    {
        get => _ausgewaehlt;
        set => Setze(ref _ausgewaehlt, value);
    }

    /// <summary>bereit | wartet | läuft | OK | WARNUNG | FEHLER | aus | abgebrochen</summary>
    public string Status
    {
        get => _status;
        set => Setze(ref _status, value);
    }

    public string Dauer
    {
        get => _dauer;
        set => Setze(ref _dauer, value);
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private void Setze<T>(ref T feld, T wert, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(feld, wert))
        {
            return;
        }

        feld = wert;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }
}
