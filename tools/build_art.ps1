# Regenerates the extension cable tile art, texture pack, tile definitions and item icon.
# Usage: powershell -ExecutionPolicy Bypass -File tools\build_art.ps1
param([string]$ModRoot = (Split-Path $PSScriptRoot -Parent))

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$TileSet   = 'pgp_extension_cable'
$PackName  = 'PooledGeneratorPower'
$Media     = Join-Path $ModRoot '42\media'
$TileW     = 128
$TileH     = 256

New-Item -ItemType Directory -Force -Path (Join-Path $Media 'texturepacks') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Media 'textures') | Out-Null

function PtF([double]$x, [double]$y) { New-Object System.Drawing.PointF ([single]$x), ([single]$y) }
function Col([int]$a, [int]$r, [int]$g, [int]$b) { [System.Drawing.Color]::FromArgb($a, $r, $g, $b) }

function New-RoundPen($color, [double]$width, [switch]$Flat) {
    $p = New-Object System.Drawing.Pen $color, ([single]$width)
    $p.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $cap = if ($Flat) { [System.Drawing.Drawing2D.LineCap]::Flat } else { [System.Drawing.Drawing2D.LineCap]::Round }
    $p.StartCap = $cap
    $p.EndCap   = $cap
    return $p
}

function New-Canvas([int]$w, [int]$h) {
    $bmp = New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.Clear([System.Drawing.Color]::Transparent)
    return @($bmp, $g)
}

# Floor diamond of a 2x tile: top (64,192), right (128,224), bottom (64,256), left (0,224).
# World north edge is the upper-right edge, east the lower-right, south the lower-left, west the upper-left.
$Center = PtF 64 224
$EdgeMid = @{
    1 = (PtF 96 208)   # N
    2 = (PtF 96 240)   # E
    4 = (PtF 32 240)   # S
    8 = (PtF 32 208)   # W
}

# Cable palette: orange extension cord. Flat caps so segments meet seamlessly at tile edges.
$ShadowPen    = New-RoundPen (Col 80 0 0 0) 7.5 -Flat
$OutlinePen   = New-RoundPen (Col 255 46 22 8) 7 -Flat
$CorePen      = New-RoundPen (Col 255 232 112 26) 4.4 -Flat
$HighlightPen = New-RoundPen (Col 210 255 186 110) 1.3 -Flat

function Draw-CablePath($g, $path) {
    $m = New-Object System.Drawing.Drawing2D.Matrix
    $m.Translate(1.5, 2.5)
    $shadow = $path.Clone(); $shadow.Transform($m)
    $g.DrawPath($ShadowPen, $shadow)
    $g.DrawPath($OutlinePen, $path)
    $g.DrawPath($CorePen, $path)
    $m2 = New-Object System.Drawing.Drawing2D.Matrix
    $m2.Translate(-0.4, -1.1)
    $hi = $path.Clone(); $hi.Transform($m2)
    $g.DrawPath($HighlightPen, $hi)
}

function Mid($a, $b) { PtF (($a.X + $b.X) / 2) (($a.Y + $b.Y) / 2) }

# Socket end of the cord, pointing along the direction the cable travels.
function Draw-Socket($g, $from, $at) {
    $angle = [Math]::Atan2($at.Y - $from.Y, $at.X - $from.X) * 180 / [Math]::PI
    $state = $g.Save()
    $g.TranslateTransform($at.X, $at.Y)
    $g.RotateTransform([single]$angle)
    $shadow = New-Object System.Drawing.SolidBrush (Col 80 0 0 0)
    $g.FillRectangle($shadow, -2.5, -3.0, 16, 9.5)
    $body = New-Object System.Drawing.SolidBrush (Col 255 214 92 18)
    $edge = New-Object System.Drawing.Pen (Col 255 46 22 8), 1.6
    $g.FillRectangle($body, -4, -4.5, 15, 9)
    $g.DrawRectangle($edge, -4, -4.5, 15, 9)
    $face = New-Object System.Drawing.SolidBrush (Col 255 60 30 12)
    $g.FillRectangle($face, 9.5, -4.5, 1.5, 9)
    $slot = New-Object System.Drawing.SolidBrush (Col 255 20 10 4)
    $g.FillRectangle($slot, 6.5, -3, 3, 1.4)
    $g.FillRectangle($slot, 6.5, 1.6, 3, 1.4)
    $g.Restore($state)
}

