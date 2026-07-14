using System.Diagnostics;
using System.IO;
using System.Security.Principal;
using System.Text;

namespace JustUpdate.Ui;

/// <summary>
/// Woechentliche Wartung ueber die Windows-Aufgabenplanung.
///
/// Registriert wird per Task-XML, nicht per schtasks-Schaltern: die
/// entscheidende Einstellung <c>StartWhenAvailable</c> laesst sich auf der
/// Kommandozeile gar nicht setzen. Genau die sorgt dafuer, dass eine verpasste
/// Wartung (Rechner war aus) beim naechsten Start nachgeholt wird.
///
/// Die Aufgabe startet dieselbe EXE mit --auto: Fenster auf, Wartung ohne Klick,
/// Fenster zu, Exit-Code fuers Protokoll.
/// </summary>
internal static class Zeitplan
{
    public const string AufgabenName = "JustUpdate Wartung";

    public static readonly string[] WochentageXml =
        ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];

    public static readonly string[] WochentageDeutsch =
        ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"];

    /// <summary>Liefert eine Kurzbeschreibung der geplanten Aufgabe, oder null wenn keine existiert.</summary>
    public static string? Vorhanden()
    {
        (int code, string ausgabe) = Schtasks(["/Query", "/TN", AufgabenName, "/FO", "LIST"]);

        if (code != 0)
        {
            return null;
        }

        // Aus der LIST-Ausgabe nur die Zeilen, die den Kunden interessieren.
        string[] interessant = ["Status", "Nächste", "Naechste", "Next Run", "Letzte", "Last Run"];

        var zeilen = ausgabe
            .Split('\n')
            .Select(z => z.Trim())
            .Where(z => interessant.Any(i => z.StartsWith(i, StringComparison.OrdinalIgnoreCase)))
            .ToArray();

        return zeilen.Length > 0
            ? string.Join(Environment.NewLine, zeilen)
            : "Die Aufgabe ist eingerichtet.";
    }

    /// <summary>
    /// Richtet die woechentliche Wartung ein.
    /// </summary>
    /// <param name="tagIndex">0 = Montag ... 6 = Sonntag.</param>
    /// <param name="nachStart">
    /// true: Der Termin ist nur der Rhythmus - laeuft der Rechner zum Termin
    /// nicht, holt Windows die Wartung nach dem naechsten Start nach.
    /// false: Nur zum festen Termin. Verpasste Laeufe fallen aus.
    /// </param>
    public static (bool Erfolg, string Meldung) Einrichten(
        int tagIndex,
        int stunde,
        int minute,
        bool nachStart,
        string[] module)
    {
        string? exe = Environment.ProcessPath;

        if (exe is null)
        {
            return (false, "Der eigene Programmpfad ist nicht ermittelbar.");
        }

        string xml = XmlBauen(exe, tagIndex, stunde, minute, nachStart, module);

        // schtasks liest die XML-Datei als Unicode - ohne BOM interpretiert es
        // sie als ANSI und die Umlaute im Namen zerlegen die Registrierung.
        string datei = Path.Combine(
            Path.GetTempPath(),
            $"JustUpdate_Aufgabe_{Guid.NewGuid():N}.xml");

        try
        {
            File.WriteAllText(datei, xml, new UnicodeEncoding(false, true));

            (int code, string ausgabe) = Schtasks(
                ["/Create", "/TN", AufgabenName, "/XML", datei, "/F"]);

            if (code != 0)
            {
                return (false, $"Die Aufgabe konnte nicht angelegt werden:{Environment.NewLine}{ausgabe}");
            }

            string wann = nachStart
                ? $"Jede Woche ({WochentageDeutsch[tagIndex]}, {stunde:00}:{minute:00}). " +
                  "War der Rechner aus, wird die Wartung nach dem nächsten Start nachgeholt."
                : $"Jede Woche am {WochentageDeutsch[tagIndex]} um {stunde:00}:{minute:00}.";

            return (true, $"Die automatische Wartung ist eingerichtet.{Environment.NewLine}{Environment.NewLine}{wann}");
        }
        catch (Exception fehler)
        {
            return (false, $"Die Aufgabe konnte nicht angelegt werden: {fehler.Message}");
        }
        finally
        {
            try
            {
                File.Delete(datei);
            }
            catch (Exception)
            {
                // Die Temp-Datei raeumt spaetestens die Bereinigung weg.
            }
        }
    }

    public static (bool Erfolg, string Meldung) Entfernen()
    {
        (int code, string ausgabe) = Schtasks(["/Delete", "/TN", AufgabenName, "/F"]);

        return code == 0
            ? (true, "Die geplante Wartung wurde entfernt.")
            : (false, $"Die Aufgabe konnte nicht entfernt werden:{Environment.NewLine}{ausgabe}");
    }

    private static string XmlBauen(
        string exe,
        int tagIndex,
        int stunde,
        int minute,
        bool nachStart,
        string[] module)
    {
        string benutzer = WindowsIdentity.GetCurrent().Name;
        string tag = WochentageXml[tagIndex];

        // Der Startzeitpunkt muss in der Vergangenheit oder heute liegen, sonst
        // wartet Windows bis dahin. Das Datum ist nur der Anker, den Rhythmus
        // macht ScheduleByWeek.
        string beginn = $"2026-01-05T{stunde:00}:{minute:00}:00";

        string argumente = Schuetzen($"--auto {string.Join(' ', module)}".Trim());

        // StartWhenAvailable = "verpasste Wartung nach dem naechsten Start
        // nachholen". Genau das, was ein Kunde erwartet, dessen PC am Sonntag
        // um 10 Uhr aus war.
        return $"""
            <?xml version="1.0" encoding="UTF-16"?>
            <Task version="1.3" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
              <RegistrationInfo>
                <Author>JustUpdate</Author>
                <Description>Automatische Windows-Wartung durch JustUpdate (Itin TechSolutions).</Description>
                <URI>\{AufgabenName}</URI>
              </RegistrationInfo>
              <Triggers>
                <CalendarTrigger>
                  <StartBoundary>{beginn}</StartBoundary>
                  <Enabled>true</Enabled>
                  <ScheduleByWeek>
                    <DaysOfWeek><{tag} /></DaysOfWeek>
                    <WeeksInterval>1</WeeksInterval>
                  </ScheduleByWeek>
                </CalendarTrigger>
              </Triggers>
              <Principals>
                <Principal id="Author">
                  <UserId>{Schuetzen(benutzer)}</UserId>
                  <LogonType>InteractiveToken</LogonType>
                  <RunLevel>HighestAvailable</RunLevel>
                </Principal>
              </Principals>
              <Settings>
                <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
                <StartWhenAvailable>{(nachStart ? "true" : "false")}</StartWhenAvailable>
                <DisallowStartIfOnBatteries>true</DisallowStartIfOnBatteries>
                <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
                <AllowHardTerminate>true</AllowHardTerminate>
                <RunOnlyIfNetworkAvailable>true</RunOnlyIfNetworkAvailable>
                <AllowStartOnDemand>true</AllowStartOnDemand>
                <Enabled>true</Enabled>
                <Hidden>false</Hidden>
                <WakeToRun>false</WakeToRun>
                <ExecutionTimeLimit>PT3H</ExecutionTimeLimit>
                <Priority>7</Priority>
                <IdleSettings>
                  <StopOnIdleEnd>false</StopOnIdleEnd>
                  <RestartOnIdle>false</RestartOnIdle>
                </IdleSettings>
              </Settings>
              <Actions Context="Author">
                <Exec>
                  <Command>{Schuetzen(exe)}</Command>
                  <Arguments>{argumente}</Arguments>
                </Exec>
              </Actions>
            </Task>
            """;
    }

    /// <summary>Escaped die fuenf XML-Sonderzeichen - Pfade enthalten durchaus '&'.</summary>
    private static string Schuetzen(string text) =>
        text.Replace("&", "&amp;")
            .Replace("<", "&lt;")
            .Replace(">", "&gt;")
            .Replace("\"", "&quot;")
            .Replace("'", "&apos;");

    private static (int Code, string Ausgabe) Schtasks(string[] argumente)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = "schtasks.exe",
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };

        foreach (string argument in argumente)
        {
            startInfo.ArgumentList.Add(argument);
        }

        try
        {
            using var prozess = Process.Start(startInfo);

            if (prozess is null)
            {
                return (-1, "schtasks.exe konnte nicht gestartet werden.");
            }

            string ausgabe = prozess.StandardOutput.ReadToEnd()
                + prozess.StandardError.ReadToEnd();

            prozess.WaitForExit(30_000);

            return (prozess.ExitCode, ausgabe);
        }
        catch (Exception fehler)
        {
            return (-1, fehler.Message);
        }
    }
}
