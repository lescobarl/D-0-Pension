# Upscale store screenshots from logical (360x640, captured at dpr 3.0) to
# physical 1080x1920 (exact 3x integer scale, 9:16).
#
# Rationale: this Flutter version's golden comparator captures at logical
# paintBounds only (flutter_test/lib/src/_matchers_io.dart, layer.toImage
# without pixelRatio). The natural phone UI at dpr 3.0 is 360x640 logical,
# which on a 1080x1920 physical device renders each logical pixel as an exact
# 3x3 physical block. A 3x integer upscale therefore reproduces the physical
# 1080x1920 output deterministically.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/upscale_screenshots.ps1

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Join-Path $PSScriptRoot '..'
$srcDir = Join-Path (Join-Path $root 'test') 'store_screenshots'
$outDir = Join-Path $root 'capturas_tienda'

if (-not (Test-Path $srcDir)) {
    Write-Error "Source dir not found: $srcDir"
}

# Ensure output dir exists.
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$srcWidth  = 360
$srcHeight = 640
$outWidth  = 1080
$outHeight = 1920

Get-ChildItem -Path $srcDir -Filter '*.png' | ForEach-Object {
    $src = [System.Drawing.Image]::FromFile($_.FullName)
    try {
        if ($src.Width -ne $srcWidth -or $src.Height -ne $srcHeight) {
            Write-Warning "$($_.Name): unexpected source size $($src.Width)x$($src.Height) (expected ${srcWidth}x${srcHeight}); skipping."
            return
        }
        $bmp = New-Object System.Drawing.Bitmap($outWidth, $outHeight)
        try {
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            try {
                $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                $g.DrawImage($src, 0, 0, $outWidth, $outHeight)
            } finally {
                $g.Dispose()
            }
            $dest = Join-Path $outDir $_.Name
            $bmp.Save($dest, [System.Drawing.Imaging.ImageFormat]::Png)
            Write-Host "OK: $($_.Name) -> ${outWidth}x${outHeight} -> $dest"
        } finally {
            $bmp.Dispose()
        }
    } finally {
        $src.Dispose()
    }
}
