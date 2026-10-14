$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/windows-home-media.ps1')
$good='https://software.download.prss.microsoft.com/dbazure/example.iso'
$hash='BD4307DF32BC8AF33B39CCECB1174AEB345386630F89A2B86C7A4E36B55EA650'
$root='E:/DevBox/Tools/WindowsStateProbe/probe-123-1'
$name='DevBoxWindowsState-123-1'
function Reject($uri,$digest,$path,$vm){
    $r=Test-WindowsHomeMediaRequest -Uri $uri -Sha256 $digest -Root $path -VmName $vm
    if($r.accepted){throw 'Unsafe media request accepted'}
}
Reject 'http://software.download.prss.microsoft.com/example.iso' $hash $root $name
Reject 'https://software.download.prss.microsoft.com.evil.invalid/example.iso' $hash $root $name
Reject 'https://other.invalid/example.iso' $hash $root $name
Reject 'https://user:password@software.download.prss.microsoft.com/example.iso' $hash $root $name
Reject $good 'not-a-hash' $root $name
Reject $good $hash 'D:/DevBox' $name
Reject $good $hash $root 'WrongVm'
$r=Test-WindowsHomeMediaRequest -Uri $good -Sha256 $hash -Root $root -VmName $name
if(-not $r.accepted -or $r.maxBytes -ne 12GB){throw 'Valid official media request refused or unbounded'}
Write-Output 'WINDOWS HOME MEDIA REQUEST BOUNDARIES: 8 PASS'
