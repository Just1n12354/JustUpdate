using System;
using System.IO;
using System.Text;
using System.Diagnostics;

namespace JustUpdate.Infrastruktur;

/// <summary>
/// Führt ein PowerShell-Skript asynchron aus mit Time-Out,
/// Stream-Handling und UTF-8-Codierung. Dient als gemeinsame
/// Basis für alle Module, die PowerShell brauchen.
/// </summary>
static class PowerShellHelper
{
    /// <summary>
    /// Führt ein PowerShell-Skript aus und sammelt stdout/stderr.
    /// </summary>
    /// <param name="script">PowerShell-Skript-String (verbatim, keine Shell-Sanitization nötig)</param>
    /// <param name="timeOutSekunden">Maximale Laufzeit in Sekunden. Default: 600 (10 Min)</param>
    /// <param name="output">Gesammelte stdout-Ausgabe</param>
    /// <param name="error">Gesammelte stderr-Ausgabe</param>
    /// <param name="exitCode">Exit-Code des Prozesses, -1 wenn Timeout</param>
    /// <param name="timedOut">True wenn Zeitlimit erreicht</param>
    /// <returns>True wenn Prozess sauber beendet wurde</returns>
    public static bool Ausfuehren(
        string script,
        int timeOutSekunden = 600,
        out string output,
        out string error,
        out int exitCode,
        out bool timedOut)
    {
        output = string.Empty;
        error = string.Empty;
        exitCode = -1;
        timedOut = false;

        var startInfo = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };

        startInfo.ArgumentList.Add("-NoProfile");
        startInfo.ArgumentList.Add("-NonInteractive");
        startInfo.ArgumentList.Add("-ExecutionPolicy");
        startInfo.ArgumentList.Add("Bypass");
        startInfo.ArgumentList.Add("-Command");
        startInfo.ArgumentList.Add(script);

        using var process = new Process { StartInfo = startInfo };

        var sbOutput = new StringBuilder();
        var sbError = new StringBuilder();

        process.OutputDataReceived += (_, e) =>
        {
            if (e.Data != null)
            {
                lock (sbOutput) { sbOutput.AppendLine(e.Data); }
            }
        };

        process.ErrorDataReceived += (_, e) =>
        {
            if (e.Data != null)
            {
                lock (sbError) { sbError.AppendLine(e.Data); }
            }
        };

        if (!process.Start())
        {
            return false;
        }

        process.BeginOutputReadLine();
        process.BeginErrorReadLine();

        if (!process.WaitForExit(timeOutSekunden * 1000))
        {
            timedOut = true;
            try
            {
                process.Kill(entireProcessTree: true);
            }
            catch
            {
                // Prozess war bereits beendet
            }
            process.WaitForExit();
        }

        process.WaitForExit();

        output = sbOutput.ToString();
        error = sbError.ToString();
        exitCode = process.ExitCode;

        return true;
    }
}