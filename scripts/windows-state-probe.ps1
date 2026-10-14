# Windows Home guest probe guards and owned disposable VM lifecycle.
Set-StrictMode -Version Latest
function Test-WindowsStateProbePolicy {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root,
          [Parameter(Mandatory)][string]$VmName,
          [Parameter(Mandatory)][hashtable]$Facts)
    $reason=''
    $canonical=$Root.Replace('\','/')
    $rootMatch=[regex]::Match($canonical,'^E:/DevBox/Tools/WindowsStateProbe/probe-([0-9]+)-([0-9]+)$',[Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if(-not $rootMatch.Success){$reason='Only an exact owned E probe directory is allowed.'}
    elseif($VmName -cne ('DevBoxWindowsState-'+$rootMatch.Groups[1].Value+'-'+$rootMatch.Groups[2].Value)){$reason='VM name and probe directory identities must match.'}
    else {
        foreach($key in @('FreeBytes','AvailableMemoryBytes','HyperVReady','ExistingVm','RootOccupied')) {
            if(-not $Facts.ContainsKey($key)){$reason='Host observations incomplete.';break}
        }
        if(-not $reason){
            if($Facts.HyperVReady -isnot [bool] -or $Facts.ExistingVm -isnot [bool] -or $Facts.RootOccupied -isnot [bool]){$reason='Invalid host observation types.'}
            elseif(-not $Facts.HyperVReady){$reason='Hyper-V is not ready.'}
            elseif($Facts.ExistingVm){$reason='An existing VM must not be replaced.'}
            elseif($Facts.RootOccupied){$reason='An occupied directory must not be reused.'}
            elseif($Facts.ContainsKey('RootReparse') -and $Facts.RootReparse -ne $false){$reason='Reparse-point ancestry is not allowed.'}
            elseif($Facts.FreeBytes -isnot [ValueType] -or $Facts.AvailableMemoryBytes -isnot [ValueType]){$reason='Invalid capacity observations.'}
            elseif($Facts.FreeBytes -lt 80GB){$reason='At least 80 GiB of free E space is required for the initial probe.'}
            elseif($Facts.AvailableMemoryBytes -lt 10GB){$reason='8 GiB guest plus 2 GiB available host memory headroom is required.'}
        }
    }
    [pscustomobject]@{
        eligible=([string]::IsNullOrEmpty($reason));reason=$reason;root=$canonical;vmName=$VmName
        diskCapacityBytes=64GB;memoryBytes=8GB;processors=2;generation=2
        secureBootRequired=$true;virtualTpmRequired=$true
    }
}

function Test-WindowsStateProbeHost {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root,
          [Parameter(Mandatory)][string]$VmName)
    # Policy is checked before any host path lookup, preventing a D traversal.
    $dummy=@{FreeBytes=100GB;AvailableMemoryBytes=12GB;HyperVReady=$true;ExistingVm=$false;RootOccupied=$false}
    $policy=Test-WindowsStateProbePolicy -Root $Root -VmName $VmName -Facts $dummy
    if(-not $policy.eligible){return $policy}
    if(-not $IsWindows){throw 'Native host eligibility requires Windows PowerShell 7.'}
    $hostInfo=Get-VMHost -ErrorAction Stop
    $memory=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $drive=Get-PSDrive E -PSProvider FileSystem -ErrorAction Stop
    $existing=@(Get-VM -ErrorAction Stop | Where-Object {$_.Name -ieq $VmName})
    $reparse=$false
    $parent=$Root
    while($parent){
        if(Test-Path -LiteralPath $parent){
            $item=Get-Item -LiteralPath $parent -Force -ErrorAction Stop
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){$reparse=$true}
        }
        $parent=Split-Path -Parent $parent
    }
    $facts=@{
        FreeBytes=$drive.Free;AvailableMemoryBytes=([long]$memory.FreePhysicalMemory*1KB)
        HyperVReady=((Get-Service vmms -ErrorAction Stop).Status -eq 'Running')
        ExistingVm=($existing.Count -gt 0);RootOccupied=(Test-Path -LiteralPath $Root)
        RootReparse=$reparse
    }
    $result=Test-WindowsStateProbePolicy -Root $Root -VmName $VmName -Facts $facts
    $result | Add-Member -NotePropertyName freeBytes -NotePropertyValue $facts.FreeBytes
    $result | Add-Member -NotePropertyName availableMemoryBytes -NotePropertyValue $facts.AvailableMemoryBytes
    $result | Add-Member -NotePropertyName hyperVVersion -NotePropertyValue ([string](Get-VMHostSupportedVersion -ErrorAction Stop | Sort-Object Version -Descending | Select-Object -First 1).Version)
    return $result
}

