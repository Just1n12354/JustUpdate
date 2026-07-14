# =====================================================================
# SINGLE-INSTANCE-SCHUTZ: Ein Doppelklick zu viel (oder der Zeitplan
# waehrend einer offenen GUI) startete bisher eine ZWEITE Wartung parallel -
# DISM/SFC doppelt, Winget-Installer blockieren sich gegenseitig, zwei Logs.
# Benannter Global-Mutex; die zweite Instanz meldet sich kurz und beendet
# sich. Erst NACH der Selbst-Elevation anlegen (der nicht-elevierte Prozess
# beendet sich sofort wieder und darf den Mutex nicht besetzen).
# WICHTIG: Vor Self-Update-Neustart und EXE-Migration wird der Mutex
# explizit freigegeben, sonst weist die alte Instanz die neue ab (Race).
# =====================================================================
# FAIL-OPEN: Der Instanz-Schutz ist Komfort - wirft die Mutex-Erstellung
# selbst (exotische ACL-/Namespace-Faelle), darf das den Start NIE verhindern.
# Nur ein sauberes WaitOne(0)=false bedeutet "andere Instanz laeuft wirklich".
$script:JUMutex = $null
$juGotMutex = $true
try {
    $script:JUMutex = New-Object System.Threading.Mutex($false, "Global\JustUpdate_SingleInstance")
    $juGotMutex = $script:JUMutex.WaitOne(0)
}
catch [System.Threading.AbandonedMutexException] { $juGotMutex = $true }   # Vorinstanz abgestuerzt -> Mutex uebernehmen
catch { $juGotMutex = $true }
if (-not $juGotMutex) {
    if ($script:AutoMode) {
        # Geplanter Lauf trifft auf offene Instanz: still uebersprungen.
        # Exit 3 = "nicht gelaufen, Instanz aktiv" (0/1/2 sind Wartungs-Ergebnisse).
        exit 3
    }
    Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
    [System.Windows.MessageBox]::Show(
        "JustUpdate laeuft bereits.`n`nBitte das offene Fenster verwenden - eine zweite Wartung gleichzeitig wuerde sich mit der ersten in die Quere kommen.",
        "JustUpdate", [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Information) | Out-Null
    exit
}
function Release-JUMutex {
    # Vor einem geplanten Prozess-Neustart (Self-Update/EXE-Migration) aufrufen.
    try { $script:JUMutex.ReleaseMutex() } catch {}
    try { $script:JUMutex.Dispose() } catch {}
    $script:JUMutex = $null
}

