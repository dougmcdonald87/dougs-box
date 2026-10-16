# Privileged publisher invoked ONLY by isolated GitHub runner's local operator worker.
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Save','Finish')][string]$Operation,
      [Parameter(Mandatory)][guid]$OperationId,
      [Parameter(Mandatory)][string]$ExpectedRunId,
      [Parameter(Mandatory)][string]$ControlDir,
      [Parameter(Mandatory)][string]$OutputPath)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:DEVBOX_ISOLATED_TEST -cne '1' -or
   $env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or
   $env:GITHUB_REF -cne 'refs/heads/pilot/windows-home-connection-20261015' -or
   $env:GITHUB_RUN_ID -cne $ExpectedRunId){throw 'Only current manual isolated pilot job may publish.'}
if([string]::IsNullOrWhiteSpace($env:GH_TOKEN) -or [string]::IsNullOrWhiteSpace($env:RESTIC_PASSWORD)){throw 'Publisher job credentials not available.'}
$expected=Join-Path $env:ProgramData ('WindowsHomePilot\'+$env:GITHUB_RUN_ID)
if([IO.Path]::GetFullPath($ControlDir).TrimEnd('\') -ine [IO.Path]::GetFullPath($expected).TrimEnd('\')){throw 'Foreign control path.'}
$output=Join-Path (Join-Path $ControlDir 'responses') ('.internal-'+$OperationId.ToString('D')+'.json')
if([IO.Path]::GetFullPath($OutputPath) -ine [IO.Path]::GetFullPath($output) -or
   (Test-Path -LiteralPath $output)){throw 'Unsafe or existing response.'}
$info=Get-Content -LiteralPath (Join-Path $ControlDir 'session.json') -Raw|ConvertFrom-Json
if($info.schema -ne 1 -or $info.runId -cne $env:GITHUB_RUN_ID -or $info.vmId -cnotmatch '^[0-9a-f-]{36}$' -or
   $info.generation -cnotmatch '^devbox-checkpoint-v1-ci-' -or
   $info.originGeneration -cnotmatch '^devbox-checkpoint-v1-ci-' -or
   $info.deadlineMs -le [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()){throw 'Invalid or expired interactive owner context.'}
$vmId=[guid]::Parse([string]$info.vmId)
. (Join-Path $PSScriptRoot 'windows-state-checkpoint.ps1')
. (Join-Path $PSScriptRoot 'windows-state-roundtrip.ps1')
. (Join-Path $PSScriptRoot 'windows-state-fixture.ps1')
$owner=Get-WindowsStateCheckpointOwner -Root $info.root -VmId $vmId
if($owner.vm.State -ne 'Running'){throw 'Only an owned running guest can Save or Finish.'}
$cred=Get-WindowsStatePortableFixtureCredential -VmId $vmId
$guest=New-PSSession -VMId $vmId -Credential $cred -ErrorAction Stop
try{$baseline=Get-WindowsStateFixture -GuestSession $guest -VmId $vmId}
finally{Remove-PSSession $guest}
$checkpoint=Export-WindowsStateCheckpoint -Root $info.root -VmId $vmId -Mode 'save'
$result=Publish-WindowsStateRoundtrip -Root $info.root -VmId $vmId -Checkpoint $checkpoint -Baseline $baseline -InteractiveSessionPath (Join-Path $ControlDir 'session.json')
if($result.published -ne $true -or $result.vmId -cne $vmId.ToString() -or
   $result.generation -cnotmatch ('^devbox-checkpoint-v1-ci-'+[regex]::Escape($env:GITHUB_RUN_ID)+'-'+[regex]::Escape($env:GITHUB_RUN_ATTEMPT)+'-')){
 throw 'Publisher returned no accepted exact-current-run generation.'
}
if($Operation -eq 'Finish'){
    Stop-VM -VM (Get-VM -Id $vmId -ErrorAction Stop) -ErrorAction Stop
    $deadline=[DateTime]::UtcNow.AddMinutes(2)
    while((Get-VM -Id $vmId).State -ne 'Off' -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Seconds 5}
    if((Get-VM -Id $vmId).State -ne 'Off'){throw 'Backup published but shutdown unconfirmed.'}
}
[ordered]@{schema=1;operationId=$OperationId.ToString('D');vmId=$vmId.ToString('D');operation=$Operation;generation=$result.generation;verified=$true}|
 ConvertTo-Json -Compress|Set-Content -LiteralPath $output -Encoding utf8 -ErrorAction Stop
Write-Output ('PILOT_VERIFIED_'+$Operation.ToUpperInvariant()+'='+$result.generation)
