# First-party data bridge only; independent of the authoritative publisher/hold.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ControlDir)
Set-StrictMode -Version Latest;$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or $env:DEVBOX_ISOLATED_TEST -cne '1' -or $env:GITHUB_REPOSITORY -cne 'dougmcdonald87/dougs-box' -or $env:GITHUB_REF -cne 'refs/heads/pilot/windows-home-connection-20261015' -or $env:GITHUB_RUN_ID -cnotmatch '^[1-9][0-9]*$'){throw 'Guest bridge requires isolated manual pilot.'}
$expected=Join-Path $env:ProgramData ('WindowsHomePilot\'+$env:GITHUB_RUN_ID)
if([IO.Path]::GetFullPath($ControlDir) -cne [IO.Path]::GetFullPath($expected)){throw 'Guest bridge requires exact current host control directory.'}
$session=Get-Content -LiteralPath (Join-Path $ControlDir 'session.json') -Raw|ConvertFrom-Json
if($session.schema -ne 1 -or $session.runId -cne $env:GITHUB_RUN_ID -or $session.deadlineMs -le [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()){throw 'Guest bridge host session expired/mismatched.'}
. (Join-Path $PSScriptRoot 'windows-state-roundtrip.ps1')
. (Join-Path $PSScriptRoot 'windows-home-guest-transport.ps1')
$vmId=[guid]$session.vmId;$owner=Get-WindowsStateCheckpointOwner -Root $session.root -VmId $vmId
if($owner.name -cne $session.vmName -or $owner.vm.State -ne 'Running'){throw 'Guest bridge VM identity/state mismatch.'}
$credential=Get-WindowsStatePortableFixtureCredential -VmId $vmId
$guestDir='C:\ProgramData\WindowsHomePilot\'+$session.runId
$guest=$null;$offset=0;$lastFailure=''
try {
 while([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() -lt $session.deadlineMs){
  $receipts=@(Get-WindowsHomeGuestReceiptBatch -ControlDir $ControlDir -Offset $offset)
  # Rotate pages, including when a page contained an unsafe file that was skipped.
  $offset+=32;if($offset -ge @(Get-ChildItem -LiteralPath (Join-Path $ControlDir 'responses') -Filter 'response-*.json' -File).Count){$offset=0}
  $finish=@($receipts|Where-Object {try{$r=$_.json|ConvertFrom-Json;$r.operation -ceq 'Finish' -and $r.status -ceq 'verified' -and $r.verified -eq $true}catch{$false}})
  $state=(Get-VM -Id $vmId -ErrorAction Stop).State.ToString()
  if($state -ceq 'Off' -and $finish.Count){Write-Output 'WINDOWS_HOME_GUEST_BRIDGE_VERIFIED_FINISH=true';break}
  if($state -cne 'Running'){Start-Sleep -Seconds 2;continue}
  try {
   if(-not $guest -or $guest.State -ne 'Opened'){
    if($guest){Remove-PSSession $guest -ErrorAction SilentlyContinue}
    $guest=New-PSSession -VMId $vmId -Credential $credential -ErrorAction Stop
   }
   $requests=@(Invoke-Command -Session $guest -ScriptBlock ${function:Get-WindowsHomeGuestRequestBatch} -ArgumentList $guestDir -ErrorAction Stop)
   $ack=@()
   foreach($request in $requests){if(Add-WindowsHomeGuestRequest -ControlDir $ControlDir -Name $request.name -Json $request.json){$ack+=$request}}
   Invoke-Command -Session $guest -ScriptBlock ${function:Complete-WindowsHomeGuestControlBatch} -ArgumentList $guestDir,$ack,$receipts -ErrorAction Stop
   $lastFailure=''
  } catch {
   # PSDirect can disconnect briefly during export. Retry without terminating VM/publisher.
   $kind=$_.Exception.GetType().Name
   if($kind -cne $lastFailure){Write-Warning ('Guest control transport pending: '+$kind);$lastFailure=$kind}
   if($guest){Remove-PSSession $guest -ErrorAction SilentlyContinue;$guest=$null}
  }
  Start-Sleep -Seconds 2
 }
} finally {if($guest){Remove-PSSession $guest -ErrorAction SilentlyContinue}}
