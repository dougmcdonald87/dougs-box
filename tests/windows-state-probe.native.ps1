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
} finally {
    if($owner){Remove-WindowsStateProbe -Root $root -VmName $name}
}
if(@(Get-VM -ErrorAction Stop | Where-Object {$_.Id -eq $id}).Count){throw 'Owned VM cleanup failed'}
Write-Output 'NATIVE OWNERSHIP + EMPTY VM START + DISK + CLEANUP: PASS; Windows OS boot not tested.'
