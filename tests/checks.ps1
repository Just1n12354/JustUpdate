# JustUpdate - CI-/Lokal-Checks
# =====================================================================
# main ist der LIVE-Verteilkanal: Self-Update laedt das Skript direkt von
# dort. Was diese Checks nicht aufhalten, erreicht Kunden. Deshalb prueft
# dieses Skript vor jedem Push:
#   1. Skript ueberhaupt parsebar (kaputter Commit = unstartbare Kunden-App)
#   2. Versions-Angaben konsistent (Header Zeile 1, Fallback, Changelog)
#   3. Die reinen Parser-Funktionen (IsProgressNoise, parseWg) - beide waren
#      schon Regressions-Quellen (v2.7.1, v2.7.2). Die Funktionen werden per
#      AST aus dem Skript extrahiert, nicht dupliziert - kein Drift moeglich.
#
# Aufruf:  powershell -NoProfile -File tests\checks.ps1
# Exit:    0 = alles OK, 1 = mindestens ein Check fehlgeschlagen
# =====================================================================

$ErrorActionPreference = 'Stop'
$repo   = Split-Path -Parent $PSScriptRoot
$target = Join-Path $repo 'MaintenanceProGUI_MODERN.ps1'
$fails  = New-Object System.Collections.Generic.List[string]

function Check([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) { Write-Host "[OK]   $name" }
    else {
        Write-Host "[FAIL] $name $(if ($detail) { "- $detail" })"
        [void]$fails.Add($name)
    }
}

# --- 1) Parse-Check ---------------------------------------------------
$parseErr = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($target, [ref]$null, [ref]$parseErr)
$parseOk = ($null -eq $parseErr) -or ($parseErr.Count -eq 0)
Check 'Skript parsebar' $parseOk "$(if (-not $parseOk) { ($parseErr | Select-Object -First 3 | Out-String).Trim() })"
if (-not $parseOk) {
    Write-Host ''; Write-Host 'Abbruch - ohne parsebares Skript sind weitere Checks sinnlos.'
    exit 1
}

# --- 2) Versions-Konsistenz --------------------------------------------
$content = [IO.File]::ReadAllText($target)
$verHeader = $null; $verFallback = $null; $verChangelog = $null
if ((Get-Content $target -TotalCount 1) -match '#\s*Version:\s*([\d\.]+)') { $verHeader = $Matches[1] }
if ($content -match '\$script:JUVersion = ''([\d\.]+)''\s*}?\s*#\s*letzter Fallback') { $verFallback = $Matches[1] }
$clPath = Join-Path $repo 'CHANGELOG.md'
if ((Test-Path $clPath) -and ([IO.File]::ReadAllText($clPath) -match '(?m)^##\s*v?([\d\.]+)')) { $verChangelog = $Matches[1] }
Check "Version im Header gefunden (v$verHeader)" ($null -ne $verHeader)
Check "Header == Fallback (v$verHeader / v$verFallback)" ($verHeader -eq $verFallback) 'Zeile 1 und JUVersion-Fallback muessen bei jedem Release BEIDE gebumpt werden'
Check "Header == neuester Changelog-Eintrag (v$verHeader / v$verChangelog)" ($verHeader -eq $verChangelog) 'CHANGELOG.md braucht einen Abschnitt fuer die neue Version'

# --- 3) Parser-Funktionen per AST extrahieren ---------------------------
function Get-FnText([string]$name) {
    $fn = $ast.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true) |
        Select-Object -First 1
    if ($fn) { return $fn.Extent.Text }
    return $null
}
function Get-AssignText([string]$varName) {
    $as = $ast.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $n.Left.Extent.Text -eq $varName }, $true) |
        Select-Object -First 1
    if ($as) { return $as.Right.Extent.Text }
    return $null
}

