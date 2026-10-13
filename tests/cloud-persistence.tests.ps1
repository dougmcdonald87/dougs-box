# Real disposable Windows/Restic + cloud publication + control-queue contracts.
param([ValidateSet('Capture','Restore')][string]$Mode='Capture')
$ErrorActionPreference='Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or -not $env:RUNNER_TEMP) { throw 'CI only.' }
$adapter=Join-Path $PSScriptRoot '..\scripts\cloud-persistence.ps1'
if (-not (Test-Path -LiteralPath $adapter)) { throw 'Cloud persistence adapter unavailable.' }
$base=Join-Path $env:RUNNER_TEMP "cloud-integration-$Mode"
$env:DEVBOX_ISOLATED_TEST='1'
$env:DEVBOX_PERSISTENCE_BACKEND='github-release'
$env:DEVBOX_FAST_ROOT=$base
$env:DEVBOX_WSROOT=Join-Path $base 'DevBox'
$env:DEVBOX_CONTROL_PATH=Join-Path $env:DEVBOX_WSROOT 'Control'
foreach ($name in @('Control','Projects','PersistentData','Temp','Tools')) { New-Item -ItemType Directory -Path (Join-Path $env:DEVBOX_WSROOT $name) -Force | Out-Null }
$fixture=Join-Path $env:USERPROFILE '.config\opencode\cloud-checkpoint-fixture.json'
if ($Mode -eq 'Capture') {
    New-Item -ItemType Directory -Path (Split-Path $fixture -Parent) -Force | Out-Null
    'cloud C configuration fixture' | Set-Content -LiteralPath $fixture -Encoding utf8
    'cloud workspace fixture' | Set-Content -LiteralPath (Join-Path $env:DEVBOX_WSROOT 'Projects\work.txt') -Encoding utf8
    & (Join-Path $PSScriptRoot '..\scripts\connect-persistence.ps1')
    if ($LASTEXITCODE -eq 0) { throw 'Missing cloud generation silently accepted as empty startup.' }
    Write-Host 'MISSING CLOUD ATTACK PASS: blank startup refused before initialization.'
    & $adapter -Mode Initialize
    if ($LASTEXITCODE -ne 0) { throw 'Explicit new checkpoint repository failed.' }
    . (Join-Path $PSScriptRoot '..\scripts\common.ps1')
    . (Join-Path $PSScriptRoot '..\scripts\control-queue.ps1')
    $failures=@()
    if (Test-DevBoxRepoDestination -Repo 'rest:http://100.70.202.110:8000/devbox/') { $failures+='Cloud selected guard accepted home.' }
    if (Test-DevBoxRepoDestination -Repo (Join-Path $base 'unrelated-repository')) { $failures+='Cloud selected guard accepted unrelated cache.' }
    $receipt=Join-Path $env:DEVBOX_CONTROL_PATH 'last-backup.json'
    $sentinel='{"snapshotId":"previous-committed","utc":"previous"}'
    [IO.File]::WriteAllText($receipt,$sentinel)
    $env:DEVBOX_CLOUD_INNER_SAVE='1'
    $env:DEVBOX_CLOUD_PENDING_RECEIPT=Join-Path $env:DEVBOX_WSROOT ('Tools\CloudPersistence\pending-'+[guid]::NewGuid().ToString('N')+'.json')
    try {
        & pwsh -NoLogo -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot '..\scripts\save-state.ps1') -First
        if ($LASTEXITCODE -ne 0) { throw 'Inner native save failed.' }
        if ([IO.File]::ReadAllText($receipt) -cne $sentinel) { $failures+='Inner save exposed an uncommitted receipt.' }
        if (-not (Test-Path -LiteralPath $env:DEVBOX_CLOUD_PENDING_RECEIPT)) { $failures+='Private transaction receipt missing.' }
    } finally {
        Remove-Item -LiteralPath $env:DEVBOX_CLOUD_PENDING_RECEIPT -Force -ErrorAction SilentlyContinue
        $env:DEVBOX_CLOUD_INNER_SAVE=$null;$env:DEVBOX_CLOUD_PENDING_RECEIPT=$null
    }
    $commands=Join-Path $env:DEVBOX_CONTROL_PATH 'Commands'
    New-Item -ItemType Directory -Path $commands -Force | Out-Null
    $nonce=[guid]::NewGuid().ToString('N');'stop' | Set-Content -LiteralPath (Join-Path $commands "stop-$nonce.request")
    $stop=Invoke-DevBoxControlRequests -ControlPath $env:DEVBOX_CONTROL_PATH -VerifiedSave {
        '{"snapshotId":"local-only-new","utc":"new"}' | Set-Content -LiteralPath $receipt
        return $true
    }
    if ($stop) { $failures+='Finish accepted local-only metadata under cloud selection.' }
    Remove-Item -LiteralPath $receipt -Force
    foreach ($failure in $failures) { Write-Host "REVIEW ATTACK FAILED: $failure" }
    if ($failures.Count) { throw 'Cloud review boundary regressions failed.' }
    Write-Host 'PRIVATE RECEIPT AND CLOUD GUARD ATTACKS PASS: uncommitted save never replaces prior receipt; local-only Finish refused; home and unrelated cache refused.'
    & (Join-Path $PSScriptRoot '..\scripts\save-state.ps1') -First
    if ($LASTEXITCODE -ne 0) { throw 'Cloud save failed.' }
    $receipt=Join-Path $env:DEVBOX_CONTROL_PATH 'last-backup.json'
    $before=[IO.File]::ReadAllBytes($receipt)
    $record=Get-Content -LiteralPath $receipt -Raw | ConvertFrom-Json
    if ($record.cloudVerified -ne $true -or -not $record.cloudGeneration) { throw 'Save lacks remote verification.' }
    $identityAttack=@'
