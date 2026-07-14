using System.Windows;

namespace JustUpdate.Ui;

public partial class App : Application
{
    private Einzelinstanz? _sperre;

    internal Einzelinstanz Sperre =>
        _sperre ?? throw new InvalidOperationException("Die Sperre ist noch nicht gesetzt.");

    protected override void OnStartup(StartupEventArgs e)
    {
        _sperre = Einzelinstanz.Beanspruchen();

        if (!_sperre.IstErsteInstanz)
        {
            MessageBox.Show(
                "JustUpdate läuft bereits.\n\n" +
                "Zwei gleichzeitige Wartungsläufe würden sich gegenseitig blockieren.",
                "JustUpdate",
                MessageBoxButton.OK,
                MessageBoxImage.Information);

            Shutdown();
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
