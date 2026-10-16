$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$expectedRun='38930283997'
$expectedVm=[guid]'66b514d0-7246-493f-ade3-1f004cd12411'
$control=Join-Path $env:ProgramData ('WindowsHomePilot\'+$expectedRun)
$session=Get-Content -LiteralPath (Join-Path $control 'session.json') -Raw|ConvertFrom-Json
if($session.runId -cne $expectedRun -or [guid]$session.vmId -ne $expectedVm){throw 'Live pilot identity mismatch; no action allowed.'}
$vm=Get-VM -Id $expectedVm -ErrorAction Stop
$requests=@(Get-ChildItem -LiteralPath (Join-Path $control 'requests') -File|ForEach-Object {
 [pscustomobject]@{name=$_.Name;bytes=$_.Length;content=if($_.Extension -eq '.json'){Get-Content -LiteralPath $_.FullName -Raw}else{$null}}
})
$responses=@(Get-ChildItem -LiteralPath (Join-Path $control 'responses') -File|ForEach-Object {
 [pscustomobject]@{name=$_.Name;bytes=$_.Length;tail=(Get-Content -LiteralPath $_.FullName -Tail 60|Out-String)}
})
$processes=@(Get-CimInstance Win32_Process|Where-Object {$_.Name -in @('node.exe','pwsh.exe','cmd.exe')}|ForEach-Object {
 [pscustomobject]@{pid=$_.ProcessId;parent=$_.ParentProcessId;name=$_.Name;role=$(if($_.CommandLine -like '*supervise-restricted*'){'supervisor'}elseif($_.CommandLine -like '*windows-home-restricted-agent*'){'restricted-agent'}elseif($_.CommandLine -like '*desktop-commander*'){'desktop-commander'}else{'other'})}
})
[ordered]@{host=$env:COMPUTERNAME;run=$session.runId;vmId=$vm.Id.ToString();vmName=$vm.Name;vmState=$vm.State.ToString();generation=$session.generation;deadlineMs=$session.deadlineMs;requests=$requests;responses=$responses;processes=$processes;restrictedAccounts=@(Get-LocalUser|Where-Object {$_.Name -like 'PilotDC*'}|Select-Object Name,Enabled)}|ConvertTo-Json -Depth 8 -Compress
