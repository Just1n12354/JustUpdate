# =====================================================================
# JustUpdate — Build
# Setzt die Teile aus Stück\<NN_Name>\<Name>.ps1 wieder zu der einen
# Datei MaintenanceProGUI_MODERN.ps1 zusammen (in Ordner-Reihenfolge).
#
# WARUM: Ausgeliefert wird weiterhin EINE Datei — Self-Update laedt genau
# diese eine Datei von GitHub raw, und die EXE wird daraus kompiliert.
# Bearbeitet wird aber klein, pro Modul, hier in Stück\.
#
#   Aufruf:  powershell -ExecutionPolicy Bypass -File Stück\build.ps1
#            build.ps1 -Check    (nur pruefen, nichts schreiben)
#            build.ps1 -Force    (Direkt-Edit am Monolithen ueberschreiben)
# =====================================================================
[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'

$PartsDir = $PSScriptRoot
$RepoDir  = Split-Path -Parent $PartsDir
$Target   = Join-Path $RepoDir 'MaintenanceProGUI_MODERN.ps1'
$StampF   = Join-Path $PartsDir '.build_hash'

function Get-TextHash([string]$s) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($s)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '')
    } finally { $sha.Dispose() }
}

# --- Teile einsammeln: jeder NN_-Ordner genau eine .ps1 ---------------
$dirs = Get-ChildItem -Path $PartsDir -Directory |
        Where-Object { $_.Name -match '^\d\d_' } |
        Sort-Object Name
if ($dirs.Count -eq 0) { throw "Keine Teil-Ordner (NN_*) in $PartsDir gefunden." }

$parts = foreach ($d in $dirs) {
    $files = @(Get-ChildItem -Path $d.FullName -Filter '*.ps1' -File)
    if ($files.Count -ne 1) {
        throw "Ordner '$($d.Name)' enthaelt $($files.Count) .ps1-Dateien - erlaubt ist genau eine. (Backups/Kopien gehoeren nicht hier rein.)"
    }
    $files[0]
}

# --- Zusammensetzen ---------------------------------------------------
# Jede Teil-Datei endet mit einem Zeilenumbruch (Datei-Terminator). Genau
# EINEN abschneiden — Leerzeilen am Teil-Ende sind bewusst und bleiben.
$chunks = foreach ($f in $parts) {
    $t = [IO.File]::ReadAllText($f.FullName)
    $t = $t -replace '\r?\n$', ''
    $t -replace '\r?\n', "`r`n"          # LF-Editoren tolerieren
}
$out = ($chunks -join "`r`n") + "`r`n"

# --- Sanity-Checks ----------------------------------------------------
if ($out -notmatch '^# Version:\s*([\d\.]+)') {
    throw "Zeile 1 ist keine '# Version: X.Y.Z'-Zeile. Der Self-Update liest die Version aus Zeile 1 - Build abgebrochen."
}
$version = $Matches[1]

$parseErr = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($out, [ref]$null, [ref]$parseErr)
if ($parseErr -and $parseErr.Count -gt 0) {
    Write-Host "PARSE-FEHLER — nichts geschrieben:" -ForegroundColor Red
    $parseErr | ForEach-Object { Write-Host ("  Zeile {0}: {1}" -f $_.Extent.StartLineNumber, $_.Message) -ForegroundColor Red }
    throw "Build abgebrochen: die zusammengesetzte Datei parst nicht."
}

$newHash = Get-TextHash $out
$oldText = if (Test-Path $Target) { [IO.File]::ReadAllText($Target) } else { $null }
$oldHash = if ($null -ne $oldText) { Get-TextHash $oldText } else { '' }

# Wurde der Monolith von Hand editiert, seit er zuletzt gebaut wurde?
# Dann wuerden wir diese Aenderung jetzt still ueberschreiben — Stopp.
$stamp = if (Test-Path $StampF) { (Get-Content $StampF -TotalCount 1).Trim() } else { '' }
$handEdit = ($null -ne $oldText) -and $stamp -and ($oldHash -ne $stamp) -and ($oldHash -ne $newHash)
if ($handEdit -and -not $Force) {
    Write-Host ""
    Write-Host "STOPP: MaintenanceProGUI_MODERN.ps1 wurde seit dem letzten Build von Hand geaendert." -ForegroundColor Yellow
    Write-Host "Ein Build wuerde diese Aenderung verwerfen. Uebertrage sie zuerst in die Teile" -ForegroundColor Yellow
    Write-Host "unter Stück\, oder erzwinge mit:  build.ps1 -Force" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

Write-Host "JustUpdate v$version — $($parts.Count) Teile, $((($out -split "`r`n").Count) - 1) Zeilen"

if ($Check) {
    if ($oldHash -eq $newHash) { Write-Host "AKTUELL: Monolith stimmt mit den Teilen ueberein." -ForegroundColor Green; exit 0 }
    Write-Host "ABWEICHUNG: Monolith ist nicht der Build der Teile. (build.ps1 ausfuehren)" -ForegroundColor Yellow
    exit 1
}

if ($oldHash -eq $newHash) {
    Set-Content -Path $StampF -Value $newHash -Encoding ascii
    Write-Host "Unveraendert — nichts zu tun." -ForegroundColor Green
    exit 0
}

# UTF-8 MIT BOM + CRLF, exakt wie das Original. PS5.1 liest die Datei sonst
# als ANSI und die Umlaut-Pattern (SFC-Filter, XAML-Texte) matchen nicht mehr.
[IO.File]::WriteAllText($Target, $out, (New-Object System.Text.UTF8Encoding($true)))
Set-Content -Path $StampF -Value $newHash -Encoding ascii
Write-Host "GEBAUT: $Target" -ForegroundColor Green
