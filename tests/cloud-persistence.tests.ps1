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
    & $adapter -Mode Initialize
    if ($LASTEXITCODE -ne 0) { throw 'Explicit new checkpoint repository failed.' }
    & (Join-Path $PSScriptRoot '..\scripts\save-state.ps1') -First
    if ($LASTEXITCODE -ne 0) { throw 'Cloud save failed.' }
    $receipt=Join-Path $env:DEVBOX_CONTROL_PATH 'last-backup.json'
    $before=[IO.File]::ReadAllBytes($receipt)
    $record=Get-Content -LiteralPath $receipt -Raw | ConvertFrom-Json
    if ($record.cloudVerified -ne $true -or -not $record.cloudGeneration) { throw 'Save lacks remote verification.' }
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
    $record.cloudGeneration | Set-Content -LiteralPath (Join-Path $env:RUNNER_TEMP 'cloud-generation.txt') -Encoding ascii
    "generation=$($record.cloudGeneration)" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
} else {
    if (Test-Path -LiteralPath $fixture) { throw 'Fresh runner unexpectedly has source C fixture.' }
    # Neither step contacts a home endpoint. Source repo must be an accepted generation.
    & $adapter -Mode Connect
    if ($LASTEXITCODE -ne 0) { throw 'Cloud-only connection failed.' }
    & (Join-Path $PSScriptRoot '..\scripts\restore-state.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Existing automatic restore failed on cloud repo.' }
    if ((Get-Content -LiteralPath $fixture -Raw).Trim() -cne 'cloud C configuration fixture') { throw 'Actual C hot path not restored.' }
    if ((Get-Content -LiteralPath (Join-Path $env:DEVBOX_WSROOT 'Projects\work.txt') -Raw).Trim() -cne 'cloud workspace fixture') { throw 'Workspace not restored.' }
    $persist=Get-Content -LiteralPath (Join-Path $env:DEVBOX_CONTROL_PATH 'persistence.json') -Raw | ConvertFrom-Json
    if ($persist.backend -cne 'github-release' -or $persist.repoUrl -like 'rest:*') { throw 'Home/network repo used by cloud startup.' }
    Write-Host 'CLOUD AUTOMATIC RESTORE PASS: existing verified restore recovered workspace and C config from GitHub only.'
}