# --- 3a) IsProgressNoise ------------------------------------------------
$fnText = Get-FnText 'IsProgressNoise'
Check 'IsProgressNoise im Skript gefunden' ($null -ne $fnText)
if ($fnText) {
    Invoke-Expression $fnText   # definiert die Funktion 1:1 wie im Skript
    $U = [char]0x00DC; $u = [char]0x00FC; $blk = [string][char]0x2588
    Check 'Noise: SFC-Fortschritt 5%'    (IsProgressNoise "${U}berpr${u}fung 5 % abgeschlossen.")
    Check 'Keep:  SFC-Fortschritt 100%'  (-not (IsProgressNoise "${U}berpr${u}fung 100 % abgeschlossen."))
    Check 'Noise: DISM-Balken 3.8%'      (IsProgressNoise '[==     3.8%     ]')
    Check 'Keep:  DISM-Balken 100%'      (-not (IsProgressNoise '[==========100.0%==========]'))
    Check 'Noise: winget-Block-Progress' (IsProgressNoise "$blk$blk$blk  45%")
    Check 'Noise: Leerzeile'             (IsProgressNoise '')
    Check 'Keep:  normale Log-Zeile'     (-not (IsProgressNoise 'Der Komponentenspeicher wurde repariert.'))
}

# --- 3b) parseWg (Winget-Ausgabe-Parser) ---------------------------------
$okRxText    = Get-AssignText '$okRx'
$restartText = Get-AssignText '$restartRx'
$parseWgText = Get-AssignText '$parseWg'
Check 'parseWg + Regexe im Skript gefunden' ($okRxText -and $restartText -and $parseWgText)
if ($okRxText -and $restartText -and $parseWgText) {
    # Regexe und Scriptblock 1:1 aus dem Skript uebernehmen. parseWg greift
    # per dynamischem Scope auf $okRx/$restartRx zu - hier genauso.
    $okRx      = Invoke-Expression $okRxText
    $restartRx = Invoke-Expression $restartText
    $parseWg   = Invoke-Expression $parseWgText

    $r = & $parseWg @('(1/1) Gefunden OBS Studio [OBSProject.OBSStudio]', 'Erfolgreich installiert')
    Check 'parseWg: Erfolg zaehlt als Installed' (@($r.Installed).Count -eq 1 -and @($r.Failed).Count -eq 0)

    $r = & $parseWg @('(1/1) Gefunden Claude [Anthropic.Claude]', 'Die Installation war erfolgreich. Starten Sie die Anwendung neu, um das Upgrade abzuschliessen.')
    Check 'parseWg: Erfolg-mit-App-Neustart zaehlt als Installed+Restart' (@($r.Installed).Count -eq 1 -and @($r.Installed)[0].Restart)

    $r = & $parseWg @('(1/1) Gefunden Foo [Foo.Bar]', 'Installation fehlgeschlagen mit Exitcode 1603')
    Check 'parseWg: Exit 1603 zaehlt als Failed+InUse' (@($r.Failed).Count -eq 1 -and @($r.Failed)[0].InUse)

    $r = & $parseWg @('(1/1) Gefunden Foo [Foo.Bar]')
    Check 'parseWg: Paket ohne Endstatus zaehlt als Failed' (@($r.Failed).Count -eq 1)

    $r = & $parseWg @(
        '(1/2) Gefunden Microsoft Edge [Microsoft.Edge]',
        'Fuer die installierte Version wurde kein anwendbares Upgrade gefunden.',
        '(2/2) Gefunden Foo [Foo.Bar]',
        'Erfolgreich installiert')
    Check 'parseWg: "kein anwendbares Upgrade" ist KEIN Fehlschlag' (@($r.Failed).Count -eq 0 -and @($r.Installed).Count -eq 1)
}

# --- Ergebnis ------------------------------------------------------------
Write-Host ''
if ($fails.Count -gt 0) {
    Write-Host "$($fails.Count) Check(s) fehlgeschlagen - NICHT auf main pushen."
    exit 1
}
Write-Host 'Alle Checks bestanden.'
exit 0
