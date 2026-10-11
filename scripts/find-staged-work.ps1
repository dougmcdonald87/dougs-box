# find-staged-work.ps1 — map paths from the EXACT Restic snapshot manifest.
# Do NOT infer the previous runner's drive from the new runner's drive.
Set-StrictMode -Version Latest

function Find-DevBoxStagedWork {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StagingRoot,
        [Parameter(Mandatory)][ValidateSet('Projects', 'Workspace')][string]$Name,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$SnapshotPaths
    )
    if (-not (Test-Path -LiteralPath $StagingRoot -PathType Container)) {
        throw 'Staging directory absent.'
    }

    $candidates = @()
    foreach ($sourcePath in $SnapshotPaths) {
        # Only original absolute drive paths listed in THIS Restic snapshot.
        # Relative or traversal paths must never be interpreted as restore roots.
        $m = [regex]::Match([string]$sourcePath, '^([A-Za-z]):[\\/](.+)$')
        if (-not $m.Success) { continue }
        $drive = $m.Groups[1].Value
        $parts = @($m.Groups[2].Value -split '[\\/]')
        if ($parts.Count -lt 2 -or $parts[-1] -cne $Name) { continue }
        if (@($parts | Where-Object { $_ -eq '.' -or $_ -eq '..' -or $_ -eq '' }).Count -gt 0) {
            throw 'Unsafe source path in backup snapshot manifest.'
        }
        # Windows Restic stage layout is <target>/<original-drive>/<path>.
        # Also support the no-drive staging format as an alternative, but reject
        # multiple candidates to avoid silently importing the wrong directory.
        $relative = ($parts -join [IO.Path]::DirectorySeparatorChar)
        $candidates += Join-Path $StagingRoot (Join-Path $drive $relative)
        $candidates += Join-Path $StagingRoot $relative
    }

    $matches = @($candidates |
        Where-Object { Test-Path -LiteralPath $_ -PathType Container } |
        Select-Object -Unique)
    if ($matches.Count -gt 1) {
        throw "Multiple staged $Name roots match this snapshot manifest; refusing ambiguous import."
    }
    if ($matches.Count -eq 0) { return $null }
    return [string]$matches[0]
}
