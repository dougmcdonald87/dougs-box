$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -ne 'true' -or $env:DEVBOX_ISOLATED_TEST -ne '1'){throw 'Disposable CI runner only.'}
. (Join-Path $PSScriptRoot '../scripts/windows-state-probe.ps1')
& (Join-Path $PSScriptRoot '../scripts/bootstrap.ps1') -CloudCandidate
if(-not $? -or -not (Test-Path 'E:/DevBox/Control/session.json')){throw 'Owned E bootstrap failed'}
$root='E:/DevBox/Tools/WindowsStateProbe/probe-'+$env:GITHUB_RUN_ID+'-'+$env:GITHUB_RUN_ATTEMPT
$name='DevBoxWindowsState-'+$env:GITHUB_RUN_ID+'-'+$env:GITHUB_RUN_ATTEMPT
$owner=$null
try {
    $owner=New-WindowsStateProbe -Root $root -VmName $name
    $id=[guid]::Parse($owner.vmId)
    Start-VM -VM (Get-VM -Id $id -ErrorAction Stop) -ErrorAction Stop
    Start-Sleep -Seconds 3
    $vm=Get-VM -Id $id -ErrorAction Stop
    if($vm.State -ne 'Running'){throw 'Owned empty VM did not start'}
    Write-Output ('NATIVE OWNED EMPTY VM RUNNING: '+$id+' path='+$vm.Path)
    Stop-VM -VM $vm -TurnOff -Force -ErrorAction Stop
    $disk=New-WindowsStateGuestDisk -Root $root -VmName $name
    if($disk.capacityBytes -ne 64GB -or $disk.type -ne 'Dynamic' -or $disk.secureBoot -ne 'On'){throw 'Guest disk native contract mismatch'}
    $hash=(Get-FileHash -LiteralPath $disk.diskPath -Algorithm SHA256).Hash
    try {New-WindowsStateGuestDisk -Root $root -VmName $name;throw 'Existing disk replaced'}
    catch {if($_.Exception.Message -notmatch '^Existing guest disk must not be replaced'){throw}}
    if((Get-FileHash -LiteralPath $disk.diskPath -Algorithm SHA256).Hash -cne $hash){throw 'Refused retry changed existing disk'}
    Write-Output ('NATIVE OWNED DYNAMIC DISK + REFUSED RETRY: '+($disk|ConvertTo-Json -Compress))
    if($env:WINDOWS_STATE_MEDIA_URI){
        . (Join-Path $PSScriptRoot '../scripts/windows-home-media.ps1')
        $media=Get-WindowsHomeMedia -Root $root -VmName $name -Uri $env:WINDOWS_STATE_MEDIA_URI -Sha256 $env:WINDOWS_STATE_MEDIA_SHA256
        $image=Mount-DiskImage -ImagePath $media.path -PassThru -ErrorAction Stop
        try {
            $volume=$image | Get-Volume -ErrorAction Stop
            if(@($volume).Count -ne 1 -or -not $volume.DriveLetter){throw 'Installer volume ambiguous'}
            $wim=([string]$volume.DriveLetter)+':\sources\install.wim'
            if(-not (Test-Path -LiteralPath $wim)){throw 'Expected official install.wim missing'}
            $home=@(Get-WindowsImage -ImagePath $wim -ErrorAction Stop | Where-Object {$_.ImageName -ceq 'Windows 10 Home'})
            if($home.Count -ne 1){throw 'Windows 10 Home image ambiguous or missing'}
            $detail=Get-WindowsImage -ImagePath $wim -Index $home[0].ImageIndex -ErrorAction Stop
            if($detail.EditionId -cne 'Core'){throw 'Selected Windows image is not Home/Core'}
            Write-Output ('NATIVE WINDOWS10 HOME MEDIA VERIFIED: '+([pscustomobject]@{sha256=$media.sha256;bytes=$media.bytes;index=$detail.ImageIndex;name=$detail.ImageName;edition=$detail.EditionId;version=[string]$detail.Version;imageBytes=$detail.ImageSize}|ConvertTo-Json -Compress))
        } finally {Dismount-DiskImage -ImagePath $media.path -ErrorAction Stop | Out-Null}
        if($env:WINDOWS_STATE_INSTALL_IMAGE -eq 'true'){
            $receipt=Install-WindowsStateHomeImage -Root $root -VmName $name -Sha256 $env:WINDOWS_STATE_MEDIA_SHA256
            Write-Output ('NATIVE HOME IMAGE APPLIED: '+($receipt|ConvertTo-Json -Compress))
            Start-VM -VM (Get-VM -Id $id -ErrorAction Stop) -ErrorAction Stop
            $deadline=[DateTime]::UtcNow.AddMinutes(5);$heartbeat=$null
            do {
                Start-Sleep -Seconds 5
                $heartbeat=Get-VMIntegrationService -VM (Get-VM -Id $id -ErrorAction Stop) -Name Heartbeat -ErrorAction Stop
            } while($heartbeat.PrimaryStatusDescription -ne 'OK' -and [DateTime]::UtcNow -lt $deadline)
            if($heartbeat.PrimaryStatusDescription -ne 'OK'){throw 'Applied Home guest did not report a healthy OS heartbeat'}
            Write-Output ('NATIVE APPLIED WINDOWS10 DISK HEARTBEAT: '+$heartbeat.PrimaryStatusDescription+'; first-run setup and program fixture remain pending')
            Stop-VM -VM (Get-VM -Id $id -ErrorAction Stop) -Shutdown -ErrorAction Stop
        }
    }
} finally {
    if($owner){Remove-WindowsStateProbe -Root $root -VmName $name}
}
if(@(Get-VM -ErrorAction Stop | Where-Object {$_.Id -eq $id}).Count){throw 'Owned VM cleanup failed'}
Write-Output 'NATIVE OWNERSHIP + EMPTY VM START + DISK + CLEANUP: PASS; Windows OS boot not tested.'
