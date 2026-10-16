$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$expectedRun='38971777364'
$expectedVm=[guid]'66b514d0-7246-493f-ade3-1f004cd12411'
$control=Join-Path $env:ProgramData ('WindowsHomePilot\'+$expectedRun)
$sessionPath=Join-Path $control 'session.json'
$hasSession=Test-Path -LiteralPath $sessionPath -PathType Leaf
$vmQueryErrors=@()
$vm=Get-VM -Id $expectedVm -ErrorAction SilentlyContinue -ErrorVariable vmQueryErrors
$result=[ordered]@{runId=$expectedRun;computerName=$env:COMPUTERNAME;readOnly=$true;sessionPresent=$hasSession;vmRegistered=[bool]$vm;vmState=$null;remainingMinutes=$null;links=@();tailnetIPv4=@(& tailscale ip -4)}
if($vm){
    if($vm.Name -cne 'DevBoxWindowsState-38647908553-1'){throw 'Replacement VM identity mismatch.'}
    $result.vmState=$vm.State.ToString()
}
if($hasSession){
    $session=Get-Content -LiteralPath $sessionPath -Raw|ConvertFrom-Json
    if($session.runId -cne $expectedRun -or [guid]$session.vmId -ne $expectedVm){throw 'Replacement control session identity mismatch.'}
    $result.remainingMinutes=[math]::Floor(($session.deadlineMs-[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())/60000)
}
foreach($name in @('Windows 10 Home VM.lnk','Windows 10 Home Save.lnk','Windows 10 Home Finish.lnk')){
    $path=Join-Path (Join-Path $env:PUBLIC 'Desktop') $name
    $result.links+=@{name=$name;exists=(Test-Path -LiteralPath $path -PathType Leaf)}
}
$work='E:\DevBox\Tools\WindowsStateProbe\probe-'+$expectedRun+'-1'
$result.restoreWorkPresent=Test-Path -LiteralPath $work -PathType Container
$result.archivePresent=Test-Path -LiteralPath (Join-Path $work 'recovered-encrypted.zip') -PathType Leaf
$result.vmQueryErrorIds=@($vmQueryErrors|ForEach-Object {$_.FullyQualifiedErrorId})
$failurePath=Join-Path $env:ProgramData ('WindowsHomeRecovery\'+$expectedRun+'\failure.json')
if(Test-Path -LiteralPath $failurePath -PathType Leaf){
    $failure=Get-Content -LiteralPath $failurePath -Raw|ConvertFrom-Json
    if($failure.schema -ne 1 -or $failure.runId -cne $expectedRun){throw 'Foreign recovery failure record refused.'}
    $result.recoveryFailure=$failure
}
# Read-only native provider inventory; no import, removal, or VM changes.
$result.nativeInventory=@(Get-CimInstance -Namespace root/virtualization/v2 -ClassName Msvm_ComputerSystem -ErrorAction Stop|Where-Object {$_.Name -eq $expectedVm.ToString()}|Select-Object Name,ElementName,Caption,EnabledState)
$result.plannedInventory=@(Get-CimInstance -Namespace root/virtualization/v2 -ClassName Msvm_PlannedComputerSystem -ErrorAction Stop|Where-Object {$_.Name -eq $expectedVm.ToString()}|Select-Object Name,ElementName,Caption)
$result.getVmCommand=@(Get-Command Get-VM|Select-Object Name,CommandType,Source)
$result.originPresent=Test-Path -LiteralPath 'E:/DevBox/Tools/WindowsStateProbe/probe-38647908553-1'
# Controlled comparison only, on the recovered disposable copy. No import,
# saved-state removal, network change, start, stop or disk deletion.
if($result.vmRegistered -or $result.nativeInventory.Count -or $result.plannedInventory.Count){throw 'Diagnostic comparison refuses occupied identity.'}
$root='E:/DevBox/Tools/WindowsStateProbe/probe-38647908553-1'
$manifests=@(Get-ChildItem -LiteralPath (Join-Path $root 'checkpoints') -Filter manifest.json -Recurse -File)
if($manifests.Count -ne 1){throw 'Diagnostic manifest ambiguous.'}
$m=Get-Content -LiteralPath $manifests[0].FullName -Raw|ConvertFrom-Json
if([guid]$m.vm_id -ne $expectedVm){throw 'Diagnostic manifest identity mismatch.'}
$payload=Join-Path $manifests[0].DirectoryName 'payload'
$config=Join-Path $payload $m.config
$dirs=@($m.disks|ForEach-Object {Split-Path (Join-Path $payload $_.path) -Parent}|Sort-Object -Unique)
if($dirs.Count -ne 1 -or -not (Test-Path -LiteralPath $config -PathType Leaf)){throw 'Diagnostic comparison layout refused.'}
$r=Compare-VM -Path $config -Copy -VhdSourcePath $dirs[0] -VirtualMachinePath (Join-Path $root $m.vm_name) -VhdDestinationPath (Join-Path $root 'restored-disks') -SnapshotFilePath (Join-Path $root 'restored-snapshots') -ErrorAction Stop
$result.readOnly=$false
$result.comparisonOnly=$true
$result.reportVm=$r.VM|Select-Object Id,Name,State,Path,IsPlanned,Version
$result.afterCompareVm=@(Get-VM -Id $expectedVm -ErrorAction SilentlyContinue|Select-Object Id,Name,State,Path,IsPlanned,Version)
$result.afterNative=@(Get-CimInstance -Namespace root/virtualization/v2 -ClassName Msvm_ComputerSystem|Where-Object {$_.Name -eq $expectedVm.ToString()}|Select-Object Name,ElementName,Caption,EnabledState)
$result.afterPlanned=@(Get-CimInstance -Namespace root/virtualization/v2 -ClassName Msvm_PlannedComputerSystem|Where-Object {$_.Name -eq $expectedVm.ToString()}|Select-Object Name,ElementName,Caption)
$result.issues=@($r.Incompatibilities|ForEach-Object {[ordered]@{messageId=$_.MessageId;message=$_.Message;sourceType=$_.Source.GetType().FullName;sourceVmId=[string]$_.Source.VMId;sourceId=[string]$_.Source.Id}})
$result|ConvertTo-Json -Depth 8 -Compress
