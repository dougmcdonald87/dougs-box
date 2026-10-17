# Built-in authenticated WinRM for the disposable pilot only. No remote agent install.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest;$ErrorActionPreference='Stop'
function Get-WindowsHomeRepairAccessPolicy {
 param([Parameter(Mandatory)][string]$PilotIp)
 $ip=$null
 if(-not [Net.IPAddress]::TryParse($PilotIp,[ref]$ip) -or $ip.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or $ip.ToString() -cne $PilotIp){throw 'Canonical pilot IPv4 required.'}
 $bytes=$ip.GetAddressBytes()
 if($bytes[0] -ne 100 -or $bytes[1] -lt 64 -or $bytes[1] -gt 127){throw 'Repair access requires the pilot tailnet address.'}
 [pscustomobject]@{LocalAddress=$PilotIp;RemoteAddress='100.64.0.0/10';LocalPort=5985;Basic=$false;AllowUnencrypted=$false}
}
if($env:GITHUB_ACTIONS -cne 'true' -or $env:DEVBOX_ISOLATED_TEST -cne '1' -or $env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or $env:GITHUB_REPOSITORY -cne 'dougmcdonald87/dougs-box' -or $env:GITHUB_REF -cne 'refs/heads/pilot/windows-home-connection-20261015'){throw 'Repair access is restricted to the isolated manual pilot.'}
$ips=@(& tailscale ip -4)
if($LASTEXITCODE -ne 0 -or $ips.Count -ne 1){throw 'Exactly one connected pilot tailnet address required.'}
$policy=Get-WindowsHomeRepairAccessPolicy -PilotIp $ips[0]
$receipt=Join-Path (Join-Path $env:RUNNER_TEMP 'windows-home-restore-hold-rdp') 'rdp-state.txt'
$match=[regex]::Match((Get-Content -LiteralPath $receipt -Raw).Trim(),'^rdpAccounts=(runneradmin|devbox)$')
if(-not $match.Success -or -not (Get-LocalUser -Name $match.Groups[1].Value -ErrorAction Stop).Enabled){throw 'Existing owner account receipt required for repair access.'}
# Close standard WinRM firewall exceptions before starting/creating a listener.
Get-NetFirewallRule -Name 'WINRM-*' -ErrorAction SilentlyContinue|Disable-NetFirewallRule -ErrorAction Stop|Out-Null
$ruleName='WindowsHomePilot-Repair-WinRM'
if(Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue){Remove-NetFirewallRule -Name $ruleName -ErrorAction Stop}
New-NetFirewallRule -Name $ruleName -DisplayName 'Windows Home pilot authenticated repair' -Direction Inbound -Action Allow -Protocol TCP -LocalPort $policy.LocalPort -LocalAddress $policy.LocalAddress -RemoteAddress $policy.RemoteAddress -Profile Any -ErrorAction Stop|Out-Null
Set-Service -Name WinRM -StartupType Manual -ErrorAction Stop;Start-Service -Name WinRM -ErrorAction Stop
Import-Module Microsoft.WSMan.Management -ErrorAction Stop
Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $false -ErrorAction Stop
Set-Item WSMan:\localhost\Service\Auth\Basic -Value $false -ErrorAction Stop
Set-Item WSMan:\localhost\Service\Auth\Negotiate -Value $true -ErrorAction Stop
$listeners=@(Get-ChildItem WSMan:\localhost\Listener|Where-Object {$_.Keys -contains 'Transport=HTTP'})
if(-not $listeners.Count){New-Item -Path WSMan:\localhost\Listener -Transport HTTP -Address '*' -Force -ErrorAction Stop|Out-Null}
$adminPolicy='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
Set-ItemProperty -Path $adminPolicy -Name LocalAccountTokenFilterPolicy -Value 1 -Type DWord -ErrorAction Stop
if([string](Get-Item WSMan:\localhost\Service\AllowUnencrypted).Value -ine 'false' -or [string](Get-Item WSMan:\localhost\Service\Auth\Basic).Value -ine 'false'){throw 'Repair message security readback failed.'}
$rule=Get-NetFirewallRule -Name $ruleName -ErrorAction Stop
$addresses=$rule|Get-NetFirewallAddressFilter -ErrorAction Stop
$ports=$rule|Get-NetFirewallPortFilter -ErrorAction Stop
if($rule.Enabled.ToString() -cne 'True' -or $rule.Action.ToString() -cne 'Allow' -or @($addresses.LocalAddress).Count -ne 1 -or @($addresses.LocalAddress)[0] -cne $policy.LocalAddress -or @($addresses.RemoteAddress).Count -ne 1 -or @($addresses.RemoteAddress)[0] -cne $policy.RemoteAddress -or [string]$ports.LocalPort -cne '5985'){throw 'Repair firewall scope readback failed.'}
$dir=Join-Path $env:ProgramData ('WindowsHomePilotRepair\'+$env:GITHUB_RUN_ID)
if(Test-Path -LiteralPath $dir){throw 'Repair access directory must be new.'}
New-Item -ItemType Directory -Path $dir -ErrorAction Stop|Out-Null
$path=Join-Path $dir 'access.json'
[ordered]@{schema=1;runId=$env:GITHUB_RUN_ID;hostname=('windows-home-pilot-'+$env:GITHUB_RUN_ID);ip=$policy.LocalAddress;port=5985;account=$match.Groups[1].Value;sourceSha=$env:GITHUB_SHA;workspace=$env:GITHUB_WORKSPACE;transport='ntlm-message-encrypted';nativeReadback=$true}|ConvertTo-Json -Compress|Set-Content -LiteralPath $path -Encoding utf8
Write-Output ('PILOT_REPAIR_ACCESS_CONFIGURED='+$policy.LocalAddress+':5985')
# A separate tailnet client must authenticate and exercise this before guest download.

$ready=Join-Path $dir 'ready.json';$deadline=[DateTime]::UtcNow.AddMinutes(5);$verified=$false
while([DateTime]::UtcNow -lt $deadline){
 if(Test-Path -LiteralPath $ready){
  $proof=Get-Content -LiteralPath $ready -Raw|ConvertFrom-Json
  if($proof.schema -ne 1 -or $proof.runId -cne $env:GITHUB_RUN_ID -or $proof.sourceSha -cne $env:GITHUB_SHA -or $proof.account -cne $match.Groups[1].Value -or $proof.admin -ne $true){throw 'Independent repair access proof mismatch.'}
  $verified=$true;break
 }
 Start-Sleep -Seconds 5
}
if(-not $verified){throw 'Independent authenticated repair client unavailable; expensive recovery forbidden.'}
Write-Output 'PILOT_REPAIR_ACCESS_AUTHENTICATED=true'
