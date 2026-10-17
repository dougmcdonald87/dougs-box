$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$path=Join-Path $PSScriptRoot '../scripts/windows-home-session-budget.ps1'
if(-not(Test-Path $path)){throw 'ASSERT: real host publication budget missing'}
. $path
$now=10000000L;$stop=$now+120*60000L
if((Get-WindowsHomeAdmissionDeadline -NowMs $now -HostStopMs $stop) -ne ($stop-45*60000L)){throw 'ASSERT: 45minute publication reserve missing'}
foreach($minutes in @(45,44,0,-1)){$failed=$false;try{Get-WindowsHomeAdmissionDeadline -NowMs $now -HostStopMs ($now+$minutes*60000L)|Out-Null}catch{$failed=$true};if(-not $failed){throw 'ASSERT: late publication admission accepted'}}
Write-Host 'HOST PUBLICATION BUDGET: PASS (5 cases)'
