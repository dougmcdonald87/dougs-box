# find-staged-work.ps1 — locate Restic-staged DevBox work regardless of drive letter.
# Restrict candidates to the expected exact DevBox/Projects or DevBox/Workspace roots.
Set-StrictMode -Version Latest

function Find-DevBoxStagedWork {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StagingRoot,
        [Parameter(Mandatory)][ValidateSet('Projects', 'Workspace')][string]$Name
    )
    if (-not (Test-Path -LiteralPath $StagingRoot -PathType Container)) {
        throw "Staging directory absent."
    }
    $candidates = @((Join-Path $StagingRoot (Join-Path 'DevBox' $Name)))

    # Restic on Windows can stage D:\DevBox\Projects under <target>\D\DevBox\Projects.
    # A later session may use E: or C:. Inspect staged drive-letter buckets,
    # never assume the current runner's drive matches the prior snapshot.
    foreach ($bucket in @(Get-ChildItem -LiteralPath $StagingRoot -Directory -Force)) {
        if ($bucket.Name -cmatch '^[A-Za-z]$') {
            $candidates += Join-Path $bucket.FullName (Join-Path 'DevBox' $Name)
        }
    }
    $matches = @($candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Container } | Select-Object -Unique)
    if ($matches.Count -gt 1) {
        throw "Multiple staged DevBox $Name directories; ambiguous snapshot layout."
    }
    if ($matches.Count -eq 0) { return $null }
    return [string]$matches[0]
}
