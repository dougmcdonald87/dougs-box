# Realistic manifest-based cross-drive restore falsifiers. No live DevBox touched.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\find-staged-work.ps1')
function Assert([bool]$ok, [string]$message) {
    if (-not $ok) { throw "STAGED WORK FAIL: $message" }
}
$root = Join-Path ([IO.Path]::GetTempPath()) ("devbox-cross-drive-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
try {
    # The snapshot manifest records the ORIGINAL runner's absolute path,
    # which need not match the current runner's disk letter or temporary root.
    $oldProjects = Join-Path $root 'D\a\_temp\DevBox-Storage-QA\Projects'
    New-Item -ItemType Directory -Path $oldProjects -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $oldProjects 'persist-me.txt') -Value 'cross-drive-proof'
    $manifest = @('D:\a\_temp\DevBox-Storage-QA\Projects')
    $found = Find-DevBoxStagedWork -StagingRoot $root -Name Projects -SnapshotPaths $manifest
    Assert ($found -eq $oldProjects) 'Prior D: temp project was not found'
    Assert ((Get-Content -LiteralPath (Join-Path $found 'persist-me.txt') -Raw).Trim() -eq 'cross-drive-proof') 'Recovered content differs'

    # Standard live workload D:\DevBox\Workspace also works.
    $oldWorkspace = Join-Path $root 'E\DevBox\Workspace'
    New-Item -ItemType Directory -Path $oldWorkspace -Force | Out-Null
    Assert ((Find-DevBoxStagedWork -StagingRoot $root -Name Workspace -SnapshotPaths @('E:\DevBox\Workspace')) -eq $oldWorkspace) 'Prior E: Workspace not found'

    # Restic may stage without a drive bucket in some environments.
    $root2 = Join-Path $root 'NoDrive'
    $flat = Join-Path $root2 'DevBox\Projects'
    New-Item -ItemType Directory -Path $flat -Force | Out-Null
    Assert ((Find-DevBoxStagedWork -StagingRoot $root2 -Name Projects -SnapshotPaths @('E:\DevBox\Projects')) -eq $flat) 'Flat restore root not found'

    # Other directory names and missing manifest roots cannot be accepted.
    Assert ($null -eq (Find-DevBoxStagedWork -StagingRoot $root2 -Name Workspace -SnapshotPaths @('E:\DevBox\Workspace'))) 'Missing Workspace falsely found'
    New-Item -ItemType Directory -Path (Join-Path $root2 'NotDevBox\Workspace') -Force | Out-Null
    Assert ($null -eq (Find-DevBoxStagedWork -StagingRoot $root2 -Name Workspace -SnapshotPaths @('E:\DevBox\Workspace'))) 'Unrelated directory falsely imported'

    # Real ambiguity: two manifest roots both present; never pick one.
    $duplicate = Join-Path $root 'F\DevBox\Projects'
    New-Item -ItemType Directory -Path $duplicate -Force | Out-Null
    $blocked = $false
    try { $null = Find-DevBoxStagedWork -StagingRoot $root -Name Projects -SnapshotPaths @($manifest[0], 'F:\DevBox\Projects') }
    catch { $blocked = $_.Exception.Message -match 'ambiguous' }
    Assert $blocked 'Ambiguous snapshot accepted'

    # Security: a forged traversal source must be rejected before access.
    $blocked = $false
    try { $null = Find-DevBoxStagedWork -StagingRoot $root -Name Projects -SnapshotPaths @('D:\..\DevBox\Projects') }
    catch { $blocked = $_.Exception.Message -match 'Unsafe' }
    Assert $blocked 'Unsafe traversal accepted'

    Write-Output 'STAGED WORK CROSS-DRIVE ADVERSARIAL TESTS: 7 PASS'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