function Test-WindowsStateProbeVmPath {
    param([Parameter(Mandatory)][string]$Root,
          [Parameter(Mandatory)][string]$VmName,
          [Parameter(Mandatory)][string]$VmPath)
    $base=$Root.Replace('\','/').TrimEnd('/')
    $actual=$VmPath.Replace('\','/').TrimEnd('/')
    return ($actual -ieq $base -or $actual -ieq ($base+'/'+$VmName))
}

function New-WindowsStateProbe {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root,
          [Parameter(Mandatory)][string]$VmName)
    $policy=Test-WindowsStateProbeHost -Root $Root -VmName $VmName
    if(-not $policy.eligible){throw $policy.reason}
    # Recheck at the mutation boundary; no occupied directory or VM is replaced.
    if((Test-Path -LiteralPath $Root) -or @(Get-VM -ErrorAction Stop | Where-Object {$_.Name -ieq $VmName}).Count){throw 'Probe resource became occupied.'}
    New-Item -ItemType Directory -Path $Root -ErrorAction Stop | Out-Null
    $markerPath=Join-Path $Root 'probe-owner.json'
    $owner=[ordered]@{schema=1;root=$policy.root;name=$VmName;vmId=$null;status='creating';utc=[DateTime]::UtcNow.ToString('o')}
    $owner | ConvertTo-Json | Set-Content -LiteralPath $markerPath -Encoding utf8 -ErrorAction Stop
    $vm=New-VM -Name $VmName -Generation 2 -MemoryStartupBytes $policy.memoryBytes -NoVHD -Path $Root -ErrorAction Stop
    $owner.vmId=$vm.Id.ToString();$owner.status='created'
    $owner | ConvertTo-Json | Set-Content -LiteralPath $markerPath -Encoding utf8 -ErrorAction Stop
    Set-VMProcessor -VM $vm -Count $policy.processors -ErrorAction Stop
    # This Task 1 probe is diskless. Real Windows disk/TPM setup belongs to Task 2.
    return $owner
}

function Remove-WindowsStateProbe {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root,
          [Parameter(Mandatory)][string]$VmName)
    $dummy=@{FreeBytes=100GB;AvailableMemoryBytes=12GB;HyperVReady=$true;ExistingVm=$false;RootOccupied=$false}
    $policy=Test-WindowsStateProbePolicy -Root $Root -VmName $VmName -Facts $dummy
    if(-not $policy.eligible){throw $policy.reason}
    $marker=Get-Content -LiteralPath (Join-Path $Root 'probe-owner.json') -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if($marker.schema -ne 1 -or $marker.root -cne $policy.root -or $marker.name -cne $VmName -or $marker.status -ne 'created'){throw 'Ownership marker mismatch.'}
    $id=[guid]::Parse($marker.vmId)
    $vm=Get-VM -Id $id -ErrorAction Stop
    if($vm.Name -cne $VmName -or -not (Test-WindowsStateProbeVmPath -Root $policy.root -VmName $VmName -VmPath $vm.Path)){throw 'VM identity/path mismatch; cleanup refused.'}
    # Keep files as evidence; unregister only the verified owned disposable VM.
    if($vm.State -ne 'Off'){Stop-VM -VM $vm -TurnOff -Force -ErrorAction Stop}
    Remove-VM -VM $vm -Force -ErrorAction Stop
    $marker.status='removed'
    $marker | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Root 'probe-owner.json') -Encoding utf8 -ErrorAction Stop
}
