# =====================================================================
# LANGUAGE
# =====================================================================
function Update-UI {
    $e.xTitleBar.Text = T "Title"
    $e.xTag.Text      = T "Tag"
    $e.xTitle.Text     = T "Title"
    $e.xDesc.Text      = T "Desc"
    $e.xModHdr.Text    = T "Modules"
    $e.xStart.Content  = T "Start"
    $e.xStop.Content   = T "Stop"
    $e.xLog.Content    = T "OpenLog"
    $e.xLogHdr.Text    = T "LiveLog"
    $e.xEnvLbl.Text    = T "Env"
    $e.xFooter.Text    = "v$($script:JUVersion)  -  " + (T "Footer")
    $e.xStatus.Text    = T "Ready"
    $e.xRestore.Text   = T "Restore";   $e.xRestoreD.Text   = T "RestoreD"
    $e.xDefender.Text  = T "Defender";  $e.xDefenderD.Text  = T "DefenderD"
    $e.xWinUpdate.Text = T "WinUpdate"; $e.xWinUpdateD.Text = T "WinUpdateD"
    $e.xDrivers.Text   = T "Drivers";  $e.xDriversD.Text   = T "DriversD"
    $e.xWinget.Text    = T "Winget";   $e.xWingetD.Text    = T "WingetD"
    $e.xStoreApps.Text = T "StoreApps"; $e.xStoreAppsD.Text = T "StoreAppsD"
    $e.xRepair.Text    = T "Repair";   $e.xRepairD.Text    = T "RepairD"
    $e.xNetwork.Text   = T "Network";  $e.xNetworkD.Text   = T "NetworkD"
    $e.xCleanup.Text   = T "Cleanup";  $e.xCleanupD.Text   = T "CleanupD"
}

# Icon map
$script:Icons = @{
    Restore="R"; Defender="D"; WinUpdate="W"; Drivers="T"
    Winget="A"; Store="S"; Repair="F"; Network="N"; Cleanup="C"
}
$script:IconElements = @{
    Restore=$e.xIcoRestore; Defender=$e.xIcoDefender; WinUpdate=$e.xIcoWinUpdate; Drivers=$e.xIcoDrivers
    Winget=$e.xIcoWinget; Store=$e.xIcoStore; Repair=$e.xIcoRepair; Network=$e.xIcoNetwork; Cleanup=$e.xIcoCleanup
}
# Text-Elemente der Module (links im Panel) - werden zusammen mit dem Icon umgefaerbt,
# damit der User den Status auch am Wort und nicht nur am Buchstaben sieht.
$script:TextElements = @{
    Restore=$e.xRestore; Defender=$e.xDefender; WinUpdate=$e.xWinUpdate; Drivers=$e.xDrivers
    Winget=$e.xWinget; Store=$e.xStoreApps; Repair=$e.xRepair; Network=$e.xNetwork; Cleanup=$e.xCleanup
}
# Modul-ID -> Toggle-Schalter. Grundlage fuer Settings-Persistenz und Auto-Modus.
$script:ToggleMap = @{
    Restore=$e.xTglRestore; Defender=$e.xTglDefender; WinUpdate=$e.xTglWinUpdate; Drivers=$e.xTglDrivers
    Winget=$e.xTglWinget; Store=$e.xTglStore; Repair=$e.xTglRepair; Network=$e.xTglNetwork; Cleanup=$e.xTglCleanup
}

