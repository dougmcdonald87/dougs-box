# Bounded read-only evidence for one existing, authenticated retained Home guest.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$run='__TARGET_RUN__';$sha='__TARGET_SHA__'
if($run -cnotmatch '^[1-9][0-9]*$' -or $sha -cnotmatch '^[0-9a-f]{40}$'){throw 'Pinned guest evidence target required.'}
$repair='C:\ProgramData\WindowsHomePilotRepair\'+$run
$a=Get-Content (Join-Path $repair 'access.json') -Raw|ConvertFrom-Json
$s=Get-Content (Join-Path $repair 'recovery.json') -Raw|ConvertFrom-Json
if($a.runId -cne $run -or $a.sourceSha -cne $sha -or $s.runId -cne $run -or $s.consumerHost -ine ([guid](Get-CimInstance Win32_ComputerSystemProduct).UUID).ToString()){throw 'Retained host evidence identity mismatch.'}
$root=[string]$s.record.root;$id=[guid]$s.record.vm_id
if($id -eq [guid]::Empty -or $root -cnotmatch '^E:/DevBox/Tools/WindowsStateProbe/probe-[0-9]+-[0-9]+$'){throw 'Owned guest evidence scope refused.'}
$markerPath=Join-Path $root 'probe-owner.json'
if((Get-Item $markerPath).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Owner marker link refused.'}
$marker=Get-Content $markerPath -Raw|ConvertFrom-Json
$vm=Get-VM -Id $id -ErrorAction Stop;$path=$vm.Path.Replace('\','/').TrimEnd('/')
if($marker.schema -ne 1 -or $marker.status -cne 'created' -or $marker.root -cne $root -or [guid]$marker.vmId -ne $id -or $marker.name -cne $s.record.vm_name -or $vm.Name -cne $marker.name -or $path -notin @($root,($root+'/'+$vm.Name)) -or $vm.State.ToString() -cne 'Running'){throw 'Owned running guest proof refused.'}
$control='C:\ProgramData\WindowsHomePilot\'+$run
$session=Get-Content (Join-Path $control 'session.json') -Raw|ConvertFrom-Json
if($session.runId -cne $run -or [guid]$session.vmId -ne $id -or $session.root -cne $root){throw 'Guest controls not bound to this session.'}
if([string]::IsNullOrEmpty($env:PILOT_GUEST_OWNER_PASSWORD)){throw 'Owner credential absent from transient encrypted shell.'}
$password=ConvertTo-SecureString $env:PILOT_GUEST_OWNER_PASSWORD -AsPlainText -Force
$env:PILOT_GUEST_OWNER_PASSWORD=$null
$guest=$null
try {
 $guest=New-PSSession -VMId $id -Credential ([pscredential]::new('PilotOwner',$password)) -ErrorAction Stop
 $inventory=Invoke-Command -Session $guest -ArgumentList $run,$id.ToString() -ErrorAction Stop -ScriptBlock {
  param($run,$id)
  $ErrorActionPreference='Stop'
  $identity=[Security.Principal.WindowsIdentity]::GetCurrent().Name
  if($identity -cnotmatch '(?i)\\PilotOwner$'){throw 'Guest evidence authenticated unexpected account.'}
  $dir='C:\ProgramData\WindowsHomePilot\'+$run
  $public=Get-Content (Join-Path $dir 'session.json') -Raw|ConvertFrom-Json
  if($public.runId -cne $run -or $public.vmId -cne $id -or @($public.PSObject.Properties.Name).Count -ne 5){throw 'Guest control identity/metadata count mismatch.'}
  $drives=@(Get-CimInstance Win32_LogicalDisk|Select-Object DeviceID,DriveType,ProviderName)
  if(@($drives|Where-Object {$_.DriveType -eq 4 -or $_.ProviderName -or ($_.DriveType -eq 3 -and $_.DeviceID -cne 'C:')}).Count){throw 'Guest drive isolation failed.'}
  $shell=New-Object -ComObject WScript.Shell
  $links=@(foreach($op in @('Save','Finish')){
   $file=Join-Path (Join-Path $env:PUBLIC 'Desktop') ($op+' Windows Home.lnk')
   if(-not(Test-Path $file)){throw ('Missing guest desktop '+$op)}
   $link=$shell.CreateShortcut($file)
   if($link.Arguments -cnotlike ('*'+$dir+'*') -or $link.TargetPath -notlike 'C:\Windows\*'){throw 'Guest shortcut does not target current C session.'}
   [pscustomobject]@{operation=$op;target=$link.TargetPath;arguments=$link.Arguments}
  })
  [pscustomobject]@{authenticatedOwner=$identity;guiLoggedOnUser=[string](Get-CimInstance Win32_ComputerSystem).UserName;drives=$drives;links=$links;publicFields=@($public.PSObject.Properties.Name)}
 }
} finally {if($guest){Remove-PSSession $guest};$password.Dispose()}
$frame=$null;$frameInfo=$null
try {
 $system=Get-CimInstance -Namespace root/virtualization/v2 -ClassName Msvm_ComputerSystem -Filter ("Name='"+$id+"'")
 $settings=@(Get-CimAssociatedInstance -InputObject $system -Association Msvm_SettingsDefineState -ResultClassName Msvm_VirtualSystemSettingData)
 if($settings.Count -ne 1){throw 'One realized guest setting required.'}
 $service=Get-CimInstance -Namespace root/virtualization/v2 -ClassName Msvm_VirtualSystemManagementService
 $image=Invoke-CimMethod -InputObject $service -MethodName GetVirtualSystemThumbnailImage -Arguments @{TargetSystem=$settings[0];WidthPixels=[uint16]640;HeightPixels=[uint16]480}
 $frameInfo=@{returnValue=$image.ReturnValue;type=$image.ImageData.GetType().FullName;length=$image.ImageData.Length;count=@($image.ImageData).Count;requestedWidth=640;requestedHeight=480}
 if($image.ReturnValue -ne 0 -or $image.ImageData.Length -ne (640*480*2)){throw ('Thumbnail return/size refused: '+$image.ReturnValue)}
 Add-Type -AssemblyName System.Drawing
 $bitmap=[Drawing.Bitmap]::new(640,480,[Drawing.Imaging.PixelFormat]::Format16bppRgb565)
 $memory=[IO.MemoryStream]::new()
 try {
  $bits=$bitmap.LockBits([Drawing.Rectangle]::new(0,0,640,480),[Drawing.Imaging.ImageLockMode]::WriteOnly,[Drawing.Imaging.PixelFormat]::Format16bppRgb565)
  try {[Runtime.InteropServices.Marshal]::Copy([byte[]]$image.ImageData,0,$bits.Scan0,$image.ImageData.Length)} finally {$bitmap.UnlockBits($bits)}
  $bitmap.Save($memory,[Drawing.Imaging.ImageFormat]::Png)
  $frame=@{format='png';width=640;height=480;base64=[Convert]::ToBase64String($memory.ToArray())}
 } finally {$bitmap.Dispose();$memory.Dispose()}
} catch {$frame=@{unavailable=$_.Exception.Message;native=$frameInfo}}
$workers=@(Get-CimInstance Win32_Process|Where-Object {$_.CommandLine -like '*windows-home-guest-bridge.ps1*' -or $_.CommandLine -like '*hold-operator.mjs*' -or $_.CommandLine -like '*supervise-restricted.mjs*'}|Select-Object ProcessId,Name)
$bridgeErrors=@();$bridgeErrorPath=Join-Path $control 'bridge.stderr.log'
if(Test-Path $bridgeErrorPath){$bridgeErrors=@(Get-Content -LiteralPath $bridgeErrorPath -Tail 16|Where-Object {$_ -notmatch '::add-mask::'})}
[ordered]@{runId=$run;sourceSha=$sha;phase='guest-evidence';vmId=$id.ToString();vmState=[string]$vm.State;hostIp=$a.ip;hostAccount=$a.account;deadlineMs=$session.deadlineMs;inventory=$inventory;workers=$workers;bridgeErrors=$bridgeErrors;frame=$frame}|ConvertTo-Json -Depth 8 -Compress
