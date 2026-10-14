$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/windows-state-probe.ps1')
$fixture=Join-Path $PSScriptRoot '../scripts/windows-state-fixture.ps1'
if(Test-Path -LiteralPath $fixture){. $fixture}
if(-not (Get-Command Assert-WindowsStateGuestSession -ErrorAction SilentlyContinue)){throw 'Guest session guard unavailable'}
$id=[guid]'00000000-0000-0000-0000-000000000123'
foreach($session in @($null,[pscustomobject]@{Runspace=[pscustomobject]@{ConnectionInfo=[pscustomobject]@{VMGuid=$id}}})){
    try {Assert-WindowsStateGuestSession -GuestSession $session -VmId $id;throw 'Forged guest session accepted'}
    catch {if($_.Exception.Message -notmatch '^Only an open PowerShell Direct guest session'){throw}}
}
Write-Output 'NULL AND FORGED GUEST SESSIONS REFUSED BEFORE INVOKE: PASS'