# Small power strip used where three or four cables meet.
function Draw-Strip($g) {
    $state = $g.Save()
    $g.TranslateTransform($Center.X, $Center.Y)
    $g.RotateTransform(-26.565)
    $shadow = New-Object System.Drawing.SolidBrush (Col 90 0 0 0)
    $g.FillRectangle($shadow, -12, -5, 27, 13)
    $body = New-Object System.Drawing.SolidBrush (Col 255 70 76 84)
    $top  = New-Object System.Drawing.SolidBrush (Col 255 104 112 122)
    $edge = New-Object System.Drawing.Pen (Col 255 22 24 28), 1.6
    $g.FillRectangle($body, -13, -6.5, 26, 12)
    $g.FillRectangle($top, -12, -5.5, 24, 5)
    $g.DrawRectangle($edge, -13, -6.5, 26, 12)
    $hole = New-Object System.Drawing.SolidBrush (Col 255 18 18 20)
    foreach ($x in @(-8, -2, 4)) { $g.FillEllipse($hole, $x, -1, 4, 4) }
    $led = New-Object System.Drawing.SolidBrush (Col 255 230 40 30)
    $g.FillEllipse($led, 9, -4.5, 2.6, 2.6)
    $g.Restore($state)
}

function Draw-CableTile([int]$mask) {
    $bmp, $g = New-Canvas $TileW $TileH
    $dirs = @(1, 2, 4, 8) | Where-Object { ($mask -band $_) -ne 0 }
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    if ($dirs.Count -eq 0) {
        # Coiled cord lying on the floor.
        for ($i = 0; $i -lt 3; $i++) {
            $path.StartFigure()
            $path.AddEllipse([single](46 + $i * 2), [single](214 - $i * 2.5), [single](36 - $i * 4), [single](17 - $i * 2))
        }
        $path.StartFigure()
        $path.AddBezier((PtF 80 224), (PtF 88 228), (PtF 90 234), (PtF 84 238))
        Draw-CablePath $g $path
        Draw-Socket $g (PtF 90 234) (PtF 84 238)
    } elseif ($dirs.Count -eq 1) {
        $p = $EdgeMid[[int]$dirs[0]]
        $end = Mid $p $Center
        $end = PtF (($end.X + $Center.X) / 2) (($end.Y + $Center.Y) / 2)
        $path.AddLine($p, $end)
        Draw-CablePath $g $path
        Draw-Socket $g $p $end
    } elseif ($dirs.Count -eq 2) {
        $a = $EdgeMid[[int]$dirs[0]]; $b = $EdgeMid[[int]$dirs[1]]
        $path.AddBezier($a, (Mid $a $Center), (Mid $b $Center), $b)
        Draw-CablePath $g $path
    } else {
        foreach ($d in $dirs) {
            $path.StartFigure()
            $path.AddLine($EdgeMid[[int]$d], $Center)
        }
        Draw-CablePath $g $path
        Draw-Strip $g
    }
    $g.Dispose()
    return $bmp
}

function Get-TrimRect($bmp) {
    $minX = $bmp.Width; $minY = $bmp.Height; $maxX = -1; $maxY = -1
    $rect = New-Object System.Drawing.Rectangle 0, 0, $bmp.Width, $bmp.Height
    $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $bytes = New-Object byte[] ($data.Stride * $bmp.Height)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
    $bmp.UnlockBits($data)
    for ($y = 0; $y -lt $bmp.Height; $y++) {
        $row = $y * $data.Stride
        for ($x = 0; $x -lt $bmp.Width; $x++) {
            if ($bytes[$row + $x * 4 + 3] -ne 0) {
                if ($x -lt $minX) { $minX = $x }; if ($x -gt $maxX) { $maxX = $x }
                if ($y -lt $minY) { $minY = $y }; if ($y -gt $maxY) { $maxY = $y }
            }
        }
    }
    return New-Object System.Drawing.Rectangle $minX, $minY, ($maxX - $minX + 1), ($maxY - $minY + 1)
}

# Render, trim and lay out the 16 variants (index = N1|E2|S4|W8 connection mask).
$tiles = @()
for ($mask = 0; $mask -lt 16; $mask++) {
    $bmp = Draw-CableTile $mask
    $trim = Get-TrimRect $bmp
    $tiles += [pscustomobject]@{ Index = $mask; Bitmap = $bmp; Trim = $trim }
}

