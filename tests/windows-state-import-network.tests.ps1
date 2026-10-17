$ErrorActionPreference='Stop'
$module=Join-Path $PSScriptRoot '../scripts/windows-state-checkpoint.ps1'
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($module,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Checkpoint source parser failure'}
$definition=$ast.Find({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Resolve-WindowsStateImportCompatibility'},$true)
if(-not $definition){throw 'ASSERT: guarded import compatibility resolver missing'}
Invoke-Expression $definition.Extent.Text
$id=[guid]'66b514d0-7246-493f-ade3-1f004cd12411'
$name='DevBoxWindowsState-38647908553-1'
function New-Report {
    $adapter=[pscustomobject]@{VMId=$id;SwitchName='nat'}
    $adapter.PSObject.TypeNames.Insert(0,'Microsoft.HyperV.PowerShell.VMNetworkAdapter')
    [pscustomobject]@{VM=[pscustomobject]@{Id=$id;Name=$name;Version='12.0'};Incompatibilities=@([pscustomobject]@{MessageId=33012;Source=$adapter;Message='Missing original switch binding'})}
}
function New-SnapshotIssue {
    $snapshot=[pscustomobject]@{VMId=$id;Id=[guid]'b4f026df-7ddd-4ed5-bfd1-d3ee7dbf70ce';Name='test checkpoint one';State='Saved'}
    $snapshot.PSObject.TypeNames.Insert(0,'Microsoft.HyperV.PowerShell.VMSnapshot')
    [pscustomobject]@{MessageId=24002;Source=$snapshot;Message='Intel saved checkpoint on AMD host'}
}
function Get-VM {param($Id,$ErrorAction) $script:existingVm}
function Clear-WindowsStatePlannedSnapshotSavedState {param($Snapshot,$ExpectedVmId) $VMSnapshot=$Snapshot; $script:stateRemovals++;if($VMSnapshot.VMId -ne $id -or $VMSnapshot.Id -eq $id){throw 'Wrong checkpoint'};if($script:clearFails){throw 'Injected clear failure'}}
function Get-CimInstance {param($Namespace,$ClassName,$Filter,$ErrorAction) if($script:existingVm -and -not $script:plannedOnly){$script:existingVm}}
function Get-VMSwitch {param($Name,$ErrorAction) if($script:missingSwitch){throw 'Missing target'};[pscustomobject]@{Name='nat';SwitchType=$script:switchType}}
function Connect-VMNetworkAdapter {param($VMNetworkAdapter,$SwitchName,$ErrorAction) $script:connections++;if($SwitchName -cne 'nat'){throw 'Wrong target'}}
function Compare-VM {param($CompatibilityReport,$ErrorAction) $script:comparisons++;if(-not $script:stillBad){$CompatibilityReport.Incompatibilities=@()};$CompatibilityReport}
function Reset-Case {$script:caseCount++;$script:connections=0;$script:comparisons=0;$script:stateRemovals=0;$script:existingVm=$null;$script:plannedOnly=$false;$script:clearFails=$false;$script:switchType='Internal';$script:missingSwitch=$false;$script:stillBad=$false}
function Resolve-Test($Report){Resolve-WindowsStateImportCompatibility -Report $Report -ExpectedVmId $id -ExpectedName $name -ExpectedVersion '12.0'}
function Assert-Refused($Report,$ExpectedConnections=0,$ExpectedRemovals=0){
    $refused=$false;try{Resolve-Test $Report|Out-Null}catch{$refused=$true}
    if(-not $refused -or $script:connections -ne $ExpectedConnections -or $script:stateRemovals -ne $ExpectedRemovals){throw 'ASSERT: unsafe compatibility acceptance or mutation'}
}
$script:caseCount=0
Reset-Case
$r=New-Report;$r.Incompatibilities=@();$actual=Resolve-Test $r
if($script:connections -or $script:comparisons -or $actual.VM.Id -ne $id){throw 'ASSERT: compatible report unnecessarily modified'}
Reset-Case
$r=New-Report;$actual=Resolve-Test $r
if($script:connections -ne 1 -or $script:comparisons -ne 1 -or @($actual.Incompatibilities).Count){throw 'ASSERT: exact nat mapping not rechecked'}
Reset-Case;$r=New-Report;$r.Incompatibilities[0].MessageId=99999;Assert-Refused $r
Reset-Case;$r=New-Report;$r.VM.Id=[guid]::NewGuid();Assert-Refused $r
Reset-Case;$r=New-Report;$r.VM.Name='foreign';Assert-Refused $r
Reset-Case;$r=New-Report;$r.VM.Version='99.0';Assert-Refused $r
Reset-Case;$r=New-Report;$r.Incompatibilities[0].Source.VMId=[guid]::NewGuid();Assert-Refused $r
Reset-Case;$r=New-Report;$r.Incompatibilities[0].Source.SwitchName='foreign';Assert-Refused $r
Reset-Case;$r=New-Report;$script:switchType='External';Assert-Refused $r
Reset-Case;$r=New-Report;$script:missingSwitch=$true;Assert-Refused $r
Reset-Case;$r=New-Report;$script:stillBad=$true;Assert-Refused $r 1
Reset-Case;$r=New-Report;$r.Incompatibilities=@(New-SnapshotIssue);$actual=Resolve-Test $r
if($script:stateRemovals -ne 1 -or $script:connections -or $script:comparisons -ne 1){throw 'ASSERT: exact historical checkpoint memory not cleared/rechecked'}
Reset-Case;$r=New-Report;$r.Incompatibilities+=New-SnapshotIssue;$actual=Resolve-Test $r
if($script:stateRemovals -ne 1 -or $script:connections -ne 1 -or $script:comparisons -ne 1){throw 'ASSERT: mixed demonstrated issues not resolved together'}
Reset-Case;$r=New-Report;$r.Incompatibilities=@(New-SnapshotIssue);$r.Incompatibilities[0].Source.VMId=[guid]::NewGuid();Assert-Refused $r
Reset-Case;$r=New-Report;$r.Incompatibilities=@(New-SnapshotIssue);$r.Incompatibilities[0].Source.PSObject.TypeNames.Clear();Assert-Refused $r
Reset-Case;$r=New-Report;$r.Incompatibilities+=New-SnapshotIssue;$r.Incompatibilities+=([pscustomobject]@{MessageId=99999;Source=$r.Incompatibilities[0].Source});Assert-Refused $r
Reset-Case;$r=New-Report;$script:existingVm=[pscustomobject]@{Id=$id};Assert-Refused $r
Reset-Case;$r=New-Report;$r.Incompatibilities=@(New-SnapshotIssue);$script:clearFails=$true;Assert-Refused $r 0 1
Reset-Case;$r=New-Report;$r.Incompatibilities+=New-SnapshotIssue;$script:stillBad=$true;Assert-Refused $r 1 1
Reset-Case;$r=New-Report;$script:existingVm=[pscustomobject]@{Id=$id};$script:plannedOnly=$true;$actual=Resolve-Test $r
if($script:connections -ne 1 -or $script:comparisons -ne 1){throw 'ASSERT: planned copy mistaken for registered guest'}
Reset-Case;$r=New-Report;$r.Incompatibilities[0].Source.SwitchName='';$r.Incompatibilities[0].Message="Could not find Ethernet switch 'nat'.";$actual=Resolve-Test $r
if($script:connections -ne 1 -or $script:comparisons -ne 1){throw 'ASSERT: native blank switch source refused'}
Reset-Case;$r=New-Report;$r.Incompatibilities[0].Source.SwitchName='';$r.Incompatibilities[0].Message="Could not find Ethernet switch 'foreign'.";Assert-Refused $r
# Real native retry39065587684 reported feature-mask mismatch on the same owned snapshot.
Reset-Case;$r=New-Report;$r.Incompatibilities=@(New-SnapshotIssue);$r.Incompatibilities[0].MessageId=24004;$actual=Resolve-Test $r
if($script:stateRemovals -ne 1 -or $script:connections -or $script:comparisons -ne 1){throw 'ASSERT: native24004 historical checkpoint not cleared/rechecked'}
Reset-Case;$r=New-Report;$cpu=New-SnapshotIssue;$cpu.MessageId=24004;$r.Incompatibilities+=$cpu;$actual=Resolve-Test $r
if($script:stateRemovals -ne 1 -or $script:connections -ne 1 -or $script:comparisons -ne 1){throw 'ASSERT: native24004 mixed with exact nat not resolved'}
Reset-Case;$r=New-Report;$r.Incompatibilities=@(New-SnapshotIssue);$r.Incompatibilities[0].MessageId=24004;$r.Incompatibilities[0].Source.VMId=[guid]::NewGuid();Assert-Refused $r
Reset-Case;$r=New-Report;$r.Incompatibilities=@(New-SnapshotIssue);$r.Incompatibilities[0].MessageId=24004;$r.Incompatibilities[0].Source.PSObject.TypeNames.Clear();Assert-Refused $r
Reset-Case;$r=New-Report;$r.Incompatibilities=@(New-SnapshotIssue);$r.Incompatibilities[0].MessageId=24004;$r.Incompatibilities[0].Source.Id=$id;Assert-Refused $r
Reset-Case;$r=New-Report;$r.Incompatibilities=@(New-SnapshotIssue);$r.Incompatibilities[0].MessageId=24004;$r.Incompatibilities+=([pscustomobject]@{MessageId=24005;Source=$r.Incompatibilities[0].Source});Assert-Refused $r
Write-Output ('IMPORT NETWORK + HISTORICAL CPU STATE AND FOREIGN IDENTITY REFUSALS: PASS ('+$script:caseCount+' cases)')
