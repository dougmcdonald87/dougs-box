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

function Get-WindowsStateFixture {
    param([AllowNull()][object]$GuestSession,[guid]$VmId)
    Assert-WindowsStateGuestSession -GuestSession $GuestSession -VmId $VmId
    Invoke-Command -Session $GuestSession -ErrorAction Stop -ScriptBlock {
        $ErrorActionPreference='Stop'
        $python='C:\DevBoxFixture\Python312\python.exe'
        if(-not (Test-Path -LiteralPath $python)){throw 'Guest fixture program missing'}
        $version=& $python --version
        if($LASTEXITCODE -ne 0){throw 'Guest fixture program failed'}
        $document=Join-Path $env:USERPROFILE 'Documents\DevBoxFixture.txt'
        $preferences=Join-Path $env:APPDATA 'DevBoxFixture\preferences.json'
        [pscustomobject]@{
            machineName=$env:COMPUTERNAME
            machineGuid=(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid).MachineGuid
            programPath=$python;programVersion=[string]$version
            documentSha256=(Get-FileHash -LiteralPath $document -Algorithm SHA256).Hash
            preferences=(Get-Content -LiteralPath $preferences -Raw | ConvertFrom-Json)
            windowsHideFileExt=(Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name HideFileExt).HideFileExt
        }
    }
}

function Install-WindowsStateFixture {
    param([AllowNull()][object]$GuestSession,[guid]$VmId,[string]$InstallerPath)
    Assert-WindowsStateGuestSession -GuestSession $GuestSession -VmId $VmId
    if(-not $InstallerPath -or -not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)){throw 'Verified fixture installer required.'}
    $file=Get-Item -LiteralPath $InstallerPath -ErrorAction Stop
    if($file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Fixture installer reparse point refused.'}
    $expected='67B5635E80EA51072B87941312D00EC8927C4DB9BA18938F7AD2D27B328B95FB'
    if((Get-FileHash -LiteralPath $InstallerPath -Algorithm SHA256).Hash -cne $expected){throw 'Fixture installer SHA256 mismatch.'}
    $signature=Get-AuthenticodeSignature -LiteralPath $InstallerPath
    if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Python Software Foundation'){throw 'Fixture installer vendor signature invalid.'}
    Copy-Item -LiteralPath $InstallerPath -Destination 'C:\Windows\Temp\DevBoxFixture-python.exe' -ToSession $GuestSession -ErrorAction Stop
    Invoke-Command -Session $GuestSession -ArgumentList $expected -ErrorAction Stop -ScriptBlock {
        param($expectedHash)
        $ErrorActionPreference='Stop'
        $installer='C:\Windows\Temp\DevBoxFixture-python.exe'
        if((Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash -cne $expectedHash){throw 'Guest installer transfer hash mismatch.'}
        $root='C:\DevBoxFixture'
        if(Test-Path -LiteralPath $root){throw 'Existing guest fixture directory refused.'}
        New-Item -ItemType Directory -Path $root | Out-Null
        $process=Start-Process -FilePath $installer -ArgumentList @('/quiet','InstallAllUsers=0','TargetDir=C:\DevBoxFixture\Python312','Include_launcher=0','Include_pip=0','Include_test=0','Shortcuts=0','AssociateFiles=0','PrependPath=0') -PassThru -Wait
        if($process.ExitCode -notin @(0,3010)){throw ('Guest fixture installation failed: '+$process.ExitCode)}
        $document=Join-Path $env:USERPROFILE 'Documents\DevBoxFixture.txt'
        $preferences=Join-Path $env:APPDATA 'DevBoxFixture\preferences.json'
        New-Item -ItemType Directory -Path (Split-Path $document),(Split-Path $preferences) -Force | Out-Null
        $encoding=[Text.UTF8Encoding]::new($false)
        [IO.File]::WriteAllText($document,"DevBox persistent document fixture v1`n",$encoding)
        [IO.File]::WriteAllText($preferences,'{"theme":"dark","volume":42}',$encoding)
        New-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Force | Out-Null
        New-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name HideFileExt -Value 0 -PropertyType DWord -Force | Out-Null
        Remove-Item -LiteralPath $installer -Force
        # Setup may retain credentials in cached answer files; remove before export.
        foreach($answer in @('C:\Windows\Panther\unattend.xml','C:\Windows\Panther\Unattend\unattend.xml')){
            if(Test-Path -LiteralPath $answer){Remove-Item -LiteralPath $answer -Force}
        }
    }
    Get-WindowsStateFixture -GuestSession $GuestSession -VmId $VmId
}
