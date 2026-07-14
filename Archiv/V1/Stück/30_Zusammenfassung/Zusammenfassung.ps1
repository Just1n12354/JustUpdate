        P 100
        L "============================================"
        L "  ZUSAMMENFASSUNG"
        L "============================================"
        # Klartext-Namen fuers Abschluss-Popup - der Kunde soll auf einen Blick sehen
        # WELCHES Modul WARUM gewarnt/fehlgeschlagen ist, ohne erst das Log zu oeffnen.
        $friendlyName = @{
            Restore="Wiederherstellungspunkt"; Defender="Defender aktualisieren"
            WinUpdate="Windows Updates";       Drivers="Treiber aktualisieren"
            Winget="Apps aktualisieren";       Store="Microsoft Store Apps"
            Repair="System-Reparatur";         Network="Netzwerk reparieren"
            Cleanup="Bereinigung"
        }
        $okCount = 0; $warnCount = 0; $errCount = 0
        $issueLines = New-Object System.Collections.Generic.List[string]
        foreach ($modId in $active) {
            $fn = if ($friendlyName.ContainsKey($modId)) { $friendlyName[$modId] } else { $modId }
            if ($sync.Results.ContainsKey($modId)) {
                $r = $sync.Results[$modId]
                $prefix = switch ($r.Status) {
                    "ok"   { $okCount++;   "[OK]  " }
                    "warn" { $warnCount++; "[!]   " }
                    "err"  { $errCount++;  "[FAIL]" }
                    default { "[?]   " }
                }
                L "  $prefix $modId - $($r.Details)"
                if ($r.Status -eq "warn") { $issueLines.Add("WARNUNG - ${fn}:`n   $($r.Details)") }
                elseif ($r.Status -eq "err") { $issueLines.Add("FEHLER - ${fn}:`n   $($r.Details)") }
            } else {
                L "  [?]    $modId - kein Ergebnis"
                $issueLines.Add("FEHLER - ${fn}:`n   Kein Ergebnis - das Modul wurde nicht sauber beendet.")
                $errCount++
            }
        }
        $sync.SummaryDetails = ($issueLines -join "`n`n")
        L "============================================"
        L "  $okCount OK, $warnCount Warnungen, $errCount Fehler"
        if ($sync.RebootRequired) {
            L "  >>> NEUSTART ERFORDERLICH - bitte den PC zeitnah neu starten <<<"
        }
        L "  $(Get-Date -F 'dd.MM.yyyy HH:mm:ss')"
        L "============================================"
        $sync.SummaryOk   = $okCount
        $sync.SummaryWarn = $warnCount
        $sync.SummaryErr  = $errCount
        $sync.Done = $true
    })

