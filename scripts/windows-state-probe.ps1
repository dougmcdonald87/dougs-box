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

function Test-WindowsStateGuestDiskPolicy {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root,
          [Parameter(Mandatory)][string]$VmName,
          [Parameter(Mandatory)][hashtable]$Facts)
    $dummy=@{FreeBytes=100GB;AvailableMemoryBytes=12GB;HyperVReady=$true;ExistingVm=$false;RootOccupied=$false}
    $policy=Test-WindowsStateProbePolicy -Root $Root -VmName $VmName -Facts $dummy
    $reason=$policy.reason
    if(-not $reason){
        foreach($key in @('MarkerSchema','MarkerRoot','MarkerName','MarkerId','MarkerStatus','VmId','VmName','VmPath','State','Generation','DiskCount','DiskExists','RootReparse','FreeBytes')){
            if(-not $Facts.ContainsKey($key)){$reason='Guest disk observations incomplete.';break}
        }
    }
    if(-not $reason){
        $ownerId=[guid]::Empty;$actualId=[guid]::Empty
        if($Facts.MarkerSchema -ne 1 -or $Facts.MarkerRoot -cne $policy.root -or $Facts.MarkerName -cne $VmName -or $Facts.MarkerStatus -cne 'created'){$reason='Guest disk ownership marker mismatch.'}
        elseif(-not [guid]::TryParse([string]$Facts.MarkerId,[ref]$ownerId) -or -not [guid]::TryParse([string]$Facts.VmId,[ref]$actualId) -or $ownerId -eq [guid]::Empty -or $ownerId -ne $actualId){$reason='Guest disk VM identity mismatch.'}
        elseif($Facts.VmName -cne $VmName -or -not (Test-WindowsStateProbeVmPath -Root $policy.root -VmName $VmName -VmPath $Facts.VmPath)){$reason='Guest disk VM name/path mismatch.'}
        elseif($Facts.State -cne 'Off' -or $Facts.Generation -ne 2){$reason='Guest disk requires an off Generation 2 VM.'}
        elseif($Facts.DiskCount -ne 0 -or $Facts.DiskExists -isnot [bool] -or $Facts.DiskExists){$reason='Existing guest disk must not be replaced.'}
        elseif($Facts.RootReparse -isnot [bool] -or $Facts.RootReparse){$reason='Guest disk reparse ancestry refused.'}
        elseif($Facts.FreeBytes -isnot [ValueType] -or $Facts.FreeBytes -lt 80GB){$reason='Guest disk requires 80 GiB free E space.'}
    }
    [pscustomobject]@{eligible=([string]::IsNullOrEmpty($reason));reason=$reason;diskPath=($policy.root+'/windows-home.vhdx');diskCapacityBytes=64GB}
}

