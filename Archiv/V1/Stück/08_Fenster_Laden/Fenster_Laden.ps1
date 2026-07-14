# =====================================================================
# LOAD WINDOW
# =====================================================================
$reader = New-Object System.Xml.XmlNodeReader $xamlXml
$Window = [Windows.Markup.XamlReader]::Load($reader)

# App-Icon zur Laufzeit erzeugen (rotes Quadrat mit weissem J).
# Kein .ico-File noetig - wird in-memory gerendert und an $Window.Icon gehaengt.
try {
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap 64,64
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode    = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $bg = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(163,36,59))
    $g.FillRectangle($bg, 0, 0, 64, 64)
    $font = New-Object System.Drawing.Font ("Segoe UI", 36, [System.Drawing.FontStyle]::Bold)
    $fg   = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
    $sf   = New-Object System.Drawing.StringFormat
    $sf.Alignment     = [System.Drawing.StringAlignment]::Center
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
    $rect = New-Object System.Drawing.RectangleF 0,2,64,64
    $g.DrawString("J", $font, $fg, $rect, $sf)
    $g.Dispose(); $font.Dispose(); $bg.Dispose(); $fg.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $ms.Position = 0
    $bi = New-Object System.Windows.Media.Imaging.BitmapImage
    $bi.BeginInit()
    $bi.CacheOption  = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bi.StreamSource = $ms
    $bi.EndInit()
    $bi.Freeze()
    $Window.Icon = $bi
    $bmp.Dispose()
} catch {}

# Get elements
$e = @{}
$allNames = @(
    "TitleBar","xLang","xMin","xMax","xClose","xInfo","xPatch","xSched","xTitleBar",
    "xTag","xTitle","xDesc","xModHdr",
    "xRestore","xRestoreD","xIcoRestore","xTglRestore",
    "xDefender","xDefenderD","xIcoDefender","xTglDefender",
    "xWinUpdate","xWinUpdateD","xIcoWinUpdate","xTglWinUpdate",
    "xDrivers","xDriversD","xIcoDrivers","xTglDrivers",
    "xWinget","xWingetD","xIcoWinget","xTglWinget",
    "xStoreApps","xStoreAppsD","xIcoStore","xTglStore",
    "xRepair","xRepairD","xIcoRepair","xTglRepair",
    "xNetwork","xNetworkD","xIcoNetwork","xTglNetwork",
    "xCleanup","xCleanupD","xIcoCleanup","xTglCleanup",
    "xStart","xStop","xLog",
    "xBar","xStatus","xTime",
    "xLogHdr","xLogBox",
    "xEnvLbl","xEnvInfo","xFooter"
)
foreach ($n in $allNames) { $e[$n] = $Window.FindName($n) }

