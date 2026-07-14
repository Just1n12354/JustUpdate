# JustUpdate (C#) - Selbsttest
#
# Laeuft ueber "dotnet <dll>" statt ueber die EXE: das umgeht das
# requireAdministrator-Manifest, also ist kein UAC noetig. Getestet werden
# Build, Startpfade und die Module, die ohne Adminrechte auskommen -
# insbesondere, dass die anderen KONTROLLIERT abbrechen statt abzustuerzen.
#
#   powershell -ExecutionPolicy Bypass -File tests\checks.ps1
$ErrorActionPreference = 'Continue'

$repo = Split-Path -Parent $PSScriptRoot

# Pfad nicht hart verdrahten - er haengt am Zielframework (net10.0-windows).
function Get-Dll {
    Get-ChildItem (Join-Path $repo 'JustUpdate\bin\Debug') -Recurse -Filter 'JustUpdate.dll' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

$bestanden = 0
$fehlgeschlagen = 0

function Pruefe {
    param([string]$Name, [scriptblock]$Test)

    try {
        if (& $Test) {
            Write-Host "[OK]   $Name" -ForegroundColor Green
            $script:bestanden++
        } else {
            Write-Host "[FEHL] $Name" -ForegroundColor Red
            $script:fehlgeschlagen++
        }
    } catch {
        Write-Host "[FEHL] $Name - $($_.Exception.Message)" -ForegroundColor Red
        $script:fehlgeschlagen++
    }
}

Write-Host "=== Build ===" -ForegroundColor Cyan
$build = & dotnet build $repo 2>&1
$buildOk = $LASTEXITCODE -eq 0
Pruefe "Build ohne Fehler" { $buildOk }
if (-not $buildOk) { $build | Select-Object -Last 15; exit 1 }

Pruefe "Build ohne Warnungen" { ($build | Select-String -Pattern '\d+ Warnung\(en\)' | Select-Object -Last 1) -match '0 Warnung' }

$dll = Get-Dll
if (-not $dll) { Write-Host "[FEHL] JustUpdate.dll nicht gefunden" -ForegroundColor Red; exit 1 }

Write-Host "`n=== Startpfade ===" -ForegroundColor Cyan

Pruefe "--help zeigt Module und Exit-Codes, Exit 0" {
    $t = ("" | dotnet $dll --help 2>&1) -join "`n"
    $LASTEXITCODE -eq 0 -and $t -match 'wiederherstellungspunkt' -and $t -match 'Exit-Codes'
}

Pruefe "unbekanntes Modul -> Exit 1" {
    $t = ("" | dotnet $dll quatsch 2>&1) -join "`n"
    $LASTEXITCODE -eq 1 -and $t -match 'Unbekanntes Modul'
}

Write-Host "`n=== Module ohne Adminrechte ===" -ForegroundColor Cyan

# Diese Module MUESSEN kontrolliert abbrechen (Exit 2 = Fehler sauber gemeldet),
# nicht abstuerzen. Ein Absturz wuerde einen Exit-Code jenseits von 0/1/2 liefern
# und die Zusammenfassung gaebe es gar nicht erst.
foreach ($modul in @('reparatur', 'netzwerk')) {
    Pruefe "$modul bricht kontrolliert ab (Exit 2, kein Crash)" {
        $t = ("" | dotnet $dll $modul 2>&1) -join "`n"
        $LASTEXITCODE -eq 2 -and $t -match 'muss als Administrator' -and $t -match 'ZUSAMMENFASSUNG'
    }
}

# Regression: EnumerateFiles mit SearchOption.AllDirectories warf eine
# UnauthorizedAccessException AUSSERHALB des try/catch in der Schleife
# (z.B. an C:\...\Temp\nx) und beendete den gesamten Prozess.
Pruefe "bereinigung laeuft durch, auch bei gesperrten Temp-Ordnern" {
    $t = ("" | dotnet $dll bereinigung 2>&1) -join "`n"
    $LASTEXITCODE -eq 0 -and $t -match 'Bereinigung abgeschlossen'
}

Pruefe "defender laeuft durch (Exit 0)" {
    "" | dotnet $dll defender 2>&1 | Out-Null
    $LASTEXITCODE -eq 0
}

Write-Host "`n=== Logdatei ===" -ForegroundColor Cyan

Pruefe "Log geschrieben: Zeitstempel vorhanden, Umlaute unverstuemmelt" {
    $ordner = Join-Path $env:LOCALAPPDATA 'JustUpdate\logs'
    $log = Get-ChildItem $ordner -Filter 'Maintenance_*.log' -ErrorAction SilentlyContinue |
           Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $log) { return $false }
    $inhalt = Get-Content $log.FullName -Raw -Encoding UTF8
    ($inhalt -match '\[\d{2}:\d{2}:\d{2}\]') -and ($inhalt -notmatch '├|Ã')
}

Write-Host "`n============================" -ForegroundColor Cyan
Write-Host "Bestanden: $bestanden   Fehlgeschlagen: $fehlgeschlagen"
if ($fehlgeschlagen -gt 0) { exit 1 } else { exit 0 }
