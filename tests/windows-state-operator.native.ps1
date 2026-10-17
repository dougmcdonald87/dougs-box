# Real request client -> first-party queue -> operator -> encrypted cloud receipt.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($env:GITHUB_ACTIONS -cne 'true' -or $env:DEVBOX_ISOLATED_TEST -cne '1' -or $env:GITHUB_REF -cne 'refs/heads/pilot/windows-home-connection-20261015'){throw 'Native acceptance requires isolated pilot.'}
. (Join-Path $PSScriptRoot '../scripts/windows-state-roundtrip.ps1')
$parts=@(Restore-WindowsStateRoundtrip -ExpectedGeneration $env:EXPECTED_GENERATION -ExpectedSourceSha $env:EXPECTED_SOURCE_SHA -HoldForOperator)
$results=@($parts|Where-Object {$_ -is [pscustomobject] -and $_.freshHostRestored -eq $true})
if($results.Count -ne 1){throw 'Native acceptance restore receipt missing.'}
$vm=$results[0];$id=[guid]$vm.vmId
$control=Join-Path $env:ProgramData ('WindowsHomePilot/'+$env:GITHUB_RUN_ID)
if(Test-Path $control){throw 'Native acceptance control directory occupied.'}
New-Item -ItemType Directory -Path $control,(Join-Path $control 'requests'),(Join-Path $control 'responses')|Out-Null
[ordered]@{schema=1;runId=$env:GITHUB_RUN_ID;vmId=$id.ToString();generation=$vm.generation;originGeneration=$vm.originGeneration;root=$vm.root;vmName=$vm.vmName;deadlineMs=[DateTimeOffset]::UtcNow.AddMinutes(180).ToUnixTimeMilliseconds()}|ConvertTo-Json -Compress|Set-Content (Join-Path $control 'session.json') -Encoding utf8
$env:WINDOWS_HOME_CONTROL_DIR=$control
$worker=$null
try {
 $worker=Start-Process -FilePath (Get-Command node).Source -ArgumentList ('"'+(Join-Path $PSScriptRoot '../.github/actions/pilot-device/hold-operator.mjs')+'"') -PassThru -RedirectStandardOutput (Join-Path $control 'hold.stdout.log') -RedirectStandardError (Join-Path $control 'hold.stderr.log')
 $credential=Get-WindowsStatePortableFixtureCredential -VmId $id
 $generations=@()
 foreach($operation in @('Save','Finish')){
  $guest=New-PSSession -VMId $id -Credential $credential -ErrorAction Stop
  try {
   $mark='Native operator '+$env:GITHUB_RUN_ID+' '+$operation
   $hash=Invoke-Command -Session $guest -ArgumentList $mark -ScriptBlock {
    param($mark)
    $document=Join-Path $env:USERPROFILE 'Documents/DevBoxFixture.txt'
    [IO.File]::WriteAllText($document,($mark+"`n"),[Text.UTF8Encoding]::new($false))
    (Get-FileHash $document -Algorithm SHA256).Hash
   }
  } finally {Remove-PSSession $guest}
  & (Join-Path $PSScriptRoot '../scripts/windows-home-request.ps1') -Operation $operation -ControlDir $control -WaitSeconds 3600
  $receipts=@(Get-ChildItem (Join-Path $control 'responses') -Filter 'response-*.json' -File|ForEach-Object {Get-Content $_.FullName -Raw|ConvertFrom-Json}|Where-Object {$_.operation -ceq $operation})
  if($receipts.Count -ne 1 -or $receipts[0].status -cne 'verified' -or $receipts[0].verified -ne $true){throw ('Native '+$operation+' receipt not verified.')}
  $generation=[string]$receipts[0].generation
  if($generation -cnotmatch ('^devbox-checkpoint-v1-ci-'+$env:GITHUB_RUN_ID+'-'+$env:GITHUB_RUN_ATTEMPT+'-') -or $generations -contains $generation){throw 'Native current-run publication generation invalid or reused.'}
  $generations+=$generation
  $state=(Get-VM -Id $id -ErrorAction Stop).State.ToString()
  $expected=if($operation -ceq 'Save'){'Running'}else{'Off'}
  if($state -cne $expected){throw ('Native '+$operation+' VM state mismatch.')}
  Write-Host ('NATIVE_OPERATOR_'+$operation.ToUpperInvariant()+'_VERIFIED='+([ordered]@{runId=$env:GITHUB_RUN_ID;generation=$generation;vmId=$id.ToString();state=$state;documentSha256=$hash;sourceSha=$env:GITHUB_SHA}|ConvertTo-Json -Compress))
 }
 if(-not $worker.WaitForExit(60000) -or $worker.ExitCode -ne 0){throw 'First-party worker did not complete verified Finish.'}
 Write-Host 'NATIVE_OPERATOR_ACCEPTANCE_VERIFIED=true'
} catch {
 $failure=$_
 Write-Host ('NATIVE_OPERATOR_FAILURE_TYPE='+$failure.Exception.GetType().FullName)
 if(Test-Path (Join-Path $control 'responses')){& node (Join-Path $PSScriptRoot 'windows-state-operator-diagnostics.mjs') $control}
 throw $failure
} finally {
 if($worker -and -not $worker.HasExited){Stop-Process -Id $worker.Id -Force -ErrorAction SilentlyContinue}
}