import importlib.util,sys
spec=importlib.util.spec_from_file_location('checkpoint',sys.argv[1]);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
archive,restic,snapshot,receipt=sys.argv[2:]
assert module.crypto_verify(archive,restic,{'snapshot_id':snapshot,'receipt_snapshot_id':receipt}) is True,'real encrypted receipt rejected'
assert module.crypto_verify(archive,restic,{'snapshot_id':'c'*64,'receipt_snapshot_id':receipt}) is False,'invented data identity accepted'
assert module.crypto_verify(archive,restic,{'snapshot_id':snapshot,'receipt_snapshot_id':'d'*64}) is False,'invented receipt identity accepted'
print('ENCRYPTED IDENTITY ATTACK PASS: real receipt accepted; changed manifest data/receipt identities refused.')
'@
    & python -c $identityAttack (Join-Path $PSScriptRoot '..\scripts\cloud_checkpoint.py') (Join-Path $env:DEVBOX_WSROOT 'Tools\CloudPersistence\encrypted-checkpoint.zip') $env:DEVBOX_RESTIC_EXE $record.snapshotId $record.receiptSnapshotId
    if ($LASTEXITCODE -ne 0) { throw 'Native encrypted identity attack failed.' }
    # Strongest integration attack: real local save succeeds, cloud auth then fails.
    # The existing Finish queue must refuse and the old receipt bytes must survive.
    . (Join-Path $PSScriptRoot '..\scripts\control-queue.ps1')
    . (Join-Path $PSScriptRoot '..\scripts\invoke-save-isolated.ps1')
    $commands=Join-Path $env:DEVBOX_CONTROL_PATH 'Commands'
    New-Item -ItemType Directory -Path $commands -Force | Out-Null
    $nonce=[guid]::NewGuid().ToString('N')
    'stop' | Set-Content -LiteralPath (Join-Path $commands "stop-$nonce.request")
    $token=$env:GH_TOKEN
    try {
        $env:GH_TOKEN='deliberately-invalid-disposable-credential'
        $stop=Invoke-DevBoxControlRequests -ControlPath $env:DEVBOX_CONTROL_PATH -VerifiedSave {
            Invoke-DevBoxBackupIsolated -SaveScript (Join-Path $PSScriptRoot '..\scripts\save-state.ps1')
        }
        if ($stop) { throw 'Finish accepted a failed cloud publication.' }
    } finally { $env:GH_TOKEN=$token; $token=$null }
    $result=Get-Content -LiteralPath (Join-Path $commands "stop-$nonce.result.json") -Raw | ConvertFrom-Json
    if ($result.success -ne $false) { throw 'False successful cloud save.' }
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($receipt)) -cne [Convert]::ToBase64String($before)) { throw 'Failed save destroyed prior verified receipt.' }
    Write-Host 'CLOUD FINISH ATTACK PASS: failed cloud publication preserved receipt and refused stop.'
    $nonce=[guid]::NewGuid().ToString('N')
    'stop' | Set-Content -LiteralPath (Join-Path $commands "stop-$nonce.request")
    $stop=Invoke-DevBoxControlRequests -ControlPath $env:DEVBOX_CONTROL_PATH -VerifiedSave {
        Invoke-DevBoxBackupIsolated -SaveScript (Join-Path $PSScriptRoot '..\scripts\save-state.ps1')
    }
    if (-not $stop) { throw 'Verified cloud save did not satisfy existing Finish contract.' }
    $record=Get-Content -LiteralPath $receipt -Raw | ConvertFrom-Json
    Write-Host 'VERIFIED CLOUD FINISH PASS: existing queue authorizes Finish only after cloud readback receipt.'
    $record.cloudGeneration | Set-Content -LiteralPath (Join-Path $env:RUNNER_TEMP 'cloud-generation.txt') -Encoding ascii
    "generation=$($record.cloudGeneration)" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
} else {
    if (Test-Path -LiteralPath $fixture) { throw 'Fresh runner unexpectedly has source C fixture.' }
    # Neither step contacts a home endpoint. Source repo must be an accepted generation.
    & (Join-Path $PSScriptRoot '..\scripts\connect-persistence.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Cloud-only connection failed.' }
    & (Join-Path $PSScriptRoot '..\scripts\restore-state.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Existing automatic restore failed on cloud repo.' }
    if ((Get-Content -LiteralPath $fixture -Raw).Trim() -cne 'cloud C configuration fixture') { throw 'Actual C hot path not restored.' }
    if ((Get-Content -LiteralPath (Join-Path $env:DEVBOX_WSROOT 'Projects\work.txt') -Raw).Trim() -cne 'cloud workspace fixture') { throw 'Workspace not restored.' }
    $persist=Get-Content -LiteralPath (Join-Path $env:DEVBOX_CONTROL_PATH 'persistence.json') -Raw | ConvertFrom-Json
    if ($persist.backend -cne 'github-release' -or $persist.repoUrl -like 'rest:*') { throw 'Home/network repo used by cloud startup.' }
    Write-Host 'CLOUD AUTOMATIC RESTORE PASS: existing verified restore recovered workspace and C config from GitHub only.'
}
