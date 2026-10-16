$ErrorActionPreference='Stop'
$id=[guid]'66b514d0-7246-493f-ade3-1f004cd12411'
function Inventory($class){@(Get-CimInstance -Namespace root/virtualization/v2 -ClassName $class|Where-Object {$_.Name -eq $id.ToString()}|Select-Object Name,ElementName,Caption)}
$before=@(Get-VM -Id $id -ErrorAction SilentlyContinue)
if($before.Count){throw 'Comparison refuses occupied identity.'}
$root='E:/DevBox/Tools/WindowsStateProbe/probe-38647908553-1'
$files=@(Get-ChildItem -LiteralPath (Join-Path $root 'checkpoints') -Filter manifest.json -Recurse -File)
if($files.Count -ne 1){throw 'Manifest ambiguous.'}
$m=Get-Content $files[0].FullName -Raw|ConvertFrom-Json
if([guid]$m.vm_id -ne $id){throw 'Manifest identity mismatch.'}
$p=Join-Path $files[0].DirectoryName 'payload'
$dirs=@($m.disks|ForEach-Object {Split-Path (Join-Path $p $_.path) -Parent}|Sort-Object -Unique)
if($dirs.Count -ne 1){throw 'Disk layout refused.'}
$r=Compare-VM -Path (Join-Path $p $m.config) -Copy -VhdSourcePath $dirs[0] -VirtualMachinePath (Join-Path $root $m.vm_name) -VhdDestinationPath (Join-Path $root 'restored-disks') -SnapshotFilePath (Join-Path $root 'restored-snapshots') -ErrorAction Stop
[ordered]@{runId='38971777364';comparisonOnly=$true;reportVm=($r.VM|Select-Object Id,Name,State,Path,IsPlanned,Version);afterVm=@(Get-VM -Id $id -ErrorAction SilentlyContinue|Select-Object Id,Name,State,Path,IsPlanned,Version);native=(Inventory 'Msvm_ComputerSystem');planned=(Inventory 'Msvm_PlannedComputerSystem');issues=@($r.Incompatibilities|Select-Object MessageId,Message)}|ConvertTo-Json -Depth 7 -Compress
