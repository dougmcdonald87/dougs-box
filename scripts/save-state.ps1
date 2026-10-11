# save-state.ps1 - Phase 23/24/18. Append-only backup with canary restore proof.
# ABSOLUTE LAW: this script and its callers contain NO destructive commands.
# The DevBox backs up; it NEVER deletes, NEVER rewrites repository history.
param([switch]$First)
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'common.ps1')
Write-Step 'save-state'
if ($env:DEVBOX_WSROOT) {
    Write-DevBox INFO "workspace: $env:DEVBOX_WSROOT"
}

$cfgPath = Join-Path $PSScriptRoot '..\config\devbox.json'
$cfg = if (Test-Path $cfgPath) { Get-Content $cfgPath -Raw | ConvertFrom-Json } else { $null }
$persist = (Get-Content (Join-Path $env:DEVBOX_CONTROL_PATH 'persistence.json') -Raw) | ConvertFrom-Json
$repoUrl = $persist.repoUrl

if ([string]::IsNullOrWhiteSpace($env:RESTIC_PASSWORD)) {
    Stop-DevBox "RESTIC_PASSWORD empty at save. Next action: add it to the devbox Environment secrets."
}

# ---- HOT set (Phase 20). OpenCode auth only when the owner flag says so (Phase 29)
$persistOpencodeAuth = if ($cfg -and $cfg.persist_opencode_auth) { [bool]$cfg.persist_opencode_auth } else { $false }
$hotPaths = if ($cfg -and $cfg.hot_paths) { $cfg.hot_paths } else {
    @("$env:USERPROFILE\.config\opencode", "$env:USERPROFILE\AGENTS.md", "$env:USERPROFILE\Documents\DevBox-Notes")
}
$backupRoots = @()
foreach ($p in $hotPaths) {
    if (Test-Path $p) {
        if (($p -like '*opencode*') -and -not $persistOpencodeAuth) {
            # back up config but EXCLUDE auth state files explicitly rather than the whole directory (Phase 29)
            $authExclude = @('--exclude', '*.auth*','--exclude','auth.json','--exclude','opencode.auth*')
            $backupRoots += $p; $script:AuthArgs = $authExclude
            continue
        }
        $backupRoots += $p
    }
}
if ($backupRoots.Count -eq 0) { Write-DevBox WARN 'no HOT paths exist yet; snapshot will contain canary only.' }

# ---- canary (Phase 24): proves RESTORE, not merely upload
$canaryDir = New-DevboxDirectorySafe (Join-Path $env:DEVBOX_WSROOT 'PersistentData\canary')
$canaryBody = "DEVBOX-CANARY $(Get-Date -Format 'o') run $($env:GITHUB_RUN_ID) user $(whoami)"
Set-Content -LiteralPath (Join-Path $canaryDir 'DEVBOX-CANARY.txt') -Value $canaryBody -Encoding utf8
$canaryLocalHash = (Get-FileHash (Join-Path $canaryDir 'DEVBOX-CANARY.txt') -Algorithm SHA256).Hash

# ---- password discipline: env into temp file, deleted after each invocation
function Invoke-Restic {
    param([Parameter(Mandatory)][string[]]$ResticArgs)
    $pwFile = Join-Path $env:DEVBOX_WSROOT ('Temp\restic-pw-' + [guid]::NewGuid().ToString('N'))
    $env:RESTIC_PASSWORD | Set-Content -LiteralPath $pwFile -NoNewline -Encoding ascii
    icacls $pwFile /inheritance:r /grant:r "$env:USERNAME`:R" | Out-Null
    try {
        $full = @('--repo', $repoUrl, '--password-file', $pwFile, '--cache-dir', (Join-Path $env:DEVBOX_WSROOT 'ResticCache')) + $ResticArgs
        & $env:DEVBOX_RESTIC_EXE @full 2>&1 | Write-Output
        return $LASTEXITCODE
    } finally {
        Remove-Item -LiteralPath $pwFile -Force -ErrorAction SilentlyContinue
    }
}

