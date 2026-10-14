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
