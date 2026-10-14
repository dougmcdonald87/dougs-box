$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/windows-state-probe.ps1')
$checkpoint=Join-Path $PSScriptRoot '../scripts/windows-state-checkpoint.ps1'
if(Test-Path -LiteralPath $checkpoint){. $checkpoint}
if(-not (Get-Command Export-WindowsStateCheckpoint -ErrorAction SilentlyContinue)){throw 'Owned whole VM checkpoint export unavailable'}
$id=[guid]'00000000-0000-0000-0000-000000000123'
foreach($root in @('C:/Windows','D:/User','E:/Other','E:/DevBox/Tools/WindowsStateProbe/probe-123-1/../other')){
    try {Export-WindowsStateCheckpoint -Root $root -VmId $id -Mode save;throw 'Foreign checkpoint export accepted'}
    catch {if($_.Exception.Message -notmatch '^Only an exact owned E probe directory'){throw}}
}
Write-Output 'CHECKPOINT FOREIGN C/D/E ROOTS REFUSED: PASS'
