# Disposable native E candidate and existing-source migration; no desktop/home access.
param([ValidateSet('Denied','Capture','Restore')][string]$Mode='Capture')
$ErrorActionPreference='Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or -not $env:RUNNER_TEMP) { throw 'CI only.' }
$candidate=Join-Path $PSScriptRoot '..\scripts\cloud-candidate-drive.ps1'
$migration=Join-Path $PSScriptRoot '..\scripts\migrate-cloud-persistence.ps1'
if (-not (Test-Path -LiteralPath $candidate) -or -not (Test-Path -LiteralPath $migration)) { throw 'Cloud E candidate/migration feature unavailable.' }
$env:DEVBOX_ISOLATED_TEST='1'
$sentinel=Join-Path $env:RUNNER_TEMP 'existing-D-sentinel.txt';[IO.File]::WriteAllText($sentinel,'existing D remains intact')
. $candidate
if (Test-Path 'E:\') { throw 'Disposable runner E is occupied; this test cannot create a candidate without changing it.' }
$occupied=Join-Path $env:RUNNER_TEMP 'occupied-E';New-Item -ItemType Directory -Path $occupied -Force | Out-Null
& subst E: $occupied
if ($LASTEXITCODE -ne 0) { throw 'Could not establish disposable occupied-E attack.' }
try {
    $refused=$false
    try { Initialize-DevBoxCloudCandidateDrive -PhysicalRoot $env:RUNNER_TEMP -RequiredGiB 0.01 | Out-Null } catch { $refused=$true }
    if (-not $refused -or -not (Test-Path 'E:\')) { throw 'Occupied E was modified or accepted.' }
} finally { & subst E: /D }
$drive=Initialize-DevBoxCloudCandidateDrive -PhysicalRoot $env:RUNNER_TEMP -RequiredGiB 0.01
if ($drive -cne 'E:' -or -not (Test-Path 'E:\')) { throw 'Candidate E unavailable.' }
if ([IO.File]::ReadAllText($sentinel) -cne 'existing D remains intact') { throw 'Existing D data changed.' }
$env:DEVBOX_FAST_ROOT='E:';$env:DEVBOX_WSROOT='E:\DevBox';$env:DEVBOX_CONTROL_PATH='E:\DevBox\Control'
foreach ($dir in @('Control','Projects','Workspace','PersistentData','Tools','Temp')) { New-Item -ItemType Directory -Path (Join-Path $env:DEVBOX_WSROOT $dir) -Force | Out-Null }
Write-Host 'E ISOLATION ATTACK PASS: occupied E refused; owned E working view created; D sentinel unchanged.'
$fixture=Join-Path $env:USERPROFILE '.config\opencode\cloud-migration-fixture.json'
$metadata=Join-Path $env:DEVBOX_CONTROL_PATH 'persistence.json'
if ($Mode -eq 'Restore') {
    $env:DEVBOX_PERSISTENCE_BACKEND='github-release'
    & (Join-Path $PSScriptRoot '..\scripts\connect-persistence.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Cloud-only E connection failed.' }
    & (Join-Path $PSScriptRoot '..\scripts\restore-state.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Cloud-only E restore failed.' }
    if ((Get-Content -LiteralPath $fixture -Raw).Trim() -cne 'migrated C configuration') { throw 'Migrated C configuration absent.' }
    if ((Get-Content -LiteralPath 'E:\DevBox\Projects\migration.txt' -Raw).Trim() -cne 'migrated workspace') { throw 'Migrated E workspace absent.' }
    Write-Host 'MIGRATED CLOUD RESTORE PASS: fresh E runner recovered selected C and workspace from GitHub without source.'
    exit 0
}
$env:DEVBOX_PERSISTENCE_BACKEND='home'
& (Join-Path $PSScriptRoot '..\scripts\install-restic.ps1') -ToolsRoot 'E:\DevBox\Tools\restic'
if ($LASTEXITCODE -ne 0) { throw 'Restic install failed.' }
$env:DEVBOX_RESTIC_EXE='E:\DevBox\Tools\restic\restic.exe'
$source=Join-Path $env:RUNNER_TEMP ('migration-source-'+$Mode)
& $env:DEVBOX_RESTIC_EXE --repo $source init | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Disposable source init failed.' }
[ordered]@{backend='home';repoUrl=$source;resticExe=$env:DEVBOX_RESTIC_EXE} | ConvertTo-Json -Compress | Set-Content -LiteralPath $metadata -Encoding utf8
$sourceMetadata=[IO.File]::ReadAllBytes($metadata)
# Empty source must never generate a migration proof or initialize cloud state.
& $migration
if ($LASTEXITCODE -eq 0 -or (Test-Path 'E:\DevBox\Tools\CloudPersistence\repository')) { throw 'Empty source became cloud baseline.' }
if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($metadata)) -cne [Convert]::ToBase64String($sourceMetadata)) { throw 'Empty-source refusal changed source metadata.' }
New-Item -ItemType Directory -Path (Split-Path $fixture -Parent) -Force | Out-Null
'migrated C configuration' | Set-Content -LiteralPath $fixture -Encoding utf8
'migrated workspace' | Set-Content -LiteralPath 'E:\DevBox\Projects\migration.txt' -Encoding utf8
& (Join-Path $PSScriptRoot '..\scripts\save-state.ps1') -First
if ($LASTEXITCODE -ne 0) { throw 'Verified source fixture save failed.' }
$beforeSnapshots=(& $env:DEVBOX_RESTIC_EXE --repo $source snapshots --json | Out-String)
$receipt=Join-Path $env:DEVBOX_CONTROL_PATH 'last-backup.json';$beforeReceipt=[IO.File]::ReadAllBytes($receipt)
Remove-Item -LiteralPath $fixture,'E:\DevBox\Projects\migration.txt' -Force
& $migration
$status=$LASTEXITCODE
$afterSnapshots=(& $env:DEVBOX_RESTIC_EXE --repo $source snapshots --json | Out-String)
if ($beforeSnapshots -cne $afterSnapshots) { throw 'Migration modified source backup snapshots.' }
if ($Mode -eq 'Denied') {
    if ($status -eq 0) { throw 'Read-only token allowed successful cloud migration.' }
    if (-not (Test-Path 'E:\DevBox\Tools\CloudPersistence\repository')) { throw 'Denied attack did not reach cloud publication boundary.' }
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($metadata)) -cne [Convert]::ToBase64String($sourceMetadata)) { throw 'Denied cloud publication lost source metadata.' }
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($receipt)) -cne [Convert]::ToBase64String($beforeReceipt)) { throw 'Denied migration changed committed source receipt.' }
    Write-Host 'MIGRATION PUBLICATION ATTACK PASS: real read-only job token refused publication; source metadata/receipt/snapshots retained.'
    exit 0
}
if ($status -ne 0) { throw 'Verified source migration failed.' }
if ((Get-Content -LiteralPath $fixture -Raw).Trim() -cne 'migrated C configuration') { throw 'Migration did not restore source C state before save.' }
$record=Get-Content -LiteralPath $receipt -Raw | ConvertFrom-Json
if ($record.cloudVerified -ne $true) { throw 'Migration lacks cloud proof.' }
$cloudMetadata=[IO.File]::ReadAllBytes($metadata)
[IO.File]::WriteAllBytes($metadata,$sourceMetadata);$env:DEVBOX_PERSISTENCE_BACKEND='home'
& $migration
if ($LASTEXITCODE -eq 0) { throw 'Existing cloud baseline was migrated again.' }
if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($metadata)) -cne [Convert]::ToBase64String($sourceMetadata)) { throw 'Existing-channel refusal changed source metadata.' }
[IO.File]::WriteAllBytes($metadata,$cloudMetadata);$env:DEVBOX_PERSISTENCE_BACKEND='github-release'
Write-Host 'VERIFIED MIGRATION PASS: source restored before cloud publication; source backup unchanged; repeated migration refused.'
"generation=$($record.cloudGeneration)" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
