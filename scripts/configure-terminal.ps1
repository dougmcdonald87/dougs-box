# Install a Windows command endpoint on the disposable runner, never a laptop.
param([switch]$IsolatedTest)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true') { throw 'Terminal setup is restricted to a disposable Actions runner.' }
if ($IsolatedTest -and $env:DEVBOX_ISOLATED_TEST -ne '1') { throw 'Loopback setup requires the isolated test flag.' }
$address = if ($IsolatedTest) { '127.0.0.1' } else { (& tailscale ip -4 | Select-Object -First 1).Trim() }
$parsed = $null
if (-not [Net.IPAddress]::TryParse($address, [ref]$parsed)) { throw 'No valid listener address.' }
if (-not $IsolatedTest -and ($parsed.GetAddressBytes()[0] -ne 100 -or $parsed.GetAddressBytes()[1] -lt 64 -or $parsed.GetAddressBytes()[1] -gt 127)) {
    throw 'Terminal listener must use the Tailscale IPv4 address.'
}
$state = Join-Path $env:DEVBOX_CONTROL_PATH 'rdp-state.txt'
$account = if ($IsolatedTest) { 'runneradmin' } else { ((Get-Content -LiteralPath $state -Raw).Trim() -replace '^rdpAccounts=', '') }
if ($account -notin @('runneradmin','devbox')) { throw 'Unrecognised DevBox account.' }
$sshd = Join-Path $env:WINDIR 'System32\OpenSSH\sshd.exe'
if (-not (Test-Path -LiteralPath $sshd)) {
    $installed = Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0'
    if ($installed.RestartNeeded) { throw 'OpenSSH install requested a reboot; leaving RDP intact.' }
}
if (-not (Test-Path -LiteralPath $sshd)) { throw 'Built-in OpenSSH server unavailable.' }
Stop-Service sshd -ErrorAction SilentlyContinue
$sshRoot = Join-Path $env:ProgramData 'ssh'
if (-not (Test-Path -LiteralPath $sshRoot)) { New-Item -ItemType Directory -Path $sshRoot | Out-Null }
$keygen = Join-Path $env:WINDIR 'System32\OpenSSH\ssh-keygen.exe'
& $keygen -A
if ($LASTEXITCODE -ne 0) { throw 'SSH host key generation failed.' }
$hostKey = Join-Path $sshRoot 'ssh_host_ed25519_key'
$config = Join-Path $sshRoot 'sshd_config'
@"
Port 22
ListenAddress $address
HostKey $($hostKey.Replace('\','/'))
PasswordAuthentication yes
PubkeyAuthentication yes
PermitEmptyPasswords no
AllowUsers $account
Subsystem sftp sftp-server.exe
"@ | Set-Content -LiteralPath $config -Encoding ascii
& $sshd -t -f $config
if ($LASTEXITCODE -ne 0) { throw 'SSH configuration validation failed.' }
# No public listener. Also restrict the vendor firewall rule to the tailnet.
Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue | Disable-NetFirewallRule | Out-Null
$name = 'DevBox-Tailnet-Terminal'
$rule = Get-NetFirewallRule -Name $name -ErrorAction SilentlyContinue
if ($rule) { $rule | Disable-NetFirewallRule | Out-Null }
$remote = if ($IsolatedTest) { '127.0.0.1' } else { '100.64.0.0/10' }
if ($rule) {
    $rule | Get-NetFirewallAddressFilter | Set-NetFirewallAddressFilter -LocalAddress $address -RemoteAddress $remote | Out-Null
    $rule | Enable-NetFirewallRule | Out-Null
} else {
    New-NetFirewallRule -Name $name -DisplayName 'DevBox terminal (Tailscale only)' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 22 -LocalAddress $address -RemoteAddress $remote | Out-Null
}
Set-Service sshd -StartupType Automatic
Start-Service sshd
(Get-Service sshd).WaitForStatus('Running', [TimeSpan]::FromSeconds(20))
$listeners = @(Get-NetTCPConnection -LocalPort 22 -State Listen -ErrorAction Stop)
if (-not $listeners.Count -or @($listeners | Where-Object LocalAddress -ne $address).Count) { throw 'SSH is not exclusively bound to the selected private address.' }
$destination = Join-Path $env:DEVBOX_CONTROL_PATH 'Terminal'
New-Item -ItemType Directory -Path $destination -Force | Out-Null
[ordered]@{
    version = 1
    runId = [string]$env:GITHUB_RUN_ID
    runAttempt = [string]$env:GITHUB_RUN_ATTEMPT
    address = $address
    account = $account
    workspaceRoot = [string]$env:DEVBOX_WSROOT
    controlPath = [string]$env:DEVBOX_CONTROL_PATH
    hostKey = (Get-Content -LiteralPath "$hostKey.pub" -Raw).Trim()
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $destination 'manifest.json') -Encoding utf8
Write-Output 'WINDOWS TERMINAL HOST READY: private listener and public host-key manifest verified; remote execution still requires a client test.'
