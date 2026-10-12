# Built-in RDP audio playback host setup. Run elevated; no driver downloads.
# Microsoft TS_CLIENT_AUDIO policy maps to fDisableCam (not printer fDisableCpm).
# https://learn.microsoft.com/windows/client-management/mdm/policy-csp-admx-terminalserver#ts_client_audio
param([switch]$CheckOnly)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
$listener = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
$services = @('AudioEndpointBuilder','Audiosrv')
if (-not $CheckOnly) {
    foreach ($key in @($policy,$listener)) {
        New-Item -Path $key -Force | Out-Null
        New-ItemProperty -Path $key -Name fDisableCam -PropertyType DWord -Value 0 -Force | Out-Null
    }
    foreach ($name in $services) {
        $before = Get-Service -Name $name -ErrorAction Stop
        Write-Output "RDP AUDIO BEFORE: $name status=$($before.Status)"
        Set-Service -Name $name -StartupType Automatic -ErrorAction Stop
        Start-Service -Name $name -ErrorAction Stop
        (Get-Service -Name $name).WaitForStatus([ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromSeconds(15))
    }
}
foreach ($key in @($policy,$listener)) {
    if ((Get-ItemProperty -LiteralPath $key -Name fDisableCam -ErrorAction Stop).fDisableCam -ne 0) {
        throw 'RDP audio/video playback redirection is blocked.'
    }
}
foreach ($name in $services) {
    $state = Get-CimInstance -ClassName Win32_Service -Filter "Name='$name'" -ErrorAction Stop
    if (-not $state -or $state.State -ne 'Running' -or $state.StartMode -ne 'Auto') {
        throw "RDP audio prerequisite failed: $name must be running with automatic startup."
    }
    Write-Output "RDP AUDIO HOST: $name running; automatic startup verified."
}
Write-Output 'RDP AUDIO HOST CONFIGURATION: PASS. Audible client output requires an RDP connection configured to play sound on the local device.'
# Do not restart TermService or disconnect an existing desktop. Reconnect the
# client to renegotiate audio. An endpoint need not exist in the Actions session.
