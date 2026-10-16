# check-storage-host.ps1 - Phase 43. Verifies every mandatory storage-host property.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '..\scripts\common.ps1')
Write-Step 'check-storage-host'

$statePath = 'C:\DevBox-Storage\rest-server\storage-host-state.json'
if (-not (Test-Path $statePath)) { Stop-DevBox 'storage host state file missing. Next action: run setup-storage-host.ps1 first.' }
$state = Get-Content $statePath -Raw | ConvertFrom-Json
$failures = @()

# tailscale online + identity
$tsStatus = & tailscale status --json | ConvertFrom-Json
if (-not $tsStatus) { $failures += 'tailscale status empty' }
elseif ([string]::IsNullOrWhiteSpace($tsStatus.Self.TailscaleIPs[0])) { $failures += 'no tailnet IP on host' }

# rest-server process + bound address + port
$task = Get-ScheduledTask -TaskName 'DevBox-RestServer' -ErrorAction SilentlyContinue
if (-not $task) { $failures += 'boot task DevBox-RestServer missing' }
$listener = Get-NetTCPConnection -LocalPort $state.port -State Listen -ErrorAction SilentlyContinue
if (-not $listener) { $failures += "nothing listening on port $($state.port)" }
elseif (($listener | Where-Object { $_.LocalAddress -eq '0.0.0.0' })) {
    $failures += 'bind is 0.0.0.0 which the Phase 16 law PROHIBITS (must be the tailnet IP only)'
}

# append-only / no-auth / persistent-path verification = task arguments
$argLine = $task.Actions[0].Arguments
if ($argLine -notmatch '--append-only') { $failures += 'task args lack --append-only' }
if ($argLine -notmatch '--no-auth')     { $failures += 'task args lack --no-auth' }
if ($argLine -match 'TLS|https|htpasswd') { $failures += 'task args mention TLS/auth stack (extra security layer NOT allowed)' }
if ($argLine -match 'TEMP') { $failures += 'data path is under TEMP (prohibited)' }

# free space
$drive = Get-PSDrive -Name ($state.dataPath.SubString(0, 1)) -ErrorAction SilentlyContinue
Write-DevBox INFO ("storage free: {0} GiB on {1}" -f [math]::Round($drive.Free / $OneGiB, 2), $state.dataPath)
if (($drive.Free / $OneGiB) -lt 10) { $failures += 'storage below 10 GiB free; maintenance conversation needed' }

if ($failures.Count) {
    $failures | ForEach-Object { Write-DevBox FAIL $_ }
    exit 2
}
Write-DevBox OK "storage host healthy: $($state.tailnetIp):$($state.port), append-only, no-auth, persistent path, boot task registered."
exit 0
