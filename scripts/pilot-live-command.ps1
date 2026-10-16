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
$r=Compare-VM -VM $v -ErrorAction Stop
$r=Resolve-WindowsStateImportCompatibility -Report $r -ExpectedVmId $id -ExpectedName 'DevBoxWindowsState-38647908553-1' -ExpectedVersion '12.0'
[ordered]@{runId='38971777364';correctionOnly=$true;remainingIssues=@($r.Incompatibilities).Count;vmId=[string]$r.VM.Id;vmName=$r.VM.Name;version=[string]$r.VM.Version}|ConvertTo-Json -Compress
