# Pure cadence falsification: a missing or corrupt last-backup.json has no
# bearing on the in-process backup schedule. No secrets, storage or timers.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\backup-cadence.ps1')
$start = [datetime]'2026-10-12T01:04:20Z'
$interval = [timespan]::FromMinutes(10)
if (Test-DevBoxPeriodicSaveDue -NowUtc $start.AddSeconds(10) -LastAttemptUtc $start -Interval $interval) { throw 'Early repeated backup accepted.' }
if (Test-DevBoxPeriodicSaveDue -NowUtc $start.AddMinutes(9).AddSeconds(59) -LastAttemptUtc $start -Interval $interval) { throw 'Backup permitted before ten minutes.' }
if (-not (Test-DevBoxPeriodicSaveDue -NowUtc $start.AddMinutes(10) -LastAttemptUtc $start -Interval $interval)) { throw 'Ten-minute backup suppressed.' }
# Mimic update-before-attempt even if backup failed. First retry 10 seconds
# later must remain blocked, instead of creating 601 backups in four hours.
$attempt = $start.AddMinutes(10)
if (Test-DevBoxPeriodicSaveDue -NowUtc $attempt.AddSeconds(10) -LastAttemptUtc $attempt -Interval $interval) { throw 'Failed backup immediately retried.' }
if (-not (Test-DevBoxPeriodicSaveDue -NowUtc $attempt.AddMinutes(10) -LastAttemptUtc $attempt -Interval $interval)) { throw 'Failed backup never retried.' }
$rejected = $false
try { Test-DevBoxPeriodicSaveDue -NowUtc $start -LastAttemptUtc $start -Interval ([timespan]::Zero) | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw 'Dangerous zero interval accepted.' }
Write-Output 'DEVBOX TEN-MINUTE PERIODIC CADENCE: PASS'
