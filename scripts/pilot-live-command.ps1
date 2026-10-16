$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$expectedRun='38930283997'
$expectedVm=[guid]'66b514d0-7246-493f-ade3-1f004cd12411'
$control=Join-Path $env:ProgramData ('WindowsHomePilot\'+$expectedRun)
$session=Get-Content -LiteralPath (Join-Path $control 'session.json') -Raw|ConvertFrom-Json
if($session.runId -cne $expectedRun -or [guid]$session.vmId -ne $expectedVm){throw 'Live pilot identity mismatch; no action allowed.'}
$vm=Get-VM -Id $expectedVm -ErrorAction Stop

$operationId='292e0186-46e3-4b31-a488-4224285e486b'
$requestPath=Join-Path (Join-Path $control 'requests') ('request-'+$operationId+'.json')
$responsePath=Join-Path (Join-Path $control 'responses') ('response-'+$operationId+'.json')
if(-not(Test-Path -LiteralPath $requestPath) -and -not(Test-Path -LiteralPath ($requestPath+'.working')) -and -not(Test-Path -LiteralPath $responsePath)){
 if($vm.State -ne 'Running'){throw 'Save test requires running owned guest.'}
 if(@(Get-ChildItem -LiteralPath (Join-Path $control 'requests') -File).Count -ne 0){throw 'Owner queue is not idle; no concurrent Save submitted.'}
 if($session.deadlineMs -le [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()){throw 'Owner session expired; no Save submitted.'}
 $request=[ordered]@{schema=1;runId=$session.runId;vmId=$session.vmId;generation=$session.generation;operation='Save';operationId=$operationId;createdUtc=[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')}
 $temp=Join-Path (Join-Path $control 'requests') ('.tmp-'+$operationId)
 [IO.File]::WriteAllText($temp,($request|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
 [IO.File]::Move($temp,$requestPath)
 [ordered]@{operationId=$operationId;requestSubmitted=$true}|ConvertTo-Json -Compress
}

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
