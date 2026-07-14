# =====================================================================
# SETTINGS-PERSISTENZ: Modul-Auswahl + Sprache ueberleben den Neustart.
# Liegt im (verifiziert beschreibbaren) Log-Ordner als settings.json.
# Komplett gekapselt - ein Defekt hier darf den App-Start NIE verhindern.
# =====================================================================
$script:SettingsPath = Join-Path $LogDir "settings.json"
function Save-JUSettings {
    try {
        $mods = @{}
        foreach ($k in $script:ToggleMap.Keys) { $mods[$k] = [bool]$script:ToggleMap[$k].IsChecked }
        $s = [pscustomobject]@{ lang = $script:Lang; modules = [pscustomobject]$mods }
        [IO.File]::WriteAllText($script:SettingsPath, ($s | ConvertTo-Json -Depth 4),
            (New-Object System.Text.UTF8Encoding($false)))
    } catch {}
}
function Restore-JUSettings {
    try {
        if (-not (Test-Path $script:SettingsPath)) { return }
        $s = Get-Content $script:SettingsPath -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($s.lang -and $script:TR.ContainsKey([string]$s.lang)) {
            foreach ($item in $e.xLang.Items) {
                if ($item.Tag -eq [string]$s.lang) { $e.xLang.SelectedItem = $item; break }
            }
            $script:Lang = [string]$s.lang
        }
        if ($s.modules) {
            foreach ($k in @($script:ToggleMap.Keys)) {
                $p = $s.modules.PSObject.Properties[$k]
                if ($null -ne $p) { $script:ToggleMap[$k].IsChecked = [bool]$p.Value }
            }
        }
    } catch {}
}

function Set-ModIcon([string]$id, [string]$state) {
    $ico = $script:IconElements[$id]
    $txt = $script:TextElements[$id]
    if (-not $ico) { return }
    $ico.Dispatcher.Invoke([Action]{
        $brush = $null
        switch ($state) {
            "run"  {
                $ico.Text = "..."
                $brush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#A3243B")
            }
            "ok"   {
                $ico.Text = [string][char]0x2713
                $brush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#22C55E")
            }
            "warn" {
                $ico.Text = "!"
                $brush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#e8a020")
            }
            "err"  {
                $ico.Text = "X"
                $brush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#EF4444")
            }
            default {
                $ico.Text = $script:Icons[$id]
                $brush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#A3243B")
            }
        }
        $ico.Foreground = $brush
        # Bei "default" bleibt der Text-Block in Standard-Fg (weiss/grau), sonst Status-Farbe:
        if ($txt) {
            if ($state -eq "default" -or [string]::IsNullOrEmpty($state)) {
                $txt.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#ededf2")
            } else {
                $txt.Foreground = $brush
            }
        }
    })
}

function Reset-AllIcons {
    foreach ($k in $script:Icons.Keys) {
        $ico = $script:IconElements[$k]
        $txt = $script:TextElements[$k]
        if ($ico) {
            $ico.Text = $script:Icons[$k]
            $ico.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#A3243B")
        }
        if ($txt) {
            $txt.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#ededf2")
        }
    }
}

