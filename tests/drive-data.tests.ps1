# Disposable Windows-only adversarial backup/restore scope tests.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$oldFlag = $env:DEVBOX_ISOLATED_TEST
$env:DEVBOX_ISOLATED_TEST = '1'
. (Join-Path $PSScriptRoot '..\scripts\drive-data.ps1')
function Assert([bool]$ok, [string]$label) {
    if (-not $ok) { throw "DRIVE BACKUP TEST FALSIFIED: $label" }
}
$root = Join-Path $env:RUNNER_TEMP ('devbox-drive-scope-' + [guid]::NewGuid().ToString('N'))
$drive = Join-Path $root 'SelectedDrive'
$workspace = Join-Path $drive 'DevBox'
$staging = Join-Path $root 'Staging'
try {
    foreach ($p in @($workspace, (Join-Path $workspace 'Projects'),
        (Join-Path $workspace 'PersistentData'), (Join-Path $workspace 'Control'),
        (Join-Path $drive 'My Project'), (Join-Path $drive 'a'),
        (Join-Path $staging 'E\DevBox\Projects'), (Join-Path $staging 'E\DevBox\Control'),
        (Join-Path $staging 'E\My Project'))) {
        New-Item -ItemType Directory -Path $p -Force | Out-Null
    }
    Set-Content -LiteralPath (Join-Path $drive 'My Project\OUTSIDE-WORKSPACE.txt') -Value 'user-work'
    Set-Content -LiteralPath (Join-Path $workspace 'PersistentData\KEEP.txt') -Value 'persistent'
    Set-Content -LiteralPath (Join-Path $drive 'a\DO-NOT-SAVE.txt') -Value 'runner-internal'
    Set-Content -LiteralPath (Join-Path $drive 'DumpStack.log.tmp') -Value 'system-log'
    Set-Content -LiteralPath (Join-Path $drive 'user-work.tmp') -Value 'user-work'
    Set-Content -LiteralPath (Join-Path $drive 'My Project\DumpStack.log.tmp') -Value 'nested-user-work'
    $scope = Get-DevBoxDriveRoots -DriveRoot $drive -WorkspaceRoot $workspace
    Assert (@($scope.Roots | Where-Object { $_ -ieq (Join-Path $drive 'My Project') }).Count -eq 1) 'Custom drive-root user folder omitted'
    Assert (@($scope.Roots | Where-Object { $_ -ieq (Join-Path $workspace 'PersistentData') }).Count -eq 0) 'Nested root wrongly duplicated'
    Assert (@($scope.Roots | Where-Object { $_ -ieq (Join-Path $drive 'a') }).Count -eq 0) 'GitHub runner root was included'
    Assert (@($scope.ExcludePatterns | Where-Object { $_ -match '/Control' }).Count -gt 0) 'Live control state not excluded'
    Assert (@($scope.Roots | Where-Object { $_ -ieq (Join-Path $drive 'DumpStack.log.tmp') }).Count -eq 0) 'Windows locked dump log was included'
    Assert (@($scope.Roots | Where-Object { $_ -ieq (Join-Path $drive 'user-work.tmp') }).Count -eq 1) 'User-owned temporary file was omitted'
    Assert (@($scope.ExcludePatterns | Where-Object { $_ -match 'DumpStack|\*\.tmp' }).Count -eq 0) 'Nested user temporary files were excluded'
    Write-Output 'ATTACK 1: custom D root included, runner folder excluded: SURVIVED'
    Set-Content -LiteralPath (Join-Path $staging 'E\DevBox\Projects\STATE.txt') -Value 'restored'
    Set-Content -LiteralPath (Join-Path $staging 'E\DevBox\Control\DANGER.txt') -Value 'wrong-run-control'
    Set-Content -LiteralPath (Join-Path $staging 'E\My Project\OUTSIDE-WORKSPACE.txt') -Value 'recovered-user-work'
    $restored = Import-DevBoxDriveRoots -StagingRoot $staging -SnapshotPaths @('E:\DevBox','E:\My Project') -DriveRoot $drive -WorkspaceRoot $workspace
    Assert $restored 'Cross-drive restore rejected valid manifest'
    Assert ((Get-Content -LiteralPath (Join-Path $workspace 'Projects\STATE.txt') -Raw).Trim() -eq 'restored') 'Nested Projects not restored'
    Assert ((Get-Content -LiteralPath (Join-Path $drive 'My Project\OUTSIDE-WORKSPACE.txt') -Raw).Trim() -eq 'recovered-user-work') 'Custom root not recovered'
    Assert (-not (Test-Path -LiteralPath (Join-Path $workspace 'Control\DANGER.txt'))) 'Old runner control files restored'
    Write-Output 'ATTACK 2: previous E: drive -> current workspace with isolated control state: SURVIVED'
    $legacy = Import-DevBoxDriveRoots -StagingRoot $staging -SnapshotPaths @('E:\DevBox\Projects') -DriveRoot $drive -WorkspaceRoot $workspace
    Assert (-not $legacy) 'Legacy selected-folder snapshot misclassified as full-drive'
    Write-Output 'ATTACK 3: legacy manifest triggers old importer: SURVIVED'
    $blocked = $false
    try {
        $null = Import-DevBoxDriveRoots -StagingRoot $staging -SnapshotPaths @('E:\DevBox','E:\..\DevBox') -DriveRoot $drive -WorkspaceRoot $workspace
    } catch { $blocked = $true }
    Assert $blocked 'Traversal/competing saved root accepted'
    Write-Output 'ATTACK 4: forged manifest rejected: SURVIVED'
    Write-Output 'DRIVE SCOPE/RESTORE ADVERSARIAL TESTS: PASS'
} finally {
    $env:DEVBOX_ISOLATED_TEST = $oldFlag
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

