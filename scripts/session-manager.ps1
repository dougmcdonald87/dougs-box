# session-manager.ps1 - Phase 31/32/33/34. Heartbeat, safe deadline, backup
# schedule, disk monitor, tailnet path awareness. No busy loop (60s cadence,
# small writes). Runs detached from the workflow process.
param([switch]$JobStart)
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'common.ps1')

if (-not $JobStart) {
    Write-Output 'session-manager: pass -JobStart to run the loop as a background worker.'
    exit 0
}

Write-Step 'session-manager'

$session = Get-Content (Join-Path $env:DEVBOX_CONTROL_PATH 'session.json') -Raw | ConvertFrom-Json
$persistPath = Join-Path $env:DEVBOX_CONTROL_PATH 'persistence.json'
$hasPersist = Test-Path $persistPath

# ---- session maths (Phase 32): deadline = JobStart + readyTarget, hard stop at job timeout minus reserve
$sessionStart     = [DateTime]::Parse($session.startedUtc, [CultureInfo]::InvariantCulture, [DateTimeStyles]::RoundtripKind)
$readyTarget      = New-TimeSpan -Minutes ([int]$session.readyTargetMinutes)
$deadline         = $sessionStart.Add($readyTarget)
$hardLimit        = New-TimeSpan -Minutes ([int]$session.jobHardLimitMinutes)
$backupEvery      = New-TimeSpan -Minutes ([int]$session.backupIntervalMin)

# ---- heartbeat loop; 60-second cadence; tiny writes; no busy loop (Phase 31)
$cwd = Get-Location
while ($true) {
    Start-Sleep -Seconds 60
    $now = Get-Date
    $elapsed = $now - $sessionStart
    $remaining = $deadline - $now

    # ---- heartbeat (public-safe fields)
    $freeGiB = 0
    try {
        $null = $elapsed
    $driveLetter = if ($env:DEVBOX_WSROOT) { $env:DEVBOX_WSROOT.SubString(0, 2) } else { $session.workspaceRoot.SubString(0, 2) }
        $drive = Get-PSDrive -Name $driveLetter[0] -ErrorAction SilentlyContinue
        $freeGiB = [math]::Round($drive.Free / $OneGiB, 2)
    } catch { $freeGiB = -1 }

    # ---- disk monitor (Phase 34)
    if ($freeGiB -ge 0) {
        if ($freeGiB -le [double]$session.diskCritFreeGiB) {
            Write-DevBox WARN "DISK CRITICAL at $freeGiB GiB. Hydration suspended; disposable dirs named in TROUBLESHOOTING; NO user data deleted automatically."
        } elseif ($freeGiB -le [double]$session.diskWarnFreeGiB) {
            Write-DevBox WARN "disk below warning at $freeGiB GiB."
        }
    }

    # ---- backup scheduler: periodic saves; skip if persistence offline
    $lastSave = Join-Path $env:DEVBOX_CONTROL_PATH 'last-backup.json'
    $lastUtc = if (Test-Path $lastSave) { [DateTime]::Parse((Get-Content $lastSave -Raw | ConvertFrom-Json).utc) } else { $sessionStart.AddMinutes(-1) }
    $sinceLast = $now - $lastUtc
    if ($hasPersist -and $sinceLast -gt $backupEvery) {
        try {
            & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'save-state.ps1') 2>&1 |
                Out-File (Join-Path $env:DEVBOX_LOGS_PATH 'save-state-periodic.log') -Encoding utf8 -Append -ErrorAction SilentlyContinue
        } catch {
            Write-DevBox WARN "periodic save failed: $($_.Exception.Message)"
        }
    }

    # ---- safe deadline: write sentinel past which finishing is unsafe
    if ($remaining -le (New-TimeSpan -Minutes 10)) {
        Set-Content -LiteralPath (Join-Path $env:DEVBOX_CONTROL_PATH 'finish-now-sentinel.txt') `
            -Value 'deadline closing; owner must run Finish DevBox Safely NOW' -Encoding utf8
    }

    if ($elapsed -ge $hardLimit.Subtract([TimeSpan]::FromMinutes(15))) {
        Write-DevBox WARN "approaching GitHub hard limit; forced-save path triggered."
        if ($hasPersist) {
            & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'save-state.ps1') 2>&1 |
                Out-File (Join-Path $env:DEVBOX_LOGS_PATH 'save-state-final-attempt.log') -Encoding utf8 -ErrorAction SilentlyContinue
        }
        Set-Content -LiteralPath (Join-Path $env:DEVBOX_CONTROL_PATH 'session-deadline-met.txt') `
            -Value 'hard-limit window entered; session must end' -Encoding utf8
        exit 0
    }
}
