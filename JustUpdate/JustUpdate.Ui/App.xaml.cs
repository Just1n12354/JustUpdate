using System.Windows;

namespace JustUpdate.Ui;

public partial class App : Application
{
    private Einzelinstanz? _sperre;

    internal Einzelinstanz Sperre =>
        _sperre ?? throw new InvalidOperationException("Die Sperre ist noch nicht gesetzt.");

    /// <summary>
    /// Automatikmodus fuer die geplante Wartung (--auto). Das Fenster geht auf,
    /// die Wartung laeuft ohne Klick, das Fenster schliesst sich wieder.
    /// Wichtig fuer geplante Laeufe: KEIN Dialog darf den Lauf blockieren.
    /// </summary>
    internal bool Automatik { get; private set; }

    /// <summary>Modulauswahl aus den Argumenten. Leer = alle ausgewaehlten.</summary>
    internal string[] AutomatikModule { get; private set; } = [];

    protected override void OnStartup(StartupEventArgs e)
    {
        Automatik = e.Args.Any(a =>
            string.Equals(a, "--auto", StringComparison.OrdinalIgnoreCase));

        AutomatikModule = e.Args
            .Where(a => !a.StartsWith('-'))
            .ToArray();

        _sperre = Einzelinstanz.Beanspruchen();

        if (!_sperre.IstErsteInstanz)
        {
            // Im Automatikmodus keine MessageBox: ein geplanter Lauf haette
            // sonst ewig auf einen Klick gewartet, den niemand macht.
            if (!Automatik)
            {
                MessageBox.Show(
                    "JustUpdate läuft bereits.\n\n" +
                    "Zwei gleichzeitige Wartungsläufe würden sich gegenseitig blockieren.",
                    "JustUpdate",
                    MessageBoxButton.OK,
                    MessageBoxImage.Information);
            }

            Shutdown(1);
            return;
        }

        base.OnStartup(e);
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _sperre?.Dispose();
        base.OnExit(e);
    }
}
