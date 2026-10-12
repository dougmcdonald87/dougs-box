# Portable scope for selected Windows workspace volume; never a full-system image.
Set-StrictMode -Version Latest

function Get-DevBoxDriveRoots {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DriveRoot,
          [Parameter(Mandatory)][string]$WorkspaceRoot)
    if ($DriveRoot -match '^[A-Za-z]:$') { $DriveRoot += '\' }
    if (-not (Test-Path -LiteralPath $DriveRoot -PathType Container)) {
        throw "Selected data drive is not accessible: $DriveRoot"
    }
    $base = [IO.Path]::GetFullPath($DriveRoot).TrimEnd('\')
    $workspace = [IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd('\')
    if (-not $workspace.StartsWith($base + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Managed workspace outside selected drive.'
    }
    $subpath = $workspace.Substring($base.Length).TrimStart('\')
    if ($env:DEVBOX_ISOLATED_TEST -ne '1' -and $subpath -ne 'DevBox') {
        throw 'Production workspace must be immediately under selected drive.'
    }
    $excluded = @('a','_temp','_work','_tool','hostedtoolcache','runner','agent',
        'System Volume Information','$RECYCLE.BIN','Windows','WindowsApps',
        'Program Files','Program Files (x86)','ProgramData','PerfLogs',
        'pagefile.sys','swapfile.sys','hiberfil.sys','DumpStack.log.tmp')
    # Windows holds the volume-root crash-dump log open exclusively. Exclude
    # that exact root entry; user .tmp files (including nested names) remain.
    $enumerate = if ($base -match '^[A-Za-z]:$') { $base + '\' } else { $base }
    $roots = @()
    $skipped = @()
    foreach ($item in @(Get-ChildItem -LiteralPath $enumerate -Force -ErrorAction Stop)) {
        if ($item.Name -in $excluded) { $skipped += $item.Name; continue }
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            $skipped += $item.Name + ' (reparse)'
            continue
        }
        $roots += $item.FullName
    }
    if (@($roots | Where-Object { $_ -ieq $workspace }).Count -ne 1) {
        throw 'Managed DevBox root not present in backup scope.'
    }
    # GitHub-runner runtime components are rebuilt each startup.
    $patterns = @()
    foreach ($name in @('Temp','ResticCache','Control','Tools')) {
        $p = $workspace.Replace('\','/') + '/' + $name
        $patterns += @($p, ($p + '/**'))
    }
    [pscustomobject]@{
        Roots = @($roots)
        Skipped = @($skipped)
        ExcludePatterns = @($patterns)
        WorkspaceRoot = $workspace
    }
}

function Merge-DevBoxStagedTree {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Source,
          [Parameter(Mandatory)][string]$Target,
          [Parameter(Mandatory)][string]$WorkspaceRoot)
    $item = Get-Item -LiteralPath $Source -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'Reparse point in staged data. Refusing unsafe copy.'
    }
    if ($item.PSIsContainer) {
        if (-not (Test-Path -LiteralPath $Target -PathType Container)) {
            New-Item -ItemType Directory -Path $Target -Force | Out-Null
        }
        foreach ($child in @(Get-ChildItem -LiteralPath $Source -Force -ErrorAction Stop)) {
            if ($Target.TrimEnd('\') -ieq $WorkspaceRoot.TrimEnd('\') -and
                $child.Name -in @('Temp','ResticCache','Control','Tools')) { continue }
            Merge-DevBoxStagedTree -Source $child.FullName -Target (Join-Path $Target $child.Name) -WorkspaceRoot $WorkspaceRoot
        }
    } else {
        New-Item -ItemType Directory -Path (Split-Path $Target -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $Source -Destination $Target -Force -ErrorAction Stop
    }
}

function Import-DevBoxDriveRoots {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StagingRoot,
          [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$SnapshotPaths,
          [Parameter(Mandatory)][string]$DriveRoot,
          [Parameter(Mandatory)][string]$WorkspaceRoot)
    if ($DriveRoot -match '^[A-Za-z]:$') { $DriveRoot += '\' }
    $currentBase = [IO.Path]::GetFullPath($DriveRoot).TrimEnd('\')
    $workspace = [IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd('\')
    if (-not $workspace.StartsWith($currentBase + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Restore workspace outside current drive.'
    }
    $workspaceTail = $workspace.Substring($currentBase.Length).TrimStart('\')
    $matches = @($SnapshotPaths | Where-Object {
        ([string]$_) -match '^[A-Za-z]:[\\/]' -and
        ([string]$_).Replace('/','\').EndsWith('\' + $workspaceTail, [StringComparison]::OrdinalIgnoreCase)
    })
    if ($matches.Count -eq 0) { return $false } # legacy snapshot
    if ($matches.Count -ne 1) { throw 'Multiple saved workspace roots in snapshot manifest.' }
    $oldWorkspace = ([string]$matches[0]).Replace('/','\')
    $oldBase = $oldWorkspace.Substring(0, $oldWorkspace.Length - $workspaceTail.Length).TrimEnd('\')
    # Real DevBox snapshots originate at D:\DevBox or E:\DevBox.
    # Isolated CI fixtures intentionally use nested ephemeral roots.
    if ($oldBase -notmatch '^[A-Za-z]:$') {
        if ($env:DEVBOX_ISOLATED_TEST -ne '1' -or
            $oldBase -notmatch '^[A-Za-z]:\\') {
            throw 'Saved drive root is invalid for production.'
        }
    }
    $oldLetter = $oldBase.Substring(0,1)
    $blocked = @('a','_temp','_work','_tool','hostedtoolcache','runner','agent',
        'System Volume Information','$RECYCLE.BIN','Windows','WindowsApps',
        'Program Files','Program Files (x86)','ProgramData','PerfLogs')
    $count = 0
    foreach ($manifestPath in $SnapshotPaths) {
        $oldPath = ([string]$manifestPath).Replace('/','\')
        if (-not $oldPath.StartsWith($oldBase + '\', [StringComparison]::OrdinalIgnoreCase)) { continue }
        $relative = $oldPath.Substring($oldBase.Length).TrimStart('\')
        $components = @($relative -split '\\')
        if (-not $relative -or @($components | Where-Object { $_ -eq '' -or $_ -eq '.' -or $_ -eq '..' }).Count) {
            throw 'Unsafe source path in saved manifest.'
        }
        if ($components[0] -in $blocked) { throw 'Saved manifest unexpectedly contains runner/system root.' }
        $target = [IO.Path]::GetFullPath((Join-Path ($currentBase + '\') $relative))
        if (-not $target.StartsWith($currentBase + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Restored data would escape selected drive.'
        }
        $tail = $oldPath.Substring(3)
        $from = @( (Join-Path $StagingRoot (Join-Path $oldLetter $tail)), (Join-Path $StagingRoot $tail) )
        $existing = @($from | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -Unique)
        if ($existing.Count -ne 1) { throw "Missing or ambiguous staged source for $relative" }
        Merge-DevBoxStagedTree -Source $existing[0] -Target $target -WorkspaceRoot $workspace
        $count++
        Write-Host "DRIVE RESTORE VERIFIED ROOT: $relative"
    }
    if ($count -eq 0) { throw 'Saved workspace listed but no drive roots restored.' }
    return $true
}

