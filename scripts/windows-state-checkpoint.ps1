$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'windows-state-probe.ps1')

function Get-WindowsStateCheckpointOwner {
    param([string]$Root,[guid]$VmId,[switch]$AllowMissingVm)
    $canonical=$Root.Replace('\','/')
    $match=[regex]::Match($canonical,'^E:/DevBox/Tools/WindowsStateProbe/probe-([0-9]+)-([0-9]+)$',[Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if(-not $match.Success){throw 'Only an exact owned E probe directory is allowed.'}
    $name='DevBoxWindowsState-'+$match.Groups[1].Value+'-'+$match.Groups[2].Value
    $ancestor=$Root
    while($ancestor){
        $item=Get-Item -LiteralPath $ancestor -ErrorAction Stop
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Checkpoint owner reparse ancestry refused.'}
        $ancestor=if($item.Parent){$item.Parent.FullName}else{$null}
    }
    $markerPath=Join-Path $Root 'probe-owner.json'
    if((Get-Item -LiteralPath $markerPath).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Checkpoint owner marker link refused.'}
    $marker=Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
    if($marker.schema -ne 1 -or $marker.root -cne $canonical -or $marker.name -cne $name -or $marker.status -cne 'created' -or [guid]::Parse($marker.vmId) -ne $VmId -or $VmId -eq [guid]::Empty){throw 'Checkpoint ownership marker mismatch.'}
    if(-not $IsWindows){throw 'Checkpoint requires native Windows PowerShell 7.'}
    $vm=Get-VM -Id $VmId -ErrorAction SilentlyContinue
    if($vm){
        if($vm.Name -cne $name -or -not (Test-WindowsStateProbeVmPath -Root $Root -VmName $name -VmPath $vm.Path)){throw 'Checkpoint VM identity/path mismatch.'}
    } elseif(-not $AllowMissingVm){throw 'Owned checkpoint VM missing.'}
    [pscustomobject]@{root=$Root;vmId=$VmId;name=$name;vm=$vm}
}

function Assert-WindowsStateOwnedPath {
    param([string]$Root,[string]$Path)
    $base=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    $full=[IO.Path]::GetFullPath($Path)
    # Hyper-V resolves SUBST E: to its D: backing path. Accept only the verified live E: alias.
    $substLine=(& cmd.exe /c subst 2>$null | Where-Object {$_ -match '^E:'} | Select-Object -First 1)
    if($base.StartsWith('E:\',[StringComparison]::OrdinalIgnoreCase) -and $substLine -match '^E:\\: => (.+)$'){
        $physical=$Matches[1].TrimEnd('\')+'\'
        if($full.StartsWith($physical,[StringComparison]::OrdinalIgnoreCase)){
            $full='E:\'+$full.Substring($physical.Length)
        }
    }
    if(-not $full.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Checkpoint path escaped owned root.'}
    $ancestor=$full
    while($ancestor -and $ancestor.Length -ge $base.Length){
        if(Test-Path -LiteralPath $ancestor){
            $item=Get-Item -LiteralPath $ancestor -ErrorAction Stop
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Checkpoint path reparse point refused.'}
        }
        $ancestor=Split-Path -Path $ancestor -Parent
    }
    $full
}

function Get-WindowsStateExportDiskMetadata {
    param([string]$ExportPath)
    $base=[IO.Path]::GetFullPath($ExportPath).TrimEnd('\','/')
    $diskFiles=@(Get-ChildItem -LiteralPath $base -File -Recurse | Where-Object {$_.Extension -in @('.vhdx','.avhdx')})
    if(-not $diskFiles.Count){throw 'Export disk files missing.'}
    foreach($file in $diskFiles){
        $path=Assert-WindowsStateOwnedPath -Root $base -Path $file.FullName
        $vhd=Get-VHD -Path $path -ErrorAction Stop
        $parent=$null
        if($vhd.ParentPath){
            $parentFull=Assert-WindowsStateOwnedPath -Root $base -Path $vhd.ParentPath
            if(-not (Test-Path -LiteralPath $parentFull -PathType Leaf)){throw 'Export differencing parent missing.'}
            $parent=$parentFull.Substring($base.Length+1).Replace('\','/')
        }
        [pscustomobject]@{path=$path.Substring($base.Length+1).Replace('\','/');parent=$parent;capacity_bytes=[long]$vhd.Size;type=$vhd.VhdType.ToString()}
    }
}

function Export-WindowsStateCheckpoint {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][guid]$VmId,[Parameter(Mandatory)][ValidateSet('save','finish')][string]$Mode)
    $Mode=$Mode.ToLowerInvariant()
    $owner=Get-WindowsStateCheckpointOwner -Root $Root -VmId $VmId
    $vm=$owner.vm
    if($vm.State -ne 'Running'){throw 'New Save/Finish receipt requires an owned running guest.'}
    $drives=@(Get-VMHardDiskDrive -VM $vm -ErrorAction Stop)
    if($drives.Count -ne 1){throw 'Checkpoint requires one owned guest disk chain.'}
    $cursor=$drives[0].Path;$seen=@{};$diskBytes=0L
    while($cursor){
        $cursor=Assert-WindowsStateOwnedPath -Root $Root -Path $cursor
        if($seen.ContainsKey($cursor.ToLowerInvariant())){throw 'Source differencing parent cycle refused.'}
        $seen[$cursor.ToLowerInvariant()]=$true
        $vhd=Get-VHD -Path $cursor -ErrorAction Stop
        if($vhd.Size -ne 64GB -or $vhd.VhdType -notin @('Dynamic','Differencing')){throw 'Source disk capacity/type mismatch.'}
        $diskBytes+=$vhd.FileSize;$cursor=$vhd.ParentPath
    }
    if((Get-PSDrive E).Free -lt ($diskBytes+2GB)){throw 'Checkpoint export free space insufficient.'}
    $generation=$Mode+'-'+[guid]::NewGuid().ToString('N')
    $directory=Assert-WindowsStateOwnedPath -Root $Root -Path (Join-Path $Root ('checkpoints/'+$generation))
    if(Test-Path -LiteralPath $directory){throw 'Immutable checkpoint generation already exists.'}
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $payload=Join-Path $directory 'payload';New-Item -ItemType Directory -Path $payload | Out-Null
    $snapshot=$null;$oldType=$vm.CheckpointType
    try {
        if($Mode -eq 'save'){
            Set-VM -VM $vm -CheckpointType ProductionOnly -ErrorAction Stop
            if((Get-VM -Id $VmId).CheckpointType -ne 'ProductionOnly'){throw 'Production-only checkpoint configuration refused.'}
            Export-VM -VM $vm -Path $payload -CaptureLiveState CaptureDataConsistentState -ErrorAction Stop | Out-Null
            $state='Running';$production=$true;$shutdown=$false;$checkpointId=$null
        } else {
            Stop-VM -VM $vm -ErrorAction Stop
            $deadline=[DateTime]::UtcNow.AddMinutes(2)
            while((Get-VM -Id $VmId).State -ne 'Off' -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Seconds 5}
            if((Get-VM -Id $VmId).State -ne 'Off'){throw 'Guest clean shutdown did not complete; Finish refused.'}
            Export-VM -VM (Get-VM -Id $VmId) -Path $payload -ErrorAction Stop | Out-Null
            $state='Off';$production=$false;$shutdown=$true;$checkpointId=$null
        }
        $disks=@(Get-WindowsStateExportDiskMetadata -ExportPath $payload)
        $metadata=[ordered]@{vm_id=$VmId.ToString();vm_name=$owner.name;configuration_version=$vm.Version.ToString();mode=$Mode;state=$state;production_only=$production;checkpoint_id=$checkpointId;shutdown_verified=$shutdown;capture_state=$(if($Mode -eq 'save'){'CaptureDataConsistentState'}else{$null});disks=$disks;generation=$generation}
        $metadataPath=Join-Path $directory 'metadata.json';$manifest=Join-Path $directory 'manifest.json'
        $metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $metadataPath -Encoding utf8
        & python (Join-Path $PSScriptRoot 'windows_state_manifest.py') create --root $payload --metadata $metadataPath --manifest $manifest | ForEach-Object {Write-Host $_}
        if($LASTEXITCODE -ne 0){throw 'Whole checkpoint manifest verification failed; no accepted receipt.'}
        [pscustomobject]@{vmId=$VmId.ToString();mode=$Mode;generation=$generation;exportPath=$payload;manifestPath=$manifest;exportVerified=$true;published=$false}
    } finally {
        if($snapshot){Remove-VMSnapshot -VMSnapshot $snapshot -Confirm:$false -ErrorAction Stop}
        Set-VM -VM (Get-VM -Id $VmId) -CheckpointType $oldType -ErrorAction Stop
    }
}

function Import-WindowsStateCheckpoint {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][guid]$VmId,[Parameter(Mandatory)][string]$ExportPath,[Parameter(Mandatory)][string]$ManifestPath,[ValidateSet('restored','restored-save','restored-finish')][string]$DestinationLabel='restored')
    $owner=Get-WindowsStateCheckpointOwner -Root $Root -VmId $VmId -AllowMissingVm
    if($owner.vm){throw 'Existing owned VM registration must be preserved until export is verified and deliberately unregistered.'}
    $payload=Assert-WindowsStateOwnedPath -Root $Root -Path $ExportPath
    $manifest=Assert-WindowsStateOwnedPath -Root $Root -Path $ManifestPath
    if((Split-Path $payload -Leaf) -cne 'payload' -or (Split-Path $manifest -Leaf) -cne 'manifest.json' -or (Split-Path $payload -Parent) -ine (Split-Path $manifest -Parent)){throw 'Checkpoint payload/manifest generation scope mismatch.'}
    $versions=@(Get-VMHostSupportedVersion -ErrorAction Stop | ForEach-Object {$_.Version.ToString()})
    $verification=Join-Path (Split-Path $manifest -Parent) 'import-verification.json'
    if(Test-Path -LiteralPath $verification){throw 'Existing import verification state refused.'}
    @{vm_id=$VmId.ToString();supported_versions=$versions} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $verification -Encoding utf8
    try {
        & python (Join-Path $PSScriptRoot 'windows_state_manifest.py') verify --root $payload --metadata $verification --manifest $manifest | ForEach-Object {Write-Host $_}
        if($LASTEXITCODE -ne 0){throw 'Checkpoint file/identity/parent/configuration verification refused import.'}
        $record=Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
        if($record.generation -cne (Split-Path (Split-Path $manifest -Parent) -Leaf)){throw 'Checkpoint generation and directory identity mismatch.'}
        $actualDisks=@(Get-WindowsStateExportDiskMetadata -ExportPath $payload)
        if(($actualDisks | ConvertTo-Json -Depth 5 -Compress) -cne ($record.disks | ConvertTo-Json -Depth 5 -Compress)){throw 'Native VHD disk/parent metadata differs from manifest.'}
        $config=Assert-WindowsStateOwnedPath -Root $payload -Path (Join-Path $payload $record.config)
        $vmPath=Assert-WindowsStateOwnedPath -Root $Root -Path (Join-Path $Root $owner.name)
        $diskPath=Assert-WindowsStateOwnedPath -Root $Root -Path (Join-Path $Root ($DestinationLabel+'-disks'))
        $snapshotPath=Assert-WindowsStateOwnedPath -Root $Root -Path (Join-Path $Root ($DestinationLabel+'-snapshots'))
        foreach($destination in @($diskPath,$snapshotPath)){if(Test-Path -LiteralPath $destination){throw 'Import destination must not replace existing files.'}}
        $required=($record.files | Measure-Object -Property bytes -Sum).Sum
        if((Get-PSDrive E).Free -lt ($required+2GB)){throw 'Import free space insufficient.'}
        $sourceDirectories=@($record.disks | ForEach-Object {Split-Path (Join-Path $payload $_.path) -Parent} | Sort-Object -Unique)
        if($sourceDirectories.Count -ne 1){throw 'Export disk layout requires explicit supported source directory.'}
        $report=Compare-VM -Path $config -Copy -VhdSourcePath $sourceDirectories[0] -VirtualMachinePath $vmPath -VhdDestinationPath $diskPath -SnapshotFilePath $snapshotPath -ErrorAction Stop
        $issues=@($report.Incompatibilities | Where-Object {$_})
        if($issues.Count -or $report.VM.Id -ne $VmId -or $report.VM.Name -cne $owner.name -or $report.VM.Version.ToString() -cne $record.configuration_version){throw 'Hyper-V compatibility or preserved identity check refused import.'}
        $vm=Import-VM -CompatibilityReport $report -ErrorAction Stop
        if($vm.Id -ne $VmId -or $vm.Name -cne $owner.name -or -not (Test-WindowsStateProbeVmPath -Root $Root -VmName $owner.name -VmPath $vm.Path)){throw 'Imported VM identity/path did not match verified export.'}
        $importedDrives=@(Get-VMHardDiskDrive -VM $vm -ErrorAction Stop)
        if($importedDrives.Count -ne 1){throw 'Imported guest disk attachment mismatch.'}
        $cursor=$importedDrives[0].Path;$seen=@{}
        while($cursor){
            $cursor=Assert-WindowsStateOwnedPath -Root $diskPath -Path $cursor
            if($seen.ContainsKey($cursor.ToLowerInvariant())){throw 'Imported disk parent cycle refused.'}
            $seen[$cursor.ToLowerInvariant()]=$true
            $disk=Get-VHD -Path $cursor -ErrorAction Stop
            if($disk.Size -ne 64GB -or $disk.VhdType -notin @('Dynamic','Differencing')){throw 'Imported disk metadata mismatch.'}
            $cursor=$disk.ParentPath
        }
        $vm
    } finally {if(Test-Path -LiteralPath $verification){Remove-Item -LiteralPath $verification -Force}}
}
