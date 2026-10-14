$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/windows-state-probe.ps1')
$checkpoint=Join-Path $PSScriptRoot '../scripts/windows-state-checkpoint.ps1'
if(Test-Path -LiteralPath $checkpoint){. $checkpoint}
$missing=@('Export-WindowsStateCheckpoint','Import-WindowsStateCheckpoint' | Where-Object {-not (Get-Command $_ -ErrorAction SilentlyContinue)})
if($missing.Count){throw ('Owned checkpoint functions unavailable: '+($missing -join ', '))}
$id=[guid]'00000000-0000-0000-0000-000000000123'
foreach($root in @('C:/Windows','D:/User','E:/Other','E:/DevBox/Tools/WindowsStateProbe/probe-123-1/../other')){
    try {Export-WindowsStateCheckpoint -Root $root -VmId $id -Mode save;throw 'Foreign checkpoint export accepted'}
    catch {if($_.Exception.Message -notmatch '^Only an exact owned E probe directory'){throw}}
}
Write-Output 'CHECKPOINT FOREIGN C/D/E ROOTS REFUSED: PASS'

foreach($root in @('C:/Windows','D:/User','E:/Other')){
    try {Import-WindowsStateCheckpoint -Root $root -VmId $id -ExportPath 'E:/Other' -ManifestPath 'E:/Other.json';throw 'Foreign checkpoint import accepted'}
    catch {if($_.Exception.Message -notmatch '^Only an exact owned E probe directory'){throw}}
}
Write-Output 'CHECKPOINT IMPORT FOREIGN C/D/E ROOTS REFUSED: PASS'
