# configure-timezone.ps1 — Windows DevBox only: UK civil time with automatic BST/GMT.
# Does not set the system clock, change the host or touch other tailnet devices.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Command 'tzutil.exe' -ErrorAction SilentlyContinue)) {
    throw 'DEVBOX TIMEZONE FAILED: Windows tzutil.exe is unavailable.'
}

# tzutil /s with NO "_dstoff" suffix keeps the Windows DST adjustment enabled.
& tzutil.exe /s 'GMT Standard Time'
if ($LASTEXITCODE -ne 0) {
    throw "DEVBOX TIMEZONE FAILED: tzutil /s returned $LASTEXITCODE."
}

$current = (& tzutil.exe /g | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $current -cne 'GMT Standard Time') {
    throw "DEVBOX TIMEZONE FAILED: expected GMT Standard Time without _dstoff, got '$current'."
}

# Rule 1: a matching time-zone name alone is insufficient. Check both sides
# of the UK DST transition using genuine UTC instants on this Windows runner.
$zone = [TimeZoneInfo]::Local
$winter = [datetime]::SpecifyKind([datetime]'2026-01-15T12:00:00', [DateTimeKind]::Utc)
$summer = [datetime]::SpecifyKind([datetime]'2026-07-15T12:00:00', [DateTimeKind]::Utc)
$winterMinutes = [int]$zone.GetUtcOffset($winter).TotalMinutes
$summerMinutes = [int]$zone.GetUtcOffset($summer).TotalMinutes
if ($zone.Id -cne 'GMT Standard Time' -or $winterMinutes -ne 0 -or $summerMinutes -ne 60) {
    throw "DEVBOX TIMEZONE FAILED: id=$($zone.Id), winter=$winterMinutes, summer=$summerMinutes; expected GMT Standard Time, 0 and 60."
}

Write-Output "DEVBOX TIMEZONE VERIFIED: $current; January GMT UTC+0, July BST UTC+1."
Write-Output "DEVBOX LOCAL DISPLAY TIME: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
