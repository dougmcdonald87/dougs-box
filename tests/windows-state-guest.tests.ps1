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

if(-not (Get-Command New-WindowsStateFixtureAnswerFile -ErrorAction SilentlyContinue)){throw 'Fixture setup answer-file builder unavailable'}
$testCredential=[pscredential]::new('DevBoxFixture',(ConvertTo-SecureString 'FixtureOnly-Test123!' -AsPlainText -Force))
[xml]$answer=New-WindowsStateFixtureAnswerFile -Credential $testCredential
$ns=[Xml.XmlNamespaceManager]::new($answer.NameTable);$ns.AddNamespace('u','urn:schemas-microsoft-com:unattend')
$account=$answer.SelectSingleNode('//u:LocalAccount',$ns)
if($account.Name -cne 'DevBoxFixture' -or $account.Group -cne 'Administrators'){throw 'Fixture local account contract failed'}
if($answer.SelectNodes('//u:settings[@pass="oobeSystem"]',$ns).Count -ne 1){throw 'Fixture OOBE setup pass missing'}
if($answer.SelectNodes('//u:SkipMachineOOBE|//u:SkipUserOOBE|//u:ProductKey',$ns).Count){throw 'Unsupported setup bypass or activation field included'}
Write-Output 'SUPPORTED FIXTURE OOBE ANSWER-FILE CONTRACT: PASS'

foreach($name in @('Get-WindowsStateFixture','Install-WindowsStateFixture')){
    if(-not (Get-Command $name -ErrorAction SilentlyContinue)){throw ('Guest fixture function unavailable: '+$name)}
    try {& $name -GuestSession $null -VmId $id;throw 'Guest fixture reached host without session'}
    catch {if($_.Exception.Message -notmatch '^Only an open PowerShell Direct guest session'){throw}}
}
Write-Output 'FIXTURE READ/WRITE REJECT HOST CONTEXT: PASS'
