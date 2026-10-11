# Prove Me Wrong: staged Restic work should restore after drive-letter changes.
# Runs in actual pwsh on CI. No changes to any user's machines.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\find-staged-work.ps1')
function Assert([bool]$ok, [string]$message) {
    if (-not $ok) { throw "STAGED WORK FAIL: $message" }
}
$root = Join-Path ([IO.Path]::GetTempPath()) ("devbox-cross-drive-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
try {
    # A project saved under the previous D: must work even when the new
    # machine is on a different drive (E:/C:/etc).
    $oldProjects = Join-Path $root 'D\DevBox\Projects'
    New-Item -ItemType Directory -Path $oldProjects -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $oldProjects 'persist-me.txt') -Value 'cross-drive-proof'
    $found = Find-DevBoxStagedWork -StagingRoot $root -Name Projects
    Assert ($found -eq $oldProjects) 'Prior D: Projects not found on different-drive restore'
    Assert ((Get-Content -LiteralPath (Join-Path $found 'persist-me.txt') -Raw).Trim() -eq 'cross-drive-proof') 'Recovered content differs'

    # Stage from another independent drive letter too.
    $oldWorkspace = Join-Path $root 'E\DevBox\Workspace'
    New-Item -ItemType Directory -Path $oldWorkspace -Force | Out-Null
    Assert ((Find-DevBoxStagedWork -StagingRoot $root -Name Workspace) -eq $oldWorkspace) 'Prior E: Workspace not found'

    # Restic can also stage a root without drive-letter bucket.
    $root2 = Join-Path $root 'NoDrive'
    $noDrive = Join-Path $root2 'DevBox\Projects'
    New-Item -ItemType Directory -Path $noDrive -Force | Out-Null
    Assert ((Find-DevBoxStagedWork -StagingRoot $root2 -Name Projects) -eq $noDrive) 'Flat DevBox root not found'

    # Missing directory is NOT a success or unbounded recursive search.
    Assert ($null -eq (Find-DevBoxStagedWork -StagingRoot $root2 -Name Workspace)) 'Missing Workspace falsely found'
    $malicious = Join-Path $root2 'NotDevBox\Workspace'
    New-Item -ItemType Directory -Path $malicious -Force | Out-Null
    Assert ($null -eq (Find-DevBoxStagedWork -StagingRoot $root2 -Name Workspace)) 'Unrelated directory falsely imported'

    # If a snapshot contains multiple different drive roots, refuse to guess.
    $duplicate = Join-Path $root 'F\DevBox\Projects'
    New-Item -ItemType Directory -Path $duplicate -Force | Out-Null
    $blocked = $false
    try { $null = Find-DevBoxStagedWork -StagingRoot $root -Name Projects }
    catch { $blocked = $_.Exception.Message -match 'ambiguous' }
    Assert $blocked 'Ambiguous two-drive snapshot accepted'

    # Only expected Name is permitted.
    $blocked = $false
    try { $null = Find-DevBoxStagedWork -StagingRoot $root -Name 'Windows' }
    catch { $blocked = $true }
    Assert $blocked 'Unknown working-root name accepted'

    Write-Output 'STAGED WORK CROSS-DRIVE ADVERSARIAL TESTS: 7 PASS'
} finally {
    Remove-Item -LiteralPath $root -Force -Recurse -ErrorAction SilentlyContinue
}
