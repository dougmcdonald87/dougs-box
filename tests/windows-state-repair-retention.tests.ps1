$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../scripts/windows-state-roundtrip.ps1')
if(-not(Get-Command Complete-WindowsStateRestoreLifecycle -ErrorAction SilentlyContinue)){throw 'ASSERT: failed pilot recovery retention is missing'}
$keys=@('GITHUB_ACTIONS','DEVBOX_ISOLATED_TEST','GITHUB_EVENT_NAME','GITHUB_REPOSITORY','GITHUB_REF');$old=@{};foreach($k in $keys){$old[$k]=[Environment]::GetEnvironmentVariable($k)}
function Get-VM {param($Name,$ErrorAction) [pscustomobject]@{Name=$Name}}
function Remove-WindowsStateProbe {param($Root,$VmName) $script:removed++}
$root='E:/DevBox/Tools/WindowsStateProbe/probe-38647908553-1';$name='DevBoxWindowsState-38647908553-1'
try {
 $env:GITHUB_ACTIONS='true';$env:DEVBOX_ISOLATED_TEST='1';$env:GITHUB_EVENT_NAME='workflow_dispatch';$env:GITHUB_REPOSITORY='dougmcdonald87/dougs-box';$env:GITHUB_REF='refs/heads/pilot/windows-home-connection-20261015'
 $script:removed=0;$out=@(Complete-WindowsStateRestoreLifecycle $root $name $false $true $true)
 if($script:removed -or ($out -join '') -notlike '*FAILED_GUEST_PRESERVED_FOR_REPAIR*' -or ($out -join '') -like '*VERIFIED_GUEST_HELD*'){throw 'ASSERT: failed recovery deleted or falsely verified'}
 $script:removed=0;$out=@(Complete-WindowsStateRestoreLifecycle $root $name $true $true $true)
 if($script:removed -or ($out -join '') -notlike '*VERIFIED_GUEST_HELD*'){throw 'ASSERT: verified held VM changed'}
 $script:removed=0;Complete-WindowsStateRestoreLifecycle $root $name $false $false $false|Out-Null
 if($script:removed -ne 1){throw 'ASSERT: ordinary failed recovery cleanup changed'}
 $script:removed=0;Complete-WindowsStateRestoreLifecycle $root $name $true $false $false|Out-Null
 if($script:removed -ne 1){throw 'ASSERT: disposable verifier cleanup changed'}
 $script:removed=0;$env:GITHUB_REF='refs/heads/main';$failed=$false
 try{Complete-WindowsStateRestoreLifecycle $root $name $false $true $true|Out-Null}catch{$failed=$true}
 if(-not $failed -or $script:removed){throw 'ASSERT: foreign repair context accepted or mutated'}
 Write-Host 'REPAIR RETENTION: PASS (5 lifecycle cases)'
} finally {foreach($k in $keys){[Environment]::SetEnvironmentVariable($k,$old[$k])}}
