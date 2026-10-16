$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($env:GITHUB_REF -cne 'refs/heads/pilot/windows-home-connection-20261015'){throw 'Pilot branch only.'}
$name='PilotCompatibility-'+$env:GITHUB_RUN_ID
$switch='nat'
$root=Join-Path $env:RUNNER_TEMP $name
if((Get-VM -Name $name -ErrorAction SilentlyContinue) -or (Get-VMSwitch -Name $switch -ErrorAction SilentlyContinue) -or (Test-Path $root)){throw 'Disposable identities occupied.'}
New-Item -ItemType Directory $root|Out-Null
New-VMSwitch -Name $switch -SwitchType Internal|Out-Null
$vm=New-VM -Name $name -Generation 2 -MemoryStartupBytes 128MB -NoVHD -Path (Join-Path $root 'source') -SwitchName $switch
$id=$vm.Id
Export-VM -VM $vm -Path (Join-Path $root 'export')
Remove-VM -VM $vm -Force
Remove-VMSwitch -Name $switch -Force
$config=@(Get-ChildItem (Join-Path $root 'export') -Recurse -Filter *.vmcx)
if($config.Count -ne 1){throw 'Export config ambiguous.'}
$r=Compare-VM -Path $config[0].FullName -Copy -VirtualMachinePath (Join-Path $root 'destination') -ErrorAction Stop
$diagnostic=[ordered]@{vmId=[string]$r.VM.Id;version=[string]$r.VM.Version;issues=@($r.Incompatibilities|ForEach-Object {$s=$_.Source;[ordered]@{messageId=$_.MessageId;message=$_.Message;sourceType=$s.GetType().FullName;typeNames=@($s.PSObject.TypeNames);properties=@($s.PSObject.Properties|Where-Object {$_.Name -match 'Id|Name|Switch'}|ForEach-Object {@{name=$_.Name;value=[string]$_.Value}})}})}
Write-Host ('NATIVE_COMPATIBILITY_SOURCE='+($diagnostic|ConvertTo-Json -Depth 8 -Compress))
if(@($r.Incompatibilities|Where-Object {$_.MessageId -eq 33012}).Count -ne 1){throw 'Missing-switch native condition not reproduced.'}
Write-Host 'NATIVE_MISSING_SWITCH_REPRODUCED=true'

. (Join-Path $PSScriptRoot '../scripts/windows-state-checkpoint.ps1')
New-VMSwitch -Name 'nat' -SwitchType Internal|Out-Null
$r=Resolve-WindowsStateImportCompatibility -Report $r -ExpectedVmId $id -ExpectedName $name -ExpectedVersion $diagnostic.version
if(@($r.Incompatibilities|Where-Object {$_}).Count){throw 'Native correction left incompatibilities.'}
$imported=Import-VM -CompatibilityReport $r -ErrorAction Stop
if($imported.Id -ne $id -or $imported.Name -cne $name -or [string]$imported.Version -cne $diagnostic.version){throw 'Native import identity changed.'}
if(@(Get-VMNetworkAdapter -VM $imported|Where-Object {$_.SwitchName -ceq 'nat'}).Count -ne 1){throw 'Native import switch remap failed.'}
Write-Host 'NATIVE_NAT_CORRECTION_AND_IMPORT_VERIFIED=true'
Remove-VM -VM $imported -Force
Remove-VMSwitch -Name 'nat' -Force
