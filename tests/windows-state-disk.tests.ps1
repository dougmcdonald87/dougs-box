$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/windows-state-probe.ps1')
$root='E:/DevBox/Tools/WindowsStateProbe/probe-123-1'
$name='DevBoxWindowsState-123-1'
$id='00000000-0000-0000-0000-000000000123'
$facts=@{MarkerSchema=1;MarkerRoot=$root;MarkerName=$name;MarkerId=$id;MarkerStatus='created';VmId=$id;VmName=$name;VmPath=($root+'/'+$name);State='Off';Generation=2;DiskCount=0;DiskExists=$false;RootReparse=$false;FreeBytes=80GB}
function RefusedDisk($change) {
    $f=$facts.Clone();foreach($key in $change.Keys){$f[$key]=$change[$key]}
    $r=Test-WindowsStateGuestDiskPolicy -Root $root -VmName $name -Facts $f
    if($r.eligible){throw ('Unsafe guest disk request accepted: '+($change|ConvertTo-Json -Compress))}
}
RefusedDisk @{MarkerRoot='D:/Data'}
RefusedDisk @{MarkerName='Other'}
RefusedDisk @{MarkerId='00000000-0000-0000-0000-000000000124'}
RefusedDisk @{MarkerStatus='removed'}
RefusedDisk @{MarkerSchema=2}
RefusedDisk @{VmName='Other'}
RefusedDisk @{VmPath=($root+'/../Other')}
RefusedDisk @{State='Running'}
RefusedDisk @{Generation=1}
RefusedDisk @{DiskCount=1}
RefusedDisk @{DiskExists=$true}
RefusedDisk @{RootReparse=$true}
RefusedDisk @{FreeBytes=79GB}
RefusedDisk @{VmId='invalid'}
$result=Test-WindowsStateGuestDiskPolicy -Root $root -VmName $name -Facts $facts
if(-not $result.eligible){throw $result.reason}
if($result.diskPath -cne ($root+'/windows-home.vhdx') -or $result.diskCapacityBytes -ne 64GB){throw 'Wrong owned disk contract'}
if($facts.Count -ne 14 -or $facts.DiskExists){throw 'Observations mutated'}
Write-Output 'GUEST DISK POLICY: 14 refusals and owned 64 GiB contract PASS'

# An ownership failure must be rejected before any Hyper-V or disk operation.
$temp=Join-Path ([IO.Path]::GetTempPath()) ('GuestDisk-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $temp | Out-Null
New-PSDrive -Name E -PSProvider FileSystem -Root $temp | Out-Null
try {
    function Get-Content { return '{"schema":1,"root":"E:/Other","name":"Wrong","status":"created","vmId":"00000000-0000-0000-0000-000000000123"}' }
    function Get-VM { throw 'UNSAFE VM ACCESS' }
    function New-VHD { throw 'UNSAFE DISK MUTATION' }
    try { New-WindowsStateGuestDisk -Root $root -VmName $name;throw 'Forged marker accepted' }
    catch {if($_.Exception.Message -notmatch '^Guest disk ownership marker mismatch'){throw}}
} finally {
    Remove-Item Function:Get-Content,Function:Get-VM,Function:New-VHD
    Remove-PSDrive E
    Remove-Item $temp -Force
}
Write-Output 'FORGED OWNER REFUSED BEFORE HOST ACCESS: PASS'
