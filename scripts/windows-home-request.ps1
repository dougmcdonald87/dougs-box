# Owner command on the host or inside the Home guest; no cloud credentials.
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Save','Finish')][string]$Operation,
      [Parameter(Mandatory)][string]$ControlDir,
      [ValidateRange(1,3600)][int]$WaitSeconds=1800)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$path=Join-Path $ControlDir 'session.json'
if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'No active pilot session.'}
$session=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
if($session.schema -ne 1 -or $session.runId -cnotmatch '^[1-9][0-9]*$' -or
   $session.vmId -cnotmatch '^[0-9a-f-]{36}$' -or
   $session.deadlineMs -le [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()){
 throw 'Pilot session expired or malformed; request not submitted.'
}
$id=[guid]::NewGuid().ToString('D')
$request=[ordered]@{schema=1;runId=$session.runId;vmId=$session.vmId;generation=$session.generation;operation=$Operation;operationId=$id;createdUtc=[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')}
$root=Join-Path $ControlDir 'requests'
$temp=Join-Path $root ('.tmp-'+$id)
$dest=Join-Path $root ('request-'+$id+'.json')
[IO.File]::WriteAllText($temp,($request|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
[IO.File]::Move($temp,$dest)
Write-Host ('Submitted '+$Operation+' request '+$id+'; submission does NOT prove persistence.')
if($Operation -ceq 'Finish'){Write-Host 'Finish closes Windows after backup verification. Final confirmation is recorded on the host after Windows is off.'}
$response=Join-Path (Join-Path $ControlDir 'responses') ('response-'+$id+'.json')
$waitUntil=[DateTime]::UtcNow.AddSeconds($WaitSeconds)
$verified=$false
while([DateTime]::UtcNow -lt $waitUntil){
 if(Test-Path -LiteralPath $response){
  $r=Get-Content -LiteralPath $response -Raw|ConvertFrom-Json
  if($r.status -ceq 'verified' -and $r.verified -eq $true){Write-Host ('VERIFIED ENCRYPTED GENERATION: '+$r.generation);$verified=$true;break}
  if($r.status -ceq 'failed'){throw ('Operation failed: '+$r.reason)}
 }
 $remaining=($waitUntil-[DateTime]::UtcNow).TotalMilliseconds
 if($remaining -gt 0){Start-Sleep -Milliseconds ([int][Math]::Min(5000,[Math]::Max(1,$remaining)))}
}

if(-not $verified){Write-Warning ('Operation '+$id+' is still pending. The request remains active; check its receipt at '+$response+'. No verified backup is claimed by this window.')}
