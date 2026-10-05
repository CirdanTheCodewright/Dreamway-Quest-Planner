[CmdletBinding()]
param(
    [string]$Branch = "master",
    [string]$DatabaseBranch = "master",
    [switch]$RebuildWebApp
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Command failed with exit code $LASTEXITCODE."
    }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git is not installed or is not available on PATH."
}

foreach ($dependency in @(
    @{ Name = "Questie"; Branch = $Branch },
    @{ Name = "QuestieDB"; Branch = $DatabaseBranch }
)) {
    $dependencyBranch = $dependency.Branch
    $questieDir = Join-Path $repoRoot $dependency.Name
    $questieUrl = "https://github.com/Questie/$($dependency.Name).git"
    $safeDirectory = $questieDir.Replace("\", "/")
    Write-Host "Updating $($dependency.Name)..."
    if (-not (Test-Path (Join-Path $questieDir ".git"))) {
        if ((Test-Path $questieDir) -and (Get-ChildItem $questieDir -Force | Select-Object -First 1)) {
            throw "$($dependency.Name) exists but is not a Git checkout: $questieDir"
        }

        Write-Host "Cloning $($dependency.Name) '$dependencyBranch'..."
        Invoke-CheckedCommand git @(
            "clone",
            "--depth", "1",
            "--branch", $dependencyBranch,
            "--single-branch",
            $questieUrl,
            $questieDir
        )
    } else {
        $gitPrefix = @(
            "-c", "safe.directory=$safeDirectory",
            "-C", $questieDir
        )

        $remoteUrl = (& git @gitPrefix remote get-url origin).Trim()
        if ($LASTEXITCODE -ne 0) {
            throw "Could not read the $($dependency.Name) origin remote."
        }
        if ($remoteUrl.TrimEnd("/") -ne $questieUrl.TrimEnd("/")) {
            throw "$($dependency.Name) origin is '$remoteUrl', not the expected '$questieUrl'."
        }

        $changes = @(& git @gitPrefix status --porcelain --untracked-files=all)
        if ($LASTEXITCODE -ne 0) {
            throw "Could not inspect the $($dependency.Name) working tree."
        }
        if ($changes.Count -gt 0) {
            throw "$($dependency.Name) has local changes. Commit, stash, or remove them before updating."
        }

        $before = (& git @gitPrefix rev-parse HEAD).Trim()
        Write-Host "Fetching $($dependency.Name) '$dependencyBranch'..."
        Invoke-CheckedCommand git (@($gitPrefix) + @(
            "fetch",
            "--depth", "1",
            "origin",
            $dependencyBranch
        ))
        $latest = (& git @gitPrefix rev-parse FETCH_HEAD).Trim()

        if ($before -eq $latest) {
            Write-Host "$($dependency.Name) is already current at $($latest.Substring(0, 8))."
        } else {
            Invoke-CheckedCommand git (@($gitPrefix) + @(
                "checkout",
                "-B", $dependencyBranch,
                "FETCH_HEAD"
            ))
            Write-Host "Updated $($dependency.Name): $($before.Substring(0, 8)) -> $($latest.Substring(0, 8))."
        }
    }

    $questieGit = @(
        "-c", "safe.directory=$safeDirectory",
        "-C", $questieDir
    )
    $summary = (& git @questieGit log -1 --date=iso-strict --format="%h  %cd  %s").Trim()
    Write-Host "Current $($dependency.Name) source: $summary"
}

if ($RebuildWebApp) {
    $generator = Join-Path $PSScriptRoot "build_dreamway_webapp.py"
    $pyLauncher = Get-Command py -ErrorAction SilentlyContinue
    $python = Get-Command python -ErrorAction SilentlyContinue

    Write-Host "Regenerating Dreamway data and web app..."
    if ($pyLauncher) {
        Invoke-CheckedCommand $pyLauncher.Source @("-3", $generator)
    } elseif ($python) {
        Invoke-CheckedCommand $python.Source @($generator)
    } else {
        throw "Questie was updated, but Python was not found. Run tools/build_dreamway_webapp.py manually."
    }
}