$AtlasW = 512; $pad = 1; $cx = $pad; $cy = $pad; $rowH = 0
foreach ($t in $tiles) {
    if ($cx + $t.Trim.Width + $pad -gt $AtlasW) { $cx = $pad; $cy += $rowH + $pad; $rowH = 0 }
    $t | Add-Member -NotePropertyName AX -NotePropertyValue $cx
    $t | Add-Member -NotePropertyName AY -NotePropertyValue $cy
    $cx += $t.Trim.Width + $pad
    if ($t.Trim.Height -gt $rowH) { $rowH = $t.Trim.Height }
}
$AtlasH = 1; while ($AtlasH -lt ($cy + $rowH + $pad)) { $AtlasH *= 2 }

$atlas, $ag = New-Canvas $AtlasW $AtlasH
$ag.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
foreach ($t in $tiles) {
    $dst = New-Object System.Drawing.Rectangle $t.AX, $t.AY, $t.Trim.Width, $t.Trim.Height
    $ag.DrawImage($t.Bitmap, $dst, $t.Trim, [System.Drawing.GraphicsUnit]::Pixel)
}
$ag.Dispose()
$pngStream = New-Object System.IO.MemoryStream
$atlas.Save($pngStream, [System.Drawing.Imaging.ImageFormat]::Png)
$pngBytes = $pngStream.ToArray()

# .pack (version 1): "PZPK", version, page count; per page: name, entry count, hasAlpha, entries, PNG length + bytes.
function Write-PzString($w, [string]$s) {
    $b = [Text.Encoding]::ASCII.GetBytes($s)
    $w.Write([int]$b.Length); $w.Write($b)
}
$packPath = Join-Path $Media "texturepacks\$PackName.pack"
$fs = [IO.File]::Create($packPath)
$w = New-Object IO.BinaryWriter $fs
$w.Write([Text.Encoding]::ASCII.GetBytes('PZPK'))
$w.Write([int]1)
$w.Write([int]1)
Write-PzString $w "$($PackName)0"
$w.Write([int]$tiles.Count)
$w.Write([int]1)
foreach ($t in $tiles) {
    Write-PzString $w "$($TileSet)_$($t.Index)"
    foreach ($v in @($t.AX, $t.AY, $t.Trim.Width, $t.Trim.Height, $t.Trim.X, $t.Trim.Y, $TileW, $TileH)) { $w.Write([int]$v) }
}
$w.Write([int]$pngBytes.Length)
$w.Write($pngBytes)
$w.Close()

# .tiles (version 1): "tdef", version, tileset count; strings are '\n'-terminated.
function Write-TdString($w, [string]$s) { $w.Write([Text.Encoding]::ASCII.GetBytes($s + "`n")) }
$tilesPath = Join-Path $Media "$PackName.tiles"
$fs = [IO.File]::Create($tilesPath)
$w = New-Object IO.BinaryWriter $fs
$w.Write([Text.Encoding]::ASCII.GetBytes('tdef'))
$w.Write([int]1)
$w.Write([int]1)
Write-TdString $w $TileSet
Write-TdString $w "$TileSet.png"
$w.Write([int]8)
$w.Write([int]2)
$w.Write([int]1)
$w.Write([int]16)
for ($i = 0; $i -lt 16; $i++) {
    $props = [ordered]@{ 'attachedFloor' = ''; 'CustomName' = 'Extension Cable' }
    $w.Write([int]$props.Count)
    foreach ($k in $props.Keys) { Write-TdString $w $k; Write-TdString $w $props[$k] }
}
$w.Close()

