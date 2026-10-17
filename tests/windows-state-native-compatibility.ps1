$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($env:GITHUB_REF -cne 'refs/heads/pilot/windows-home-connection-20261015'){throw 'Pilot branch only.'}
$name='PilotCompatibility-'+$env:GITHUB_RUN_ID
$switch='PilotMissing-'+$env:GITHUB_RUN_ID
$root=Join-Path $env:RUNNER_TEMP $name
if((Get-VM -Name $name -ErrorAction SilentlyContinue) -or (Get-VMSwitch -Name $switch -ErrorAction SilentlyContinue) -or (Test-Path $root)){throw 'Disposable identities occupied.'}
New-Item -ItemType Directory $root|Out-Null
New-VMSwitch -Name $switch -SwitchType Internal|Out-Null
$vm=New-VM -Name $name -Generation 2 -MemoryStartupBytes 256MB -NoVHD -Path (Join-Path $root 'source') -SwitchName $switch
$id=$vm.Id
Set-VM -VM $vm -CheckpointType Standard
Start-VM -VM $vm -ErrorAction Stop
Checkpoint-VM -VM $vm -SnapshotName 'OwnedSavedMemoryProbe' -ErrorAction Stop
Stop-VM -VM $vm -TurnOff -ErrorAction Stop
Export-VM -VM $vm -Path (Join-Path $root 'export')
Remove-VM -VM $vm -Force
Remove-VMSwitch -Name $switch -Force
$config=@(Get-ChildItem (Join-Path $root 'export') -Recurse -Filter ($id.ToString()+'.vmcx'))
if($config.Count -ne 1){throw 'Export config ambiguous.'}
$r=Compare-VM -Path $config[0].FullName -Copy -VirtualMachinePath (Join-Path $root 'destination') -ErrorAction Stop
$diagnostic=[ordered]@{vmId=[string]$r.VM.Id;version=[string]$r.VM.Version;issues=@($r.Incompatibilities|ForEach-Object {$s=$_.Source;[ordered]@{messageId=$_.MessageId;message=$_.Message;sourceType=$s.GetType().FullName;typeNames=@($s.PSObject.TypeNames);properties=@($s.PSObject.Properties|Where-Object {$_.Name -match 'Id|Name|Switch'}|ForEach-Object {@{name=$_.Name;value=[string]$_.Value}})}})}
Write-Host ('NATIVE_COMPATIBILITY_SOURCE='+($diagnostic|ConvertTo-Json -Depth 8 -Compress))
if(@($r.Incompatibilities|Where-Object {$_.MessageId -eq 33012}).Count -ne 2){throw 'Missing-switch native condition not reproduced.'}
Write-Host 'NATIVE_MISSING_SWITCH_REPRODUCED=true'
$snapshots=@(Get-VMSnapshot -VM $r.VM -ErrorAction Stop|Where-Object {$_.Name -ceq 'OwnedSavedMemoryProbe'})
if($snapshots.Count -ne 1 -or $snapshots[0].VMId -ne $id -or $snapshots[0].State.ToString() -cne 'Saved'){throw 'Native planned saved-memory condition not reproduced.'}
Write-Host ('NATIVE_PLANNED_CHECKPOINT_BEFORE='+($snapshots[0]|Select-Object Id,VMId,Name,State|ConvertTo-Json -Compress))
Remove-VMSavedState -VMSnapshot $snapshots[0] -Confirm:$false -ErrorAction Stop
$after=@(Get-VMSnapshot -VM $r.VM -ErrorAction Stop|Where-Object {$_.Id -eq $snapshots[0].Id})
if($after.Count -ne 1 -or $after[0].VMId -ne $id -or $after[0].State.ToString() -cne 'Off'){throw 'Native planned checkpoint memory removal unverified.'}
Write-Host 'NATIVE_PLANNED_CHECKPOINT_SAVED_MEMORY_REMOVAL_VERIFIED=true' 

# Keep any preexisting nat switch untouched. Exercise the same native resolver
# with only the expected resource-name constant changed to our owned switch.
# Do not alter the native report, source objects, or command implementations.
$t=$null;$e=$null
$a=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../scripts/windows-state-checkpoint.ps1'),[ref]$t,[ref]$e)
if($e.Count){throw 'Resolver parser failed.'}
$f=$a.Find({param($n)$n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Resolve-WindowsStateImportCompatibility'},$true).Extent.Text
Invoke-Expression $f.Replace("'nat'",("'"+$switch+"'"))
New-VMSwitch -Name $switch -SwitchType Internal|Out-Null
$r=Resolve-WindowsStateImportCompatibility -Report $r -ExpectedVmId $id -ExpectedName $name -ExpectedVersion $diagnostic.version
if(@($r.Incompatibilities|Where-Object {$_}).Count){throw 'Native correction left incompatibilities.'}
$imported=Import-VM -CompatibilityReport $r -ErrorAction Stop
if($imported.Id -ne $id -or $imported.Name -cne $name -or [string]$imported.Version -cne $diagnostic.version){throw 'Native import identity changed.'}
if(@(Get-VMNetworkAdapter -VM $imported|Where-Object {$_.SwitchName -ceq $switch}).Count -ne 1){throw 'Native import switch remap failed.'}
Write-Host 'NATIVE_OWNED_SWITCH_CORRECTION_AND_IMPORT_VERIFIED=true'
Remove-VM -VM $imported -Force
Remove-VMSwitch -Name $switch -Force
