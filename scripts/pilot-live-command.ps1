$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$expectedRun='38969952512'
$expectedVm=[guid]'66b514d0-7246-493f-ade3-1f004cd12411'
$control=Join-Path $env:ProgramData ('WindowsHomePilot\'+$expectedRun)
$sessionPath=Join-Path $control 'session.json'
$hasSession=Test-Path -LiteralPath $sessionPath -PathType Leaf
$vm=Get-VM -Id $expectedVm -ErrorAction SilentlyContinue
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
$result|ConvertTo-Json -Depth 6 -Compress
