$ErrorActionPreference='Stop'
$id=[guid]'66b514d0-7246-493f-ade3-1f004cd12411'
if(Get-CimInstance -Namespace root/virtualization/v2 -ClassName Msvm_ComputerSystem -Filter ("Name='"+$id+"'") -ErrorAction Stop){throw 'Registered guest refused.'}
$path='D:/a/dougs-box/dougs-box/scripts/windows-state-checkpoint.ps1'
$t=$null;$e=$null;$a=[System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$t,[ref]$e)
if($e.Count){throw 'Parser refused.'}
$f=$a.Find({param($n)$n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Resolve-WindowsStateImportCompatibility'},$true).Extent.Text
$old="if(Get-VM -Id `$ExpectedVmId -ErrorAction SilentlyContinue)"
$new="if(Get-CimInstance -Namespace root/virtualization/v2 -ClassName Msvm_ComputerSystem -Filter (`"Name='`"+`$ExpectedVmId.ToString()+`"'`") -ErrorAction Stop)"
if(-not $f.Contains($old)){throw 'Expected guard missing.'}
Invoke-Expression $f.Replace($old,$new)
$v=Get-VM -Id $id -ErrorAction Stop
$root='E:/DevBox/Tools/WindowsStateProbe/probe-38647908553-1'
if($v.Name -cne 'DevBoxWindowsState-38647908553-1' -or $v.Path.Replace('\','/') -ine ($root+'/'+$v.Name)){throw 'Planned identity refused.'}
Remove-VM -VM $v -Force -ErrorAction Stop
$files=@(Get-ChildItem (Join-Path $root 'checkpoints') -Filter manifest.json -Recurse -File)
if($files.Count -ne 1){throw 'Manifest ambiguous.'}
$m=Get-Content $files[0].FullName -Raw|ConvertFrom-Json
if([guid]$m.vm_id -ne $id){throw 'Manifest identity refused.'}
$p=Join-Path $files[0].DirectoryName 'payload'
$dirs=@($m.disks|ForEach-Object {Split-Path (Join-Path $p $_.path) -Parent}|Sort-Object -Unique)
if($dirs.Count -ne 1){throw 'Disk layout refused.'}
$r=Compare-VM -Path (Join-Path $p $m.config) -Copy -VhdSourcePath $dirs[0] -VirtualMachinePath (Join-Path $root $m.vm_name) -VhdDestinationPath (Join-Path $root 'restored-disks') -SnapshotFilePath (Join-Path $root 'restored-snapshots') -ErrorAction Stop
[ordered]@{runId='38971777364';diagnosticOnly=$true;issues=@($r.Incompatibilities|ForEach-Object {$x=$_.Source;[ordered]@{messageId=$_.MessageId;type=$x.GetType().FullName;typeNames=@($x.PSObject.TypeNames);properties=@($x.PSObject.Properties|Where-Object {$_.Name -match 'Id|Name|Switch'}|ForEach-Object {@{name=$_.Name;value=[string]$_.Value}})}})}|ConvertTo-Json -Depth 7 -Compress
