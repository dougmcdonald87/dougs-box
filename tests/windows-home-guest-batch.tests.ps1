$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../scripts/windows-home-guest-transport.ps1')
foreach($function in @('Get-WindowsHomeGuestRequestBatch','Complete-WindowsHomeGuestControlBatch')){if(-not(Get-Command $function -ErrorAction SilentlyContinue)){throw ('ASSERT: guest batch function missing: '+$function)}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('guest-batch-'+[guid]::NewGuid());New-Item -ItemType Directory -Path $root,(Join-Path $root 'requests'),(Join-Path $root 'responses')|Out-Null
function Assert($ok,$message){if(-not $ok){throw ('ASSERT: '+$message)}}
try {
 $id='66b514d0-7246-493f-ade3-1f004cd12411';$name='request-'+$id+'.json';$path=Join-Path (Join-Path $root 'requests') $name
 [IO.File]::WriteAllText($path,'{"operation":"Save"}')
 $batch=@(Get-WindowsHomeGuestRequestBatch $root)
 Assert ($batch.Count -eq 1 -and $batch[0].name -ceq $name -and $batch[0].sha256 -match '^[0-9A-F]{64}$') 'request batch or digest missing'
 [IO.File]::WriteAllText($path,'{"operation":"Finish"}')
 Complete-WindowsHomeGuestControlBatch $root $batch @()
 Assert (Test-Path $path) 'ack removed changed request'
 $batch=@(Get-WindowsHomeGuestRequestBatch $root)
 Complete-WindowsHomeGuestControlBatch $root $batch @()
 Assert (-not(Test-Path $path)) 'matching committed request not acknowledged'
 $receipt=[pscustomobject]@{name=('response-'+$id+'.json');json='{"status":"received"}'}
 Complete-WindowsHomeGuestControlBatch $root @() @($receipt)
 $response=Join-Path (Join-Path $root 'responses') $receipt.name
 Assert ([IO.File]::ReadAllText($response) -ceq $receipt.json) 'receipt not mirrored after request acknowledgement'
 $receipt.json='{"status":"verified"}'
 Complete-WindowsHomeGuestControlBatch $root @() @($receipt)
 Assert ([IO.File]::ReadAllText($response) -ceq $receipt.json) 'final receipt did not replace received'
 [IO.File]::WriteAllText($path,('x'*4097))
 Assert (@(Get-WindowsHomeGuestRequestBatch $root).Count -eq 0) 'oversized request transported'
 Remove-Item $path
 New-Item -ItemType SymbolicLink -Path $path -Target $response|Out-Null
 Assert (@(Get-WindowsHomeGuestRequestBatch $root).Count -eq 0) 'symlink request transported'
 Remove-Item $path
 for($i=0;$i -lt 32;$i++){
  $badName='request-00000000-0000-0000-0000-'+$i.ToString('x12')+'.json'
  [IO.File]::WriteAllText((Join-Path (Join-Path $root 'requests') $badName),('x'*4097))
 }
 [IO.File]::WriteAllText($path,'{"operation":"Save"}')
 $batch=@(Get-WindowsHomeGuestRequestBatch $root)
 Assert (@($batch|Where-Object {$_.name -ceq $name}).Count -eq 1) '32 oversized requests starved valid Save'
 for($i=0;$i -lt 32;$i++){
  $badName='request-00000000-0000-0000-0000-'+$i.ToString('x12')+'.json'
  [IO.File]::WriteAllText((Join-Path (Join-Path $root 'requests') $badName),'not-json')
 }
 $batch=@(Get-WindowsHomeGuestRequestBatch $root)
 Assert ($batch.Count -eq 1 -and $batch[0].name -ceq $name) '32 malformed requests starved valid Save'
 Write-Host 'GUEST BATCH COPY/ACK: PASS (9 cases)' 
} finally {Remove-Item $root -Recurse -Force}