function Test-WindowsStateInstallDiskPolicy {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root,
          [Parameter(Mandatory)][hashtable]$Facts)
    $canonical=$Root.Replace('\','/')
    $match=[regex]::Match($canonical,'^E:/DevBox/Tools/WindowsStateProbe/probe-([0-9]+)-([0-9]+)$',[Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $reason='';$number=$null
    if(-not $match.Success){$reason='Installation requires an exact owned E probe root.'}
    else {
        foreach($key in @('ExpectedPath','ActualPath','VhdType','CapacityBytes','DiskNumber','ResolvedDiskNumber','BusType','PartitionStyle','IsBoot','IsSystem','PartitionCount','Mounted')){
            if(-not $Facts.ContainsKey($key)){$reason='Installation disk observations incomplete.';break}
        }
    }
    if(-not $reason){
        $expected=$canonical+'/windows-home.vhdx'
        if(([string]$Facts.ExpectedPath).Replace('\','/') -ine $expected -or ([string]$Facts.ActualPath).Replace('\','/') -ine $expected){$reason='Installation disk path is not the owned VHDX.'}
        elseif($Facts.VhdType -cne 'Dynamic' -or $Facts.CapacityBytes -ne 64GB){$reason='Installation disk type/capacity mismatch.'}
        elseif(($Facts.DiskNumber -isnot [int] -and $Facts.DiskNumber -isnot [uint32]) -or $Facts.DiskNumber -le 0 -or $Facts.ResolvedDiskNumber -ne $Facts.DiskNumber){$reason='Installation disk number mismatch or host disk zero.'}
        elseif($Facts.BusType -cne 'FileBackedVirtual' -or $Facts.PartitionStyle -cne 'RAW' -or $Facts.PartitionCount -ne 0){$reason='Installation requires an empty file-backed virtual disk.'}
        elseif($Facts.IsBoot -isnot [bool] -or $Facts.IsSystem -isnot [bool] -or $Facts.Mounted -isnot [bool] -or $Facts.IsBoot -or $Facts.IsSystem -or -not $Facts.Mounted){$reason='Host boot/system or unmounted disk refused.'}
        else {$number=$Facts.DiskNumber}
    }
    [pscustomobject]@{eligible=([string]::IsNullOrEmpty($reason));reason=$reason;diskNumber=$number}
}

function Install-WindowsStateHomeImage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root,
          [Parameter(Mandatory)][string]$VmName,
          [Parameter(Mandatory)][string]$Sha256)
    $dummy=@{FreeBytes=100GB;AvailableMemoryBytes=12GB;HyperVReady=$true;ExistingVm=$false;RootOccupied=$false}
    $base=Test-WindowsStateProbePolicy -Root $Root -VmName $VmName -Facts $dummy
    if(-not $base.eligible){throw $base.reason}
    $marker=Get-Content -LiteralPath (Join-Path $Root 'probe-owner.json') -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if($marker.schema -ne 1 -or $marker.root -cne $base.root -or $marker.name -cne $VmName -or $marker.status -cne 'created'){throw 'Installation ownership marker mismatch.'}
    if(-not $IsWindows){throw 'Installation requires native Windows PowerShell 7.'}
    if($Sha256 -notmatch '^[0-9a-fA-F]{64}$'){throw 'Installation requires a published SHA256.'}
    $vm=Get-VM -Id ([guid]::Parse($marker.vmId)) -ErrorAction Stop
    if($vm.Name -cne $VmName -or $vm.State -ne 'Off' -or $vm.Generation -ne 2 -or -not (Test-WindowsStateProbeVmPath -Root $base.root -VmName $VmName -VmPath $vm.Path)){throw 'Installation VM identity/state mismatch.'}
    $ancestor=$Root
    while($ancestor){
        if(Test-Path -LiteralPath $ancestor){if(((Get-Item -LiteralPath $ancestor -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Installation reparse ancestry refused.'}}
        $ancestor=Split-Path -Parent $ancestor
    }
    $diskPath=$base.root+'/windows-home.vhdx';$isoPath=$base.root+'/media/windows-home.iso'
    foreach($path in @($diskPath,$isoPath)){if(((Get-Item -LiteralPath $path -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Installation reparse file refused.'}}
    if((Get-FileHash -LiteralPath $isoPath -Algorithm SHA256).Hash -ine $Sha256){throw 'Installation media hash mismatch.'}
    $drives=@(Get-VMHardDiskDrive -VM $vm -ErrorAction Stop)
    if($drives.Count -ne 1 -or $drives[0].Path.Replace('\','/') -ine $diskPath){throw 'Installation disk attachment mismatch.'}
    $vhd=Get-VHD -Path $diskPath -ErrorAction Stop
    if($vhd.Attached -or $vhd.ParentPath -or $vhd.VhdType.ToString() -ne 'Dynamic' -or $vhd.Size -ne 64GB){throw 'Installation disk must be an unmounted standalone 64 GiB dynamic VHDX.'}
    $iso=$null;$mounted=$null
    try {
        $iso=Mount-DiskImage -ImagePath $isoPath -Access ReadOnly -PassThru -ErrorAction Stop
        $volume=$iso | Get-Volume -ErrorAction Stop
        if(@($volume).Count -ne 1 -or -not $volume.DriveLetter){throw 'Installation ISO volume ambiguous.'}
        $wim=([string]$volume.DriveLetter)+':\sources\install.wim'
        $homeImages=@(Get-WindowsImage -ImagePath $wim -ErrorAction Stop | Where-Object {$_.ImageName -ceq 'Windows 10 Home'})
        if($homeImages.Count -ne 1){throw 'Installation requires exactly one Windows 10 Home image.'}
        $detail=Get-WindowsImage -ImagePath $wim -Index $homeImages[0].ImageIndex -ErrorAction Stop
        if($detail.EditionId -cne 'Core'){throw 'Installation image is not Home/Core.'}
        $mounted=Mount-VHD -Path $diskPath -PassThru -ErrorAction Stop
        $disk=Get-Disk -Number $mounted.DiskNumber -ErrorAction Stop
        $resolved=Get-VHD -Path $diskPath -ErrorAction Stop
        $facts=@{ExpectedPath=$diskPath;ActualPath=$resolved.Path;VhdType=$resolved.VhdType.ToString();CapacityBytes=$resolved.Size;DiskNumber=$disk.Number;ResolvedDiskNumber=$resolved.DiskNumber;BusType=$disk.BusType.ToString();PartitionStyle=$disk.PartitionStyle.ToString();IsBoot=$disk.IsBoot;IsSystem=$disk.IsSystem;PartitionCount=$disk.NumberOfPartitions;Mounted=$resolved.Attached}
        $policy=Test-WindowsStateInstallDiskPolicy -Root $Root -Facts $facts
        if(-not $policy.eligible){throw $policy.reason}
        # Only the positively identified new, empty virtual disk may be initialized.
        Initialize-Disk -Number $policy.diskNumber -PartitionStyle GPT -ErrorAction Stop | Out-Null
        $efi=New-Partition -DiskNumber $policy.diskNumber -Size 260MB -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' -AssignDriveLetter -ErrorAction Stop
        New-Partition -DiskNumber $policy.diskNumber -Size 16MB -GptType '{e3c9e316-0b5c-4db8-817d-f92df00215ae}' -ErrorAction Stop | Out-Null
        $free=(Get-Disk -Number $policy.diskNumber -ErrorAction Stop).LargestFreeExtent
        $windows=New-Partition -DiskNumber $policy.diskNumber -Size ($free-1GB) -AssignDriveLetter -ErrorAction Stop
        $recovery=New-Partition -DiskNumber $policy.diskNumber -UseMaximumSize -GptType '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}' -ErrorAction Stop
        if(-not $efi.DriveLetter -or -not $windows.DriveLetter){throw 'Installation temporary drive letters missing.'}
        foreach($part in @($efi,$windows,$recovery)){if($part.DiskNumber -ne $policy.diskNumber -or $part.DriveLetter -in @('C','D','E')){throw 'Installation partition identity/letter mismatch.'}}
        Format-Volume -Partition $efi -FileSystem FAT32 -NewFileSystemLabel ProbeEFI -Force -Confirm:$false -ErrorAction Stop | Out-Null
        Format-Volume -Partition $windows -FileSystem NTFS -NewFileSystemLabel ProbeWindows -Force -Confirm:$false -ErrorAction Stop | Out-Null
        Format-Volume -Partition $recovery -FileSystem NTFS -NewFileSystemLabel ProbeRecovery -Force -Confirm:$false -ErrorAction Stop | Out-Null
        $target=([string]$windows.DriveLetter)+':\';$system=([string]$efi.DriveLetter)+':\'
        & dism.exe /English /Apply-Image ('/ImageFile:'+$wim) ('/Index:'+$detail.ImageIndex) ('/ApplyDir:'+$target) /CheckIntegrity | ForEach-Object {Write-Host $_}
        if($LASTEXITCODE -ne 0){throw ('Windows image application failed: '+$LASTEXITCODE)}
        & bcdboot.exe ($target+'Windows') /s $system /f UEFI | ForEach-Object {Write-Host $_}
        if($LASTEXITCODE -ne 0){throw ('Guest boot-file creation failed: '+$LASTEXITCODE)}
        if(-not (Test-Path -LiteralPath ($target+'Windows\System32\ntoskrnl.exe')) -or -not (Test-Path -LiteralPath ($system+'EFI\Microsoft\Boot\BCD'))){throw 'Applied guest Windows or EFI boot files missing.'}
        Set-VMFirmware -VM $vm -FirstBootDevice $drives[0] -ErrorAction Stop
        [pscustomobject]@{vmId=$vm.Id.ToString();diskPath=$diskPath;edition=$detail.EditionId;imageName=$detail.ImageName;version=[string]$detail.Version;status='image-applied-boot-unverified';oobePending=$true}
    } finally {
        try {if($mounted){Dismount-VHD -Path $diskPath -ErrorAction Stop}}
        finally {if($iso){Dismount-DiskImage -ImagePath $isoPath -ErrorAction Stop | Out-Null}}
    }
}

function New-WindowsStateGuestDisk {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root,
          [Parameter(Mandatory)][string]$VmName)
    $dummy=@{FreeBytes=100GB;AvailableMemoryBytes=12GB;HyperVReady=$true;ExistingVm=$false;RootOccupied=$false}
    $base=Test-WindowsStateProbePolicy -Root $Root -VmName $VmName -Facts $dummy
    if(-not $base.eligible){throw $base.reason}
    $marker=Get-Content -LiteralPath (Join-Path $Root 'probe-owner.json') -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if($marker.schema -ne 1 -or $marker.root -cne $base.root -or $marker.name -cne $VmName -or $marker.status -cne 'created'){throw 'Guest disk ownership marker mismatch.'}
    if(-not $IsWindows){throw 'Guest disk creation requires native Windows PowerShell 7.'}
    $vm=Get-VM -Id ([guid]::Parse($marker.vmId)) -ErrorAction Stop
    $reparse=$false;$ancestor=$Root
    while($ancestor){
        if(Test-Path -LiteralPath $ancestor){
            if(((Get-Item -LiteralPath $ancestor -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){$reparse=$true}
        }
        $ancestor=Split-Path -Parent $ancestor
    }
    $diskPath=$base.root+'/windows-home.vhdx'
    $facts=@{MarkerSchema=$marker.schema;MarkerRoot=$marker.root;MarkerName=$marker.name;MarkerId=$marker.vmId;MarkerStatus=$marker.status;VmId=$vm.Id.ToString();VmName=$vm.Name;VmPath=$vm.Path;State=$vm.State.ToString();Generation=$vm.Generation;DiskCount=@(Get-VMHardDiskDrive -VM $vm -ErrorAction Stop).Count;DiskExists=(Test-Path -LiteralPath $diskPath);RootReparse=$reparse;FreeBytes=(Get-PSDrive E -PSProvider FileSystem -ErrorAction Stop).Free}
    $policy=Test-WindowsStateGuestDiskPolicy -Root $Root -VmName $VmName -Facts $facts
    if(-not $policy.eligible){throw $policy.reason}
    # Never mount or format a host disk. New-VHD refuses an existing destination.
    $disk=New-VHD -Path $policy.diskPath -SizeBytes $policy.diskCapacityBytes -Dynamic -ErrorAction Stop
    if($disk.VhdType.ToString() -ne 'Dynamic' -or $disk.Size -ne 64GB){throw 'New guest disk verification failed; preserve it for diagnosis.'}
    Add-VMHardDiskDrive -VM $vm -Path $policy.diskPath -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 0 -ErrorAction Stop
    Set-VMFirmware -VM $vm -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows -ErrorAction Stop
    $attached=@(Get-VMHardDiskDrive -VM $vm -ErrorAction Stop)
    if($attached.Count -ne 1 -or $attached[0].Path.Replace('\','/') -ine $policy.diskPath){throw 'Guest disk attachment mismatch.'}
    [pscustomobject]@{vmId=$vm.Id.ToString();diskPath=$policy.diskPath;capacityBytes=$disk.Size;fileBytes=$disk.FileSize;type=$disk.VhdType.ToString();secureBoot=(Get-VMFirmware -VM $vm -ErrorAction Stop).SecureBoot.ToString()}
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
