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
function Get-VMSwitch {param($Name,$ErrorAction) if($script:missingSwitch){throw 'Missing target'};[pscustomobject]@{Name='nat';SwitchType=$script:switchType}}
function Connect-VMNetworkAdapter {param($VMNetworkAdapter,$SwitchName,$ErrorAction) $script:connections++;if($SwitchName -cne 'nat'){throw 'Wrong target'}}
function Compare-VM {param($CompatibilityReport,$ErrorAction) $script:comparisons++;if(-not $script:stillBad){$CompatibilityReport.Incompatibilities=@()};$CompatibilityReport}
function Reset-Case {$script:connections=0;$script:comparisons=0;$script:switchType='Internal';$script:missingSwitch=$false;$script:stillBad=$false}
function Resolve-Test($Report){Resolve-WindowsStateImportCompatibility -Report $Report -ExpectedVmId $id -ExpectedName $name -ExpectedVersion '12.0'}
function Assert-Refused($Report,$ExpectedConnections=0){
    $refused=$false;try{Resolve-Test $Report|Out-Null}catch{$refused=$true}
    if(-not $refused -or $script:connections -ne $ExpectedConnections){throw 'ASSERT: unsafe compatibility acceptance or network mutation'}
}
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
Write-Output 'IMPORT NAT REMAPPING AND FOREIGN IDENTITY/ISSUE REFUSALS: PASS (11 cases)'
