param([Parameter(Mandatory)][object]$GuestSession,[Parameter(Mandatory)][guid]$VmId,[switch]$ExpectMissing)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/windows-state-fixture.ps1')
if($ExpectMissing){
    try {Get-WindowsStateFixture -GuestSession $GuestSession -VmId $VmId | Out-Null;throw 'Clean guest unexpectedly has fixture'}
    catch {if($_.Exception.Message -notmatch '^Guest fixture program missing'){throw}}
    Write-Output 'CLEAN REAL GUEST ACCEPTANCE RED: program missing as expected'
    return
}
$r=Get-WindowsStateFixture -GuestSession $GuestSession -VmId $VmId
if($r.programPath -cne 'C:\DevBoxFixture\Python312\python.exe' -or $r.programVersion.Trim() -cne 'Python 3.12.10'){throw 'Real guest program/version contract failed'}
if($r.documentSha256 -cne '37414D64D5A2F9BF3EC81BCD961820BD691486C7369B70E4689484B01256C488'){throw 'Real guest document hash contract failed'}
if($r.preferences.theme -cne 'dark' -or $r.preferences.volume -ne 42 -or $r.windowsHideFileExt -ne 0){throw 'Real guest application/Windows setting contract failed'}
if(-not $r.machineGuid -or -not $r.machineName){throw 'Real guest machine identity missing'}
$r
