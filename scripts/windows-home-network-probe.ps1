# Disposable consumer-only experiment. No topology/addresses leave the runner.
function Test-WindowsHomeGuestNetwork {
 param([Parameter(Mandatory)][guid]$VmId,[Parameter(Mandatory)][pscredential]$Credential)
 $ErrorActionPreference='Stop'
 try {
  if($env:WINDOWS_HOME_DISPOSABLE_NETWORK_PROBE -cne '1' -or (Test-Path (Join-Path $env:ProgramData 'WindowsHomePilot')) -or $env:GITHUB_ACTIONS -cne 'true' -or $env:DEVBOX_ISOLATED_TEST -cne '1' -or $env:GITHUB_REF -cne 'refs/heads/pilot/windows-home-connection-20261015'){throw 'context'}
  $vm=Get-VM -Id $VmId -ErrorAction Stop
  $adapters=@(Get-VMNetworkAdapter -VM $vm)
  if($vm.State -ne 'Running' -or $adapters.Count -ne 1 -or -not [string]::IsNullOrEmpty($adapters[0].SwitchName)){throw 'adapter'}
  $switch=Get-VMSwitch -Name 'nat' -ErrorAction Stop
  if($switch.SwitchType.ToString() -cne 'Internal'){throw 'switch'}
  # Reuse the runner's existing NAT. Never create/remove a host switch or NAT.
  $networks=@(Get-HnsNetwork|Where-Object {$_.Name -ceq 'nat' -and $_.Type -ieq 'nat'})
  if($networks.Count -ne 1 -or @($networks[0].Subnets).Count -ne 1){throw 'nat'}
  $subnet=$networks[0].Subnets[0]
  $occupied=@(Get-HnsEndpoint|ForEach-Object {$_.IPAddress}|Where-Object {$_})
  $occupied+=@(Get-NetIPAddress -AddressFamily IPv4|ForEach-Object {$_.IPAddress})
  $raw=& python (Join-Path $PSScriptRoot 'windows_home_network_address.py') ([string]$subnet.AddressPrefix) ([string]$subnet.GatewayAddress) @occupied
  if($LASTEXITCODE -ne 0){throw 'address'}
  $address=($raw -join "`n")|ConvertFrom-Json
  Connect-VMNetworkAdapter -VMNetworkAdapter $adapters[0] -SwitchName $switch.Name -ErrorAction Stop
  $result=Invoke-Command -VMId $VmId -Credential $Credential -ArgumentList $adapters[0].MacAddress,$address.address,$address.prefix,$address.gateway -ScriptBlock {
   param($Mac,$Address,$Prefix,$Gateway)
   $ErrorActionPreference='Stop'
   $stage='adapter'
   try {
    $nics=@(Get-NetAdapter|Where-Object {$_.MacAddress.Replace('-','') -ieq $Mac})
    if($nics.Count -ne 1){throw 'adapter'}
    $idx=$nics[0].ifIndex
    $existing=@(Get-NetIPAddress -InterfaceIndex $idx -AddressFamily IPv4 -ErrorAction SilentlyContinue)
    if(@($existing|Where-Object {$_.IPAddress -notmatch '^169\.254\.'}).Count){throw 'configured'}
    $stage='address'
    Set-NetIPInterface -InterfaceIndex $idx -AddressFamily IPv4 -Dhcp Disabled
    foreach($ip in @(Get-NetIPAddress -InterfaceIndex $idx -AddressFamily IPv4 -ErrorAction SilentlyContinue)){Remove-NetIPAddress -InputObject $ip -Confirm:$false -ErrorAction Stop}
    New-NetIPAddress -InterfaceIndex $idx -IPAddress $Address -PrefixLength $Prefix -DefaultGateway $Gateway|Out-Null
    Set-DnsClientServerAddress -InterfaceIndex $idx -ServerAddresses @('1.1.1.1','8.8.8.8')
    Start-Sleep -Seconds 5
    $stage='dns'
    $resolved=@(Resolve-DnsName www.microsoft.com -Type A -ErrorAction Stop)
    if(-not $resolved.Count){throw 'dns'}
    $stage='https'
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    $response=Invoke-WebRequest -Uri 'https://www.microsoft.com/' -UseBasicParsing -TimeoutSec 25 -ErrorAction Stop
    if([int]$response.StatusCode -ne 200){throw 'https'}
    [pscustomobject]@{verified=$true;stage='https'}
   } catch {[pscustomobject]@{verified=$false;stage=$stage}}
  }
  [pscustomobject]@{verified=($result.verified -eq $true);stage=[string]$result.stage;consumerOnly=$true}
 } catch {[pscustomobject]@{verified=$false;stage='host-preflight';consumerOnly=$true}}
}
