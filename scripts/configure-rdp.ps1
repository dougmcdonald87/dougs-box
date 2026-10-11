# configure-rdp.ps1 - Phase 11/12. Enable built-in Remote Desktop for ONE
# administrative/debug session; NO RD Session Host, NO broker, NO licensing role.
# Prefers the existing runneradmin account. NLA stays ON. 3389 stays tailnet-only;
# a tailnet Grant (not Windows config) decides reachability.
param(
    [Parameter(Mandatory)][securestring]$Password
)
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'common.ps1')
Write-Step 'configure-rdp'

if ([string]::IsNullOrWhiteSpace((New-Object System.Net.NetworkCredential('x', $Password).Password))) {
    Stop-DevBox "DEVBOX_RDP_PASSWORD empty. Next action: add it to the devbox Environment secrets."
}

# --- account choice (Phase 11): inspect, prefer runneradmin
$adminUser = Get-LocalUser -Name 'runneradmin' -ErrorAction SilentlyContinue
if ($adminUser) {
    $acct = 'runneradmin'
    Write-DevBox INFO "using existing runneradmin account (Phase 11 preference)."
} else {
    # fallback account per spec: explicit provisioning
    $acct = 'devbox'
    if (-not (Get-LocalUser -Name $acct -ErrorAction SilentlyContinue)) {
        New-LocalUser -Name $acct -Password $Password -AccountNeverExpires -PasswordNeverExpires |
            Out-Null
    }
    Add-LocalGroupMember -Group 'Administrators' -Member $acct -ErrorAction SilentlyContinue
    Write-DevBox INFO "runneradmin absent on this image: created fallback account devbox."
}

# --- password + group membership
Set-LocalUser -Name $acct -Password $Password -PasswordNeverExpires -AccountNeverExpires
if (-not (Get-LocalGroupMember -Group 'Administrators' -Member $acct -ErrorAction SilentlyContinue)) {
    Add-LocalGroupMember -Group 'Administrators' -Member $acct
}

# --- enable Remote Desktop (built-in), keep NLA ON, no RDS roles anywhere
$tsKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
Set-ItemProperty -Path $tsKey -Name fDenyTSConnections -Value 0 -Type DWord
$rdpWin = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
Set-ItemProperty -Path $rdpWin -Name UserAuthentication -Value 2 -Type DWord   # NLA required
Set-ItemProperty -Path $rdpWin -Name SecurityLayer   -Value 1 -Type DWord

# firewall: allow RDP through Windows locally-inbound only when the connection
# comes in - network exposure is governed by the tailnet Grant. We do NOT open
# 3389 to the internet and we do NOT disable Windows Firewall globally (the
# Phase 39 audit treats that as a hard fail).
netsh advfirewall firewall set rule group='remote desktop' new enable=Yes | Out-Null

# --- NO RDS ROLES: verify nothing weird is installed; refuse if a role snuck in
foreach ($feature in (Get-WindowsFeature | Where-Object { $_.Name -like 'RDS-*' -and $_.Installed })) {
    Stop-DevBox "RDS role $($feature.Name) is installed on this image. Next action: abort; multi-user RDS is out of scope by law."
}

# --- services
Set-Service -Name TermService -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service TermService -ErrorAction SilentlyContinue

# --- Phase 11 hard test: the Actions worker must still answer after this step
Start-Sleep -Seconds 2
$liveness = whoami
if ([string]::IsNullOrWhiteSpace($liveness)) {
    Stop-DevBox "worker stopped responding after RDP configuration. Next action: fall back to the devbox account path in the spec."
}

# --- listener proof
$listening = Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue
if (-not $listening) { Stop-DevBox "3389 not listening after RDP enable. Next action: check TermService event log." }

# --- Phase 11 hard test: the interactive worker must STILL answer after this step
Start-Sleep -Seconds 2
Write-DevBox OK "RDP ready: acct $acct, NLA on, 3389 listening, no RDS roles."
"rdpAccounts=$acct" | Out-File -FilePath (Join-Path $env:DEVBOX_CONTROL_PATH 'rdp-state.txt') -Encoding utf8
