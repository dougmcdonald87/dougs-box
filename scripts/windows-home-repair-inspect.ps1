# Read-only inspection sent only to an independently authenticated retained pilot.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
function Get-WindowsHomeExportNameCollisions {
 param([object[]]$References)
 $paths=@($References|ForEach-Object {$_.path.Replace('\','/')}|Sort-Object -Unique)
 foreach($group in @($paths|Group-Object {($_.Split('/')[-1]).ToLowerInvariant()})){
  if($group.Count -gt 1){[pscustomobject]@{name=$group.Name;paths=@($group.Group)}}
 }
}
function Test-WindowsHomeInspectionVmPath {
 param([string]$Root,[string]$VmName,[string]$VmPath)
 $base=$Root.Replace('\','/').TrimEnd('/');$actual=$VmPath.Replace('\','/').TrimEnd('/')
 return ($actual -ieq $base -or $actual -ieq ($base+'/'+$VmName))
}
$run='__TARGET_RUN__';$sha='__TARGET_SHA__'
if($run -cnotmatch '^[1-9][0-9]*$' -or $sha -cnotmatch '^[0-9a-f]{40}$'){throw 'Exact retained pilot target required.'}
$base='C:\ProgramData\WindowsHomePilotRepair\'+$run
if(-not(Test-Path -LiteralPath (Join-Path $base 'access.json'))){[ordered]@{runId=$run;sourceSha=$sha;phase='waiting-access'}|ConvertTo-Json -Compress;return}
$access=Get-Content -LiteralPath (Join-Path $base 'access.json') -Raw|ConvertFrom-Json
if($access.runId -cne $run -or $access.sourceSha -cne $sha){throw 'Retained host identity mismatch.'}
$recovery=Join-Path $base 'recovery.json'
if(-not(Test-Path -LiteralPath $recovery)){
 [ordered]@{runId=$run;sourceSha=$sha;phase='waiting-recovery'}|ConvertTo-Json -Compress;return
}
$state=Get-Content -LiteralPath $recovery -Raw|ConvertFrom-Json
if($state.runId -cne $run -or $state.consumerHost -ine ([guid](Get-CimInstance Win32_ComputerSystemProduct).UUID).ToString()){throw 'Recovery host proof mismatch.'}
$root=[string]$state.record.root;$id=[guid]$state.record.vm_id
if($root -cnotmatch '^E:/DevBox/Tools/WindowsStateProbe/probe-[0-9]+-[0-9]+$'){throw 'Owned guest root refused.'}
$vm=Get-VM -Id $id -ErrorAction SilentlyContinue
if(-not $vm){[ordered]@{runId=$run;sourceSha=$sha;phase='waiting-import'}|ConvertTo-Json -Compress;return}
$markerPath=Join-Path $root 'probe-owner.json'
if((Get-Item -LiteralPath $markerPath -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Inspection owner marker link refused.'}
$marker=Get-Content -LiteralPath $markerPath -Raw|ConvertFrom-Json
if($marker.schema -ne 1 -or $marker.status -cne 'created' -or $marker.root -cne $root -or $marker.name -cne $state.record.vm_name -or [guid]$marker.vmId -ne $id){throw 'Inspection ownership marker mismatch.'}
$legacyPathAccepted=$vm.Path.Replace('\','/').TrimEnd('/') -ieq ($root+'/'+$vm.Name)
if($vm.Name -cne $state.record.vm_name -or -not(Test-WindowsHomeInspectionVmPath $root $vm.Name $vm.Path)){throw ('Guest VM identity/path refused: actualName='+$vm.Name+'; actualPath='+$vm.Path+'; expectedName='+$state.record.vm_name+'; root='+$root)}
$refs=@();$refs+=@(Get-VMHardDiskDrive -VM $vm -ErrorAction Stop|ForEach-Object {[pscustomobject]@{kind='current';snapshotId=$null;path=$_.Path}})
$snapshots=@(Get-VMSnapshot -VM $vm -ErrorAction Stop)
foreach($snapshot in $snapshots){$refs+=@(Get-VMHardDiskDrive -VMSnapshot $snapshot -ErrorAction Stop|ForEach-Object {[pscustomobject]@{kind='checkpoint';snapshotId=[string]$snapshot.Id;path=$_.Path}})}
$disks=@();$seen=@{}
foreach($ref in $refs){
 $cursor=$ref.path
 for($depth=0;$cursor -and $depth -lt 32;$depth++){
  $canonical=$cursor.Replace('\','/')
  if(-not $canonical.StartsWith(($root+'/'),[StringComparison]::OrdinalIgnoreCase)){throw 'Disk reference outside owned recovery root refused.'}
  if($seen.ContainsKey($canonical.ToLowerInvariant())){break};$seen[$canonical.ToLowerInvariant()]=$true
  $disk=Get-VHD -Path $cursor -ErrorAction Stop
  $disks+=[pscustomobject]@{path=$disk.Path;parent=$disk.ParentPath;diskId=[string]$disk.DiskIdentifier;type=[string]$disk.VhdType;fileBytes=[long]$disk.FileSize}
  $cursor=$disk.ParentPath
 }
}
$failures=@();$diagnostic='C:\ProgramData\WindowsHomeRecovery\'+$run
foreach($name in @('failure.json','resume-failure.json')){$file=Join-Path $diagnostic $name;if(Test-Path -LiteralPath $file){$failures+=@(Get-Content -LiteralPath $file -Raw|ConvertFrom-Json)}}
[ordered]@{runId=$run;sourceSha=$sha;phase='inspected';vmPath=$vm.Path;root=$root;legacyPathAccepted=$legacyPathAccepted;vmId=$id.ToString();vmState=[string]$vm.State;snapshots=@($snapshots|Select-Object Id,Name,State);references=$refs;disks=$disks;collisions=@(Get-WindowsHomeExportNameCollisions $disks);failures=$failures}|ConvertTo-Json -Depth 9 -Compress
