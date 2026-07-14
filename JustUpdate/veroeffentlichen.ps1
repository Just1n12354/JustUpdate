# =====================================================================
# Baut die Auslieferung:
#   dist\JustUpdate.exe        - die App selbst (self-contained, eine Datei)
#   dist\JustUpdate-Setup.exe  - Setup fuer Neukunden
#
# JustUpdate.exe ist self-contained + single-file, weil beim Kunden KEIN
# .NET-Runtime liegt und die EXE-Migration aus v1 (04_EXE_Migration) genau EINE
# Datei herunterlaedt. Der Dateiname MUSS JustUpdate.exe sein - danach sucht die
# Migration im GitHub-Release.
#
#   .\veroeffentlichen.ps1              -> baut nur
#   .\veroeffentlichen.ps1 -Release 2.7.9 -> baut + legt das GitHub-Release an
#
# PFLICHT vor jedem Release: die gebaute EXE STARTEN. Ein "Build erfolgreich"
# sagt nichts darueber, ob das Fenster aufgeht - v2.7.8.1 wurde so mit einem
# Absturz beim Start ausgeliefert (fehlende WPF-Ressource).
# =====================================================================
[CmdletBinding()]
param(
    [string]$Release,
    [switch]$OhneSetup
)

$ErrorActionPreference = 'Stop'

$wurzel  = $PSScriptRoot
$projekt = Join-Path $wurzel 'JustUpdate.Ui\JustUpdate.Ui.csproj'
$ziel    = Join-Path $wurzel 'dist'
$iss     = Join-Path $wurzel 'Installer\JustUpdate.iss'

if (Test-Path $ziel) { Remove-Item $ziel -Recurse -Force }
New-Item -ItemType Directory -Path $ziel | Out-Null

Write-Host "Baue JustUpdate.exe (self-contained, single-file) ..." -ForegroundColor Cyan

dotnet publish $projekt `
    -c Release `
    -r win-x64 `
    --self-contained true `
    -p:PublishSingleFile=true `
    -o $ziel

if ($LASTEXITCODE -ne 0) { throw "Der Build ist fehlgeschlagen (Exit-Code $LASTEXITCODE)." }

$exe = Join-Path $ziel 'JustUpdate.exe'
if (-not (Test-Path $exe)) { throw "JustUpdate.exe wurde nicht erzeugt." }

# Aufraeumen: Die .pdb will kein Kunde herunterladen.
Get-ChildItem $ziel -Exclude 'JustUpdate.exe' | Remove-Item -Recurse -Force

$version = (Get-Item $exe).VersionInfo.FileVersion
$mb = [math]::Round((Get-Item $exe).Length / 1MB, 1)

Write-Host ""
Write-Host "  JustUpdate.exe      v$version  ($mb MB)" -ForegroundColor Green

# --- Setup fuer Neukunden -------------------------------------------------
if (-not $OhneSetup) {
    $iscc = @(
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $iscc) {
        Write-Host ""
        Write-Host "[WARNUNG] Inno Setup nicht gefunden - es wird KEIN Setup gebaut." -ForegroundColor Yellow
        Write-Host "          Installieren mit:  winget install JRSoftware.InnoSetup" -ForegroundColor Yellow
    }
    else {
        Write-Host "Baue JustUpdate-Setup.exe ..." -ForegroundColor Cyan

        # Inno will drei Stellen (2.7.9), nicht vier (2.7.9.0).
        $kurz = ($version -split '\.')[0..2] -join '.'

        & $iscc "/DVersion=$kurz" $iss | Out-Null

        if ($LASTEXITCODE -ne 0) { throw "Das Setup konnte nicht gebaut werden (Exit-Code $LASTEXITCODE)." }

        $setup = Join-Path $ziel 'JustUpdate-Setup.exe'
        if (-not (Test-Path $setup)) { throw "JustUpdate-Setup.exe wurde nicht erzeugt." }

        $setupMb = [math]::Round((Get-Item $setup).Length / 1MB, 1)
        Write-Host "  JustUpdate-Setup.exe  v$kurz  ($setupMb MB)" -ForegroundColor Green
    }
}

Write-Host ""

# WARNUNG, die nicht untergehen darf: eine unsignierte, frisch heruntergeladene
# EXE loest SmartScreen aus und wird von Virenscannern gerne in Quarantaene
# gelegt (in v1 dokumentiert fuer HP Wolf Security). Vor dem Ausrollen an
# Bestandskunden gehoert hier eine Code-Signatur hin.
if (-not (Get-AuthenticodeSignature $exe).SignerCertificate) {
    Write-Host "[WARNUNG] Die EXE ist NICHT signiert." -ForegroundColor Yellow
    Write-Host "          SmartScreen warnt den Kunden, Virenscanner koennen sie" -ForegroundColor Yellow
    Write-Host "          in Quarantaene legen. Vor dem Ausrollen signieren." -ForegroundColor Yellow
    Write-Host ""
}

if (-not $Release) {
    Write-Host "Kein -Release angegeben: es wurde nur gebaut, nichts veroeffentlicht."
    Write-Host "JETZT die EXE starten und pruefen, ob das Fenster aufgeht." -ForegroundColor Cyan
    return
}

# Das Release-Asset MUSS JustUpdate.exe heissen, sonst findet die EXE-Migration
# aus v1 es nicht.
Write-Host "Lege GitHub-Release v$Release an ..." -ForegroundColor Cyan

$assets = @($exe)
$setup = Join-Path $ziel 'JustUpdate-Setup.exe'
if (Test-Path $setup) { $assets += $setup }

gh release create "v$Release" $assets `
    --repo Just1n12354/JustUpdate `
    --title "JustUpdate v$Release" `
    --notes "Siehe CHANGELOG.md"

if ($LASTEXITCODE -ne 0) { throw "Das Release konnte nicht angelegt werden (gh eingeloggt?)." }

Write-Host "Release v$Release veroeffentlicht." -ForegroundColor Green
