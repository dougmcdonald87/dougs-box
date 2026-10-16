# Provision the owner-approved GUI login INSIDE the isolated, already verified guest.
# PowerShell Direct carries SecureString across the host/VM boundary. Do not print secrets.
[CmdletBinding()]
param([Parameter(Mandatory)][guid]$VmId,
      [Parameter(Mandatory)][string]$Root,
      [Parameter(Mandatory)][string]$OriginGeneration)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

if($env:GITHUB_ACTIONS -cne 'true' -or
   $env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or
   $env:DEVBOX_ISOLATED_TEST -cne '1' -or
   $env:GITHUB_REPOSITORY -cne 'dougmcdonald87/dougs-box' -or
   $env:GITHUB_REF -cne 'refs/heads/pilot/windows-home-connection-20261015'){
    throw 'Guest owner login is permitted only in the isolated manual Windows Home pilot.'
}
if([string]::IsNullOrWhiteSpace($env:DEVBOX_RDP_PASSWORD)){
    throw 'Existing owner-known RDP password unavailable. Refuse guest-account provisioning.'
}
$pattern='^devbox-checkpoint-v1-ci-([1-9][0-9]*)-([1-9][0-9]*)-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{32}$'
$origin=[regex]::Match($OriginGeneration,$pattern)
if(-not $origin.Success){throw 'Original owned guest generation invalid.'}
. (Join-Path $PSScriptRoot 'windows-state-checkpoint.ps1')
$owner=Get-WindowsStateCheckpointOwner -Root $Root -VmId $VmId
$expectedName='DevBoxWindowsState-'+$origin.Groups[1].Value+'-'+$origin.Groups[2].Value
if($owner.name -cne $expectedName -or $owner.vm.State -ne 'Running'){
    throw 'Guest identity/state mismatch; refuse owner account provisioning.'
}
. (Join-Path $PSScriptRoot 'windows-state-roundtrip.ps1')
$fixtureCredential=Get-WindowsStatePortableFixtureCredential -VmId $VmId
$ownerPassword=ConvertTo-SecureString $env:DEVBOX_RDP_PASSWORD -AsPlainText -Force
$fixtureSession=$null
$ownerSession=$null
try {
    $fixtureSession=New-PSSession -VMId $VmId -Credential $fixtureCredential -ErrorAction Stop
    $state=Invoke-Command -Session $fixtureSession -ArgumentList $ownerPassword -ErrorAction Stop -ScriptBlock {
        param([securestring]$Password)
        $ErrorActionPreference='Stop'
        $name='PilotOwner'
        $existing=Get-LocalUser -Name $name -ErrorAction SilentlyContinue
        if(-not $existing){
            New-LocalUser -Name $name -Password $Password -AccountNeverExpires -PasswordNeverExpires -ErrorAction Stop|Out-Null
        } elseif(-not $existing.Enabled){
            throw 'Preexisting PilotOwner account is disabled; refuse to modify it.'
        }
        # Resolve the built-in Administrators group by SID, never by English name.
        $adminSid=[Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
        $admins=Get-LocalGroup -SID $adminSid -ErrorAction Stop
        $user=Get-LocalUser -Name $name -ErrorAction Stop
        $members=@(Get-LocalGroupMember -Group $admins.Name -ErrorAction Stop)
        if(-not @($members|Where-Object {$_.SID.Value -eq $user.SID.Value}).Count){
            Add-LocalGroupMember -Group $admins.Name -Member $name -ErrorAction Stop
        }
        $members=@(Get-LocalGroupMember -Group $admins.Name -ErrorAction Stop)
        if(-not @($members|Where-Object {$_.SID.Value -eq $user.SID.Value}).Count){
            throw 'Guest owner group membership not verified.'
        }
        if(-not (Get-LocalUser -Name $name -ErrorAction Stop).Enabled){
            throw 'Guest owner account disabled after provisioning.'
        }
        # Never change DevBoxFixture: it remains the verified recovery account.
        [pscustomobject]@{owner=$name;administrator=$true}
    }
    if($state.owner -cne 'PilotOwner' -or $state.administrator -ne $true){
        throw 'Guest owner creation result was not verified.'
    }
    Remove-PSSession -Session $fixtureSession -ErrorAction Stop
    $fixtureSession=$null
    # A successful PowerShell Direct login verifies the newly configured password,
    # not a rendered GUI session. The owner must still test VMConnect interactively.
    $ownerCredential=[pscredential]::new('PilotOwner',$ownerPassword)
    $ownerSession=New-PSSession -VMId $VmId -Credential $ownerCredential -ErrorAction Stop
    $actual=Invoke-Command -Session $ownerSession -ErrorAction Stop -ScriptBlock {
        [Security.Principal.WindowsIdentity]::GetCurrent().Name
    }
    if([string]$actual -cnotmatch '(?i)\\PilotOwner$'){
        throw 'Guest owner credential authenticated as an unexpected account.'
    }
    Write-Output 'PILOT_GUEST_OWNER_LOGIN_VERIFIED=PilotOwner'
} finally {
    if($ownerSession){Remove-PSSession -Session $ownerSession -ErrorAction SilentlyContinue}
    if($fixtureSession){Remove-PSSession -Session $fixtureSession -ErrorAction SilentlyContinue}
    if($ownerPassword){$ownerPassword.Dispose()}
}
