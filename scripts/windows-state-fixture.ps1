$ErrorActionPreference='Stop'
function Assert-WindowsStateGuestSession {
    param([AllowNull()][object]$GuestSession,[guid]$VmId)
    if($VmId -eq [guid]::Empty -or $GuestSession -isnot [System.Management.Automation.Runspaces.PSSession] -or $GuestSession.State -ne 'Opened'){
        throw 'Only an open PowerShell Direct guest session for the owned VM is allowed.'
    }
    $connection=$GuestSession.Runspace.ConnectionInfo
    if($connection -isnot [System.Management.Automation.Runspaces.VMConnectionInfo] -or $connection.VMGuid -ne $VmId){
        throw 'Only an open PowerShell Direct guest session for the owned VM is allowed.'
    }
}

function New-WindowsStateFixtureAnswerFile {
    param([Parameter(Mandatory)][pscredential]$Credential)
    if($Credential.UserName -cne 'DevBoxFixture'){throw 'Only the isolated DevBoxFixture account is allowed.'}
    $password=[Security.SecurityElement]::Escape($Credential.GetNetworkCredential().Password)
    if([string]::IsNullOrWhiteSpace($password)){throw 'Fixture account password required.'}
    @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <InputLocale>0809:00000809</InputLocale><SystemLocale>en-GB</SystemLocale><UILanguage>en-GB</UILanguage><UserLocale>en-GB</UserLocale>
    </component>
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <TimeZone>GMT Standard Time</TimeZone>
      <OOBE><HideEULAPage>true</HideEULAPage><HideOEMRegistrationScreen>true</HideOEMRegistrationScreen><HideOnlineAccountScreens>true</HideOnlineAccountScreens><HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE><ProtectYourPC>1</ProtectYourPC></OOBE>
      <UserAccounts><LocalAccounts><LocalAccount wcm:action="add"><Name>DevBoxFixture</Name><DisplayName>DevBoxFixture</DisplayName><Group>Administrators</Group><Password><Value>$password</Value><PlainText>true</PlainText></Password></LocalAccount></LocalAccounts></UserAccounts>
    </component>
  </settings>
</unattend>
"@
}
