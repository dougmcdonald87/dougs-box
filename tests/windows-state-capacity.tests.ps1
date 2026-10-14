$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/windows-state-probe.ps1')
$capacity=Join-Path $PSScriptRoot '../scripts/windows-state-capacity.ps1'
if(Test-Path -LiteralPath $capacity){. $capacity}
if(-not (Get-Command Measure-WindowsStateExportCapacity -ErrorAction SilentlyContinue)){throw 'Whole guest capacity guard unavailable'}
foreach($root in @('C:/Windows','D:/User','E:/Other','E:/DevBox/Tools/WindowsStateProbe/probe-123-1/../other')){
    try {Measure-WindowsStateExportCapacity -Root $root -VmName 'DevBoxWindowsState-123-1';throw 'Foreign capacity export accepted'}
    catch {if($_.Exception.Message -notmatch '^Probe root must'){throw}}
}
Write-Output 'FOREIGN C/D/E EXPORT ROOTS REFUSED: PASS'
