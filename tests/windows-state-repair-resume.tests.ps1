$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../scripts/windows-state-roundtrip.ps1')
if(-not(Get-Command Resume-WindowsStateRecovery -ErrorAction SilentlyContinue)){throw 'ASSERT: verified local payload resume entrypoint missing'}
# Public resume guard: a registered guest must never be unregistered/replaced.
$run='123';$old=@{};foreach($key in @('GITHUB_ACTIONS','GITHUB_EVENT_NAME','DEVBOX_ISOLATED_TEST','GITHUB_REPOSITORY','GITHUB_REF','GITHUB_RUN_ID','RESTIC_PASSWORD','GH_TOKEN','ProgramData')){$old[$key]=[Environment]::GetEnvironmentVariable($key)}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('resume-'+[guid]::NewGuid());New-Item -ItemType Directory -Path (Join-Path $temp 'WindowsHomePilotRepair/123') -Force|Out-Null
$root=Join-Path $temp 'owned';New-Item -ItemType Directory -Path $root|Out-Null
$script:calls=0;$script:registered=$false
function Get-CimInstance {param($ClassName,$Namespace,$Filter,$ErrorAction) if($ClassName -ceq 'Win32_ComputerSystemProduct'){[pscustomobject]@{UUID='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'}}elseif($script:registered){[pscustomobject]@{Name='registered'}}}
function Get-WindowsStateCheckpointOwner {param($Root,$VmId,[switch]$AllowMissingVm) [pscustomobject]@{vm=$null;root=$Root;name='DevBoxWindowsState-100-1'}}
function Assert-WindowsStateOwnedPath {param($Root,$Path) $Path}
function Invoke-WindowsStateRecoveredGuest {param($Record,$ExpectedGeneration,$ConsumerHost,[switch]$HoldForOperator,[switch]$KeepForRepair) $script:calls++;[pscustomobject]@{freshHostRestored=$true}}
function RefuseResume {$failed=$false;try{Resume-WindowsStateRecovery -ExpectedGeneration $generation -ExpectedSourceSha ('a'*40)|Out-Null}catch{$failed=$true};if(-not $failed){throw 'ASSERT: unsafe resume accepted'}}
try {
 $env:GITHUB_ACTIONS='true';$env:GITHUB_EVENT_NAME='workflow_dispatch';$env:DEVBOX_ISOLATED_TEST='1';$env:GITHUB_REPOSITORY='dougmcdonald87/dougs-box';$env:GITHUB_REF='refs/heads/pilot/windows-home-connection-20261015';$env:GITHUB_RUN_ID=$run;$env:RESTIC_PASSWORD='test-only';$env:GH_TOKEN='test-only';$env:ProgramData=$temp
 $generation='devbox-checkpoint-v1-ci-100-1-20261016T200332Z-'+('b'*32)
 $record=[ordered]@{root=$root;vm_name='DevBoxWindowsState-100-1';vm_id='66b514d0-7246-493f-ade3-1f004cd12411';generation=('save-'+('b'*32))}
 $state=[ordered]@{schema=1;runId=$run;sourceSha=('a'*40);expectedGeneration=$generation;consumerHost='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';record=$record}
 $file=Join-Path $temp 'WindowsHomePilotRepair/123/recovery.json'
 function Save-State {$state|ConvertTo-Json -Depth 8|Set-Content $file}
 Save-State;Resume-WindowsStateRecovery -ExpectedGeneration $generation -ExpectedSourceSha ('a'*40)|Out-Null
 if($script:calls -ne 1){throw 'ASSERT: verified retained payload not resumed'}
 $script:registered=$true;RefuseResume;$script:registered=$false
 $state.runId='999';Save-State;RefuseResume;$state.runId=$run
 $state.consumerHost='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';Save-State;RefuseResume;$state.consumerHost='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
 $record.vm_name='checkpoints';Save-State;RefuseResume;$record.vm_name='DevBoxWindowsState-100-1'
 $state.sourceSha='b'*40;Save-State;RefuseResume
 if($script:calls -ne 1){throw 'ASSERT: refused resume reached import'}
 Write-Host 'RETAINED PAYLOAD RESUME: PASS (6 guards)'
} finally {foreach($key in $old.Keys){[Environment]::SetEnvironmentVariable($key,$old[$key])};Remove-Item $temp -Recurse -Force}
