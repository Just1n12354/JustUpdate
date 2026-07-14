# =====================================================================
# TRANSLATIONS
# =====================================================================
$script:TR = @{
    "de" = @{
        Title="System Wartung Pro"; Tag="All-in-One PC Wartung"
        Desc="Ein Klick - alles aktuell. Windows Updates, Treiber, Apps, Sicherheit und Bereinigung."
        Start="WARTUNG STARTEN"; Stop="ABBRECHEN"; OpenLog="LOG OEFFNEN"
        Modules="Wartungs-Module"; LiveLog="Live-Protokoll"
        Ready="Bereit"; Running="Laeuft..."; Done="Abgeschlossen!"; Stopped="Abgebrochen"
        Footer="Administratorrechte aktiv"
        Restore="Wiederherstellungspunkt"; RestoreD="Sicherung vor Aenderungen"
        Defender="Defender aktualisieren"; DefenderD="Viren-Signaturen updaten"
        WinUpdate="Windows Updates"; WinUpdateD="OS-Updates installieren"
        Drivers="Treiber aktualisieren"; DriversD="Geraete-Treiber updaten"
        Winget="Apps aktualisieren"; WingetD="Alle Apps via Winget"
        StoreApps="Store Apps updaten"; StoreAppsD="Microsoft Store Apps"
        Repair="System-Reparatur"; RepairD="SFC und DISM Pruefung"
        Network="Netzwerk reparieren"; NetworkD="DNS, Winsock, IP Reset"
        Cleanup="Bereinigung"; CleanupD="Temp, Cache, Papierkorb"
        Env="System"
        CloseAppsTitle="Apps vor Update schliessen?"
        CloseAppsMsg="Vor Windows-Updates und Store-Updates sollten alle offenen Programme geschlossen werden, damit sich keine Update-Installation an gesperrten Dateien aufhaengt.`n`nJetzt alle laufenden Programme schliessen?`n`nWICHTIG: Ungespeicherte Daten gehen verloren!"
    }
    "en" = @{
        Title="System Maintenance Pro"; Tag="All-in-One PC Maintenance"
        Desc="One click - everything up to date. Windows Updates, drivers, apps, security, and cleanup."
        Start="START MAINTENANCE"; Stop="CANCEL"; OpenLog="OPEN LOG"
        Modules="Maintenance Modules"; LiveLog="Live Log"
        Ready="Ready"; Running="Running..."; Done="Complete!"; Stopped="Cancelled"
        Footer="Administrator privileges active"
        Restore="Restore Point"; RestoreD="Safety checkpoint"
        Defender="Update Defender"; DefenderD="Update virus signatures"
        WinUpdate="Windows Updates"; WinUpdateD="Install OS updates"
        Drivers="Update Drivers"; DriversD="Device driver updates"
        Winget="Update Apps"; WingetD="All apps via Winget"
        StoreApps="Update Store Apps"; StoreAppsD="Microsoft Store apps"
        Repair="System Repair"; RepairD="SFC and DISM check"
        Network="Repair Network"; NetworkD="DNS, Winsock, IP reset"
        Cleanup="Cleanup"; CleanupD="Temp, cache, recycle bin"
        Env="System"
        CloseAppsTitle="Close apps before updating?"
        CloseAppsMsg="Before Windows Updates and Store updates, all open applications should be closed so update installations don't get stuck on locked files.`n`nClose all running applications now?`n`nWARNING: Unsaved data will be lost!"
    }
    "fr" = @{
        Title="Maintenance Systeme Pro"; Tag="Maintenance PC tout-en-un"
        Desc="Un clic - tout a jour. Mises a jour Windows, pilotes, apps, securite et nettoyage."
        Start="DEMARRER"; Stop="ANNULER"; OpenLog="OUVRIR LOG"
        Modules="Modules"; LiveLog="Journal en direct"
        Ready="Pret"; Running="En cours..."; Done="Termine!"; Stopped="Annule"
        Footer="Privileges administrateur actifs"
        Restore="Point de restauration"; RestoreD="Sauvegarde avant modifications"
        Defender="Mettre a jour Defender"; DefenderD="Signatures antivirus"
        WinUpdate="Mises a jour Windows"; WinUpdateD="Installer les MAJ OS"
        Drivers="Mettre a jour pilotes"; DriversD="Pilotes via Windows Update"
        Winget="Mettre a jour apps"; WingetD="Toutes les apps via Winget"
        StoreApps="Mettre a jour Store"; StoreAppsD="Apps Microsoft Store"
        Repair="Reparation systeme"; RepairD="Verification SFC et DISM"
        Network="Reparer reseau"; NetworkD="Reset DNS, Winsock, IP"
        Cleanup="Nettoyage"; CleanupD="Temp, cache, corbeille"
        Env="Systeme"
        CloseAppsTitle="Fermer les apps avant la mise a jour?"
        CloseAppsMsg="Avant les mises a jour Windows et Store, toutes les applications ouvertes doivent etre fermees pour eviter les blocages sur des fichiers verrouilles.`n`nFermer toutes les applications en cours maintenant?`n`nATTENTION: Les donnees non enregistrees seront perdues!"
    }
}
$script:Lang = "de"
function T([string]$k) { return $script:TR[$script:Lang][$k] }