# Inventory icon: coiled orange cord with a plug, drawn large and downscaled.
$big, $g = New-Canvas 128 128
$iconOutline = New-RoundPen (Col 255 46 22 8) 14
$iconCore    = New-RoundPen (Col 255 232 112 26) 8.5
$iconHi      = New-RoundPen (Col 220 255 190 120) 2.5
$coil = New-Object System.Drawing.Drawing2D.GraphicsPath
for ($i = 0; $i -lt 3; $i++) {
    $coil.StartFigure()
    $coil.AddEllipse([single](14 + $i * 7), [single](22 + $i * 5), [single](84 - $i * 14), [single](66 - $i * 10))
}
$tail = New-Object System.Drawing.Drawing2D.GraphicsPath
$tail.AddBezier((PtF 92 70), (PtF 112 84), (PtF 104 104), (PtF 86 108))
foreach ($p in @($coil, $tail)) { $g.DrawPath($iconOutline, $p) }
foreach ($p in @($coil, $tail)) { $g.DrawPath($iconCore, $p) }
foreach ($p in @($coil, $tail)) { $g.DrawPath($iconHi, $p) }
$state = $g.Save()
$g.TranslateTransform(86, 108); $g.RotateTransform(160)
$plugBody = New-Object System.Drawing.SolidBrush (Col 255 214 92 18)
$plugEdge = New-Object System.Drawing.Pen (Col 255 46 22 8), 3.5
$g.FillRectangle($plugBody, 0, -11, 26, 22); $g.DrawRectangle($plugEdge, 0, -11, 26, 22)
$prong = New-Object System.Drawing.SolidBrush (Col 255 200 200 190)
$g.FillRectangle($prong, 26, -8, 12, 4); $g.FillRectangle($prong, 26, 4, 12, 4)
$g.Restore($state)
$g.Dispose()
$icon, $ig = New-Canvas 32 32
$ig.DrawImage($big, (New-Object System.Drawing.Rectangle 0, 0, 32, 32))
$ig.Dispose()
$icon.Save((Join-Path $Media 'textures\Item_PGP_ExtensionCable.png'), [System.Drawing.Imaging.ImageFormat]::Png)

# Preview: a small cable run on an iso floor grid (not shipped with the mod).
$layout = @{ '2,0' = 1; '2,1' = 1; '2,2' = 1; '3,2' = 1; '4,2' = 1; '2,3' = 1; '1,2' = 1; '4,3' = 1; '0,4' = 1 }
$genAt = '2,-1'
$pw = 900; $ph = 560
$prev, $pg = New-Canvas $pw $ph
$pg.Clear((Col 255 52 58 48))
$ox = 420; $oy = -60
$floor = New-Object System.Drawing.SolidBrush (Col 255 120 118 104)
$grid  = New-Object System.Drawing.Pen (Col 255 96 94 82), 1
for ($y = -1; $y -lt 6; $y++) { for ($x = -1; $x -lt 6; $x++) {
    $sx = $ox + ($x - $y) * 64; $sy = $oy + ($x + $y) * 32 + 192
    $pts = [System.Drawing.PointF[]]@((PtF ($sx + 64) $sy), (PtF ($sx + 128) ($sy + 32)), (PtF ($sx + 64) ($sy + 64)), (PtF $sx ($sy + 32)))
    $pg.FillPolygon($floor, $pts); $pg.DrawPolygon($grid, $pts)
} }
$gx, $gy = $genAt.Split(',') | ForEach-Object { [int]$_ }
$gsx = $ox + ($gx - $gy) * 64; $gsy = $oy + ($gx + $gy) * 32 + 192
$genBrush = New-Object System.Drawing.SolidBrush (Col 255 200 60 40)
$pg.FillRectangle($genBrush, $gsx + 40, $gsy - 10, 48, 50)
$pg.DrawString('GEN', (New-Object System.Drawing.Font 'Arial', 11, ([System.Drawing.FontStyle]::Bold)), [System.Drawing.Brushes]::White, $gsx + 47, $gsy + 6)
$occupied = @{}; foreach ($k in $layout.Keys) { $occupied[$k] = $true }; $occupied[$genAt] = $true
foreach ($k in ($layout.Keys | Sort-Object { $a = $_.Split(','); [int]$a[0] + [int]$a[1] })) {
    $x, $y = $k.Split(',') | ForEach-Object { [int]$_ }
    $m = 0
    if ($occupied["$x,$($y-1)"]) { $m = $m -bor 1 }
    if ($occupied["$($x+1),$y"]) { $m = $m -bor 2 }
    if ($occupied["$x,$($y+1)"]) { $m = $m -bor 4 }
    if ($occupied["$($x-1),$y"]) { $m = $m -bor 8 }
    $sx = $ox + ($x - $y) * 64; $sy = $oy + ($x + $y) * 32
    $pg.DrawImage($tiles[$m].Bitmap, [single]$sx, [single]$sy, [single]$TileW, [single]$TileH)
}
$pg.Dispose()
$prev.Save((Join-Path $PSScriptRoot 'preview.png'), [System.Drawing.Imaging.ImageFormat]::Png)

"pack:    $packPath ($((Get-Item $packPath).Length) bytes, atlas ${AtlasW}x${AtlasH})"
"tiles:   $tilesPath"
"icon:    " + (Join-Path $Media 'textures\Item_PGP_ExtensionCable.png')
"preview: " + (Join-Path $PSScriptRoot 'preview.png')
