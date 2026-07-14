using System.Windows;
using System.Windows.Input;

namespace JustUpdate.Ui;

public partial class ZeitplanFenster : Window
{
    private readonly string[] _module;

    internal ZeitplanFenster(string[] module)
    {
        InitializeComponent();

        _module = module;

        foreach (string tag in Zeitplan.WochentageDeutsch)
        {
            xTag.Items.Add(tag);
        }

        for (int stunde = 0; stunde < 24; stunde++)
        {
            xStunde.Items.Add($"{stunde:00}");
        }

        foreach (int minute in new[] { 0, 15, 30, 45 })
        {
            xMinute.Items.Add($"{minute:00}");
        }

        // Sonntag 10:00 - da laeuft der Rechner meistens, aber niemand arbeitet damit.
        xTag.SelectedIndex = 6;
        xStunde.SelectedIndex = 10;
        xMinute.SelectedIndex = 0;

        xModulHinweis.Text = _module.Length > 0
            ? $"Automatisch laufen die im Hauptfenster gewählten Module: {string.Join(", ", _module)}."
            : "Achtung: Im Hauptfenster ist kein Modul gewählt.";

        StatusAktualisieren();
    }

    private void StatusAktualisieren()
    {
        string? vorhanden = Zeitplan.Vorhanden();

        if (vorhanden is null)
        {
            xStatus.Text = "Die automatische Wartung ist ausgeschaltet.";
            xEntfernen.IsEnabled = false;
            return;
        }

        xStatus.Text = vorhanden;
        xEntfernen.IsEnabled = true;
    }

    private void Einrichten(object sender, RoutedEventArgs e)
    {
        if (_module.Length == 0)
        {
            MessageBox.Show(this,
                "Es ist kein Modul ausgewählt. Wähle im Hauptfenster die Module, " +
                "die automatisch laufen sollen.",
                "JustUpdate", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        (bool erfolg, string meldung) = Zeitplan.Einrichten(
            xTag.SelectedIndex,
            xStunde.SelectedIndex,
            xMinute.SelectedIndex * 15,
            xNachStart.IsChecked == true,
            _module);

        MessageBox.Show(this, meldung, "JustUpdate",
            MessageBoxButton.OK,
            erfolg ? MessageBoxImage.Information : MessageBoxImage.Error);

        StatusAktualisieren();
    }

    private void Entfernen(object sender, RoutedEventArgs e)
    {
        (bool erfolg, string meldung) = Zeitplan.Entfernen();

        MessageBox.Show(this, meldung, "JustUpdate",
            MessageBoxButton.OK,
            erfolg ? MessageBoxImage.Information : MessageBoxImage.Error);

        StatusAktualisieren();
    }

    private void Gezogen(object sender, MouseButtonEventArgs e) => DragMove();

    private void Schliessen(object sender, RoutedEventArgs e) => Close();
}
