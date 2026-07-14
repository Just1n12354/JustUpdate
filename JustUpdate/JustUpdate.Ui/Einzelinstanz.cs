using System.Threading;

namespace JustUpdate.Ui;

/// <summary>
/// Verhindert, dass zwei JustUpdate-Fenster gleichzeitig Wartung fahren.
/// Zwei parallele DISM- oder winget-Laeufe blockieren sich gegenseitig und
/// hinterlassen halbe Installationen.
///
/// Global\ statt Local\: sonst greift die Sperre nur je Sitzung und der
/// erhoehte Prozess sieht den nicht-erhoehten nicht.
/// </summary>
internal sealed class Einzelinstanz : IDisposable
{
    private const string SperrName = @"Global\JustUpdate_Einzelinstanz";

    private readonly Mutex? _sperre;

    private Einzelinstanz(Mutex? sperre, bool istErste)
    {
        _sperre = sperre;
        IstErsteInstanz = istErste;
    }

    public bool IstErsteInstanz { get; }

    public static Einzelinstanz Beanspruchen()
    {
        try
        {
            var sperre = new Mutex(initiallyOwned: true, SperrName, out bool neuErzeugt);

            if (!neuErzeugt)
            {
                sperre.Dispose();
                return new Einzelinstanz(null, istErste: false);
            }

            return new Einzelinstanz(sperre, istErste: true);
        }
        catch (UnauthorizedAccessException)
        {
            // Der Mutex existiert, gehoert aber einem Prozess mit anderen
            // Rechten - also laeuft bereits eine Instanz.
            return new Einzelinstanz(null, istErste: false);
        }
        catch (Exception)
        {
            // Die Sperre ist eine Vorsichtsmassnahme, kein Startkriterium.
            // Scheitert sie, laeuft die App trotzdem.
            return new Einzelinstanz(null, istErste: true);
        }
    }

    /// <summary>
    /// Muss VOR dem Start eines Nachfolgeprozesses aufgerufen werden (Update) -
    /// sonst weist die alte Instanz die frisch gestartete ab.
    /// </summary>
    public void Freigeben()
    {
        Dispose();
    }

    public void Dispose()
    {
        try
        {
            _sperre?.ReleaseMutex();
        }
        catch (ApplicationException)
        {
            // Der Mutex gehoert einem anderen Thread - dann gibt ihn das
            // Prozessende ohnehin frei.
        }

        _sperre?.Dispose();
    }
}
