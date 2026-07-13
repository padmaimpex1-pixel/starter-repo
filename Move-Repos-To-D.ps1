param(
    [string[]]$SourceRoots = @(
        "C:\Users\$env:USERNAME\source\repos",
        "C:\Users\$env:USERNAME\Documents\GitHub",
        "C:\Users\$env:USERNAME\Desktop"
    ),
    [string]$DestinationRoot = "D:\GitRepos",
    [double]$TargetFreeGB = 50,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

function Get-FreeGB([string]$DriveLetter) {
    $d = Get-PSDrive -Name $DriveLetter
    return [math]::Round($d.Free / 1GB, 2)
}

function Get-FreeBytes([string]$DriveLetter) {
    $d = Get-PSDrive -Name $DriveLetter
    return [int64]$d.Free
}

function Get-DirSizeBytes([string]$Path) {
    $sum = (Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sum) { return 0 }
    return [int64]$sum
}

function Resolve-UniquePath([string]$BasePath) {
    if (-not (Test-Path -LiteralPath $BasePath)) { return $BasePath }
    $i = 1
    while ($true) {
        $candidate = "$BasePath-$i"
        if (-not (Test-Path -LiteralPath $candidate)) { return $candidate }
        $i++
    }
}

if (-not (Test-Path -LiteralPath $DestinationRoot)) {
    if ($WhatIf) {
        Write-Host "[WhatIf] Would create $DestinationRoot"
    } else {
        New-Item -ItemType Directory -Path $DestinationRoot | Out-Null
    }
}

$currentFreeC = Get-FreeGB "C"
Write-Host "Current free space on C: $currentFreeC GB"
Write-Host "Target free space on C:  $TargetFreeGB GB"

if ($currentFreeC -ge $TargetFreeGB) {
    Write-Host "C: already has enough free space. Nothing to do."
    exit 0
}

# Find git repos (.git folder) under source roots
$repos = @()
foreach ($root in $SourceRoots) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    $found = Get-ChildItem -LiteralPath $root -Directory -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName ".git") }
    $repos += $found
}

$repos = $repos | Sort-Object -Property FullName -Unique

if (-not $repos -or $repos.Count -eq 0) {
    Write-Host "No git repos found in SourceRoots."
    exit 0
}

# Size repos and move largest first
$repoInfo = @(foreach ($r in $repos) {
    $size = Get-DirSizeBytes $r.FullName
    [pscustomobject]@{
        Path = $r.FullName
        Name = $r.Name
        SizeBytes = $size
        SizeGB = [math]::Round($size / 1GB, 2)
    }
}) | Sort-Object -Property SizeBytes -Descending

$moved = @()

foreach ($repo in $repoInfo) {
    $currentFreeC = Get-FreeGB "C"
    if ($currentFreeC -ge $TargetFreeGB) { break }

    $freeDBytes = Get-FreeBytes "D"
    if ($freeDBytes -lt ($repo.SizeBytes + 1GB)) {
        Write-Warning "Skipping '$($repo.Path)' (not enough free space on D:)."
        continue
    }

    $dest = Resolve-UniquePath (Join-Path $DestinationRoot $repo.Name)
    Write-Host ("`nRepo: {0}`nSize: {1} GB`nFrom: {2}`nTo:   {3}" -f $repo.Name, $repo.SizeGB, $repo.Path, $dest)

    if ($WhatIf) {
        Write-Host "[WhatIf] Would move repo."
        $moved += $repo
        continue
    }

    New-Item -ItemType Directory -Path $dest | Out-Null

    # Robust cross-drive move (copy + remove source files)
    $rc = Start-Process -FilePath "robocopy.exe" -ArgumentList @(
        $repo.Path, $dest, "/E", "/MOVE", "/R:2", "/W:2", "/NFL", "/NDL", "/NP"
    ) -NoNewWindow -Wait -PassThru

    # Robocopy exit codes < 8 are success/warnings
    if ($rc.ExitCode -ge 8) {
        Write-Warning "Robocopy failed for '$($repo.Path)' (exit code $($rc.ExitCode))."
        continue
    }

    # Remove leftover empty source folder
    if (Test-Path -LiteralPath $repo.Path) {
        try {
            Remove-Item -LiteralPath $repo.Path -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Warning "Could not remove leftover source folder: $($repo.Path)"
        }
    }

    $moved += $repo
    Write-Host ("Moved. Free space on C: {0} GB" -f (Get-FreeGB "C"))
}

Write-Host "`nDone."
Write-Host ("Final free space on C: {0} GB" -f (Get-FreeGB "C"))
Write-Host ("Repos moved: {0}" -f $moved.Count)
