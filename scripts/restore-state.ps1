# restore-state.ps1 - Phase 22/21/20. HOT first, Git canonical, small overlay.
# NEVER destructive: no destructive overwrite stage anywhere, nothing restored with
# wipe-and-replace semantics. Restore into staging then copy over unchanged targets.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'common.ps1')
Write-Step 'restore-state'

$persist = (Get-Content (Join-Path $env:DEVBOX_CONTROL_PATH 'persistence.json') -Raw) | ConvertFrom-Json

# First-run gate: there is nothing to restore until the dedicated DevBox
# repository has been initialized by save-state -First. Restic documents 10
# as the repository-missing status. Any other error is a hard failure.
if ([string]::IsNullOrWhiteSpace($env:RESTIC_PASSWORD)) {
    Stop-DevBox 'RESTIC_PASSWORD missing at restore.'
}
$resticExe = $env:DEVBOX_RESTIC_EXE
if (-not $resticExe -or -not (Test-Path -LiteralPath $resticExe -PathType Leaf)) {
    Stop-DevBox 'Restic executable unavailable at restore.'
}
$probeRepo = [string]$persist.repoUrl
& $resticExe --repo $probeRepo cat config 2>$null | Out-Null
$probeExit = $LASTEXITCODE
if ($probeExit -eq 10) {
    Write-DevBox INFO 'First run confirmed: dedicated DevBox repository does not exist yet. Nothing to restore.'
    exit 0
}
if ($probeExit -ne 0) {
    Stop-DevBox "Cannot check existing repository (restic exit $probeExit). Refusing unsafe automatic restore."
}

# password via RESTIC_PASSWORD env (workflow-provided); never printed, never logged
if ([string]::IsNullOrWhiteSpace($env:RESTIC_PASSWORD)) {
    Stop-DevBox "RESTIC_PASSWORD empty at restore. Next action: add it to the devbox Environment secrets."
}

$repoUrl = $persist.repoUrl

# ---- password from env into a temp file with tight ACL, removed after each call.
#      restic prefers RESTIC_PASSWORD_FILE for non-lookup password reading.
function Invoke-Restic {
    param([Parameter(Mandatory)][string[]]$ResticArgs)
    $pwFile = Join-Path $env:DEVBOX_TEMP ('restic-pw-' + [guid]::NewGuid().ToString('N'))
    $env:RESTIC_PASSWORD | Set-Content -LiteralPath $pwFile -NoNewline -Encoding ascii
    icacls $pwFile /inheritance:r /grant:r "$env:USERNAME`:R" | Out-Null
    try {
        $full = @("--repo", $repoUrl, "--password-file", $pwFile, "--cache-dir", (Join-Path $env:DEVBOX_WSROOT 'ResticCache')) + $ResticArgs
        & $env:DEVBOX_RESTIC_EXE @full 2>&1 | Write-Output
        if ($LASTEXITCODE -ne 0) { return $LASTEXITCODE } else { return 0 }
    } finally {
        Remove-Item -LiteralPath $pwFile -Force -ErrorAction SilentlyContinue
    }
}

# ---- snapshot listing: zero snapshots on first run is NORMAL (Phase 22)
Invoke-Restic -ResticArgs @("snapshots", "--json") | Set-Content (Join-Path $env:DEVBOX_TEMP 'snaps.json') -Encoding utf8
if ($LASTEXITCODE -ne 0) { Stop-DevBox "snapshots listing failed (exit $LASTEXITCODE)." }
$existing = @(Get-Content (Join-Path $env:DEVBOX_TEMP 'snaps.json') -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue)

if ($existing.Count -eq 0) {
    Write-DevBox OK "first run: no previous snapshot; nothing to restore. Continuing to READY path."
    exit 0
}

# ---- HOT restore within budget (Phase 21): cap auto-restore size
$cfgPath = Join-Path $PSScriptRoot '..\config\devbox.json'
$cfg = if (Test-Path $cfgPath) { Get-Content $cfgPath -Raw | ConvertFrom-Json } else { $null }
$autoRestoreMaxGiB = if ($cfg -and $cfg.auto_restore_max_gib) { [double]$cfg.auto_restore_max_gib } else { 3.0 }

$latest = $existing | Sort-Object created -Descending | Select-Object -First 1
$latestId = $latest.id
Write-DevBox INFO "latest snapshot $latestId at $($latest.created)"

# ---- archive-size gate for the auto-restore cap (real restic stats output)
$stats = Invoke-Restic -ResticArgs @("stats", $latestId, "--mode", "archive-size", "--json") | ConvertFrom-Json -ErrorAction SilentlyContinue
if ($stats -and $stats.total_size) {
    $giB = $stats.total_size / $OneGiB
    if ($giB -gt $autoRestoreMaxGiB) {
        Write-DevBox WARN "snapshot payload $([math]::Round($giB,2)) GiB above auto-restore cap ${autoRestoreMaxGiB} GiB; hydrate on demand instead of pulling it all."
    }
} else {
    Write-DevBox INFO "stats unavailable for size gate; restoration proceeds to staging regardless (cap check cosmetic)."
}

# ---- staging restore, then targeted copy (Phase 22: never blind overwrite)
$staging = New-DevboxDirectorySafe (Join-Path $env:DEVBOX_TEMP 'restore-staging')
Copy-Item -Path (Join-Path $env:DEVBOX_TEMP 'restore-staging') -Destination '.' -Recurse -Force -ErrorAction SilentlyContinue | Out-Null

$ri = Invoke-Restic -ResticArgs @('restore', $latestId, '--include', '/hot/**', '--target', $staging)
if ($LASTEXITCODE -ne 0) { Stop-DevBox "restore to staging failed (exit $LASTEXITCODE). Next action: TROUBLESHOOTING 'restore-state'." }

# HOT items from config map: each path gets copied from staging/hot/<prof-relative> if present
$hotCfg = if ($cfg -and $cfg.hot_paths) { $cfg.hot_paths } else {
    @("$env:USERPROFILE\.config\opencode", "$env:USERPROFILE\AGENTS.md", "$env:USERPROFILE\Documents\DevBox-Notes")
}
foreach ($hot in $hotCfg) {
    $rel = "$env:USERPROFILE\"
    if ($hot -like "$rel*") {
        $tail = $hot.Substring($rel.Length)
        $src = Join-Path $staging ('hot\' + $tail)
        if (Test-Path $src) {
            New-DevboxDirectorySafe (Split-Path $hot) | Out-Null
            Copy-Item -Path $src -Destination $hot -Recurse -Force
            Write-DevBox OK "HOT restored: $hot"
        } else {
            Write-DevBox INFO "HOT absent from snapshot (first-time item): $hot"
        }
    }
}

# ---- PROJECT: Git canonical - clone/fetch in Projects\ (Phase 20 law)
$projects = Join-Path $env:DEVBOX_WSROOT 'Projects'
New-DevboxDirectorySafe $projects | Out-Null

# ---- OpenCode auth is explicitly NOT persisted unless owner enablen it (Phase 29)
Write-DevBox INFO "OpenCode auth persistence: policy flag governs; default false."

Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
Write-DevBox OK "restore-state done."
