using System.IO;
using System.Text;

namespace JustUpdate.Ui;

/// <summary>
/// Nimmt die Konsolenausgabe der Module entgegen und reicht sie zeilenweise an
/// die Oberflaeche weiter.
///
/// Die Module schreiben ihre Ausgabe aus Threadpool-Threads (die Lese-Tasks der
/// gestarteten Prozesse). WPF-Steuerelemente duerfen nur vom UI-Thread
/// angefasst werden - das Umschalten uebernimmt der Aufrufer im Rueckruf,
/// nicht diese Klasse.
/// </summary>
internal sealed class UiSchreiber : TextWriter
{
    private readonly Action<string> _zeileEmpfangen;
    private readonly StringBuilder _puffer = new();
    private readonly object _schloss = new();

    public UiSchreiber(Action<string> zeileEmpfangen)
    {
        _zeileEmpfangen = zeileEmpfangen;
    }

    public override Encoding Encoding => Encoding.UTF8;

    public override void WriteLine(string? zeile)
    {
        Zeile(zeile ?? string.Empty);
    }

    /// <summary>
    /// Console.WriteLine() ohne Argument landet als einzelne Zeichen hier.
    /// Deshalb wird bis zum Zeilenumbruch gepuffert.
    /// </summary>
    public override void Write(char zeichen)
    {
        string? fertigeZeile = null;

        lock (_schloss)
        {
            if (zeichen == '\n')
            {
                fertigeZeile = _puffer.ToString().TrimEnd('\r');
                _puffer.Clear();
            }
            else
            {
                _puffer.Append(zeichen);
            }
        }

        if (fertigeZeile is not null)
        {
            Zeile(fertigeZeile);
        }
    }

    private void Zeile(string zeile)
    {
        _zeileEmpfangen(zeile);
    }
}
