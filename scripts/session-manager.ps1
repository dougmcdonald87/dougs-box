# session-manager.ps1 — keep the one GitHub Actions job alive after readiness.
# No laptop, existing Tailscale policy, mapped drive, or RustDesk configuration
# is modified by this script.
param([switch]$JobStart, [switch]$SmokeOnly)
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'control-queue.ps1')
. (Join-Path $PSScriptRoot 'invoke-save-isolated.ps1')
. (Join-Path $PSScriptRoot 'backup-cadence.ps1')

if (-not $JobStart) {
    Write-Output 'Session manager requires -JobStart.'
    exit 2
}
Write-Step 'session-manager'

$sessionFile = Join-Path $env:DEVBOX_CONTROL_PATH 'session.json'
if (-not (Test-Path -LiteralPath $sessionFile)) {
    Stop-DevBox 'session.json absent after bootstrap.'
}
$session = Get-Content -LiteralPath $sessionFile -Raw | ConvertFrom-Json
$sessionStart = [DateTime]::Parse($session.startedUtc).ToUniversalTime()
$deadline = $sessionStart.AddMinutes([double]$session.readyTargetMinutes)
$forceStop = $sessionStart.AddMinutes(([double]$session.jobHardLimitMinutes) - 15)
$backupEvery = [TimeSpan]::FromMinutes([double]$session.backupIntervalMin)
$heartbeatFile = Join-Path $env:DEVBOX_CONTROL_PATH 'heartbeat.json'
$lastBackupFile = Join-Path $env:DEVBOX_CONTROL_PATH 'last-backup.json'
# First canary/backup proof already ran before this manager. Never use a
# missing, corrupt, or stale receipt file as the scheduling clock.
$lastPeriodicAttemptUtc = [DateTime]::UtcNow

function Write-Heartbeat {
    $utcNow = [DateTime]::UtcNow
    [ordered]@{
        utc = $utcNow.ToString('o')
        status = 'running'
        minutesRemaining = [math]::Max(0, [math]::Floor(($deadline - $utcNow).TotalMinutes))
    } | ConvertTo-Json -Compress |
        Set-Content -LiteralPath $heartbeatFile -Encoding utf8
}
function Invoke-VerifiedSave {
    param([string]$Reason)
    $saveScript = Join-Path $PSScriptRoot 'save-state.ps1'
    Write-DevBox INFO "Starting $Reason save."
    $saved = Invoke-DevBoxBackupIsolated -SaveScript $saveScript
    if (-not $saved) {
        Write-DevBox WARN "$Reason backup failed. Check the job log and do not assume work was saved."
        return $false
    }
    Write-DevBox OK "$Reason backup step exited 0."
    return $true
}

if ([DateTime]::UtcNow -ge $deadline) {
    Stop-DevBox 'Session startup used its time budget; refusing false READY.'
}
if ([string]::IsNullOrWhiteSpace($env:RESTIC_PASSWORD)) {
    Stop-DevBox 'Session manager has no backup password; cannot promise periodic saves.'
}
# Health-check must see a real, current heartbeat before declaring readiness.
Write-Heartbeat
& (Join-Path $PSScriptRoot 'health-check.ps1')
if ($LASTEXITCODE -ne 0) {
    Stop-DevBox 'Session health check failed. DEVBOX READY was not announced.'
}
& (Join-Path $PSScriptRoot 'health-check.ps1') -SummaryOnly
if ($SmokeOnly) {
    if ($env:DEVBOX_ISOLATED_TEST -ne '1' -or $env:GITHUB_ACTIONS -ne 'true') {
        Stop-DevBox 'Smoke-only session exit is restricted to isolated GitHub regression jobs.'
    }
    Write-DevBox OK 'SESSION STARTUP SMOKE: health checks passed; no long-running session started.'
    exit 0
}
Write-DevBox OK 'DEVBOX READY — interactive session now held open by the active Actions job.'

while ($true) {
    Start-Sleep -Seconds 10
    Write-Heartbeat
    $now = [DateTime]::UtcNow

    if ($now -ge $deadline -or $now -ge $forceStop) {
        Write-DevBox WARN 'Session deadline reached. Attempting final backup before the runner closes.'
        $saved = Invoke-VerifiedSave -Reason 'Final'
        if (-not $saved) {
            Write-DevBox FAIL 'Final save failed; recover earlier verified snapshot if needed.'
            exit 2
        }
        Write-DevBox OK 'Final verified backup succeeded. Closing the session cleanly.'
        exit 0
    }

    # Only the runner process has restic credentials; RDP shortcuts do not.
    # A user-requested stop requires a NEW verified snapshot. Failure keeps
    # this session alive so the user can retry without losing their work.
    $safeStop = Invoke-DevBoxControlRequests -ControlPath $env:DEVBOX_CONTROL_PATH -VerifiedSave {
        param([string]$Action)
        Invoke-VerifiedSave -Reason "Manual $Action"
    }
    if ($safeStop) {
        Write-DevBox OK 'Owner-requested STOP: fresh verified backup succeeded. Ending runner job.'
        exit 0
    }

    # A failed save or malformed on-disk receipt must never cause an endless
    # immediate retry loop. Manual Save/Finish remain processed above.
    if (Test-DevBoxPeriodicSaveDue -NowUtc $now -LastAttemptUtc $lastPeriodicAttemptUtc -Interval $backupEvery) {
        $lastPeriodicAttemptUtc = [DateTime]::UtcNow
        $null = Invoke-VerifiedSave -Reason 'Periodic'
    }

    if (($deadline - $now).TotalMinutes -le 10) {
        Set-Content -LiteralPath (Join-Path $env:DEVBOX_CONTROL_PATH 'finish-now-sentinel.txt') -Value 'Session deadline approaching. Finish work now.' -Encoding utf8
    }
}
