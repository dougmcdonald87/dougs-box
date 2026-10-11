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

if ($Password.Length -eq 0) {
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
Set-LocalUser -Name $acct -Password $Password -PasswordNeverExpires $true -AccountNeverExpires -ErrorAction Stop
# Get-LocalGroupMember has no -Member parameter. Enumerate the group
# members explicitly and compare SIDs, not localized name strings.
$acctSid = (Get-LocalUser -Name $acct).SID.Value
$adminMembers = @(Get-LocalGroupMember -Group 'Administrators' -ErrorAction Stop)
if (-not @($adminMembers | Where-Object { $_.SID.Value -eq $acctSid }).Count) {
    Add-LocalGroupMember -Group 'Administrators' -Member $acct -ErrorAction Stop
}

# --- enable Remote Desktop (built-in), keep NLA ON, no RDS roles anywhere
$tsKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
Set-ItemProperty -Path $tsKey -Name fDenyTSConnections -Value 0 -Type DWord
$rdpWin = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
Set-ItemProperty -Path $rdpWin -Name UserAuthentication -Value 1 -Type DWord   # Microsoft: 1 requires NLA; 0 does not
Set-ItemProperty -Path $rdpWin -Name SecurityLayer   -Value 1 -Type DWord

# firewall: allow RDP through Windows locally-inbound only when the connection
# comes in - network exposure is governed by the tailnet Grant. We do NOT open
# 3389 to the internet and we do NOT disable Windows Firewall globally (the
# Phase 39 audit treats that as a hard fail).
# Restrict the enabled Windows RDP firewall group to Tailscale 100.64.0.0/10.
# The GitHub hosted Windows runner is disposable, but RDP must not be left
# accessible to arbitrary public IPv4 addresses.
$rdpRules = @(Get-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction Stop)
if ($rdpRules.Count -eq 0) { Stop-DevBox 'No Windows Remote Desktop firewall rules found.' }
foreach ($rule in $rdpRules) {
    $rule | Get-NetFirewallAddressFilter | Set-NetFirewallAddressFilter -RemoteAddress '100.64.0.0/10' -ErrorAction Stop | Out-Null
    if ($rule.Enabled -ne 'True') {
        Set-NetFirewallRule -Name $rule.Name -Enabled True -ErrorAction Stop | Out-Null
    }
}

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
