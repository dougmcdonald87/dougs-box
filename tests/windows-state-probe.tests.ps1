$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/windows-state-probe.ps1')
$facts=@{FreeBytes=100GB;AvailableMemoryBytes=12GB;HyperVReady=$true;ExistingVm=$false;RootOccupied=$false}
function Refused($root,$name,$change) {
    $f=$facts.Clone();foreach($k in $change.Keys){$f[$k]=$change[$k]}
    $r=Test-WindowsStateProbePolicy -Root $root -VmName $name -Facts $f
    if($r.eligible){throw "Unsafe request accepted: $root $name"}
}
$root='E:/DevBox/Tools/WindowsStateProbe/probe-123-1'
$name='DevBoxWindowsState-123-1'
Refused 'D:/DevBox/test' $name @{}
Refused 'E:/DevBox/Tools/WindowsStateProbe/../Other' $name @{}
Refused 'E:/DevBox/Tools/WindowsStateProbe/probe-123-1/child' $name @{}
Refused $root 'ExistingDesktop' @{}
Refused $root $name @{RootOccupied=$true}
Refused $root $name @{ExistingVm=$true}
Refused $root $name @{FreeBytes=1GB}
Refused $root $name @{AvailableMemoryBytes=4GB}
Refused $root $name @{HyperVReady=$false}
Refused $root $name @{RootReparse=$true}
Refused $root 'DevBoxWindowsState-124-1' @{}
$r=Test-WindowsStateProbePolicy -Root $root -VmName $name -Facts $facts
if(-not $r.eligible){throw $r.reason}
if($r.diskCapacityBytes -lt 64GB -or $r.memoryBytes -ne 8GB -or $r.processors -lt 2){throw 'Windows 11 VM hardware requirements not met'}
# Caller facts are observations and must not be modified by policy evaluation.
if($facts.Count -ne 5 -or $facts.FreeBytes -ne 100GB){throw 'Input facts mutated'}
# Cleanup must reject a forged marker before looking up or stopping a VM.
$temp=Join-Path ([IO.Path]::GetTempPath()) ('ProbePolicy-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $temp | Out-Null
New-PSDrive -Name E -PSProvider FileSystem -Root $temp -ErrorAction Stop | Out-Null
try {
    function Get-Content { return '{"schema":1,"root":"E:/Other","name":"Wrong","status":"created","vmId":"00000000-0000-0000-0000-000000000001"}' }
    function Get-VM { throw 'UNSAFE VM ACCESS' }
    try { Remove-WindowsStateProbe -Root $root -VmName $name; throw 'Forged owner accepted' }
    catch { if($_.Exception.Message -notmatch '^Ownership marker mismatch'){throw} }
} finally {
    Remove-Item Function:Get-Content,Function:Get-VM
    Remove-PSDrive E
    Remove-Item $temp -Force
}
Write-Output 'WINDOWS HOME PROBE POLICY: 12 safety cases and hardware contract PASS'

if(-not (Test-WindowsStateProbeVmPath -Root $root -VmName $name -VmPath ($root+'/'+$name))){throw 'Hyper-V name subdirectory refused'}
if(Test-WindowsStateProbeVmPath -Root $root -VmName $name -VmPath ($root+'/../unrelated')){throw 'Escaped VM path accepted'}
if(Test-WindowsStateProbeVmPath -Root $root -VmName $name -VmPath ($root+'/unrelated')){throw 'Wrong VM directory accepted'}
Write-Output 'HYPER-V OWNED NAME SUBDIRECTORY BOUNDARY: PASS'
