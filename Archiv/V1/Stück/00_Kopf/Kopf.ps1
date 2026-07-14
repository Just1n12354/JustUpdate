# Version: 2.7.7
# Copyright (c) 2026 Itin TechSolutions / Justin Itin
# Alle Rechte vorbehalten - info@itintechsolutions.ch
# https://itintechsolutions.ch

# -Auto: Automatik-Modus fuer geplante Wartung (Task Scheduler / Zeitplan-
# Button in der Titelleiste). Startet die Wartung ohne Klick mit den
# gespeicherten Modulen, zeigt keine Dialoge, schliesst keine laufenden
# Programme, beendet sich selbst und liefert einen Exit-Code fuers
# Fleet-Monitoring (0=OK, 1=Warnungen, 2=Fehler).
# Alternativ aktivierbar via Umgebungsvariable JUSTUPDATE_AUTO=1.
param([switch]$Auto)

# Determine script/exe path first
$ScriptPath = if ($PSCommandPath) { $PSCommandPath }
              elseif ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path }
              else { [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName }

# Laeuft das hier als kompilierte JustUpdate.exe (PS2EXE) statt als .ps1 ueber
# powershell.exe? Dann duerfen Self-Elevation (powershell -File <exe> ist ungueltig)
# und Self-Update (wuerde die laufende .exe mit einer .ps1 ueberschreiben) NICHT
# den .ps1-Pfad gehen. Die EXE aktualisiert sich spaeter ueber GitHub-Releases.
$isExe = $ScriptPath -match '\.exe$'

# Automatik-Modus aktiv? (Parameter ODER Umgebungsvariable, z.B. fuer
# bestehende geplante Aufgaben, die keinen Parameter mitgeben koennen)
$script:AutoMode = [bool]$Auto -or ($env:JUSTUPDATE_AUTO -eq '1')

# Eine einzige Laufzeit-Versionsquelle fuer das ganze Skript (Footer, Report, ...).
# .ps1: Header in Zeile 1.  .exe: aus den FileVersionInfo-Metadaten (von build.ps1
# via PS2EXE -version gesetzt) - in der Binaerdatei gibt es keine lesbare "Zeile 1",
# darum zeigte die EXE vorher "v?".
$script:JUVersion = $null
if ($isExe) {
    try {
        $pv = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($ScriptPath).ProductVersion
        if ($pv) {
            # "2.6.0.0" -> sauber auf x.y.z (erste 3 Teile), NICHT Nullen strippen
            $parts = ([string]$pv).Trim() -split '\.'
            $script:JUVersion = (@($parts + '0' + '0')[0..2]) -join '.'
        }
    } catch {}
} else {
    try {
        if ((Get-Content $ScriptPath -TotalCount 1) -match '#\s*Version:\s*([\d\.]+)') { $script:JUVersion = $Matches[1] }
    } catch {}
}
if (-not $script:JUVersion) { $script:JUVersion = '2.7.6' }   # letzter Fallback statt "?"

