$ErrorActionPreference='Stop'
$t=$null;$e=$null
$a=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../scripts/windows-state-checkpoint.ps1'),[ref]$t,[ref]$e)
$f=$a.Find({param($n)$n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Clear-WindowsStatePlannedSnapshotSavedState'},$true)
if(-not $f){throw 'ASSERT: verified native planned-state helper missing'}
Invoke-Expression $f.Extent.Text
$id=[guid]'66b514d0-7246-493f-ade3-1f004cd12411'
$sid=[guid]'b4f026df-7ddd-4ed5-bfd1-d3ee7dbf70ce'
function Reset-Test {
 $script:calls=0;$script:registered=$false;$script:code=0;$script:remain=$false;$script:jobError=0
 $script:snapshot=[pscustomobject]@{VMId=$id;Id=$sid};$script:snapshot.PSObject.TypeNames.Insert(0,'Microsoft.HyperV.PowerShell.VMSnapshot')
 $script:settings=[pscustomobject]@{ConfigurationID=$sid.ToString();VirtualSystemIdentifier=$id.ToString();VirtualSystemType='Microsoft:Hyper-V:Snapshot:Planned';IsSaved=$true}
}
function Get-CimInstance {param($Namespace,$ClassName,$Filter,$InputObject,$ErrorAction)
 if($ErrorAction -ne 'Stop'){throw 'ASSERT: query must fail closed'}
 if($InputObject){if($InputObject.kind -eq 'job'){return [pscustomobject]@{JobState=7;ErrorCode=$script:jobError}};return $script:settings}
 if($Namespace -cne 'root/virtualization/v2'){throw 'ASSERT: wrong namespace'}
 switch($ClassName){
 'Msvm_ComputerSystem' {if($Filter -cne ("Name='"+$id+"'")){throw 'ASSERT: wrong registered GUID filter'};if($script:registered){[pscustomobject]@{Name=$id}}}
 'Msvm_VirtualSystemSettingData' {if($Filter -cne ("ConfigurationID='"+$sid+"'")){throw 'ASSERT: wrong snapshot filter'};$script:settings}
 'Msvm_VirtualSystemSnapshotService' {[pscustomobject]@{kind='service'}}
 default {throw 'ASSERT: unexpected native class'}
 }
}
function Invoke-CimMethod {param($InputObject,$MethodName,$Arguments,$ErrorAction)
 if($MethodName -cne 'ClearSnapshotState' -or $Arguments.SnapshotSettingData.ConfigurationID -ne $sid.ToString()){throw 'ASSERT: wrong native method/source'}
 $script:calls++;if(-not $script:remain){$script:settings.IsSaved=$false}
 [pscustomobject]@{ReturnValue=$script:code;Job=[pscustomobject]@{kind='job'}}
}
function Run-Test {Clear-WindowsStatePlannedSnapshotSavedState -Snapshot $script:snapshot -ExpectedVmId $id}
function Refuse($mutations=0){$failed=$false;try{Run-Test}catch{$failed=$true};if(-not $failed -or $script:calls -ne $mutations){throw 'ASSERT: unsafe saved-state acceptance/mutation'}}
Reset-Test;Run-Test;if($script:calls -ne 1 -or $script:settings.IsSaved){throw 'ASSERT: native clear postcondition'}
Reset-Test;$script:registered=$true;Refuse
Reset-Test;$script:snapshot.VMId=[guid]::NewGuid();Refuse
Reset-Test;$script:settings.VirtualSystemIdentifier=[guid]::NewGuid();Refuse
Reset-Test;$script:settings.VirtualSystemType='Microsoft:Hyper-V:Snapshot:Realized';Refuse
Reset-Test;$script:settings.IsSaved=$false;Run-Test;if($script:calls){throw 'ASSERT: clear unnecessarily repeated'}
Reset-Test;$script:code=32775;Refuse 1
Reset-Test;$script:remain=$true;Refuse 1
Reset-Test;$script:code=4096;Run-Test;if($script:calls -ne 1){throw 'ASSERT: asynchronous success missing'}
Reset-Test;$script:code=4096;$script:jobError=1;Refuse 1
Write-Host 'PLANNED SAVED MEMORY NATIVE GUARDS: PASS (10 cases)'
