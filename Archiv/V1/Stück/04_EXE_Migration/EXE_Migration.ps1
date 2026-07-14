# =====================================================================
# EXE-MIGRATION (Bestandskunden .ps1 -> JustUpdate.exe, ohne Reinstall)
# Holt die EXE aus dem GitHub-Release, legt sie in den App-Ordner, biegt
# die Verknuepfungen um und startet die EXE. Einmalig (Marker-Datei).
#
# v2.7.7: SCHARF. Die Nachfolge-EXE (C#/WPF, eigene Versionslinie ab 3.0.0)
# liegt als Release-Asset JustUpdate.exe bereit und bringt ein eigenes
# Self-Update mit - der Kunde bleibt also auch nach der Migration erreichbar.
# Abschaltbar mit JUSTUPDATE_MIGRATE_EXE=0 (Notbremse, z.B. wenn ein
# Virenscanner die EXE wegschnappt).
# Die .ps1 bleibt liegen (Fallback) - die Migration ist reversibel, die
# Marker-Datei .exe_migrated enthaelt den Rueckweg.
# =====================================================================
if (-not $isExe -and $env:JUSTUPDATE_MIGRATE_EXE -ne "0") {
    try {
        $appDir   = Split-Path -Parent $ScriptPath
        $exePath  = Join-Path $appDir "JustUpdate.exe"
        $marker   = Join-Path $appDir ".exe_migrated"
        if (-not (Test-Path $marker)) {
            $tmpExe = Join-Path $env:TEMP "JustUpdate_new.exe"
            # Test-Override: lokale Datei / Test-URL, ohne das oeffentliche Release
            # anzufassen. z.B.  $env:JUSTUPDATE_EXE_URL = "C:\...\JustUpdate.exe"
            $exeUrl = if ($env:JUSTUPDATE_EXE_URL) { $env:JUSTUPDATE_EXE_URL }
                      else { "https://github.com/Just1n12354/JustUpdate/releases/latest/download/JustUpdate.exe" }
            if ($exeUrl -notmatch '^https?://') {
                Copy-Item $exeUrl $tmpExe -Force -ErrorAction Stop   # lokaler Pfad
            } else {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                $sp = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
                try {
                    Invoke-WebRequest -Uri $exeUrl -OutFile $tmpExe -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
                } finally { $ProgressPreference = $sp }
            }

            # Integritaet: echte PE-Datei (MZ-Header) + plausible Groesse?
            $okPe = $false
            if ((Test-Path $tmpExe) -and (Get-Item $tmpExe).Length -gt 100KB) {
                $fs = [IO.File]::OpenRead($tmpExe)
                try { $b = New-Object byte[] 2; [void]$fs.Read($b,0,2) } finally { $fs.Close() }
                $okPe = ($b[0] -eq 0x4D -and $b[1] -eq 0x5A)   # 'MZ'
            }
            if ($okPe) {
                Copy-Item $tmpExe $exePath -Force
                Remove-Item $tmpExe -ErrorAction SilentlyContinue

                # Verknuepfungen umbiegen: Desktop (Public/User) + Startmenue.
                $sh = New-Object -ComObject WScript.Shell
                $lnkDirs = @(
                    "$env:PUBLIC\Desktop", "$env:USERPROFILE\Desktop",
                    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
                    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
                )
                $changed = 0
                foreach ($d in $lnkDirs) {
                    if (-not (Test-Path $d)) { continue }
                    Get-ChildItem $d -Filter "JustUpdate*.lnk" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                        try {
                            $lnk = $sh.CreateShortcut($_.FullName)
                            $lnk.TargetPath       = $exePath
                            $lnk.Arguments        = ""
                            $lnk.WorkingDirectory = $appDir
                            $lnk.IconLocation     = "$exePath,0"
                            $lnk.Save()
                            $changed++
                        } catch {}
                    }
                }
                # Marker mit Revert-Info (falls je zurueck auf .ps1 noetig).
                @(
                    "migrated=$(Get-Date -Format o)",
                    "exe=$exePath",
                    "revert_target=powershell.exe",
                    "revert_args=-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$ScriptPath`"",
                    "shortcuts_changed=$changed"
                ) | Out-File -FilePath $marker -Encoding utf8 -Force

                # In die frische EXE wechseln.
                Release-JUMutex   # sonst weist diese Instanz die frisch gestartete EXE ab
                Start-Process -FilePath $exePath
                exit
            }
        }
    } catch {
        # Migration fehlgeschlagen -> .ps1 laeuft normal weiter (kein Bruch).
    }
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

