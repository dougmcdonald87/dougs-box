# restore-state.ps1 — isolated GitHub runner restore.
# Restores the latest known DevBox snapshot to staging and imports approved
# HOT configuration. Never writes to Lenovo, HP, Z: or tailnet settings.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'common.ps1')
Write-Step 'restore-state'

if ([string]::IsNullOrWhiteSpace($env:RESTIC_PASSWORD)) {
    Stop-DevBox 'RESTIC_PASSWORD missing at restore; no automatic restore permitted.'
}
$restic = $env:DEVBOX_RESTIC_EXE
if ([string]::IsNullOrWhiteSpace($restic) -or -not (Test-Path -LiteralPath $restic -PathType Leaf)) {
    Stop-DevBox 'Restic executable unavailable; run persistence setup first.'
}
$persistenceFile = Join-Path $env:DEVBOX_CONTROL_PATH 'persistence.json'
if (-not (Test-Path -LiteralPath $persistenceFile -PathType Leaf)) {
    Stop-DevBox 'Dedicated DevBox persistence metadata missing.'
}
$persist = Get-Content -LiteralPath $persistenceFile -Raw | ConvertFrom-Json
$repo = [string]$persist.repoUrl
if (-not (Test-DevBoxRepoDestination -Repo $repo)) {
    Stop-DevBox 'Refusing restore: repository is not the dedicated Lenovo endpoint or an approved disposable CI test repository.'
}

# A brand-new, dedicated repository is initialized only by the first verified
# backup. A wrong password or unreachable server must NOT masquerade as empty.
& $restic --repo $repo cat config 2>$null | Out-Null
$repoStatus = $LASTEXITCODE
if ($repoStatus -eq 10) {
    Write-DevBox INFO 'First session: dedicated DevBox repository does not yet exist; restore is not required.'
    exit 0
}
if ($repoStatus -ne 0) {
    Stop-DevBox "Restic repository check failed (exit $repoStatus). Verify backup password and storage connection before proceeding."
}

$rawSnapshots = (& $restic --repo $repo snapshots --json 2>&1 | Out-String)
$snapshotsStatus = $LASTEXITCODE
if ($snapshotsStatus -ne 0) {
    Stop-DevBox "Restic snapshots listing failed (exit $snapshotsStatus)."
}
try {
    $entries = @($rawSnapshots | ConvertFrom-Json -ErrorAction Stop)
} catch {
    Stop-DevBox 'Restic snapshots response was not valid JSON.'
}
if ($entries.Count -eq 0) {
    Write-DevBox INFO 'Initialized DevBox repository contains no snapshots; nothing to restore.'
    exit 0
}
$latest = $entries | Sort-Object { [DateTime]::Parse([string]$_.time) } -Descending | Select-Object -First 1
$snapshotId = [string]$latest.id
if ([string]::IsNullOrWhiteSpace($snapshotId)) {
    Stop-DevBox 'Latest snapshot does not contain an ID.'
}

# Check the total snapshot size before hydrating onto an ephemeral runner.
$cfgFile = Join-Path $PSScriptRoot '..\config\devbox.json'
$cfg = if (Test-Path -LiteralPath $cfgFile) { Get-Content -LiteralPath $cfgFile -Raw | ConvertFrom-Json } else { $null }
$limitGiB = if ($cfg -and $cfg.auto_restore_max_gib) { [double]$cfg.auto_restore_max_gib } else { 3.0 }
$statsRaw = (& $restic --repo $repo stats $snapshotId --mode restore-size --json 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) {
    Stop-DevBox 'Could not measure snapshot size. Refusing an unbounded automatic restore.'
}
try {
    $stats = $statsRaw | ConvertFrom-Json -ErrorAction Stop
} catch {
    Stop-DevBox 'Snapshot size output was malformed. Refusing unbounded restore.'
}
if ($null -eq $stats.total_size) {
    Stop-DevBox 'Snapshot size could not be determined.'
}
$sizeGiB = [double]$stats.total_size / 1073741824
if ($sizeGiB -gt $limitGiB) {
    Stop-DevBox "Latest snapshot is $([math]::Round($sizeGiB,2)) GiB; above automatic restore cap $limitGiB GiB. Review before restoring."
}
$tempDir = Join-Path $env:DEVBOX_WSROOT 'Temp'
$staging = New-DevboxDirectorySafe (Join-Path $tempDir ('restore-' + [guid]::NewGuid().ToString('N')))
try {
    & $restic --repo $repo restore $snapshotId --target $staging | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Stop-DevBox "Snapshot restore into staging failed ($snapshotId)."
    }

    # Imported files apply to this new ephemeral GitHub runner only. Restic's
    # Windows staging layout may include a drive-letter directory.
    $hotPaths = if ($cfg -and $cfg.hot_paths) { @($cfg.hot_paths) } else {
        @("$env:USERPROFILE\.config\opencode",
          "$env:USERPROFILE\AGENTS.md",
          "$env:USERPROFILE\Documents\DevBox-Notes")
    }
    foreach ($rawPath in $hotPaths) {
        $target = [Environment]::ExpandEnvironmentVariables([string]$rawPath)
        if (-not $target.StartsWith($env:USERPROFILE + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-DevBox WARN 'Ignoring HOT path outside ephemeral runner user profile.'
            continue
        }
        $drive = $target.Substring(0,1)
        $tail = $target.Substring(3)
        $candidates = @(
            (Join-Path $staging (Join-Path $drive $tail)),
            (Join-Path $staging $tail)
        )
        $source = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (-not $source) {
            Write-DevBox INFO "Saved HOT path not found in snapshot: $target"
            continue
        }
        if (Test-Path -LiteralPath $source -PathType Container) {
            New-DevboxDirectorySafe $target | Out-Null
            foreach ($child in (Get-ChildItem -LiteralPath $source -Force)) {
                Copy-Item -LiteralPath $child.FullName -Destination (Join-Path $target $child.Name) -Recurse -Force -ErrorAction Stop
            }
        } else {
            New-DevboxDirectorySafe (Split-Path -Path $target -Parent) | Out-Null
            Copy-Item -LiteralPath $source -Destination $target -Force -ErrorAction Stop
        }
        Write-DevBox OK "HOT state restored into runner: $target"
    }

    # Restore the DevBox's actual working directories. The backup script
    # includes these roots; otherwise the next ephemeral runner starts empty.
    # Stage first, then copy into the new runner workspace only.
    foreach ($name in @('Projects', 'Workspace')) {
        $target = Join-Path $env:DEVBOX_WSROOT $name
        $driveLetter = $target.Substring(0, 1)
        $tail = $target.Substring(3)
        $candidates = @(
            (Join-Path $staging (Join-Path $driveLetter $tail)),
            (Join-Path $staging $tail)
        )
        $source = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Container } | Select-Object -First 1
        if (-not $source) {
            Write-DevBox WARN "Snapshot did not contain saved $name directory; older canary-only snapshot is possible."
            continue
        }
        New-DevboxDirectorySafe $target | Out-Null
        foreach ($child in (Get-ChildItem -LiteralPath $source -Force)) {
            Copy-Item -LiteralPath $child.FullName -Destination (Join-Path $target $child.Name) -Recurse -Force -ErrorAction Stop
        }
        Write-DevBox OK "Restored saved DevBox $name into the new ephemeral runner."
    }
} finally {
    Remove-Item -LiteralPath $staging -Force -Recurse -ErrorAction SilentlyContinue
}
Write-DevBox OK "Snapshot $snapshotId safely processed for this temporary GitHub runner."
exit 0
