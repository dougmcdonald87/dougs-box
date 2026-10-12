# drive-data.ps1 — persistent user-data roots on the disposable workspace drive.
# Save every top-level user-data entry (including the complete DevBox tree)
# without capturing GitHub runner internals, OS metadata or staging/temp files.
Set-StrictMode -Version Latest

function Get-DevBoxDriveRoots {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DriveRoot,
          [Parameter(Mandatory)][string]$WorkspaceRoot)
    if ($DriveRoot -match '^[A-Za-z]:
        throw "Selected workspace volume missing: $DriveRoot"
    }
    $rootFull = [IO.Path]::GetFullPath($DriveRoot).TrimEnd('\')
    $workspaceFull = [IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd('\')
    if (-not $workspaceFull.StartsWith($rootFull + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Workspace does not reside beneath the selected drive data root.'
    }
    $relativeWorkspace = $workspaceFull.Substring($rootFull.Length).TrimStart('\')
    if ($relativeWorkspace.Contains('\')) {
        if ($env:DEVBOX_ISOLATED_TEST -ne '1') {
            throw 'Production workspace must be directly beneath selected drive root.'
        }
    }
    # Protect the GitHub runner, Windows/volume metadata, and other machine
    # infrastructure. Treat excluded roots as NOT SAVED, never claim full disk.
    $excluded = @(
        'a', '_temp', '_work', '_tool', 'hostedtoolcache', 'agent', 'runner',
        '$RECYCLE.BIN', 'System Volume Information',
        'Windows', 'WindowsApps', 'Program Files', 'Program Files (x86)',
        'ProgramData', 'PerfLogs', 'pagefile.sys', 'swapfile.sys', 'hiberfil.sys'
    )
    $roots = @()
    $skipped = @()
    $scanRoot = if ($rootFull -match '^[A-Za-z]:
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            $skipped += $entry.Name + ' (reparse/link)'
            continue
        }
        if ($excluded -contains $entry.Name) {
            $skipped += $entry.Name + ' (runner/system)'
            continue
        }
        $roots += $entry.FullName
    }
    if ($roots -notcontains $workspaceFull) {
        throw 'Managed DevBox workspace was missing from the drive coverage set.'
    }
    # Workspace backup deliberately excludes these disposable/runtime subtrees.
    $subtreeExcludes = @('Temp', 'ResticCache', 'Control')
    $patterns = @()
    foreach ($part in $subtreeExcludes) {
        # Match exact folder and descendants under the managed DevBox root.
        $pattern = $workspaceFull.Replace('\','/') + '/' + $part
        $patterns += $pattern
        $patterns += $pattern + '/**'
    }
    [pscustomobject]@{
        Roots = @($roots)
        ExcludePatterns = @($patterns)
        Skipped = @($skipped)
        DriveRoot = $rootFull
        WorkspaceRoot = $workspaceFull
    }
}

function Copy-DevBoxStagedEntry {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Source,
          [Parameter(Mandatory)][string]$Destination,
          [Parameter(Mandatory)][string]$WorkspaceRoot)
    if (-not (Test-Path -LiteralPath $Source)) { throw "Saved staged path is missing: $Source" }
    # Never follow a restored reparse point into a different volume or user dir.
    $links = @(Get-Item -LiteralPath $Source -Force)
    if (Test-Path -LiteralPath $Source -PathType Container) {
        $links += @(Get-ChildItem -LiteralPath $Source -Recurse -Force -ErrorAction Stop |
            Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })
    }
    if (@($links | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count -gt 0) {
        throw 'Saved user-data tree contains a reparse point: refusing unsafe automatic import.'
    }
    if (Test-Path -LiteralPath $Source -PathType Container) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        foreach ($child in @(Get-ChildItem -LiteralPath $Source -Force -ErrorAction Stop)) {
            # Do not import prior-run tools/control/temp over current live runner.
            if ($Destination.TrimEnd('\') -ieq $WorkspaceRoot.TrimEnd('\') -and
                $child.Name -in @('Temp', 'ResticCache', 'Control')) { continue }
            Copy-Item -LiteralPath $child.FullName -Destination (Join-Path $Destination $child.Name) -Recurse -Force -ErrorAction Stop
        }
    } else {
        New-Item -ItemType Directory -Path (Split-Path $Destination -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $Source -Destination $Destination -Force -ErrorAction Stop
    }
}

function Import-DevBoxDriveRoots {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StagingRoot,
          [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$SnapshotPaths,
          [Parameter(Mandatory)][string]$DriveRoot,
          [Parameter(Mandatory)][string]$WorkspaceRoot)
    if ($DriveRoot -match '^[A-Za-z]:
    $destWorkspace = [IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd('\')
    $workspaceTail = $destWorkspace.Substring($destRoot.Length).TrimStart('\')
    $workspaceManifest = @($SnapshotPaths | Where-Object {
        [string]$_ -match '^[A-Za-z]:[\\/]' -and
        ([string]$_).Replace('/','\').EndsWith('\' + $workspaceTail, [StringComparison]::OrdinalIgnoreCase)
    })
    if ($workspaceManifest.Count -eq 0) {
        # Legacy backup had separately backed Projects/Workspace rather than
        # the whole workspace root; caller must use its legacy importer.
        return $false
    }
    if ($workspaceManifest.Count -ne 1) { throw 'Ambiguous prior managed workspace roots in snapshot.' }
    $oldWorkspace = ([string]$workspaceManifest[0]).Replace('/','\')
    $oldBase = $oldWorkspace.Substring(0, $oldWorkspace.Length - $workspaceTail.Length).TrimEnd('\')
    $oldDrive = $oldBase.Substring(0,1)
    $allowed = @('a', '_temp', '_work', '_tool', 'hostedtoolcache', 'agent', 'runner',
        '$RECYCLE.BIN','System Volume Information','Windows','WindowsApps',
        'Program Files','Program Files (x86)','ProgramData','PerfLogs')
    $imported = 0
    foreach ($original in $SnapshotPaths) {
        $normalized = ([string]$original).Replace('/','\')
        if (-not $normalized.StartsWith($oldBase + '\', [StringComparison]::OrdinalIgnoreCase)) { continue }
        $relative = $normalized.Substring($oldBase.Length).TrimStart('\')
        $segments = @($relative.Split('\'))
        if (-not $relative -or @($segments | Where-Object { -not $_ -or $_ -in @('.','..') }).Count -gt 0) {
            throw 'Unsafe old drive path in snapshot manifest.'
        }
        if ($segments[0] -in $allowed) {
            throw 'Unexpected runner or system path in claimed user backup; refusing automatic import.'
        }
        # No path can escape the selected new drive root.
        $destination = [IO.Path]::GetFullPath((Join-Path $destRoot $relative))
        if (-not $destination.StartsWith($destRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Restore destination escaped selected drive root.'
        }
        $oldPathTail = $normalized.Substring(3)
        $stageOne = Join-Path $StagingRoot (Join-Path $oldDrive $oldPathTail)
        $stageTwo = Join-Path $StagingRoot $oldPathTail
        $matches = @(@($stageOne, $stageTwo) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -Unique)
        if ($matches.Count -ne 1) {
            throw "Expected exactly one staged backup root for $relative; found $($matches.Count)."
        }
        Copy-DevBoxStagedEntry -Source $matches[0] -Destination $destination -WorkspaceRoot $destWorkspace
        $imported++
        Write-Host "DRIVE DATA RESTORED: $relative"
    }
    if ($imported -eq 0) { throw 'Workspace manifest found but nothing imported.' }
    return $true
}
) { $DriveRoot = $DriveRoot + '\\' }
    if (-not (Test-Path -LiteralPath $DriveRoot -PathType Container)) {
        throw "Selected workspace volume missing: $DriveRoot"
    }
    $rootFull = [IO.Path]::GetFullPath($DriveRoot).TrimEnd('\')
    $workspaceFull = [IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd('\')
    if (-not $workspaceFull.StartsWith($rootFull + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Workspace does not reside beneath the selected drive data root.'
    }
    $relativeWorkspace = $workspaceFull.Substring($rootFull.Length).TrimStart('\')
    if ($relativeWorkspace.Contains('\')) {
        if ($env:DEVBOX_ISOLATED_TEST -ne '1') {
            throw 'Production workspace must be directly beneath selected drive root.'
        }
    }
    # Protect the GitHub runner, Windows/volume metadata, and other machine
    # infrastructure. Treat excluded roots as NOT SAVED, never claim full disk.
    $excluded = @(
        'a', '_temp', '_work', '_tool', 'hostedtoolcache', 'agent', 'runner',
        '$RECYCLE.BIN', 'System Volume Information',
        'Windows', 'WindowsApps', 'Program Files', 'Program Files (x86)',
        'ProgramData', 'PerfLogs', 'pagefile.sys', 'swapfile.sys', 'hiberfil.sys'
    )
    $roots = @()
    $skipped = @()
    foreach ($entry in @(Get-ChildItem -LiteralPath $rootFull -Force -ErrorAction Stop)) {
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            $skipped += $entry.Name + ' (reparse/link)'
            continue
        }
        if ($excluded -contains $entry.Name) {
            $skipped += $entry.Name + ' (runner/system)'
            continue
        }
        $roots += $entry.FullName
    }
    if ($roots -notcontains $workspaceFull) {
        throw 'Managed DevBox workspace was missing from the drive coverage set.'
    }
    # Workspace backup deliberately excludes these disposable/runtime subtrees.
    $subtreeExcludes = @('Temp', 'ResticCache', 'Control')
    $patterns = @()
    foreach ($part in $subtreeExcludes) {
        # Match exact folder and descendants under the managed DevBox root.
        $pattern = $workspaceFull.Replace('\','/') + '/' + $part
        $patterns += $pattern
        $patterns += $pattern + '/**'
    }
    [pscustomobject]@{
        Roots = @($roots)
        ExcludePatterns = @($patterns)
        Skipped = @($skipped)
        DriveRoot = $rootFull
        WorkspaceRoot = $workspaceFull
    }
}

function Copy-DevBoxStagedEntry {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Source,
          [Parameter(Mandatory)][string]$Destination,
          [Parameter(Mandatory)][string]$WorkspaceRoot)
    if (-not (Test-Path -LiteralPath $Source)) { throw "Saved staged path is missing: $Source" }
    # Never follow a restored reparse point into a different volume or user dir.
    $links = @(Get-Item -LiteralPath $Source -Force)
    if (Test-Path -LiteralPath $Source -PathType Container) {
        $links += @(Get-ChildItem -LiteralPath $Source -Recurse -Force -ErrorAction Stop |
            Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })
    }
    if (@($links | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count -gt 0) {
        throw 'Saved user-data tree contains a reparse point: refusing unsafe automatic import.'
    }
    if (Test-Path -LiteralPath $Source -PathType Container) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        foreach ($child in @(Get-ChildItem -LiteralPath $Source -Force -ErrorAction Stop)) {
            # Do not import prior-run tools/control/temp over current live runner.
            if ($Destination.TrimEnd('\') -ieq $WorkspaceRoot.TrimEnd('\') -and
                $child.Name -in @('Temp', 'ResticCache', 'Control')) { continue }
            Copy-Item -LiteralPath $child.FullName -Destination (Join-Path $Destination $child.Name) -Recurse -Force -ErrorAction Stop
        }
    } else {
        New-Item -ItemType Directory -Path (Split-Path $Destination -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $Source -Destination $Destination -Force -ErrorAction Stop
    }
}

function Import-DevBoxDriveRoots {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StagingRoot,
          [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$SnapshotPaths,
          [Parameter(Mandatory)][string]$DriveRoot,
          [Parameter(Mandatory)][string]$WorkspaceRoot)
    $destRoot = [IO.Path]::GetFullPath($DriveRoot).TrimEnd('\')
    $destWorkspace = [IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd('\')
    $workspaceTail = $destWorkspace.Substring($destRoot.Length).TrimStart('\')
    $workspaceManifest = @($SnapshotPaths | Where-Object {
        [string]$_ -match '^[A-Za-z]:[\\/]' -and
        ([string]$_).Replace('/','\').EndsWith('\' + $workspaceTail, [StringComparison]::OrdinalIgnoreCase)
    })
    if ($workspaceManifest.Count -eq 0) {
        # Legacy backup had separately backed Projects/Workspace rather than
        # the whole workspace root; caller must use its legacy importer.
        return $false
    }
    if ($workspaceManifest.Count -ne 1) { throw 'Ambiguous prior managed workspace roots in snapshot.' }
    $oldWorkspace = ([string]$workspaceManifest[0]).Replace('/','\')
    $oldBase = $oldWorkspace.Substring(0, $oldWorkspace.Length - $workspaceTail.Length).TrimEnd('\')
    $oldDrive = $oldBase.Substring(0,1)
    $allowed = @('a', '_temp', '_work', '_tool', 'hostedtoolcache', 'agent', 'runner',
        '$RECYCLE.BIN','System Volume Information','Windows','WindowsApps',
        'Program Files','Program Files (x86)','ProgramData','PerfLogs')
    $imported = 0
    foreach ($original in $SnapshotPaths) {
        $normalized = ([string]$original).Replace('/','\')
        if (-not $normalized.StartsWith($oldBase + '\', [StringComparison]::OrdinalIgnoreCase)) { continue }
        $relative = $normalized.Substring($oldBase.Length).TrimStart('\')
        $segments = @($relative.Split('\'))
        if (-not $relative -or @($segments | Where-Object { -not $_ -or $_ -in @('.','..') }).Count -gt 0) {
            throw 'Unsafe old drive path in snapshot manifest.'
        }
        if ($segments[0] -in $allowed) {
            throw 'Unexpected runner or system path in claimed user backup; refusing automatic import.'
        }
        # No path can escape the selected new drive root.
        $destination = [IO.Path]::GetFullPath((Join-Path $destRoot $relative))
        if (-not $destination.StartsWith($destRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Restore destination escaped selected drive root.'
        }
        $oldPathTail = $normalized.Substring(3)
        $stageOne = Join-Path $StagingRoot (Join-Path $oldDrive $oldPathTail)
        $stageTwo = Join-Path $StagingRoot $oldPathTail
        $matches = @(@($stageOne, $stageTwo) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -Unique)
        if ($matches.Count -ne 1) {
            throw "Expected exactly one staged backup root for $relative; found $($matches.Count)."
        }
        Copy-DevBoxStagedEntry -Source $matches[0] -Destination $destination -WorkspaceRoot $destWorkspace
        $imported++
        Write-Output "DRIVE DATA RESTORED: $relative"
    }
    if ($imported -eq 0) { throw 'Workspace manifest found but nothing imported.' }
    return $true
}
) { $rootFull + '\\' } else { $rootFull }
    foreach ($entry in @(Get-ChildItem -LiteralPath $scanRoot -Force -ErrorAction Stop)) {
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            $skipped += $entry.Name + ' (reparse/link)'
            continue
        }
        if ($excluded -contains $entry.Name) {
            $skipped += $entry.Name + ' (runner/system)'
            continue
        }
        $roots += $entry.FullName
    }
    if ($roots -notcontains $workspaceFull) {
        throw 'Managed DevBox workspace was missing from the drive coverage set.'
    }
    # Workspace backup deliberately excludes these disposable/runtime subtrees.
    $subtreeExcludes = @('Temp', 'ResticCache', 'Control')
    $patterns = @()
    foreach ($part in $subtreeExcludes) {
        # Match exact folder and descendants under the managed DevBox root.
        $pattern = $workspaceFull.Replace('\','/') + '/' + $part
        $patterns += $pattern
        $patterns += $pattern + '/**'
    }
    [pscustomobject]@{
        Roots = @($roots)
        ExcludePatterns = @($patterns)
        Skipped = @($skipped)
        DriveRoot = $rootFull
        WorkspaceRoot = $workspaceFull
    }
}

function Copy-DevBoxStagedEntry {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Source,
          [Parameter(Mandatory)][string]$Destination,
          [Parameter(Mandatory)][string]$WorkspaceRoot)
    if (-not (Test-Path -LiteralPath $Source)) { throw "Saved staged path is missing: $Source" }
    # Never follow a restored reparse point into a different volume or user dir.
    $links = @(Get-Item -LiteralPath $Source -Force)
    if (Test-Path -LiteralPath $Source -PathType Container) {
        $links += @(Get-ChildItem -LiteralPath $Source -Recurse -Force -ErrorAction Stop |
            Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })
    }
    if (@($links | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count -gt 0) {
        throw 'Saved user-data tree contains a reparse point: refusing unsafe automatic import.'
    }
    if (Test-Path -LiteralPath $Source -PathType Container) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        foreach ($child in @(Get-ChildItem -LiteralPath $Source -Force -ErrorAction Stop)) {
            # Do not import prior-run tools/control/temp over current live runner.
            if ($Destination.TrimEnd('\') -ieq $WorkspaceRoot.TrimEnd('\') -and
                $child.Name -in @('Temp', 'ResticCache', 'Control')) { continue }
            Copy-Item -LiteralPath $child.FullName -Destination (Join-Path $Destination $child.Name) -Recurse -Force -ErrorAction Stop
        }
    } else {
        New-Item -ItemType Directory -Path (Split-Path $Destination -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $Source -Destination $Destination -Force -ErrorAction Stop
    }
}

function Import-DevBoxDriveRoots {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StagingRoot,
          [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$SnapshotPaths,
          [Parameter(Mandatory)][string]$DriveRoot,
          [Parameter(Mandatory)][string]$WorkspaceRoot)
    $destRoot = [IO.Path]::GetFullPath($DriveRoot).TrimEnd('\')
    $destWorkspace = [IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd('\')
    $workspaceTail = $destWorkspace.Substring($destRoot.Length).TrimStart('\')
    $workspaceManifest = @($SnapshotPaths | Where-Object {
        [string]$_ -match '^[A-Za-z]:[\\/]' -and
        ([string]$_).Replace('/','\').EndsWith('\' + $workspaceTail, [StringComparison]::OrdinalIgnoreCase)
    })
    if ($workspaceManifest.Count -eq 0) {
        # Legacy backup had separately backed Projects/Workspace rather than
        # the whole workspace root; caller must use its legacy importer.
        return $false
    }
    if ($workspaceManifest.Count -ne 1) { throw 'Ambiguous prior managed workspace roots in snapshot.' }
    $oldWorkspace = ([string]$workspaceManifest[0]).Replace('/','\')
    $oldBase = $oldWorkspace.Substring(0, $oldWorkspace.Length - $workspaceTail.Length).TrimEnd('\')
    $oldDrive = $oldBase.Substring(0,1)
    $allowed = @('a', '_temp', '_work', '_tool', 'hostedtoolcache', 'agent', 'runner',
        '$RECYCLE.BIN','System Volume Information','Windows','WindowsApps',
        'Program Files','Program Files (x86)','ProgramData','PerfLogs')
    $imported = 0
    foreach ($original in $SnapshotPaths) {
        $normalized = ([string]$original).Replace('/','\')
        if (-not $normalized.StartsWith($oldBase + '\', [StringComparison]::OrdinalIgnoreCase)) { continue }
        $relative = $normalized.Substring($oldBase.Length).TrimStart('\')
        $segments = @($relative.Split('\'))
        if (-not $relative -or @($segments | Where-Object { -not $_ -or $_ -in @('.','..') }).Count -gt 0) {
            throw 'Unsafe old drive path in snapshot manifest.'
        }
        if ($segments[0] -in $allowed) {
            throw 'Unexpected runner or system path in claimed user backup; refusing automatic import.'
        }
        # No path can escape the selected new drive root.
        $destination = [IO.Path]::GetFullPath((Join-Path $destRoot $relative))
        if (-not $destination.StartsWith($destRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Restore destination escaped selected drive root.'
        }
        $oldPathTail = $normalized.Substring(3)
        $stageOne = Join-Path $StagingRoot (Join-Path $oldDrive $oldPathTail)
        $stageTwo = Join-Path $StagingRoot $oldPathTail
        $matches = @(@($stageOne, $stageTwo) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -Unique)
        if ($matches.Count -ne 1) {
            throw "Expected exactly one staged backup root for $relative; found $($matches.Count)."
        }
        Copy-DevBoxStagedEntry -Source $matches[0] -Destination $destination -WorkspaceRoot $destWorkspace
        $imported++
        Write-Output "DRIVE DATA RESTORED: $relative"
    }
    if ($imported -eq 0) { throw 'Workspace manifest found but nothing imported.' }
    return $true
}
) { $DriveRoot = $DriveRoot + '\\' }
    if (-not (Test-Path -LiteralPath $DriveRoot -PathType Container)) {
        throw "Selected workspace volume missing: $DriveRoot"
    }
    $rootFull = [IO.Path]::GetFullPath($DriveRoot).TrimEnd('\')
    $workspaceFull = [IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd('\')
    if (-not $workspaceFull.StartsWith($rootFull + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Workspace does not reside beneath the selected drive data root.'
    }
    $relativeWorkspace = $workspaceFull.Substring($rootFull.Length).TrimStart('\')
    if ($relativeWorkspace.Contains('\')) {
        if ($env:DEVBOX_ISOLATED_TEST -ne '1') {
            throw 'Production workspace must be directly beneath selected drive root.'
        }
    }
    # Protect the GitHub runner, Windows/volume metadata, and other machine
    # infrastructure. Treat excluded roots as NOT SAVED, never claim full disk.
    $excluded = @(
        'a', '_temp', '_work', '_tool', 'hostedtoolcache', 'agent', 'runner',
        '$RECYCLE.BIN', 'System Volume Information',
        'Windows', 'WindowsApps', 'Program Files', 'Program Files (x86)',
        'ProgramData', 'PerfLogs', 'pagefile.sys', 'swapfile.sys', 'hiberfil.sys'
    )
    $roots = @()
    $skipped = @()
    foreach ($entry in @(Get-ChildItem -LiteralPath $rootFull -Force -ErrorAction Stop)) {
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            $skipped += $entry.Name + ' (reparse/link)'
            continue
        }
        if ($excluded -contains $entry.Name) {
            $skipped += $entry.Name + ' (runner/system)'
            continue
        }
        $roots += $entry.FullName
    }
    if ($roots -notcontains $workspaceFull) {
        throw 'Managed DevBox workspace was missing from the drive coverage set.'
    }
    # Workspace backup deliberately excludes these disposable/runtime subtrees.
    $subtreeExcludes = @('Temp', 'ResticCache', 'Control')
    $patterns = @()
    foreach ($part in $subtreeExcludes) {
        # Match exact folder and descendants under the managed DevBox root.
        $pattern = $workspaceFull.Replace('\','/') + '/' + $part
        $patterns += $pattern
        $patterns += $pattern + '/**'
    }
    [pscustomobject]@{
        Roots = @($roots)
        ExcludePatterns = @($patterns)
        Skipped = @($skipped)
        DriveRoot = $rootFull
        WorkspaceRoot = $workspaceFull
    }
}

function Copy-DevBoxStagedEntry {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Source,
          [Parameter(Mandatory)][string]$Destination,
          [Parameter(Mandatory)][string]$WorkspaceRoot)
    if (-not (Test-Path -LiteralPath $Source)) { throw "Saved staged path is missing: $Source" }
    # Never follow a restored reparse point into a different volume or user dir.
    $links = @(Get-Item -LiteralPath $Source -Force)
    if (Test-Path -LiteralPath $Source -PathType Container) {
        $links += @(Get-ChildItem -LiteralPath $Source -Recurse -Force -ErrorAction Stop |
            Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })
    }
    if (@($links | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count -gt 0) {
        throw 'Saved user-data tree contains a reparse point: refusing unsafe automatic import.'
    }
    if (Test-Path -LiteralPath $Source -PathType Container) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        foreach ($child in @(Get-ChildItem -LiteralPath $Source -Force -ErrorAction Stop)) {
            # Do not import prior-run tools/control/temp over current live runner.
            if ($Destination.TrimEnd('\') -ieq $WorkspaceRoot.TrimEnd('\') -and
                $child.Name -in @('Temp', 'ResticCache', 'Control')) { continue }
            Copy-Item -LiteralPath $child.FullName -Destination (Join-Path $Destination $child.Name) -Recurse -Force -ErrorAction Stop
        }
    } else {
        New-Item -ItemType Directory -Path (Split-Path $Destination -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $Source -Destination $Destination -Force -ErrorAction Stop
    }
}

function Import-DevBoxDriveRoots {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StagingRoot,
          [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$SnapshotPaths,
          [Parameter(Mandatory)][string]$DriveRoot,
          [Parameter(Mandatory)][string]$WorkspaceRoot)
    $destRoot = [IO.Path]::GetFullPath($DriveRoot).TrimEnd('\')
    $destWorkspace = [IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd('\')
    $workspaceTail = $destWorkspace.Substring($destRoot.Length).TrimStart('\')
    $workspaceManifest = @($SnapshotPaths | Where-Object {
        [string]$_ -match '^[A-Za-z]:[\\/]' -and
        ([string]$_).Replace('/','\').EndsWith('\' + $workspaceTail, [StringComparison]::OrdinalIgnoreCase)
    })
    if ($workspaceManifest.Count -eq 0) {
        # Legacy backup had separately backed Projects/Workspace rather than
        # the whole workspace root; caller must use its legacy importer.
        return $false
    }
    if ($workspaceManifest.Count -ne 1) { throw 'Ambiguous prior managed workspace roots in snapshot.' }
    $oldWorkspace = ([string]$workspaceManifest[0]).Replace('/','\')
    $oldBase = $oldWorkspace.Substring(0, $oldWorkspace.Length - $workspaceTail.Length).TrimEnd('\')
    $oldDrive = $oldBase.Substring(0,1)
    $allowed = @('a', '_temp', '_work', '_tool', 'hostedtoolcache', 'agent', 'runner',
        '$RECYCLE.BIN','System Volume Information','Windows','WindowsApps',
        'Program Files','Program Files (x86)','ProgramData','PerfLogs')
    $imported = 0
    foreach ($original in $SnapshotPaths) {
        $normalized = ([string]$original).Replace('/','\')
        if (-not $normalized.StartsWith($oldBase + '\', [StringComparison]::OrdinalIgnoreCase)) { continue }
        $relative = $normalized.Substring($oldBase.Length).TrimStart('\')
        $segments = @($relative.Split('\'))
        if (-not $relative -or @($segments | Where-Object { -not $_ -or $_ -in @('.','..') }).Count -gt 0) {
            throw 'Unsafe old drive path in snapshot manifest.'
        }
        if ($segments[0] -in $allowed) {
            throw 'Unexpected runner or system path in claimed user backup; refusing automatic import.'
        }
        # No path can escape the selected new drive root.
        $destination = [IO.Path]::GetFullPath((Join-Path $destRoot $relative))
        if (-not $destination.StartsWith($destRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Restore destination escaped selected drive root.'
        }
        $oldPathTail = $normalized.Substring(3)
        $stageOne = Join-Path $StagingRoot (Join-Path $oldDrive $oldPathTail)
        $stageTwo = Join-Path $StagingRoot $oldPathTail
        $matches = @(@($stageOne, $stageTwo) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -Unique)
        if ($matches.Count -ne 1) {
            throw "Expected exactly one staged backup root for $relative; found $($matches.Count)."
        }
        Copy-DevBoxStagedEntry -Source $matches[0] -Destination $destination -WorkspaceRoot $destWorkspace
        $imported++
        Write-Output "DRIVE DATA RESTORED: $relative"
    }
    if ($imported -eq 0) { throw 'Workspace manifest found but nothing imported.' }
    return $true
}
) { $DriveRoot = $DriveRoot + '\\' }
    $destRoot = [IO.Path]::GetFullPath($DriveRoot).TrimEnd('\')
    $destWorkspace = [IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd('\')
    $workspaceTail = $destWorkspace.Substring($destRoot.Length).TrimStart('\')
    $workspaceManifest = @($SnapshotPaths | Where-Object {
        [string]$_ -match '^[A-Za-z]:[\\/]' -and
        ([string]$_).Replace('/','\').EndsWith('\' + $workspaceTail, [StringComparison]::OrdinalIgnoreCase)
    })
    if ($workspaceManifest.Count -eq 0) {
        # Legacy backup had separately backed Projects/Workspace rather than
        # the whole workspace root; caller must use its legacy importer.
        return $false
    }
    if ($workspaceManifest.Count -ne 1) { throw 'Ambiguous prior managed workspace roots in snapshot.' }
    $oldWorkspace = ([string]$workspaceManifest[0]).Replace('/','\')
    $oldBase = $oldWorkspace.Substring(0, $oldWorkspace.Length - $workspaceTail.Length).TrimEnd('\')
    $oldDrive = $oldBase.Substring(0,1)
    $allowed = @('a', '_temp', '_work', '_tool', 'hostedtoolcache', 'agent', 'runner',
        '$RECYCLE.BIN','System Volume Information','Windows','WindowsApps',
        'Program Files','Program Files (x86)','ProgramData','PerfLogs')
    $imported = 0
    foreach ($original in $SnapshotPaths) {
        $normalized = ([string]$original).Replace('/','\')
        if (-not $normalized.StartsWith($oldBase + '\', [StringComparison]::OrdinalIgnoreCase)) { continue }
        $relative = $normalized.Substring($oldBase.Length).TrimStart('\')
        $segments = @($relative.Split('\'))
        if (-not $relative -or @($segments | Where-Object { -not $_ -or $_ -in @('.','..') }).Count -gt 0) {
            throw 'Unsafe old drive path in snapshot manifest.'
        }
        if ($segments[0] -in $allowed) {
            throw 'Unexpected runner or system path in claimed user backup; refusing automatic import.'
        }
        # No path can escape the selected new drive root.
        $destination = [IO.Path]::GetFullPath((Join-Path $destRoot $relative))
        if (-not $destination.StartsWith($destRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Restore destination escaped selected drive root.'
        }
        $oldPathTail = $normalized.Substring(3)
        $stageOne = Join-Path $StagingRoot (Join-Path $oldDrive $oldPathTail)
        $stageTwo = Join-Path $StagingRoot $oldPathTail
        $matches = @(@($stageOne, $stageTwo) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -Unique)
        if ($matches.Count -ne 1) {
            throw "Expected exactly one staged backup root for $relative; found $($matches.Count)."
        }
        Copy-DevBoxStagedEntry -Source $matches[0] -Destination $destination -WorkspaceRoot $destWorkspace
        $imported++
        Write-Output "DRIVE DATA RESTORED: $relative"
    }
    if ($imported -eq 0) { throw 'Workspace manifest found but nothing imported.' }
    return $true
}
) { $DriveRoot = $DriveRoot + '\\' }
    if (-not (Test-Path -LiteralPath $DriveRoot -PathType Container)) {
        throw "Selected workspace volume missing: $DriveRoot"
    }
    $rootFull = [IO.Path]::GetFullPath($DriveRoot).TrimEnd('\')
    $workspaceFull = [IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd('\')
    if (-not $workspaceFull.StartsWith($rootFull + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Workspace does not reside beneath the selected drive data root.'
    }
    $relativeWorkspace = $workspaceFull.Substring($rootFull.Length).TrimStart('\')
    if ($relativeWorkspace.Contains('\')) {
        if ($env:DEVBOX_ISOLATED_TEST -ne '1') {
            throw 'Production workspace must be directly beneath selected drive root.'
        }
    }
    # Protect the GitHub runner, Windows/volume metadata, and other machine
    # infrastructure. Treat excluded roots as NOT SAVED, never claim full disk.
    $excluded = @(
        'a', '_temp', '_work', '_tool', 'hostedtoolcache', 'agent', 'runner',
        '$RECYCLE.BIN', 'System Volume Information',
        'Windows', 'WindowsApps', 'Program Files', 'Program Files (x86)',
        'ProgramData', 'PerfLogs', 'pagefile.sys', 'swapfile.sys', 'hiberfil.sys'
    )
    $roots = @()
    $skipped = @()
    foreach ($entry in @(Get-ChildItem -LiteralPath $rootFull -Force -ErrorAction Stop)) {
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            $skipped += $entry.Name + ' (reparse/link)'
            continue
        }
        if ($excluded -contains $entry.Name) {
            $skipped += $entry.Name + ' (runner/system)'
            continue
        }
        $roots += $entry.FullName
    }
    if ($roots -notcontains $workspaceFull) {
        throw 'Managed DevBox workspace was missing from the drive coverage set.'
    }
    # Workspace backup deliberately excludes these disposable/runtime subtrees.
    $subtreeExcludes = @('Temp', 'ResticCache', 'Control')
    $patterns = @()
    foreach ($part in $subtreeExcludes) {
        # Match exact folder and descendants under the managed DevBox root.
        $pattern = $workspaceFull.Replace('\','/') + '/' + $part
        $patterns += $pattern
        $patterns += $pattern + '/**'
    }
    [pscustomobject]@{
        Roots = @($roots)
        ExcludePatterns = @($patterns)
        Skipped = @($skipped)
        DriveRoot = $rootFull
        WorkspaceRoot = $workspaceFull
    }
}

function Copy-DevBoxStagedEntry {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Source,
          [Parameter(Mandatory)][string]$Destination,
          [Parameter(Mandatory)][string]$WorkspaceRoot)
    if (-not (Test-Path -LiteralPath $Source)) { throw "Saved staged path is missing: $Source" }
    # Never follow a restored reparse point into a different volume or user dir.
    $links = @(Get-Item -LiteralPath $Source -Force)
    if (Test-Path -LiteralPath $Source -PathType Container) {
        $links += @(Get-ChildItem -LiteralPath $Source -Recurse -Force -ErrorAction Stop |
            Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })
    }
    if (@($links | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count -gt 0) {
        throw 'Saved user-data tree contains a reparse point: refusing unsafe automatic import.'
    }
    if (Test-Path -LiteralPath $Source -PathType Container) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        foreach ($child in @(Get-ChildItem -LiteralPath $Source -Force -ErrorAction Stop)) {
            # Do not import prior-run tools/control/temp over current live runner.
            if ($Destination.TrimEnd('\') -ieq $WorkspaceRoot.TrimEnd('\') -and
                $child.Name -in @('Temp', 'ResticCache', 'Control')) { continue }
            Copy-Item -LiteralPath $child.FullName -Destination (Join-Path $Destination $child.Name) -Recurse -Force -ErrorAction Stop
        }
    } else {
        New-Item -ItemType Directory -Path (Split-Path $Destination -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $Source -Destination $Destination -Force -ErrorAction Stop
    }
}

function Import-DevBoxDriveRoots {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StagingRoot,
          [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$SnapshotPaths,
          [Parameter(Mandatory)][string]$DriveRoot,
          [Parameter(Mandatory)][string]$WorkspaceRoot)
    $destRoot = [IO.Path]::GetFullPath($DriveRoot).TrimEnd('\')
    $destWorkspace = [IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd('\')
    $workspaceTail = $destWorkspace.Substring($destRoot.Length).TrimStart('\')
    $workspaceManifest = @($SnapshotPaths | Where-Object {
        [string]$_ -match '^[A-Za-z]:[\\/]' -and
        ([string]$_).Replace('/','\').EndsWith('\' + $workspaceTail, [StringComparison]::OrdinalIgnoreCase)
    })
    if ($workspaceManifest.Count -eq 0) {
        # Legacy backup had separately backed Projects/Workspace rather than
        # the whole workspace root; caller must use its legacy importer.
        return $false
    }
    if ($workspaceManifest.Count -ne 1) { throw 'Ambiguous prior managed workspace roots in snapshot.' }
    $oldWorkspace = ([string]$workspaceManifest[0]).Replace('/','\')
    $oldBase = $oldWorkspace.Substring(0, $oldWorkspace.Length - $workspaceTail.Length).TrimEnd('\')
    $oldDrive = $oldBase.Substring(0,1)
    $allowed = @('a', '_temp', '_work', '_tool', 'hostedtoolcache', 'agent', 'runner',
        '$RECYCLE.BIN','System Volume Information','Windows','WindowsApps',
        'Program Files','Program Files (x86)','ProgramData','PerfLogs')
    $imported = 0
    foreach ($original in $SnapshotPaths) {
        $normalized = ([string]$original).Replace('/','\')
        if (-not $normalized.StartsWith($oldBase + '\', [StringComparison]::OrdinalIgnoreCase)) { continue }
        $relative = $normalized.Substring($oldBase.Length).TrimStart('\')
        $segments = @($relative.Split('\'))
        if (-not $relative -or @($segments | Where-Object { -not $_ -or $_ -in @('.','..') }).Count -gt 0) {
            throw 'Unsafe old drive path in snapshot manifest.'
        }
        if ($segments[0] -in $allowed) {
            throw 'Unexpected runner or system path in claimed user backup; refusing automatic import.'
        }
        # No path can escape the selected new drive root.
        $destination = [IO.Path]::GetFullPath((Join-Path $destRoot $relative))
        if (-not $destination.StartsWith($destRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Restore destination escaped selected drive root.'
        }
        $oldPathTail = $normalized.Substring(3)
        $stageOne = Join-Path $StagingRoot (Join-Path $oldDrive $oldPathTail)
        $stageTwo = Join-Path $StagingRoot $oldPathTail
        $matches = @(@($stageOne, $stageTwo) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -Unique)
        if ($matches.Count -ne 1) {
            throw "Expected exactly one staged backup root for $relative; found $($matches.Count)."
        }
        Copy-DevBoxStagedEntry -Source $matches[0] -Destination $destination -WorkspaceRoot $destWorkspace
        $imported++
        Write-Output "DRIVE DATA RESTORED: $relative"
    }
    if ($imported -eq 0) { throw 'Workspace manifest found but nothing imported.' }
    return $true
}
) { $rootFull + '\\' } else { $rootFull }
    foreach ($entry in @(Get-ChildItem -LiteralPath $scanRoot -Force -ErrorAction Stop)) {
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            $skipped += $entry.Name + ' (reparse/link)'
            continue
        }
        if ($excluded -contains $entry.Name) {
            $skipped += $entry.Name + ' (runner/system)'
            continue
        }
        $roots += $entry.FullName
    }
    if ($roots -notcontains $workspaceFull) {
        throw 'Managed DevBox workspace was missing from the drive coverage set.'
    }
    # Workspace backup deliberately excludes these disposable/runtime subtrees.
    $subtreeExcludes = @('Temp', 'ResticCache', 'Control')
    $patterns = @()
    foreach ($part in $subtreeExcludes) {
        # Match exact folder and descendants under the managed DevBox root.
        $pattern = $workspaceFull.Replace('\','/') + '/' + $part
        $patterns += $pattern
        $patterns += $pattern + '/**'
    }
    [pscustomobject]@{
        Roots = @($roots)
        ExcludePatterns = @($patterns)
        Skipped = @($skipped)
        DriveRoot = $rootFull
        WorkspaceRoot = $workspaceFull
    }
}

function Copy-DevBoxStagedEntry {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Source,
          [Parameter(Mandatory)][string]$Destination,
          [Parameter(Mandatory)][string]$WorkspaceRoot)
    if (-not (Test-Path -LiteralPath $Source)) { throw "Saved staged path is missing: $Source" }
    # Never follow a restored reparse point into a different volume or user dir.
    $links = @(Get-Item -LiteralPath $Source -Force)
    if (Test-Path -LiteralPath $Source -PathType Container) {
        $links += @(Get-ChildItem -LiteralPath $Source -Recurse -Force -ErrorAction Stop |
            Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })
    }
    if (@($links | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count -gt 0) {
        throw 'Saved user-data tree contains a reparse point: refusing unsafe automatic import.'
    }
    if (Test-Path -LiteralPath $Source -PathType Container) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        foreach ($child in @(Get-ChildItem -LiteralPath $Source -Force -ErrorAction Stop)) {
            # Do not import prior-run tools/control/temp over current live runner.
            if ($Destination.TrimEnd('\') -ieq $WorkspaceRoot.TrimEnd('\') -and
                $child.Name -in @('Temp', 'ResticCache', 'Control')) { continue }
            Copy-Item -LiteralPath $child.FullName -Destination (Join-Path $Destination $child.Name) -Recurse -Force -ErrorAction Stop
        }
    } else {
        New-Item -ItemType Directory -Path (Split-Path $Destination -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $Source -Destination $Destination -Force -ErrorAction Stop
    }
}

function Import-DevBoxDriveRoots {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StagingRoot,
          [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$SnapshotPaths,
          [Parameter(Mandatory)][string]$DriveRoot,
          [Parameter(Mandatory)][string]$WorkspaceRoot)
    $destRoot = [IO.Path]::GetFullPath($DriveRoot).TrimEnd('\')
    $destWorkspace = [IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd('\')
    $workspaceTail = $destWorkspace.Substring($destRoot.Length).TrimStart('\')
    $workspaceManifest = @($SnapshotPaths | Where-Object {
        [string]$_ -match '^[A-Za-z]:[\\/]' -and
        ([string]$_).Replace('/','\').EndsWith('\' + $workspaceTail, [StringComparison]::OrdinalIgnoreCase)
    })
    if ($workspaceManifest.Count -eq 0) {
        # Legacy backup had separately backed Projects/Workspace rather than
        # the whole workspace root; caller must use its legacy importer.
        return $false
    }
    if ($workspaceManifest.Count -ne 1) { throw 'Ambiguous prior managed workspace roots in snapshot.' }
    $oldWorkspace = ([string]$workspaceManifest[0]).Replace('/','\')
    $oldBase = $oldWorkspace.Substring(0, $oldWorkspace.Length - $workspaceTail.Length).TrimEnd('\')
    $oldDrive = $oldBase.Substring(0,1)
    $allowed = @('a', '_temp', '_work', '_tool', 'hostedtoolcache', 'agent', 'runner',
        '$RECYCLE.BIN','System Volume Information','Windows','WindowsApps',
        'Program Files','Program Files (x86)','ProgramData','PerfLogs')
    $imported = 0
    foreach ($original in $SnapshotPaths) {
        $normalized = ([string]$original).Replace('/','\')
        if (-not $normalized.StartsWith($oldBase + '\', [StringComparison]::OrdinalIgnoreCase)) { continue }
        $relative = $normalized.Substring($oldBase.Length).TrimStart('\')
        $segments = @($relative.Split('\'))
        if (-not $relative -or @($segments | Where-Object { -not $_ -or $_ -in @('.','..') }).Count -gt 0) {
            throw 'Unsafe old drive path in snapshot manifest.'
        }
        if ($segments[0] -in $allowed) {
            throw 'Unexpected runner or system path in claimed user backup; refusing automatic import.'
        }
        # No path can escape the selected new drive root.
        $destination = [IO.Path]::GetFullPath((Join-Path $destRoot $relative))
        if (-not $destination.StartsWith($destRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Restore destination escaped selected drive root.'
        }
        $oldPathTail = $normalized.Substring(3)
        $stageOne = Join-Path $StagingRoot (Join-Path $oldDrive $oldPathTail)
        $stageTwo = Join-Path $StagingRoot $oldPathTail
        $matches = @(@($stageOne, $stageTwo) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -Unique)
        if ($matches.Count -ne 1) {
            throw "Expected exactly one staged backup root for $relative; found $($matches.Count)."
        }
        Copy-DevBoxStagedEntry -Source $matches[0] -Destination $destination -WorkspaceRoot $destWorkspace
        $imported++
        Write-Output "DRIVE DATA RESTORED: $relative"
    }
    if ($imported -eq 0) { throw 'Workspace manifest found but nothing imported.' }
    return $true
}
) { $DriveRoot = $DriveRoot + '\\' }
    if (-not (Test-Path -LiteralPath $DriveRoot -PathType Container)) {
        throw "Selected workspace volume missing: $DriveRoot"
    }
    $rootFull = [IO.Path]::GetFullPath($DriveRoot).TrimEnd('\')
    $workspaceFull = [IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd('\')
    if (-not $workspaceFull.StartsWith($rootFull + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Workspace does not reside beneath the selected drive data root.'
    }
    $relativeWorkspace = $workspaceFull.Substring($rootFull.Length).TrimStart('\')
    if ($relativeWorkspace.Contains('\')) {
        if ($env:DEVBOX_ISOLATED_TEST -ne '1') {
            throw 'Production workspace must be directly beneath selected drive root.'
        }
    }
    # Protect the GitHub runner, Windows/volume metadata, and other machine
    # infrastructure. Treat excluded roots as NOT SAVED, never claim full disk.
    $excluded = @(
        'a', '_temp', '_work', '_tool', 'hostedtoolcache', 'agent', 'runner',
        '$RECYCLE.BIN', 'System Volume Information',
        'Windows', 'WindowsApps', 'Program Files', 'Program Files (x86)',
        'ProgramData', 'PerfLogs', 'pagefile.sys', 'swapfile.sys', 'hiberfil.sys'
    )
    $roots = @()
    $skipped = @()
    foreach ($entry in @(Get-ChildItem -LiteralPath $rootFull -Force -ErrorAction Stop)) {
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            $skipped += $entry.Name + ' (reparse/link)'
            continue
        }
        if ($excluded -contains $entry.Name) {
            $skipped += $entry.Name + ' (runner/system)'
            continue
        }
        $roots += $entry.FullName
    }
    if ($roots -notcontains $workspaceFull) {
        throw 'Managed DevBox workspace was missing from the drive coverage set.'
    }
    # Workspace backup deliberately excludes these disposable/runtime subtrees.
    $subtreeExcludes = @('Temp', 'ResticCache', 'Control')
    $patterns = @()
    foreach ($part in $subtreeExcludes) {
        # Match exact folder and descendants under the managed DevBox root.
        $pattern = $workspaceFull.Replace('\','/') + '/' + $part
        $patterns += $pattern
        $patterns += $pattern + '/**'
    }
    [pscustomobject]@{
        Roots = @($roots)
        ExcludePatterns = @($patterns)
        Skipped = @($skipped)
        DriveRoot = $rootFull
        WorkspaceRoot = $workspaceFull
    }
}

function Copy-DevBoxStagedEntry {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Source,
          [Parameter(Mandatory)][string]$Destination,
          [Parameter(Mandatory)][string]$WorkspaceRoot)
    if (-not (Test-Path -LiteralPath $Source)) { throw "Saved staged path is missing: $Source" }
    # Never follow a restored reparse point into a different volume or user dir.
    $links = @(Get-Item -LiteralPath $Source -Force)
    if (Test-Path -LiteralPath $Source -PathType Container) {
        $links += @(Get-ChildItem -LiteralPath $Source -Recurse -Force -ErrorAction Stop |
            Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })
    }
    if (@($links | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count -gt 0) {
        throw 'Saved user-data tree contains a reparse point: refusing unsafe automatic import.'
    }
    if (Test-Path -LiteralPath $Source -PathType Container) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        foreach ($child in @(Get-ChildItem -LiteralPath $Source -Force -ErrorAction Stop)) {
            # Do not import prior-run tools/control/temp over current live runner.
            if ($Destination.TrimEnd('\') -ieq $WorkspaceRoot.TrimEnd('\') -and
                $child.Name -in @('Temp', 'ResticCache', 'Control')) { continue }
            Copy-Item -LiteralPath $child.FullName -Destination (Join-Path $Destination $child.Name) -Recurse -Force -ErrorAction Stop
        }
    } else {
        New-Item -ItemType Directory -Path (Split-Path $Destination -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $Source -Destination $Destination -Force -ErrorAction Stop
    }
}

function Import-DevBoxDriveRoots {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StagingRoot,
          [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$SnapshotPaths,
          [Parameter(Mandatory)][string]$DriveRoot,
          [Parameter(Mandatory)][string]$WorkspaceRoot)
    $destRoot = [IO.Path]::GetFullPath($DriveRoot).TrimEnd('\')
    $destWorkspace = [IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd('\')
    $workspaceTail = $destWorkspace.Substring($destRoot.Length).TrimStart('\')
    $workspaceManifest = @($SnapshotPaths | Where-Object {
        [string]$_ -match '^[A-Za-z]:[\\/]' -and
        ([string]$_).Replace('/','\').EndsWith('\' + $workspaceTail, [StringComparison]::OrdinalIgnoreCase)
    })
    if ($workspaceManifest.Count -eq 0) {
        # Legacy backup had separately backed Projects/Workspace rather than
        # the whole workspace root; caller must use its legacy importer.
        return $false
    }
    if ($workspaceManifest.Count -ne 1) { throw 'Ambiguous prior managed workspace roots in snapshot.' }
    $oldWorkspace = ([string]$workspaceManifest[0]).Replace('/','\')
    $oldBase = $oldWorkspace.Substring(0, $oldWorkspace.Length - $workspaceTail.Length).TrimEnd('\')
    $oldDrive = $oldBase.Substring(0,1)
    $allowed = @('a', '_temp', '_work', '_tool', 'hostedtoolcache', 'agent', 'runner',
        '$RECYCLE.BIN','System Volume Information','Windows','WindowsApps',
        'Program Files','Program Files (x86)','ProgramData','PerfLogs')
    $imported = 0
    foreach ($original in $SnapshotPaths) {
        $normalized = ([string]$original).Replace('/','\')
        if (-not $normalized.StartsWith($oldBase + '\', [StringComparison]::OrdinalIgnoreCase)) { continue }
        $relative = $normalized.Substring($oldBase.Length).TrimStart('\')
        $segments = @($relative.Split('\'))
        if (-not $relative -or @($segments | Where-Object { -not $_ -or $_ -in @('.','..') }).Count -gt 0) {
            throw 'Unsafe old drive path in snapshot manifest.'
        }
        if ($segments[0] -in $allowed) {
            throw 'Unexpected runner or system path in claimed user backup; refusing automatic import.'
        }
        # No path can escape the selected new drive root.
        $destination = [IO.Path]::GetFullPath((Join-Path $destRoot $relative))
        if (-not $destination.StartsWith($destRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Restore destination escaped selected drive root.'
        }
        $oldPathTail = $normalized.Substring(3)
        $stageOne = Join-Path $StagingRoot (Join-Path $oldDrive $oldPathTail)
        $stageTwo = Join-Path $StagingRoot $oldPathTail
        $matches = @(@($stageOne, $stageTwo) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -Unique)
        if ($matches.Count -ne 1) {
            throw "Expected exactly one staged backup root for $relative; found $($matches.Count)."
        }
        Copy-DevBoxStagedEntry -Source $matches[0] -Destination $destination -WorkspaceRoot $destWorkspace
        $imported++
        Write-Output "DRIVE DATA RESTORED: $relative"
    }
    if ($imported -eq 0) { throw 'Workspace manifest found but nothing imported.' }
    return $true
}
