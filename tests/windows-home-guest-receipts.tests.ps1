$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../scripts/windows-home-guest-transport.ps1')
if(-not(Get-Command Get-WindowsHomeGuestReceiptBatch -ErrorAction SilentlyContinue)){throw 'ASSERT: bounded receipt batch reader missing'}
$root=Join-Path ([IO.Path]::GetTempPath()) ('guest-receipts-'+[guid]::NewGuid());New-Item -ItemType Directory -Path $root,(Join-Path $root 'responses')|Out-Null
function Assert($ok,$message){if(-not $ok){throw ('ASSERT: '+$message)}}
try {
 $id='66b514d0-7246-493f-ade3-1f004cd12411';$name='response-'+$id+'.json';$path=Join-Path (Join-Path $root 'responses') $name
 [IO.File]::WriteAllText($path,'{"status":"received"}')
 $batch=@(Get-WindowsHomeGuestReceiptBatch $root)
 Assert ($batch.Count -eq 1 -and $batch[0].name -ceq $name -and $batch[0].json -ceq '{"status":"received"}') 'receipt not read without a pending request'
 [IO.File]::WriteAllText($path,'{"status":"verified"}')
 $batch=@(Get-WindowsHomeGuestReceiptBatch $root)
 Assert ($batch[0].json -ceq '{"status":"verified"}') 'updated receipt not reread'
 [IO.File]::WriteAllText($path,('x'*4097))
 Assert (@(Get-WindowsHomeGuestReceiptBatch $root).Count -eq 0) 'oversized receipt accepted'
 Remove-Item $path
 New-Item -ItemType SymbolicLink -Path $path -Target (Join-Path $root 'missing.json')|Out-Null
 Assert (@(Get-WindowsHomeGuestReceiptBatch $root).Count -eq 0) 'symlink receipt accepted'
 Remove-Item $path
 for($i=0;$i -lt 40;$i++){[IO.File]::WriteAllText((Join-Path (Join-Path $root 'responses') ('response-'+[guid]::NewGuid()+'.json')),'{}')}
 Assert (@(Get-WindowsHomeGuestReceiptBatch $root).Count -eq 32) 'receipt batch bound missing'
 Write-Host 'GUEST RECEIPT BATCH: PASS (5 cases)'
} finally {Remove-Item $root -Recurse -Force}
