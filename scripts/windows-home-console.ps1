# Open the verified Home guest at transport login; owner controls live inside guest C.
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
# bootstrap.ps1 reassigns DEVBOX_CONTROL_PATH to E:\DevBox\Control inside restore.
# The earlier RDP setup wrote its authenticated account receipt under RUNNER_TEMP.
# Reconstruct that immutable pilot receipt path rather than trusting the rewritten env.
if([string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){throw 'GitHub runner temporary root missing.'}
$statePath=Join-Path (Join-Path $env:RUNNER_TEMP 'windows-home-restore-hold-rdp') 'rdp-state.txt'
if(-not(Test-Path -LiteralPath $statePath -PathType Leaf)){throw 'RDP account setup receipt missing.'}
$stateText=(Get-Content -LiteralPath $statePath -Raw -ErrorAction Stop).Trim()
$accountMatch=[regex]::Match($stateText,'^rdpAccounts=(runneradmin|devbox)$')
if(-not $accountMatch.Success){throw 'Unexpected RDP account receipt; account not authorized.'}
$effectiveRdpAccount=$accountMatch.Groups[1].Value
if($effectiveRdpAccount -cnotin @('runneradmin','devbox')){throw 'RDP account not allowlisted.'}
$rdpUser=Get-LocalUser -Name $effectiveRdpAccount -ErrorAction Stop
if(-not $rdpUser.Enabled){throw 'RDP owner account disabled.'}
$dir=Join-Path $env:ProgramData ('WindowsHomePilot\'+$env:GITHUB_RUN_ID)
if(Test-Path -LiteralPath $dir){throw 'Per-run control directory must be new.'}
New-Item -Path $dir -ItemType Directory -ErrorAction Stop|Out-Null
$acl=Get-Acl -LiteralPath $dir
$acl.SetAccessRuleProtection($true,$false)
$allowedSids=@([Security.Principal.WindowsIdentity]::GetCurrent().User.Value,$rdpUser.SID.Value,'S-1-5-18')|Select-Object -Unique
foreach($sid in $allowedSids){
 # Explicit SecurityIdentifier avoids Windows treating a textual SID as an
 # account name. Validated with a real disposable Windows runner in 38826328423.
 $principal=[Security.Principal.SecurityIdentifier]::new($sid)
 $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($principal,'FullControl','ContainerInherit,ObjectInherit','None','Allow'))
}
Set-Acl -LiteralPath $dir -AclObject $acl -ErrorAction Stop
$readback=Get-Acl -LiteralPath $dir -ErrorAction Stop
if(-not $readback.AreAccessRulesProtected){throw 'Pilot control ACL inheritance is not protected.'}
$actualSids=@($readback.GetAccessRules($true,$false,[Security.Principal.SecurityIdentifier])|ForEach-Object {$_.IdentityReference.Value}|Select-Object -Unique)
foreach($sid in $allowedSids){
 if($actualSids -notcontains $sid){throw ('Pilot control ACL missing authorized identity SID: '+$sid)}
}
foreach($name in @('requests','responses')){New-Item -ItemType Directory -Path (Join-Path $dir $name) -ErrorAction Stop|Out-Null}
$deadline=[DateTimeOffset]::UtcNow.AddMinutes(300).ToUnixTimeMilliseconds()
if($env:WINDOWS_HOME_HOST_STOP_MS){
 . (Join-Path $PSScriptRoot 'windows-home-session-budget.ps1')
 $deadline=Get-WindowsHomeAdmissionDeadline -NowMs ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -HostStopMs ([long]$env:WINDOWS_HOME_HOST_STOP_MS)
}
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
# The pilot host is transport. Do not redirect the owner's computer drives into it.
$rdpPolicy='HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
New-Item -Path $rdpPolicy -Force -ErrorAction Stop|Out-Null
Set-ItemProperty -Path $rdpPolicy -Name fDisableCdm -Value 1 -Type DWord -ErrorAction Stop
if((Get-ItemPropertyValue -Path $rdpPolicy -Name fDisableCdm -ErrorAction Stop) -ne 1){throw 'Pilot client drive redirection refusal did not persist.'}
$startup=[Environment]::GetFolderPath('CommonStartup')
if(-not(Test-Path -LiteralPath $startup -PathType Container)){throw 'Common Startup folder unavailable.'}
$auto=$shell.CreateShortcut((Join-Path $startup 'Open Windows Home.lnk'))
$auto.TargetPath=$vmconnect;$auto.Arguments=$console.Arguments;$auto.WindowStyle=3
$auto.Description='Open verified Windows Home guest; Server host is transport';$auto.Save()
& (Join-Path $PSScriptRoot 'windows-home-guest-controls.ps1') -ControlDir $dir
$bridgeScript=Join-Path $PSScriptRoot 'windows-home-guest-bridge.ps1'
$bridge=Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile','-File',('"'+$bridgeScript+'"'),'-ControlDir',('"'+$dir+'"')) -PassThru -RedirectStandardOutput (Join-Path $dir 'bridge.stdout.log') -RedirectStandardError (Join-Path $dir 'bridge.stderr.log')
Write-Output ('WINDOWS_HOME_GUEST_BRIDGE_PID='+$bridge.Id)
Write-Output ('WINDOWS_HOME_VMCONNECT_SHORTCUT_READY='+$owner.name)
Write-Output ('WINDOWS_HOME_CONTROL_DIR='+$dir)
Write-Output ('WINDOWS_HOME_SAVE_FINISH_CUTOFF='+[DateTimeOffset]::FromUnixTimeMilliseconds($deadline).ToString('o'))
