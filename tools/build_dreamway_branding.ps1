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
            $keyPixel = $sourceBitmap.GetPixel(0, 0)
            $keyBlue = [int]$keyPixel.B
            $keyGreen = [int]$keyPixel.G
            $keyRed = [int]$keyPixel.R
            $isMagentaKey = (
                $keyRed -gt 200 -and
                $keyBlue -gt 200 -and
                $keyGreen -lt 80
            )

            for ($y = 0; $y -lt $bitmap.Height; $y++) {
                $row = $y * $data.Stride
                for ($x = 0; $x -lt $bitmap.Width; $x++) {
                    $offset = $row + ($x * 4)
                    $blue = [int]$pixels[$offset]
                    $green = [int]$pixels[$offset + 1]
                    $red = [int]$pixels[$offset + 2]
                    if ($isMagentaKey) {
                        # The subject is green stone with a black contour, so
                        # any distinctly magenta-dominant pixel is background
                        # or key-colored antialiasing. Drop those pixels and let
                        # the resize pass antialias the clean contour.
                        if (
                            $red -gt ($green + 20) -and
                            $blue -gt ($green + 20)
                        ) {
                            $alpha = 0
                        }
                        else {
                            $alpha = 255
                        }
                    }
                    else {
                        $redDelta = $red - $keyRed
                        $greenDelta = $green - $keyGreen
                        $blueDelta = $blue - $keyBlue
                        $distance = [Math]::Sqrt(
                            ($redDelta * $redDelta) +
                            ($greenDelta * $greenDelta) +
                            ($blueDelta * $blueDelta)
                        )
                        if ($distance -le 8.0) {
                            $alpha = 0
                        }
                        elseif ($distance -ge 110.0) {
                            $alpha = 255
                        }
                        else {
                            $progress = ($distance - 8.0) / 102.0
                            $progress = $progress * $progress * (3.0 - (2.0 * $progress))
                            $alpha = [int][Math]::Round(255.0 * $progress)
                        }
                    }

                    if ($alpha -lt 16) {
                        $alpha = 0
                    }

                    $pixels[$offset + 3] = [byte]$alpha
                    if ($alpha -eq 0) {
                        $pixels[$offset] = 0
                        $pixels[$offset + 1] = 0
                        $pixels[$offset + 2] = 0
                    }
                    elseif ($alpha -lt 255) {
                        $opacity = $alpha / 255.0
                        $inverseOpacity = 1.0 - $opacity
                        $pixels[$offset] = [byte][Math]::Max(
                            0,
                            [Math]::Min(255, [Math]::Round(
                                ($blue - ($inverseOpacity * $keyBlue)) / $opacity
                            ))
                        )
                        $pixels[$offset + 1] = [byte][Math]::Max(
                            0,
                            [Math]::Min(255, [Math]::Round(
                                ($green - ($inverseOpacity * $keyGreen)) / $opacity
                            ))
                        )
                        $pixels[$offset + 2] = [byte][Math]::Max(
                            0,
                            [Math]::Min(255, [Math]::Round(
                                ($red - ($inverseOpacity * $keyRed)) / $opacity
                            ))
                        )
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

function New-PaddedSquare {
    param(
        [string]$InputPath,
        [string]$OutputPath,
        [int]$Size,
        [int]$ContentSize
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
            $graphics.Clear([System.Drawing.Color]::Transparent)
            $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
            $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $offset = [int][Math]::Floor(($Size - $ContentSize) / 2)
            $graphics.DrawImage(
                $sourceBitmap,
                (New-Object System.Drawing.Rectangle($offset, $offset, $ContentSize, $ContentSize)),
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

function New-TightSquareCrop {
    param(
        [string]$InputPath,
        [string]$OutputPath
    )

    $sourceBitmap = [System.Drawing.Bitmap]::FromFile($InputPath)
    try {
        $minX = $sourceBitmap.Width
        $minY = $sourceBitmap.Height
        $maxX = -1
        $maxY = -1
        for ($y = 0; $y -lt $sourceBitmap.Height; $y++) {
            for ($x = 0; $x -lt $sourceBitmap.Width; $x++) {
                if ($sourceBitmap.GetPixel($x, $y).A -le 8) {
                    continue
                }
                $minX = [Math]::Min($minX, $x)
                $minY = [Math]::Min($minY, $y)
                $maxX = [Math]::Max($maxX, $x)
                $maxY = [Math]::Max($maxY, $y)
            }
        }
        if ($maxX -lt $minX -or $maxY -lt $minY) {
            throw "No visible pixels found in $InputPath"
        }

        $contentWidth = $maxX - $minX + 1
        $contentHeight = $maxY - $minY + 1
        $side = [Math]::Min(
            [Math]::Min($sourceBitmap.Width, $sourceBitmap.Height),
            [Math]::Ceiling([Math]::Max($contentWidth, $contentHeight) * 1.03)
        )
        $centerX = ($minX + $maxX) / 2.0
        $centerY = ($minY + $maxY) / 2.0
        $sourceX = [Math]::Max(0, [Math]::Min(
            $sourceBitmap.Width - $side,
            [Math]::Round($centerX - ($side / 2.0))
        ))
        $sourceY = [Math]::Max(0, [Math]::Min(
            $sourceBitmap.Height - $side,
            [Math]::Round($centerY - ($side / 2.0))
        ))

        $bitmap = New-Object System.Drawing.Bitmap(
            $side,
            $side,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
        )
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
            $graphics.DrawImage(
                $sourceBitmap,
                (New-Object System.Drawing.Rectangle(0, 0, $side, $side)),
                $sourceX,
                $sourceY,
                $side,
                $side,
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

function New-ToggleStateTga {
    param(
        [string]$OutputPath,
        [ValidateSet("Questie", "Dreamway")]
        [string]$SelectedSide
    )

    $temporaryPath = Join-Path ([System.IO.Path]::GetTempPath()) ("dreamway-toggle-" + [System.Guid]::NewGuid().ToString("N") + ".png")
    $bitmap = New-Object System.Drawing.Bitmap(
        248,
        40,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.Clear([System.Drawing.Color]::Transparent)
            $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $outerPath = New-Object System.Drawing.Drawing2D.GraphicsPath
            $innerPath = New-Object System.Drawing.Drawing2D.GraphicsPath
            try {
                $outerPath.AddLine(20, 0.5, 228, 0.5)
                $outerPath.AddArc(208.5, 0.5, 39, 39, -90, 180)
                $outerPath.AddLine(228, 39.5, 20, 39.5)
                $outerPath.AddArc(0.5, 0.5, 39, 39, 90, 180)
                $outerPath.CloseFigure()

                $innerPath.AddLine(20, 4.5, 228, 4.5)
                $innerPath.AddArc(212.5, 4.5, 31, 31, -90, 180)
                $innerPath.AddLine(228, 35.5, 20, 35.5)
                $innerPath.AddArc(4.5, 4.5, 31, 31, 90, 180)
                $innerPath.CloseFigure()

                $grey = [System.Drawing.Color]::FromArgb(220, 128, 128, 128)
                $selected = if ($SelectedSide -eq "Questie") {
                    [System.Drawing.Color]::FromArgb(250, 235, 51, 36)
                }
                else {
                    [System.Drawing.Color]::FromArgb(250, 64, 224, 107)
                }
                $outerBrush = New-Object System.Drawing.SolidBrush($grey)
                $selectedBrush = New-Object System.Drawing.SolidBrush($selected)
                $innerBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Transparent)
                try {
                    $graphics.FillPath($outerBrush, $outerPath)
                    $selectedBounds = if ($SelectedSide -eq "Questie") {
                        New-Object System.Drawing.RectangleF(0, 0, 124, 40)
                    }
                    else {
                        New-Object System.Drawing.RectangleF(124, 0, 124, 40)
                    }
                    $graphics.SetClip($selectedBounds)
                    $graphics.FillPath($selectedBrush, $outerPath)
                    $graphics.ResetClip()
                    $graphics.FillPath($innerBrush, $innerPath)
                    $graphics.FillRectangle($selectedBrush, 122.5, 0.5, 3, 39)
                }
                finally {
                    $outerBrush.Dispose()
                    $selectedBrush.Dispose()
                    $innerBrush.Dispose()
                }
            }
            finally {
                $outerPath.Dispose()
                $innerPath.Dispose()
            }
        }
        finally {
            $graphics.Dispose()
        }
        $bitmap.Save($temporaryPath, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $bitmap.Dispose()
    }

    try {
        Write-Tga -InputPath $temporaryPath -OutputPath $OutputPath
    }
    finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
}

function Write-MultiResolutionIco {
    param(
        [string]$InputPath,
        [string]$OutputPath,
        [int[]]$Sizes
    )

    $temporaryDir = Join-Path (
        [System.IO.Path]::GetTempPath()
    ) ("dreamway-ico-" + [System.Guid]::NewGuid().ToString("N"))
    [System.IO.Directory]::CreateDirectory($temporaryDir) | Out-Null
    try {
        $images = @()
        foreach ($size in $Sizes) {
            $pngPath = Join-Path $temporaryDir "dreamway-$size.png"
            Resize-Png -InputPath $InputPath -OutputPath $pngPath -Size $size
            $images += @{
                Size = $size
                Bytes = [System.IO.File]::ReadAllBytes($pngPath)
            }
        }

        $stream = [System.IO.File]::Open($OutputPath, [System.IO.FileMode]::Create)
        $writer = New-Object System.IO.BinaryWriter($stream)
        try {
            $writer.Write([uint16]0)
            $writer.Write([uint16]1)
            $writer.Write([uint16]$images.Count)

            $offset = 6 + (16 * $images.Count)
            foreach ($image in $images) {
                $dimension = if ($image.Size -ge 256) { 0 } else { $image.Size }
                $writer.Write([byte]$dimension)
                $writer.Write([byte]$dimension)
                $writer.Write([byte]0)
                $writer.Write([byte]0)
                $writer.Write([uint16]1)
                $writer.Write([uint16]32)
                $writer.Write([uint32]$image.Bytes.Length)
                $writer.Write([uint32]$offset)
                $offset += $image.Bytes.Length
            }

            foreach ($image in $images) {
                $writer.Write($image.Bytes)
            }
        }
        finally {
            $writer.Dispose()
            $stream.Dispose()
        }
    }
    finally {
        if ([System.IO.Directory]::Exists($temporaryDir)) {
            [System.IO.Directory]::Delete($temporaryDir, $true)
        }
    }
}

$masterPath = Join-Path $brandingDir "dreamway-icon-master.png"
New-TransparentMaster -InputPath $sourcePath -OutputPath $masterPath
$headerMasterPath = Join-Path $brandingDir "dreamway-icon-header-master.png"
New-TightSquareCrop -InputPath $masterPath -OutputPath $headerMasterPath

foreach ($size in 400, 256, 128, 64, 32) {
    Resize-Png `
        -InputPath $masterPath `
        -OutputPath (Join-Path $brandingDir "dreamway-icon-$size.png") `
        -Size $size
}

foreach ($size in 128, 64) {
    Resize-Png `
        -InputPath $headerMasterPath `
        -OutputPath (Join-Path $brandingDir "dreamway-icon-header-$size.png") `
        -Size $size
}

Copy-Item `
    -LiteralPath (Join-Path $brandingDir "dreamway-icon-header-64.png") `
    -Destination (Join-Path $brandingDir "dreamway-favicon-64.png") `
    -Force

Write-Tga `
    -InputPath (Join-Path $brandingDir "dreamway-icon-header-64.png") `
    -OutputPath (Join-Path $addonMediaDir "DreamwayIcon.tga")

$minimapPngPath = Join-Path $brandingDir "dreamway-icon-minimap-64.png"
New-PaddedSquare `
    -InputPath (Join-Path $brandingDir "dreamway-icon-header-64.png") `
    -OutputPath $minimapPngPath `
    -Size 64 `
    -ContentSize 52
Write-Tga `
    -InputPath $minimapPngPath `
    -OutputPath (Join-Path $addonMediaDir "DreamwayMinimapIcon.tga")

New-ToggleStateTga `
    -OutputPath (Join-Path $addonMediaDir "DreamwayToggleQuestie.tga") `
    -SelectedSide "Questie"
New-ToggleStateTga `
    -OutputPath (Join-Path $addonMediaDir "DreamwayToggleDreamway.tga") `
    -SelectedSide "Dreamway"

Write-MultiResolutionIco `
    -InputPath $headerMasterPath `
    -OutputPath (Join-Path $root "dreamway.ico") `
    -Sizes 16, 24, 32, 48, 64, 128, 256

Write-Host "Dreamway branding assets generated in $brandingDir and $addonMediaDir"
