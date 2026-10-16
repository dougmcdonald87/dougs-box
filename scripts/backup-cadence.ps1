# backup-cadence.ps1 — isolated, monotonic-within-session retry gate.
# The caller must update LastAttemptUtc BEFORE invoking a potentially failing
# child backup; neither missing metadata nor an exit 3 causes rapid retries.
Set-StrictMode -Version Latest

function Test-DevBoxPeriodicSaveDue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][datetime]$NowUtc,
        [Parameter(Mandatory)][datetime]$LastAttemptUtc,
        [Parameter(Mandatory)][timespan]$Interval
    )
    if ($Interval.TotalSeconds -lt 60) {
        throw 'Periodic backup interval must be at least one minute.'
    }
    return (($NowUtc - $LastAttemptUtc) -ge $Interval)
}
