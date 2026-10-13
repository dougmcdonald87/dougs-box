# Restore the verified existing source before publishing a cloud destination.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'common.ps1')
$metadata=Join-Path $env:DEVBOX_CONTROL_PATH 'persistence.json'
$receipt=Join-Path $env:DEVBOX_CONTROL_PATH 'last-backup.json'
$oldMetadata=$null;$oldReceipt=$null;$captured=$false
$oldBackend=$env:DEVBOX_PERSISTENCE_BACKEND
$proof=$null
try {
    if ($env:GITHUB_ACTIONS -ne 'true' -or $env:DEVBOX_WSROOT -cne 'E:\DevBox' -or
        $env:DEVBOX_PERSISTENCE_BACKEND -ceq 'github-release') { throw 'Migration requires the E candidate with an existing source selected.' }
    $oldMetadata=[IO.File]::ReadAllBytes($metadata)
    if (Test-Path -LiteralPath $receipt) { $oldReceipt=[IO.File]::ReadAllBytes($receipt) }
    $captured=$true
    $source=Get-Content -LiteralPath $metadata -Raw | ConvertFrom-Json
    if (-not (Test-DevBoxRepoDestination -Repo $source.repoUrl)) { throw 'Source repository is not allowed.' }
    if ($env:DEVBOX_ISOLATED_TEST -ne '1' -and $source.repoUrl -cne 'rest:http://100.70.202.110:8000/devbox/') { throw 'Production migration requires the existing home source.' }
    $runtime=New-DevboxDirectorySafe (Join-Path $env:DEVBOX_WSROOT 'Tools\CloudPersistence')
    $channel='production'
    if ($env:DEVBOX_ISOLATED_TEST -eq '1') { $channel="ci-$env:GITHUB_RUN_ID-$env:GITHUB_RUN_ATTEMPT" }
    $probe=& python (Join-Path $PSScriptRoot 'cloud_checkpoint.py') probe --repository $env:GITHUB_REPOSITORY --channel $channel --archive (Join-Path $runtime 'unused-probe.zip') --restic-exe $env:DEVBOX_RESTIC_EXE
    if ($LASTEXITCODE -ne 0) { throw 'Cloud inventory could not be verified.' }
    $inventory=($probe | Out-String) | ConvertFrom-Json
    if (@($inventory.generations).Count -ne 0) { throw 'Existing cloud baseline must be recovered, not migrated again.' }
    $proof=Join-Path $runtime ('source-restore-'+[guid]::NewGuid().ToString('N')+'.json')
    & (Join-Path $PSScriptRoot 'restore-state.ps1') -ProofPath $proof
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $proof)) { throw 'Source did not produce verified content restore proof.' }
    $restored=Get-Content -LiteralPath $proof -Raw | ConvertFrom-Json
    if ($restored.repoUrl -cne $source.repoUrl -or [string]$restored.snapshotId -cnotmatch '^[0-9a-f]{64}$') { throw 'Source restore proof identity mismatch.' }
    $env:DEVBOX_PERSISTENCE_BACKEND='github-release'
    & (Join-Path $PSScriptRoot 'cloud-persistence.ps1') -Mode Initialize
    if ($LASTEXITCODE -ne 0) { throw 'Cloud candidate initialization failed.' }
    & (Join-Path $PSScriptRoot 'save-state.ps1') -First
    if ($LASTEXITCODE -ne 0) { throw 'Cloud migration publication failed.' }
    $committed=Get-Content -LiteralPath $receipt -Raw | ConvertFrom-Json
    if ($committed.cloudVerified -ne $true -or $committed.cloudChannel -cne $channel) { throw 'Migration lacks committed cloud verification.' }
    if ($env:GITHUB_ENV) { 'DEVBOX_PERSISTENCE_BACKEND=github-release' | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8 }
    Write-DevBox OK 'Existing source restored and published to cloud; source backup retained. Fresh cloud-only restore acceptance still required.'
} catch {
    if ($captured) {
        [IO.File]::WriteAllBytes($metadata,$oldMetadata)
        if ($null -ne $oldReceipt) { [IO.File]::WriteAllBytes($receipt,$oldReceipt) }
        elseif (Test-Path -LiteralPath $receipt) { Remove-Item -LiteralPath $receipt -Force }
    }
    $env:DEVBOX_PERSISTENCE_BACKEND=$oldBackend
    Write-DevBox WARN 'Migration refused or failed; source metadata and backup retained. No cloud migration success claimed.'
    exit 2
} finally {
    if ($proof) { Remove-Item -LiteralPath $proof -Force -ErrorAction SilentlyContinue }
}
exit 0