# ---- first run: initialize the repo EXACTLY ONCE (Phase 19)
if ($First) {
    $probe = Invoke-Restic -ResticArgs @('snapshots', '--json')
    if ($probe -eq 0) {
        Write-DevBox OK "repository already initialized; once-only law prevents re-init."
    } elseif ($probe -eq 10) {
        # restic exit 10: repository does not exist. Safe to init precisely once.
        $initRes = Invoke-Restic -ResticArgs @('init')
        if ($initRes -ne 0) { Stop-DevBox "restic init failed (exit $initRes) on empty repository. Next action: TROUBLESHOOTING 'connect-persistence'." }
        Write-DevBox OK "repository initialized exactly once."
    } else {
        Stop-DevBox "repository state AMBIGUOUS (exit $probe). Next action: inspect storage host before any retry; refuse to initialize blindly (Phase 19)."
    }
}

# ---- the backup itself (--skip-if-unchanged where supported; never a destructive flag)
$args = @('--tag', 'devbox-auto', '--json')
if ($First) { $args += @('--host', 'devbox') }
$args += $backupRoots
if ($script:AuthArgs) { $args += $script:AuthArgs }

Write-DevBox INFO "backup: $($backupRoots -join ', ')"
$out = Invoke-Restic -ResticArgs $args
if ($LASTEXITCODE -ne 0) { Stop-DevBox "restic backup FAILED (exit $LASTEXITCODE). Snapshot ID unknown - NEVER report success (Phase 23)." }

$summary = ($out | Select-Object -Last 8) | ConvertFrom-Json -ErrorAction SilentlyContinue | Where-Object { $_.snapshot }
if (-not $summary) {
    # parse the last JSON object from the summary lines
    $jsonLines = @($out | Where-Object { $_.Trim().StartsWith('{') })
    if ($jsonLines.Count -gt 0) { $summary = $jsonLines[-1] | ConvertFrom-Json }
}
$snapshotId = if ($summary -and $summary.snapshot) { $summary.snapshot } else { $null }
if ([string]::IsNullOrEmpty($snapshotId)) { Stop-DevBox "backup exited 0 but no snapshot id parsed. Next action: rerun save-state once before claiming saved." }

# ---- verify the snapshot exists in listings (Phase 23 requirement)
$verify = Invoke-Restic -ResticArgs @('snapshots', '--json') | ConvertFrom-Json -ErrorAction SilentlyContinue
$found = $verify | Where-Object { $_.id -eq $snapshotId }
if (-not $found) { Stop-DevBox "snapshot $snapshotId missing from repository listing after backup. Next action: TROUBLESHOOTING 'save-state'." }

# ---- canary restore proof (Phase 24): include canary, restore to temp, hash equal
$restoreTarget = New-DevboxDirectorySafe (Join-Path $env:DEVBOX_WSROOT 'Temp\canary-restore-' + [string](Get-Date -Format 'yyyyMMddHHmmss'))
$canaryRes = Invoke-Restic -ResticArgs @('restore', $snapshotId, '--include', '/canary/*', '--target', $restoreTarget)
if ($canaryRes -ne 0) { Stop-DevBox "canary restore failed (exit $canaryRes). Next action: TROUBLESHOOTING 'save-state'." }

$canaryRestored = Get-ChildItem -LiteralPath $restoreTarget -Recurse -Filter 'DEVBOX-CANARY.txt' | Select-Object -First 1
if (-not $canaryRestored) { Stop-DevBox "canary file absent from restore. Next action: inspect snapshot contents with restic ls." }
$canaryRemoteHash = (Get-FileHash $canaryRestored.FullName -Algorithm SHA256).Hash

if ($canaryRemoteHash -ne $canaryLocalHash) {
    Stop-DevBox "canary hash MISMATCH (local $canaryLocalHash vs restored $canaryRemoteHash). Next action: treat storage integrity as suspect; inspect storage host."
}
Write-DevBox OK "canary round-trip verified."

# ---- bookkeeping, then clean the temp restore
@{
    snapshotId = $snapshotId
    utc        = (Get-Date).ToUniversalTime().ToString('o')
    hotCount   = $backupRoots.Count
    canaryHash = $canaryLocalHash
} | ConvertTo-Json -Compress |
    Set-Content (Join-Path $env:DEVBOX_CONTROL_PATH 'last-backup.json') -Encoding utf8

Remove-Item -LiteralPath $restoreTarget -Recurse -Force -ErrorAction SilentlyContinue
Write-StepSummary @(
    "**Backup saved**: snapshot $($snapshotId)",
    "**Canary**: round-trip hash verified",
    "**HOT paths**: $($backupRoots.Count)"
)
Write-DevBox OK "save-state complete ($snapshotId)."
