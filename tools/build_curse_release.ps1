param(
    [string]$Version = "0.6.0",
    [string]$OutputRoot = (Join-Path $PSScriptRoot "..\artifacts\release")
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$outputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
$packageRoot = Join-Path $outputRoot "DreamwayQuestPlanner"
$webRoot = Join-Path $packageRoot "WebApp"
$zipPath = Join-Path $outputRoot ("DreamwayQuestPlanner-{0}.zip" -f $Version)

if (Test-Path $outputRoot) {
    Remove-Item -Path $outputRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $packageRoot | Out-Null
Copy-Item -Path (Join-Path $root "DreamwayQuestPlanner\*") -Destination $packageRoot -Recurse -Force

New-Item -ItemType Directory -Path $webRoot | Out-Null
Copy-Item -Path (Join-Path $root "dreamway.html") -Destination $webRoot
Copy-Item -Path (Join-Path $root "dreamway.ico") -Destination $webRoot
Copy-Item -Path (Join-Path $root "Create a Dreamway Shortcut.txt") -Destination $webRoot
Copy-Item -Path (Join-Path $root "data") -Destination $webRoot -Recurse

$brandingRoot = Join-Path $webRoot "assets\branding"
New-Item -ItemType Directory -Path $brandingRoot -Force | Out-Null
Copy-Item -Path (Join-Path $root "assets\branding\dreamway-favicon-64.png") -Destination $brandingRoot
Copy-Item -Path (Join-Path $root "assets\branding\dreamway-icon-header-128.png") -Destination $brandingRoot
Copy-Item -Path (Join-Path $root "assets\dreamway-maps") -Destination (Join-Path $webRoot "assets") -Recurse

Compress-Archive -Path $packageRoot -DestinationPath $zipPath -CompressionLevel Optimal

$zip = Get-Item $zipPath
$hash = Get-FileHash -Path $zipPath -Algorithm SHA256
Write-Output ("Built {0}" -f $zip.FullName)
Write-Output ("Size: {0:N2} MB" -f ($zip.Length / 1MB))
Write-Output ("SHA256: {0}" -f $hash.Hash)
