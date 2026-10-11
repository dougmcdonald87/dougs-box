# health-check.ps1 - Phase 35/36. Mandatory checks; ANY failure prints
# 'DEVBOX FAILED' with the exact next action. Never false READY.
param(
    [switch]$SummaryOnly
)
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'common.ps1')

if ($SummaryOnly) {
    # Phase 36 READY summary: public-safe fields only.
    $session = Get-Content (Join-Path $env:DEVBOX_CONTROL_PATH 'session.json') -Raw | ConvertFrom-Json
    $ocv = if (Test-Path (Join-Path $env:DEVBOX_CONTROL_PATH 'opencode-version.txt')) {
                (Get-Content (Join-Path $env:DEVBOX_CONTROL_PATH 'opencode-version.txt')) } else { 'unknown' }
    Write-StepSummary @(
        "### DEVBOX READY",
        "- mode/persistence: session file present",
        "- workspace: $($session.workspaceRoot)",
        "- OpenCode: $ocv",
        "- last backup: $(if (Test-Path (Join-Path $env:DEVBOX_CONTROL_PATH 'last-backup.json')) { (Get-Content (Join-Path $env:DEVBOX_CONTROL_PATH 'last-backup.json') -Raw | ConvertFrom-Json).snapshotId } else { 'none yet' })",
        "**Open Tailscale and select the ephemeral DevBox node. Sign in with runneradmin via RDP.**"
    )
    exit 0
}

Write-Step 'health-check'
$failures = @()

function Add-Failure {
    param([Parameter(Mandatory)][string]$Item, [Parameter(Mandatory)][string]$Action)
    $script:failures = $script:failures + "$Item -- next action: $Action"
}

# --- workspace sanity
if (-not $env:DEVBOX_WSROOT) { Add-Failure 'workspace root unset' 're-run bootstrap' }
elseif (-not (Test-Path $env:DEVBOX_WSROOT)) { Add-Failure "workspace root missing ($env:DEVBOX_WSROOT)" 're-run discover-storage + bootstrap' }

# --- OS / CPU / RAM basic expectations (informational but recorded)
$os = Get-CimInstance Win32_OperatingSystem
Write-DevBox INFO "host: $($os.Caption) build $($os.BuildNumber), RAM $([math]::Round($os.TotalVisibleMemorySize/1MB,1)) GB, CPU $env:NUMBER_OF_PROCESSORS"

# --- tools
foreach ($tool in @('git','pwsh','python')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Add-Failure "$tool missing" 'image should provide it; check probe-runners output'
    }
}

# --- OpenCode
$ocExe = Get-ChildItem "$env:DEVBOX_WSROOT\Tools\OpenCode" -Filter 'opencode.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $ocExe) { Add-Failure 'OpenCode missing' 're-run install-opencode' }

# --- Tailscale
$tsStatus = & tailscale status --json 2>$null | ConvertFrom-Json
if (-not $tsStatus) { Add-Failure 'tailscale status empty' 'confirm the join step ran' }
else {
    $self = $tsStatus.Self
    if (-not ($self.Tags -contains 'tag:github-devbox')) {
        Add-Failure 'wrong/unset node tag' 'check the join step tags argument'
    }
}

# --- RDP
$tsSvc = Get-Service TermService -ErrorAction SilentlyContinue
if ($tsSvc.Status -ne 'Running') { Add-Failure 'TermService not running' 'enable+start via configure-rdp' }
$nla = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -ErrorAction SilentlyContinue).UserAuthentication
if ($nla -ne 1) { Add-Failure 'NLA not enforced' 'configure-rdp sets UserAuthentication=1; re-run it' }
if (-not (Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue)) {
    Add-Failure '3389 not listening' 'check TermService + Windows service log'
}
# NO RDS ROLE check (law)
if (Get-WindowsFeature | Where-Object { $_.Name -like 'RDS-*' -and $_.Installed }) {
    Add-Failure 'RDS role installed' 'prohibited; image is broken for DevBox law - stop and rebuild'
}

# --- persistence (optional but enforced-if-configured)
$persistPath = Join-Path $env:DEVBOX_CONTROL_PATH 'persistence.json'
if (Test-Path $persistPath) {
    $persist = Get-Content $persistPath -Raw | ConvertFrom-Json
    $tcp = New-Object System.Net.Sockets.TcpClient
    try { $tcp.Connect($persist.storageIp, 8000) | Out-Null } catch { Add-Failure "rest-server unreachable $($persist.storageIp):8000" 'storage host down or Grant missing' } finally { $tcp.Dispose() }
    if (Test-Path (Join-Path $env:DEVBOX_CONTROL_PATH 'last-backup.json')) {
        # backup canary proof recorded by save-state; presence required after first save
        $lb = Get-Content (Join-Path $env:DEVBOX_CONTROL_PATH 'last-backup.json') -Raw | ConvertFrom-Json
        if (-not $lb.snapshotId) { Add-Failure 'last backup has no snapshot id' 'run Save DevBox State Now' }
    }
}

# --- session manager liveness
$heart = Join-Path $env:DEVBOX_CONTROL_PATH 'heartbeat.json'
if (-not (Test-Path $heart)) { Add-Failure 'session manager not yet writing heartbeats' 'expected within 60s of start; re-check' }

# --- verdict (Phase 35: loud, exact, no ambiguity)
if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-DevBox FAIL $_ }
    Write-StepSummary @("### DEVBOX FAILED", ($failures | ForEach-Object { "- $_" }))
    exit 2
}

Write-DevBox OK "all mandatory checks passed."
exit 0
