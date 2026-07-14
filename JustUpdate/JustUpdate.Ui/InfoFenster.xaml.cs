using System.IO;
using System.Windows;
using System.Windows.Input;

namespace JustUpdate.Ui;

public partial class InfoFenster : Window
{
    internal InfoFenster(IEnumerable<ModulEintrag> module)
    {
        InitializeComponent();

        xModule.ItemsSource = module;

        xKopf.Text =
            $"JustUpdate v{SelbstAktualisierung.EigeneVersion.ToString(3)} führt Windows-Wartung " +
            "mit Bordmitteln aus: winget, Windows Update, Defender, SFC und DISM. " +
            "Es installiert keine Fremdsoftware und ändert nichts an der Registry. " +
            "Jedes Modul lässt sich einzeln abschalten.";

        string logOrdner = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "JustUpdate",
            "logs");

        xLogPfad.Text = $"Protokolle: {logOrdner}";
    }

    private void Gezogen(object sender, MouseButtonEventArgs e) => DragMove();

    private void Schliessen(object sender, RoutedEventArgs e) => Close();
}
