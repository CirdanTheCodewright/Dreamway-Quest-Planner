param(
    [string]$Source = "assets\branding\dreamway-icon-generated-source.png"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$sourcePath = [System.IO.Path]::GetFullPath((Join-Path $root $Source))
$brandingDir = Join-Path $root "assets\branding"
$addonMediaDir = Join-Path $root "DreamwayQuestPlanner\Media"

[System.IO.Directory]::CreateDirectory($brandingDir) | Out-Null
[System.IO.Directory]::CreateDirectory($addonMediaDir) | Out-Null

function New-TransparentMaster {
    param(
        [string]$InputPath,
        [string]$OutputPath
    )

    $sourceBitmap = [System.Drawing.Bitmap]::FromFile($InputPath)
    try {
        $bitmap = New-Object System.Drawing.Bitmap(
            $sourceBitmap.Width,
            $sourceBitmap.Height,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
        )
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.DrawImageUnscaled($sourceBitmap, 0, 0)
        }
        finally {
            $graphics.Dispose()
        }

        $rect = New-Object System.Drawing.Rectangle(0, 0, $bitmap.Width, $bitmap.Height)
        $data = $bitmap.LockBits(
            $rect,
            [System.Drawing.Imaging.ImageLockMode]::ReadWrite,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
        )
        try {
            $byteCount = [Math]::Abs($data.Stride) * $bitmap.Height
            $pixels = New-Object byte[] $byteCount
            [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $pixels, 0, $byteCount)

            for ($y = 0; $y -lt $bitmap.Height; $y++) {
                $row = $y * $data.Stride
                for ($x = 0; $x -lt $bitmap.Width; $x++) {
                    $offset = $row + ($x * 4)
                    $blue = [int]$pixels[$offset]
                    $green = [int]$pixels[$offset + 1]
                    $red = [int]$pixels[$offset + 2]
                    $maximum = [Math]::Max($red, [Math]::Max($green, $blue))
                    $minimum = [Math]::Min($red, [Math]::Min($green, $blue))
                    $chroma = $maximum - $minimum

                    if ($maximum -gt 140) {
                        $alpha = [Math]::Max(0, [Math]::Min(255, ($chroma - 3) * 8))
                        if ($alpha -lt 72) {
                            $alpha = 0
                        }
                        $pixels[$offset + 3] = [byte]$alpha
                        if ($alpha -eq 0) {
                            $pixels[$offset] = 0
                            $pixels[$offset + 1] = 0
                            $pixels[$offset + 2] = 0
                        }
                        elseif ($chroma -lt 100) {
                            $pixels[$offset] = 0
                            $pixels[$offset + 1] = [byte][Math]::Max($green, 220)
                            $pixels[$offset + 2] = [byte][Math]::Min($red, [int]($green * 0.45))
                        }
                    }
                    else {
                        $pixels[$offset + 3] = 255
                    }
                }
            }

            [System.Runtime.InteropServices.Marshal]::Copy($pixels, 0, $data.Scan0, $byteCount)
        }
        finally {
            $bitmap.UnlockBits($data)
        }

        $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $bitmap.Dispose()
    }
    finally {
        $sourceBitmap.Dispose()
    }
}

function Resize-Png {
    param(
        [string]$InputPath,
        [string]$OutputPath,
        [int]$Size
    )

    $sourceBitmap = [System.Drawing.Bitmap]::FromFile($InputPath)
    try {
        $bitmap = New-Object System.Drawing.Bitmap(
            $Size,
            $Size,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
        )
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
            $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $graphics.DrawImage(
                $sourceBitmap,
                (New-Object System.Drawing.Rectangle(0, 0, $Size, $Size)),
                0,
                0,
                $sourceBitmap.Width,
                $sourceBitmap.Height,
                [System.Drawing.GraphicsUnit]::Pixel
            )
        }
        finally {
            $graphics.Dispose()
        }

        $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $bitmap.Dispose()
    }
    finally {
        $sourceBitmap.Dispose()
    }
}

function Write-Tga {
    param(
        [string]$InputPath,
        [string]$OutputPath
    )

    $bitmap = [System.Drawing.Bitmap]::FromFile($InputPath)
    try {
        $stream = [System.IO.File]::Open($OutputPath, [System.IO.FileMode]::Create)
        $writer = New-Object System.IO.BinaryWriter($stream)
        try {
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([byte]2)
            $writer.Write((New-Object byte[] 5))
            $writer.Write([uint16]0)
            $writer.Write([uint16]0)
            $writer.Write([uint16]$bitmap.Width)
            $writer.Write([uint16]$bitmap.Height)
            $writer.Write([byte]32)
            $writer.Write([byte]8)

            for ($y = $bitmap.Height - 1; $y -ge 0; $y--) {
                for ($x = 0; $x -lt $bitmap.Width; $x++) {
                    $pixel = $bitmap.GetPixel($x, $y)
                    $writer.Write([byte]$pixel.B)
                    $writer.Write([byte]$pixel.G)
                    $writer.Write([byte]$pixel.R)
                    $writer.Write([byte]$pixel.A)
                }
            }
        }
        finally {
            $writer.Dispose()
            $stream.Dispose()
        }
    }
    finally {
        $bitmap.Dispose()
    }
}

$masterPath = Join-Path $brandingDir "dreamway-icon-master.png"
New-TransparentMaster -InputPath $sourcePath -OutputPath $masterPath

foreach ($size in 400, 256, 128, 64, 32) {
    Resize-Png `
        -InputPath $masterPath `
        -OutputPath (Join-Path $brandingDir "dreamway-icon-$size.png") `
        -Size $size
}

Copy-Item `
    -LiteralPath (Join-Path $brandingDir "dreamway-icon-64.png") `
    -Destination (Join-Path $brandingDir "dreamway-favicon-64.png") `
    -Force

Write-Tga `
    -InputPath (Join-Path $brandingDir "dreamway-icon-64.png") `
    -OutputPath (Join-Path $addonMediaDir "DreamwayIcon.tga")

Write-Host "Dreamway branding assets generated in $brandingDir and $addonMediaDir"
