$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/windows-state-probe.ps1')
$root='E:/DevBox/Tools/WindowsStateProbe/probe-123-1'
$path=$root+'/windows-home.vhdx'
$facts=@{ExpectedPath=$path;ActualPath=$path;VhdType='Dynamic';CapacityBytes=64GB;DiskNumber=7;ResolvedDiskNumber=7;BusType='FileBackedVirtual';PartitionStyle='RAW';IsBoot=$false;IsSystem=$false;PartitionCount=0;Mounted=$true}
function RefusedInstall($change){
    $f=$facts.Clone();foreach($key in $change.Keys){$f[$key]=$change[$key]}
    $r=Test-WindowsStateInstallDiskPolicy -Root $root -Facts $f
    if($r.eligible){throw ('Unsafe installation disk accepted: '+($change|ConvertTo-Json -Compress))}
}
RefusedInstall @{ActualPath='D:/User.vhdx'}
RefusedInstall @{ActualPath=($root+'/../Other/windows-home.vhdx')}
RefusedInstall @{ExpectedPath='C:/Windows.vhdx';ActualPath='C:/Windows.vhdx'}
RefusedInstall @{VhdType='Differencing'}
RefusedInstall @{CapacityBytes=32GB}
RefusedInstall @{DiskNumber=0}
RefusedInstall @{ResolvedDiskNumber=8}
RefusedInstall @{BusType='NVMe'}
RefusedInstall @{PartitionStyle='GPT'}
RefusedInstall @{IsBoot=$true}
RefusedInstall @{IsSystem=$true}
RefusedInstall @{PartitionCount=1}
RefusedInstall @{Mounted=$false}
RefusedInstall @{IsSystem='False'}
$r=Test-WindowsStateInstallDiskPolicy -Root $root -Facts $facts
if(-not $r.eligible -or $r.diskNumber -ne 7){throw 'Owned new virtual disk refused'}
Write-Output 'INSTALLATION DISK POLICY: 14 host/existing-disk refusals and owned new virtual disk PASS'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('InstallGuard-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $temp | Out-Null
New-PSDrive -Name E -PSProvider FileSystem -Root $temp | Out-Null
try {
    function Get-Content {return '{"schema":1,"root":"E:/Other","name":"Wrong","status":"created","vmId":"00000000-0000-0000-0000-000000000123"}'}
    function Get-VM {throw 'UNSAFE HOST ACCESS'}
    function Initialize-Disk {throw 'UNSAFE DISK MUTATION'}
    try {Install-WindowsStateHomeImage -Root $root -VmName 'DevBoxWindowsState-123-1' -Sha256 ('A'*64);throw 'Forged installation owner accepted'}
    catch {if($_.Exception.Message -notmatch '^Installation ownership marker mismatch'){throw}}
} finally {
    Remove-Item Function:Get-Content,Function:Get-VM,Function:Initialize-Disk
    Remove-PSDrive E
    Remove-Item $temp -Force
}
Write-Output 'INSTALLATION FORGED OWNER REFUSED BEFORE HOST ACCESS: PASS'
