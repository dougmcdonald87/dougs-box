# Install the existing owner request client inside the verified Home guest C.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ControlDir)
Set-StrictMode -Version Latest;$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or $env:DEVBOX_ISOLATED_TEST -cne '1' -or $env:GITHUB_REPOSITORY -cne 'dougmcdonald87/dougs-box' -or $env:GITHUB_REF -cne 'refs/heads/pilot/windows-home-connection-20261015' -or $env:GITHUB_RUN_ID -cnotmatch '^[1-9][0-9]*$'){throw 'Guest controls require isolated manual pilot.'}
$expected=Join-Path $env:ProgramData ('WindowsHomePilot\'+$env:GITHUB_RUN_ID)
if([IO.Path]::GetFullPath($ControlDir) -cne [IO.Path]::GetFullPath($expected)){throw 'Guest controls require exact current host control directory.'}
$session=Get-Content -LiteralPath (Join-Path $ControlDir 'session.json') -Raw|ConvertFrom-Json
if($session.schema -ne 1 -or $session.runId -cne $env:GITHUB_RUN_ID -or $session.deadlineMs -le [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()){throw 'Guest controls require current unexpired host session.'}
. (Join-Path $PSScriptRoot 'windows-state-roundtrip.ps1')
$vmId=[guid]$session.vmId
$owner=Get-WindowsStateCheckpointOwner -Root $session.root -VmId $vmId
if($owner.name -cne $session.vmName -or $owner.vm.State -ne 'Running'){throw 'Guest control VM identity/state mismatch.'}
$publicSession=[ordered]@{schema=1;runId=$session.runId;vmId=$session.vmId;generation=$session.generation;deadlineMs=$session.deadlineMs}|ConvertTo-Json -Compress
$client=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'windows-home-request.ps1') -Raw
$credential=Get-WindowsStatePortableFixtureCredential -VmId $vmId
$guest=New-PSSession -VMId $vmId -Credential $credential -ErrorAction Stop
try {
 $result=Invoke-Command -Session $guest -ArgumentList $session.runId,$publicSession,$client -ErrorAction Stop -ScriptBlock {
  param($RunId,$PublicSession,$Client)
  $ErrorActionPreference='Stop'
  if($env:SystemDrive -cne 'C:' -or $RunId -cnotmatch '^[1-9][0-9]*$'){throw 'Guest C control target mismatch.'}
  $dir=Join-Path $env:ProgramData ('WindowsHomePilot\'+$RunId)
  foreach($path in @((Join-Path $env:ProgramData 'WindowsHomePilot'),$dir,(Join-Path $dir 'requests'),(Join-Path $dir 'responses'))){
   if(Test-Path -LiteralPath $path){$item=Get-Item -LiteralPath $path -Force;if(-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Guest control path is unsafe.'}}
   else{New-Item -ItemType Directory -Path $path|Out-Null}
  }
  $users=[Security.Principal.SecurityIdentifier]::new('S-1-5-32-545')
  $acl=Get-Acl -LiteralPath $dir
  $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($users,'ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow'))
  Set-Acl -LiteralPath $dir -AclObject $acl
  $requests=Join-Path $dir 'requests';$acl=Get-Acl -LiteralPath $requests
  $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($users,'Modify','ContainerInherit,ObjectInherit','None','Allow'))
  Set-Acl -LiteralPath $requests -AclObject $acl
  foreach($name in @('session.json','windows-home-request.ps1')){if(Test-Path -LiteralPath (Join-Path $dir $name)){$item=Get-Item -LiteralPath (Join-Path $dir $name) -Force;if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Guest control file is unsafe.'}}}
  [IO.File]::WriteAllText((Join-Path $dir 'session.json'),$PublicSession,[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText((Join-Path $dir 'windows-home-request.ps1'),$Client,[Text.UTF8Encoding]::new($false))
  $desktop=Join-Path $env:PUBLIC 'Desktop';$shell=New-Object -ComObject WScript.Shell
  foreach($operation in @('Save','Finish')){
   $link=$shell.CreateShortcut((Join-Path $desktop ($operation+' Windows Home.lnk')))
   $link.TargetPath=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
   $link.Arguments=('-NoExit -NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $dir 'windows-home-request.ps1')+'" -Operation '+$operation+' -ControlDir "'+$dir+'"')
   $link.WorkingDirectory=$dir;$link.Description='Request verified encrypted '+$operation+' for this Windows Home session';$link.Save()
  }
  [pscustomobject]@{controlDir=$dir;runId=$RunId;clientSha256=(Get-FileHash -LiteralPath (Join-Path $dir 'windows-home-request.ps1') -Algorithm SHA256).Hash;session=$PublicSession}
 }
 if($result.runId -cne $session.runId -or $result.controlDir -cne ('C:\ProgramData\WindowsHomePilot\'+$session.runId)){throw 'Guest C provisioning receipt mismatch.'}
 Write-Output ('WINDOWS_HOME_GUEST_CONTROL_DIR='+$result.controlDir)
 Write-Output ('WINDOWS_HOME_GUEST_CLIENT_SHA256='+$result.clientSha256)
} finally {Remove-PSSession $guest -ErrorAction SilentlyContinue}
