$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$source=Join-Path $PSScriptRoot '../scripts/windows-home-guest-transport.ps1'
if(Test-Path $source){. $source}
if(-not(Get-Command Add-WindowsHomeGuestRequest -ErrorAction SilentlyContinue)){throw 'ASSERT: bounded guest request intake is missing'}
$root=Join-Path ([IO.Path]::GetTempPath()) ('guest-transport-'+[guid]::NewGuid())
New-Item -ItemType Directory -Path $root,(Join-Path $root 'requests'),(Join-Path $root 'responses')|Out-Null
$name='request-66b514d0-7246-493f-ade3-1f004cd12411.json'
$json='{"operation":"Save"}'
function Assert($ok,$message){if(-not $ok){throw ('ASSERT: '+$message)}}
try {
 Assert (Add-WindowsHomeGuestRequest $root $name $json) 'new request was refused'
 $path=Join-Path (Join-Path $root 'requests') $name
 Assert ([IO.File]::ReadAllText($path) -ceq $json) 'exact request bytes not preserved'
 Assert (Add-WindowsHomeGuestRequest $root $name '{"operation":"Finish"}') 'replay was not acknowledged'
 Assert ([IO.File]::ReadAllText($path) -ceq $json) 'replay overwrote original'
 [IO.File]::Move($path,($path+'.working'))
 Assert (Add-WindowsHomeGuestRequest $root $name $json) 'working request not acknowledged'
 Assert (-not(Test-Path $path)) 'duplicate queued during execution'
 Remove-Item ($path+'.working')
 $receipt=Join-Path (Join-Path $root 'responses') ($name.Replace('request-','response-'))
 [IO.File]::WriteAllText($receipt,'{"status":"verified"}')
 Assert (Add-WindowsHomeGuestRequest $root $name $json) 'receipt replay not acknowledged'
 Assert (-not(Test-Path $path)) 'completed request requeued'
 Assert (-not(Add-WindowsHomeGuestRequest $root '../outside.json' $json)) 'path traversal accepted'
 Assert (-not(Add-WindowsHomeGuestRequest $root $name ('x'*4097))) 'oversized request accepted'
 Assert (-not(Add-WindowsHomeGuestRequest $root $name ('é'*2049))) 'UTF8 byte limit bypassed'
 Assert (-not(Add-WindowsHomeGuestRequest $root $name 'not-json')) 'non-JSON accepted'
 Remove-Item $receipt
 $outside=Join-Path $root 'outside.json';[IO.File]::WriteAllText($outside,'unchanged')
 New-Item -ItemType SymbolicLink -Path $path -Target $outside|Out-Null
 $refused=$false;try{Add-WindowsHomeGuestRequest $root $name $json|Out-Null}catch{$refused=$true}
 Assert $refused 'reparse destination accepted'
 Assert ([IO.File]::ReadAllText($outside) -ceq 'unchanged') 'reparse target changed'
 Remove-Item $path
 New-Item -ItemType Directory -Path $path|Out-Null
 $refused=$false;try{Add-WindowsHomeGuestRequest $root $name $json|Out-Null}catch{$refused=$true}
 Assert $refused 'directory destination accepted'
 Write-Host 'GUEST TRANSPORT INTAKE: PASS (11 cases)' 
} finally {Remove-Item $root -Recurse -Force}
