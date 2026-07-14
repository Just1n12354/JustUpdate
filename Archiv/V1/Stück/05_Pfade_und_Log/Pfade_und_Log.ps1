# =====================================================================
# PATHS
# =====================================================================
$BaseDir = Split-Path -Parent $ScriptPath
# Log-Ordner liegt neben dem Script/Exe (relativ, nicht hardcoded auf Program Files).
# Fallback auf APPDATA falls App-Ordner schreibgeschuetzt ist (z.B. portable von Read-Only-Medium).
$LogDir = Join-Path $BaseDir "logs"
try {
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force -ErrorAction Stop | Out-Null }
    # Schreibtest
    $probe = Join-Path $LogDir ".write_probe"
    "" | Out-File -FilePath $probe -Encoding utf8 -ErrorAction Stop
    Remove-Item $probe -Force -ErrorAction SilentlyContinue
} catch {
    $LogDir = Join-Path $env:APPDATA "JustUpdate\logs"
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
}
# Legt eine frische Logdatei (Zeitstempel im Namen) an und schreibt den
# Metadaten-Kopf - fuer den Support sofort sichtbar welche Version, welcher
# Host, wann gelaufen. Als Funktion (v2.7.5), weil sie beim App-Start UND vor
# jedem weiteren Wartungslauf derselben Sitzung gebraucht wird: vorher haengte
# Lauf 2 sein Log an die Datei von Lauf 1 an und ueberschrieb dessen
# result_*.json (der JSON-Name leitet sich aus dem Log-Namen ab).
function New-JULogFile {
    $script:LogPath = Join-Path $LogDir ("Maintenance_{0}_v{1}.log" -f (Get-Date -Format "yyyy-MM-dd_HH-mm-ss"), $script:JUVersion)
    $logHeader = @"
=================================================
JustUpdate Logdatei
=================================================
Version:    v$($script:JUVersion)
Host:       $($env:COMPUTERNAME)
Benutzer:   $($env:USERNAME)
Erstellt:   $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')
Skript:     $ScriptPath
Log-Datei:  $script:LogPath
=================================================

"@
    $logHeader | Out-File -FilePath $script:LogPath -Encoding utf8
}
New-JULogFile

# Log-Rotation: max 10 Logs behalten, aeltere loeschen
try {
    Get-ChildItem -Path $LogDir -Filter "Maintenance_*.log" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip 10 |
        ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
} catch {}

