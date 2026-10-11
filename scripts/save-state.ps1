# save-state.ps1 — Save a verified restic snapshot of the DevBox workspace.
# Acts ONLY inside the new GitHub runner and the dedicated DevBox restic repo.
# Never touches the Lenovo Z: share, existing OpenCode servers, or Tailscale config.
param([switch]$First)
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'common.ps1')
Write-Step 'save-state'

if ([string]::IsNullOrWhiteSpace($env:RESTIC_PASSWORD)) {
    Stop-DevBox 'RESTIC_PASSWORD is missing; refuse to create an unverified backup.'
}
if (-not (Test-Path -LiteralPath $env:DEVBOX_RESTIC_EXE -PathType Leaf)) {
    Stop-DevBox 'Restic binary missing; persistence setup must complete first.'
}
$stateFile = Join-Path $env:DEVBOX_CONTROL_PATH 'persistence.json'
if (-not (Test-Path -LiteralPath $stateFile)) {
    Stop-DevBox 'persistence.json missing; storage connection must complete first.'
}
$state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
$repo = [string]$state.repoUrl
$restic = [string]$env:DEVBOX_RESTIC_EXE
if (-not (Test-DevBoxRepoDestination -Repo $repo)) {
    Stop-DevBox 'Refusing backup: repository is not the dedicated Lenovo endpoint or an approved disposable CI test repository.'
}

# Restic natively supports RESTIC_PASSWORD from the process environment.
# Do not copy passwords to temp files, output or persistent config.
& $restic --repo $repo cat config | Out-Null
$repoStatus = $LASTEXITCODE
if ($repoStatus -eq 10) {
    if (-not $First) {
        Stop-DevBox 'Repository does not exist on a periodic save; refuse automatic init.'
    }
    Write-DevBox INFO 'Dedicated DevBox repository missing; initialize it once.'
    & $restic --repo $repo init | Out-Null
    if ($LASTEXITCODE -ne 0) { Stop-DevBox 'restic init failed; no backup claimed.' }
} elseif ($repoStatus -ne 0) {
    Stop-DevBox "Cannot open repository (restic exit $repoStatus). Password, permissions, network or repository may be incorrect."
}

$canaryDir = New-DevboxDirectorySafe (Join-Path $env:DEVBOX_WSROOT 'PersistentData\canary')
$canaryFile = Join-Path $canaryDir 'DEVBOX-CANARY.txt'
$canaryText = "DEVBOX-CANARY $([DateTime]::UtcNow.ToString('o')) run $env:GITHUB_RUN_ID"
Set-Content -LiteralPath $canaryFile -Value $canaryText -Encoding utf8
$expectedHash = (Get-FileHash -LiteralPath $canaryFile -Algorithm SHA256).Hash

# Explicitly include the canary. The original script created it but never
# added its directory to the backup command.
# The actual work must be saved. Canary-only snapshots are NOT persistence.
# Do not back up disposable Tools, Temp, Downloads or Build directories.
$projectsDir = New-DevboxDirectorySafe (Join-Path $env:DEVBOX_WSROOT 'Projects')
$workspaceDir = New-DevboxDirectorySafe (Join-Path $env:DEVBOX_WSROOT 'Workspace')
$roots = @($canaryDir, $projectsDir, $workspaceDir)
$configFile = Join-Path $PSScriptRoot '..\config\devbox.json'
$config = if (Test-Path -LiteralPath $configFile) { Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json } else { $null }
$hot = if ($config -and $config.hot_paths) { @($config.hot_paths) } else {
    @("$env:USERPROFILE\.config\opencode",
      "$env:USERPROFILE\AGENTS.md",
      "$env:USERPROFILE\Documents\DevBox-Notes")
}
foreach ($p in $hot) {
    $expanded = [Environment]::ExpandEnvironmentVariables([string]$p)
    if ((Test-Path -LiteralPath $expanded) -and ($roots -notcontains $expanded)) {
        $roots += $expanded
    }
}

$excludes = @()
if (-not ($config -and $config.persist_opencode_auth)) {
    $excludes = @('--exclude', 'auth.json', '--exclude', '*.auth*', '--exclude', 'opencode.auth*')
}

# Restic backup syntax and JSON field names verified against upstream docs.
$lines = @(& $restic --repo $repo --json backup --tag 'devbox-auto' @excludes @roots 2>&1)
$backupStatus = $LASTEXITCODE
if ($backupStatus -ne 0) {
    Stop-DevBox "Restic backup failed (exit $backupStatus). A successful snapshot was not proven."
}
$summary = $null
foreach ($line in $lines) {
    try {
        $obj = ([string]$line) | ConvertFrom-Json -ErrorAction Stop
        if ($obj.message_type -eq 'summary') { $summary = $obj }
    } catch {
        # Ignore non-JSON progress text; rely on a valid final summary below.
    }
}
if (-not $summary -or [string]::IsNullOrWhiteSpace([string]$summary.snapshot_id)) {
    Stop-DevBox 'Backup returned success but no JSON summary with snapshot_id was found; snapshot unproven.'
}
$snapshotId = [string]$summary.snapshot_id
$snapshotsText = (& $restic --repo $repo snapshots --json 2>&1 | Out-String)
$listStatus = $LASTEXITCODE
if ($listStatus -ne 0) { Stop-DevBox "Snapshot verification failed (exit $listStatus)." }
$snapshots = @($snapshotsText | ConvertFrom-Json)
if (-not @($snapshots | Where-Object { $_.id -eq $snapshotId }).Count) {
    Stop-DevBox "Snapshot $snapshotId not found in restic snapshots listing."
}

# Canary recovery proof: recover only the canary, never a whole working tree.
$tempRoot = New-DevboxDirectorySafe (Join-Path $env:DEVBOX_WSROOT 'Temp')
$restoreTarget = New-DevboxDirectorySafe (Join-Path $tempRoot ('canary-verify-' + [guid]::NewGuid().ToString('N')))
try {
    & $restic --repo $repo restore $snapshotId --include '**/DEVBOX-CANARY.txt' --target $restoreTarget | Out-Null
    $restoreStatus = $LASTEXITCODE
    if ($restoreStatus -ne 0) { Stop-DevBox "Canary restore failed (exit $restoreStatus)." }
    $matches = @(Get-ChildItem -LiteralPath $restoreTarget -Recurse -File -Filter 'DEVBOX-CANARY.txt' -ErrorAction SilentlyContinue)
    if ($matches.Count -ne 1) { Stop-DevBox 'Canary verification failed: exactly one recovered canary required.' }
    $actualHash = (Get-FileHash -LiteralPath $matches[0].FullName -Algorithm SHA256).Hash
    if ($actualHash -ne $expectedHash) { Stop-DevBox 'Canary checksum mismatch; backup is not verified.' }
} finally {
    Remove-Item -LiteralPath $restoreTarget -Recurse -Force -ErrorAction SilentlyContinue
}
[ordered]@{
    snapshotId = $snapshotId
    utc = [DateTime]::UtcNow.ToString('o')
    canaryHash = $expectedHash
    rootCount = $roots.Count
} | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $env:DEVBOX_CONTROL_PATH 'last-backup.json') -Encoding utf8
Write-DevBox OK "Verified backup $snapshotId (snapshot listed and canary restored with matching SHA256)."
