# Create VMConnect and owner desktop Save/Finish shortcuts on the DISPOSABLE RDP host.
[CmdletBinding()]
param([Parameter(Mandatory)][guid]$VmId,[Parameter(Mandatory)][string]$Root,
      [Parameter(Mandatory)][string]$ExpectedGeneration,[Parameter(Mandatory)][string]$OriginGeneration)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:DEVBOX_ISOLATED_TEST -cne '1' -or $env:GITHUB_REF -cne 'refs/heads/pilot/windows-home-connection-20261015' -or $env:GITHUB_RUN_ID -cnotmatch '^[1-9][0-9]*$'){throw 'Only isolated manual pilot runner may provision desktop controls.'}
$pattern='^devbox-checkpoint-v1-ci-([1-9][0-9]*)-([1-9][0-9]*)-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{32}$'
if($ExpectedGeneration -cnotmatch $pattern){throw 'Exact transferred generation required.'}
$origin=[regex]::Match($OriginGeneration,$pattern)
if(-not $origin.Success){throw 'Invalid original owned guest generation.'}
. (Join-Path $PSScriptRoot 'windows-state-checkpoint.ps1')
$owner=Get-WindowsStateCheckpointOwner -Root $Root -VmId $VmId
if($owner.name -cne ('DevBoxWindowsState-'+$origin.Groups[1].Value+'-'+$origin.Groups[2].Value) -or $owner.vm.State -ne 'Running'){throw 'Unexpected guest identity or state.'}
$vmconnect=Join-Path $env:WINDIR 'System32\vmconnect.exe'
if(-not(Test-Path -LiteralPath $vmconnect -PathType Leaf)){throw 'Hyper-V console executable missing.'}
$rdpUser=Get-LocalUser -Name 'runneradmin' -ErrorAction Stop
if(-not $rdpUser.Enabled){throw 'RDP owner account disabled.'}
$dir=Join-Path $env:ProgramData ('WindowsHomePilot\'+$env:GITHUB_RUN_ID)
if(Test-Path -LiteralPath $dir){throw 'Per-run control directory must be new.'}
New-Item -Path $dir -ItemType Directory -ErrorAction Stop|Out-Null
$acl=Get-Acl -LiteralPath $dir
$acl.SetAccessRuleProtection($true,$false)
foreach($sid in @([Security.Principal.WindowsIdentity]::GetCurrent().User.Value,$rdpUser.SID.Value,'S-1-5-18')|Select-Object -Unique){
 $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow'))
}
Set-Acl -LiteralPath $dir -AclObject $acl -ErrorAction Stop
foreach($name in @('requests','responses')){New-Item -ItemType Directory -Path (Join-Path $dir $name) -ErrorAction Stop|Out-Null}
$deadline=[DateTimeOffset]::UtcNow.AddMinutes(220).ToUnixTimeMilliseconds()
[ordered]@{schema=1;runId=$env:GITHUB_RUN_ID;vmId=$VmId.ToString('D').ToLowerInvariant();generation=$ExpectedGeneration;originGeneration=$OriginGeneration;root=$owner.root;vmName=$owner.name;deadlineMs=$deadline}|
 ConvertTo-Json -Compress|Set-Content -LiteralPath (Join-Path $dir 'session.json') -Encoding utf8
$desktop=Join-Path $env:PUBLIC 'Desktop'
if(-not(Test-Path -LiteralPath $desktop -PathType Container)){throw 'Public Desktop unavailable.'}
$shell=New-Object -ComObject WScript.Shell
$console=$shell.CreateShortcut((Join-Path $desktop 'Windows 10 Home VM.lnk'))
$console.TargetPath=$vmconnect
$console.Arguments=('localhost "'+$owner.name+'"')
$console.Description='Actual Hyper-V Windows 10 Home guest console (not runner host)'
$console.Save()
$client=Join-Path $PSScriptRoot 'windows-home-request.ps1'
if(-not(Test-Path -LiteralPath $client -PathType Leaf)){throw 'Save/Finish helper missing.'}
foreach($op in @('Save','Finish')){
 $link=$shell.CreateShortcut((Join-Path $desktop ('Windows 10 Home '+$op+'.lnk')))
 $link.TargetPath=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $link.Arguments=('-NoProfile -ExecutionPolicy Bypass -File "'+$client+'" -Operation '+$op+' -ControlDir "'+$dir+'"')
 $link.Description='Submit owner '+$op+'; only published encrypted receipt is success'
 $link.Save()
}
Write-Output ('WINDOWS_HOME_VMCONNECT_SHORTCUT_READY='+$owner.name)
Write-Output ('WINDOWS_HOME_CONTROL_DIR='+$dir)
Write-Output ('WINDOWS_HOME_SAVE_FINISH_CUTOFF='+[DateTimeOffset]::FromUnixTimeMilliseconds($deadline).ToString('o'))
