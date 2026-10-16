$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$expectedRun='38930283997'
$expectedVm=[guid]'66b514d0-7246-493f-ade3-1f004cd12411'
if($env:COMPUTERNAME -ine 'runnervm0xl3a'){throw 'Unexpected host; refusing guest link test.'}
$control=Join-Path $env:ProgramData ('WindowsHomePilot\'+$expectedRun)
$session=[IO.File]::ReadAllText((Join-Path $control 'session.json'))|ConvertFrom-Json
if($session.runId -cne $expectedRun -or [guid]$session.vmId -ne $expectedVm){throw 'Live pilot identity mismatch.'}
$vm=Get-VM -Id $expectedVm -ErrorAction Stop
if($vm.State -ne 'Running' -or $vm.Name -cne 'DevBoxWindowsState-38647908553-1'){throw 'Unexpected guest state or identity.'}
$adapters=@(Get-VMNetworkAdapter -VM $vm)
if($adapters.Count -ne 1 -or -not [string]::IsNullOrEmpty($adapters[0].SwitchName)){throw 'Guest adapter no longer disconnected; refusing to change it.'}
$target=Get-VMSwitch -Name 'nat' -ErrorAction Stop
if($target.SwitchType.ToString() -cne 'Internal'){throw 'Expected existing internal switch only.'}
$addressAssigned=$false
try {
 Connect-VMNetworkAdapter -VMNetworkAdapter $adapters[0] -SwitchName $target.Name -ErrorAction Stop
 $end=[DateTime]::UtcNow.AddSeconds(45)
 do {
  Start-Sleep -Seconds 5
  $current=Get-VMNetworkAdapter -VM $vm
  foreach($raw in $current.IPAddresses){
   $ip=$null
   if([Net.IPAddress]::TryParse($raw,[ref]$ip) -and $ip.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork -and $raw -notmatch '^(169\.254\.|127\.|0\.)'){$addressAssigned=$true}
  }
 }while(-not $addressAssigned -and [DateTime]::UtcNow -lt $end)
} finally {
 Disconnect-VMNetworkAdapter -VMNetworkAdapter (Get-VMNetworkAdapter -VM $vm) -ErrorAction Stop
}
$final=Get-VMNetworkAdapter -VM $vm
[ordered]@{test='guest-link-dhcp';addressAssigned=$addressAssigned;restoredDisconnected=[string]::IsNullOrEmpty($final.SwitchName);vmStillRunning=((Get-VM -Id $expectedVm).State.ToString() -ceq 'Running')}|ConvertTo-Json -Compress
