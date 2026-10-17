# Native readback reproduction only: one disposable firewall rule, no listener/guest VM.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if($env:GITHUB_ACTIONS -cne 'true' -or $env:DEVBOX_ISOLATED_TEST -cne '1' -or $env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or $env:GITHUB_REPOSITORY -cne 'dougmcdonald87/dougs-box' -or $env:GITHUB_REF -cne 'refs/heads/pilot/windows-home-connection-20261015'){throw 'Native readback probe requires isolated pilot.'}
$name='WindowsHomePilot-ScopeProbe-'+$env:GITHUB_RUN_ID
if(Get-NetFirewallRule -Name $name -ErrorAction SilentlyContinue){throw 'Probe must not replace an existing rule.'}
try {
 New-NetFirewallRule -Name $name -DisplayName $name -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5985 -LocalAddress '100.64.0.42' -RemoteAddress '100.64.0.0/10' -Profile Any -ErrorAction Stop|Out-Null
 $rule=Get-NetFirewallRule -Name $name -ErrorAction Stop;$addresses=$rule|Get-NetFirewallAddressFilter -ErrorAction Stop;$ports=$rule|Get-NetFirewallPortFilter -ErrorAction Stop
 Write-Host ('PILOT_SCOPE_NATIVE_READBACK='+([ordered]@{enabled=$rule.Enabled.ToString();action=$rule.Action.ToString();localAddress=@($addresses.LocalAddress);remoteAddress=@($addresses.RemoteAddress);localPort=@($ports.LocalPort);protocol=[string]$ports.Protocol;localType=$addresses.LocalAddress.GetType().FullName;remoteType=$addresses.RemoteAddress.GetType().FullName;portType=$ports.LocalPort.GetType().FullName}|ConvertTo-Json -Compress))
 $matched=$rule.Enabled.ToString() -ceq 'True' -and $rule.Action.ToString() -ceq 'Allow' -and @($addresses.LocalAddress).Count -eq 1 -and @($addresses.LocalAddress)[0] -ceq '100.64.0.42' -and @($addresses.RemoteAddress).Count -eq 1 -and @($addresses.RemoteAddress)[0] -ceq '100.64.0.0/10' -and [string]$ports.LocalPort -ceq '5985'
 Write-Host ('PILOT_SCOPE_ORIGINAL_PREDICATE='+$matched)
 if(-not $matched){throw 'Exact old firewall predicate reproduced failure; inspect native readback before changing scope.'}
} finally {Remove-NetFirewallRule -Name $name -ErrorAction SilentlyContinue}
