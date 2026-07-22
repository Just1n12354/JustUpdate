using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace JustUpdate.Infrastruktur;

/// <summary>
/// Führt einen externen Prozess asynchron aus mit Zeitlimit,
/// Stream-Handling und UTF-8-Codierung. Nutzbare für winget, netsh, DISM, etc.
/// </summary>
static class ProzessHelper
{
    /// <summary>
    /// Ergebnis einer Prozess-Ausführung.
    /// </summary>
    public record ProzessErgebnis(int ExitCode, bool Zeitueberschreitung);

    /// <summary>
    /// Führt einen Prozess aus und sammelt die Ausgabe.
    /// </summary>
    /// <param name="dateiname">EXE-Pfad (z.B. "winget.exe", "netsh.exe", "dism.exe")</param>
    /// <param name="argumente">Argumente als Liste (wird automatisch gequotet)</param>
    /// <param name="timeout">Maximale Laufzeit</param>
    /// <param name="output">Gesammelte stdout-Ausgabe (Console.Write aus LeseStromAsync)</param>
    /// <param name="newRestartNeeded">Ob die Ausgabe einen Neustart erfordert (z.B. Winget-Updates)</param>
    /// <returns>ProzessErgebnis mit ExitCode und Timeout-Flag</returns>
    public static async Task<ProzessErgebnis> FuehreAusAsync(
        string dateiname,
        IReadOnlyList<string> argumente,
        TimeSpan timeout,
        out string output,
        out bool newRestartNeeded)
    {
        output = string.Empty;
        newRestartNeeded = false;

        var startInfo = new ProcessStartInfo
        {
            FileName = dateiname,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            StandardOutputEncoding = new UTF8Encoding(false),
            StandardErrorEncoding = new UTF8Encoding(false)
        };

        foreach (string argument in argumente)
        {
            startInfo.ArgumentList.Add(argument);
        }

        using var prozess = new Process { StartInfo = startInfo };

        var sbOutput = new StringBuilder();
        object lockObj = new();

        prozess.OutputDataReceived += (_, e) =>
        {
            if (e.Data != null)
            {
                lock (lockObj)
                {
                    sbOutput.AppendLine(e.Data);
                    Console.WriteLine(e.Data);
                }
            }
        };

        prozess.ErrorDataReceived += (_, e) =>
        {
            if (e.Data != null)
            {
                lock (lockObj)
                {
                    sbOutput.AppendLine(e.Data);
                    Console.WriteLine(e.Data);
                }
            }
        };

        if (!prozess.Start())
        {
            return new ProzessErgebnis(-1, false);
        }

        prozess.BeginOutputReadLine();
        prozess.BeginErrorReadLine();

        using var timeoutQuelle = new CancellationTokenSource(timeout);

        try
        {
            await prozess.WaitForExitAsync(timeoutQuelle.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (timeoutQuelle.IsCancellationRequested)
        {
            try
            {
                prozess.Kill(entireProcessTree: true);
            }
            catch (Exception fehler) when (fehler is InvalidOperationException or Win32Exception)
            {
                // Prozess ist zwischenzeitlich schon beendet
            }

            await prozess.WaitForExitAsync().ConfigureAwait(false);

            return new ProzessErgebnis(-1, Zeitueberschreitung: true);
        }

        await Task.WhenAll(
            prozess.StandardOutput.BaseStream.FlushAsync(),
            prozess.StandardError.BaseStream.FlushAsync()).ConfigureAwait(false);

        await Task.Delay(100).ConfigureAwait(false);

        output = sbOutput.ToString();

        // Prüfen ob Neustart erforderlich
        newRestartNeeded = VerlangtNeustart(output);

        return new ProzessErgebnis(prozess.ExitCode, Zeitueberschreitung: false);
    }

    /// <summary>
    /// Synchroner Wrapper für ProzessHelper.
    /// </summary>
    public static ProzessErgebnis FuehreAus(
        string dateiname,
        IReadOnlyList<string> argumente,
        TimeSpan timeout,
        out string output,
        out bool newRestartNeeded)
    {
        return FuehreAusAsync(dateiname, argumente, timeout, out output, out newRestartNeeded)
            .GetAwaiter()
            .GetResult();
    }

    private static bool VerlangtNeustart(string ausgabe)
    {
        // Winget-Updates benötigen oft einen Neustart
        return ausgabe.Contains("NEUSTART ERFORDERLICH", StringComparison.OrdinalIgnoreCase)
            || ausgabe.Contains("RESTART REQUIRED", StringComparison.OrdinalIgnoreCase)
            || ausgabe.Contains("reboot", StringComparison.OrdinalIgnoreCase);
    }
}
