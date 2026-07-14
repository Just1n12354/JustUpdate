# =====================================================================
# Baut die Kunden-EXE: JustUpdate.exe
#
# Self-contained + single-file, weil beim Kunden KEIN .NET-Runtime liegt und
# die EXE-Migration aus v1 (04_EXE_Migration) genau EINE Datei herunterlaedt.
# Der Dateiname MUSS JustUpdate.exe sein - danach sucht die Migration im
# GitHub-Release.
#
#   .\veroeffentlichen.ps1              -> dist\JustUpdate.exe
#   .\veroeffentlichen.ps1 -Release 3.0.0 -> baut und legt ein GitHub-Release an
# =====================================================================
[CmdletBinding()]
param(
    [string]$Release
)

$ErrorActionPreference = 'Stop'

$wurzel  = $PSScriptRoot
$projekt = Join-Path $wurzel 'JustUpdate.Ui\JustUpdate.Ui.csproj'
$ziel    = Join-Path $wurzel 'dist'

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

$mb = [math]::Round((Get-Item $exe).Length / 1MB, 1)
$version = (Get-Item $exe).VersionInfo.ProductVersion

Write-Host ""
Write-Host "Fertig: $exe" -ForegroundColor Green
Write-Host "  Version: $version"
Write-Host "  Groesse: $mb MB"
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
    return
}

# Das Release-Asset MUSS JustUpdate.exe heissen, sonst findet die Migration
# aus v1 es nicht.
Write-Host "Lege GitHub-Release v$Release an ..." -ForegroundColor Cyan

gh release create "v$Release" $exe `
    --repo Just1n12354/JustUpdate `
    --title "JustUpdate v$Release" `
    --notes "Siehe CHANGELOG.md"

if ($LASTEXITCODE -ne 0) { throw "Das Release konnte nicht angelegt werden (gh eingeloggt?)." }

Write-Host "Release v$Release veroeffentlicht." -ForegroundColor Green
