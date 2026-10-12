# restore-state.ps1 — isolated GitHub runner restore.
# Restores the latest known DevBox snapshot to staging and imports approved
# HOT configuration. Never writes to Lenovo, HP, Z: or tailnet settings.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'find-staged-work.ps1')
. (Join-Path $PSScriptRoot 'drive-data.ps1')
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
    # Legacy project/session records have their own user-profile directory.
    $hotPaths = @($hotPaths) + @(Join-Path $env:USERPROFILE '.local\share\opencode\project')
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

    # New snapshots record every user-created drive root. Locate original drive
    # paths from Restic metadata, not the current runner's drive letter. Legacy
    # snapshots had only Projects and Workspace and still use the older importer.
    $restoreDriveRoot = [string]$env:DEVBOX_FAST_ROOT
    if ([string]::IsNullOrWhiteSpace($restoreDriveRoot)) {
        if ($env:DEVBOX_ISOLATED_TEST -ne '1') {
            Stop-DevBox 'Selected workspace drive absent during restore.'
        }
        $restoreDriveRoot = Split-Path $env:DEVBOX_WSROOT -Parent
    }
    $fullDriveImported = Import-DevBoxDriveRoots -StagingRoot $staging -SnapshotPaths @($latest.paths) -DriveRoot $restoreDriveRoot -WorkspaceRoot $env:DEVBOX_WSROOT
    if (-not $fullDriveImported) {
        Write-DevBox WARN 'Legacy selected-folder snapshot. Only paths present in that older snapshot can be recovered.'
    # Restore the DevBox's actual working directories. The backup script
    # includes these roots; otherwise the next ephemeral runner starts empty.
    # Stage first, then copy into the new runner workspace only.
    foreach ($name in @('Projects', 'Workspace')) {
        $target = Join-Path $env:DEVBOX_WSROOT $name
        $source = Find-DevBoxStagedWork -StagingRoot $staging -Name $name -SnapshotPaths @($latest.paths)
        if (-not $source) {
            # Snapshot manifest claims this root; a missing staged directory
            # means the requested restore FAILED, not an empty workspace.
            $listed = @($latest.paths | Where-Object { [string]$_ -match ('[\\/]' + [regex]::Escape($name) + '$') })
            if ($listed.Count -gt 0) {
                Stop-DevBox "Snapshot lists $name but staged data was not located. Refusing silent data loss."
            }
            Write-DevBox WARN "Snapshot did not contain saved $name directory; older canary-only snapshot is possible."
            continue
        }
        New-DevboxDirectorySafe $target | Out-Null
        foreach ($child in (Get-ChildItem -LiteralPath $source -Force)) {
            Copy-Item -LiteralPath $child.FullName -Destination (Join-Path $target $child.Name) -Recurse -Force -ErrorAction Stop
        }
        Write-DevBox OK "Restored saved DevBox $name into the new ephemeral runner."
    }
    } else {
        Write-DevBox OK 'All user-data roots listed in the selected drive snapshot were imported.'
    }
    # Import only the explicitly staged OpenCode SQLite snapshot after
    # restic finishes and before this runner starts an interactive OpenCode.
    $dbSnapshots = @(Get-ChildItem -LiteralPath $staging -Recurse -File -Filter 'opencode.db' |
        Where-Object { $_.FullName -match '[\\/]+PersistentData[\\/]+OpenCodeHistory[\\/]+opencode\.db$' })
    if ($dbSnapshots.Count -gt 1) {
        Stop-DevBox 'Ambiguous OpenCode DB snapshots: refusing to import arbitrary history.'
    }
    if ($dbSnapshots.Count -eq 1) {
        $targetDb = Join-Path $env:USERPROFILE '.local\share\opencode\opencode.db'
        $recoveryDir = Join-Path $env:DEVBOX_WSROOT 'PersistentData\OpenCodeRecovery'
        & python (Join-Path $PSScriptRoot 'restore-opencode-db.py') $dbSnapshots[0].FullName $targetDb $recoveryDir
        $historyExit = $LASTEXITCODE
        if ($historyExit -eq 3) {
            Write-DevBox WARN 'OpenCode session DB could not replace a locked/inaccessible live database. A verified SQLite recovery copy was retained in PersistentData\OpenCodeRecovery. Do not claim conversations loaded; resolve and import after closing OpenCode.'
        } elseif ($historyExit -ne 0) {
            Stop-DevBox 'OpenCode DB restore and safe recovery both failed. Original Restic snapshot remains untouched.'
        } else {
            Write-DevBox OK 'Restored consistent OpenCode session history SQLite database.'
        }
    } else {
        Write-DevBox INFO 'No saved OpenCode v2 SQLite history in this snapshot.'
    }
} finally {
    Remove-Item -LiteralPath $staging -Force -Recurse -ErrorAction SilentlyContinue
}
Write-DevBox OK "Snapshot $snapshotId safely processed for this temporary GitHub runner."
exit 0
