# Native helpers. The cloud connector supplies a policy-validated plan.
# No disk initialization, formatting, filesystem repair or application migration.
function Assert-DevBoxCloudDisk {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Plan)
    if ($Plan.drive_letter -cne 'E' -or $Plan.schema_version -ne 1 -or $Plan.set_read_only -ne $true) { throw 'Invalid E read-only plan.' }
    $disk=Get-Disk -Number $Plan.disk_number -ErrorAction Stop
    if ([string]$disk.UniqueId -cne [string]$Plan.disk_unique_id) { throw 'Disk identity changed.' }
    if ($disk.IsBoot -or $disk.IsSystem) { throw 'Refusing system disk.' }
    foreach ($letter in @('C','D')) {
        $protected=@(Get-Partition -DriveLetter $letter -ErrorAction SilentlyContinue)
        if (@($protected | Where-Object { $_.DiskNumber -eq $disk.Number }).Count) { throw 'Refusing protected C:/D: disk.' }
    }
    if ([string]$disk.BusType -ne [string]$Plan.bus_type -or $disk.PartitionStyle -ne 'GPT') { throw 'Disk transport/partition identity changed.' }
    $p=Get-Partition -DiskNumber $disk.Number -PartitionNumber $Plan.partition_number -ErrorAction Stop
    if ([string]$p.Guid -ine [string]$Plan.partition_guid) { throw 'Partition identity changed.' }
    $v=@($p | Get-Volume -ErrorAction Stop)
    if ($v.Count -ne 1 -or $v[0].FileSystem -ne 'NTFS' -or [string]$v[0].UniqueId -ine [string]$Plan.volume_unique_id -or [string]$v[0].FileSystemLabel -cne [string]$Plan.volume_label) { throw 'Volume identity changed or not NTFS.' }
    return @{disk=$disk;partition=$p;volume=$v[0]}
}

function Test-DevBoxCloudEOccupied {
    return [bool]((Get-PSDrive -Name E -ErrorAction SilentlyContinue) -or (Get-Volume -DriveLetter E -ErrorAction SilentlyContinue) -or (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='E:'" -ErrorAction Stop))
}

function Assert-DevBoxCloudMarker {
    param([Parameter(Mandatory)][string]$ExpectedId)
    $root=Get-Item -LiteralPath 'E:\' -Force -ErrorAction Stop
    $item=Get-Item -LiteralPath 'E:\.devbox-cloud-volume.json' -Force -ErrorAction Stop
    if (($root.Attributes -band [IO.FileAttributes]::ReparsePoint) -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.PSIsContainer -or $item.Length -gt 8192) { throw 'Unsafe cloud marker path.' }
    $marker=Get-Content -LiteralPath $item.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    if ($marker.schema_version -ne 1 -or $marker.provider_kind -cne 'cloud-block' -or $marker.cloud_volume_id -cne $ExpectedId) { throw 'Cloud marker identity mismatch.' }
}

function Mount-DevBoxCloudCandidate {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Plan)
    if (Test-DevBoxCloudEOccupied) { throw 'E: is occupied; refusing takeover.' }
    $before=Assert-DevBoxCloudDisk -Plan $Plan
    if ($before.partition.DriveLetter -or @($before.partition.AccessPaths | Where-Object { $_ -and [string]$_ -ine [string]$Plan.volume_unique_id }).Count) { throw 'Candidate already mounted elsewhere.' }
    if ([bool]$before.disk.IsReadOnly -ne [bool]$Plan.original_read_only -or [bool]$before.disk.IsOffline -ne [bool]$Plan.original_offline) { throw 'Disk state changed before mount.' }
    $flagsChanged=$false;$mounted=$false
    try {
        Assert-DevBoxCloudDisk -Plan $Plan | Out-Null
        Set-Disk -Number $Plan.disk_number -IsReadOnly $true -ErrorAction Stop
        $flagsChanged=$true
        if ($Plan.bring_online) { Set-Disk -Number $Plan.disk_number -IsOffline $false -ErrorAction Stop }
        Assert-DevBoxCloudDisk -Plan $Plan | Out-Null
        if (Test-DevBoxCloudEOccupied) { throw 'E: became occupied before mount.' }
        Add-PartitionAccessPath -DiskNumber $Plan.disk_number -PartitionNumber $Plan.partition_number -AccessPath 'E:\' -ErrorAction Stop
        $mounted=$true
        $check=Assert-DevBoxCloudDisk -Plan $Plan
        if ($check.partition.DriveLetter -ne 'E' -or -not $check.disk.IsReadOnly) { throw 'E mount/read-only verification failed.' }
        Assert-DevBoxCloudMarker -ExpectedId $Plan.cloud_volume_id
        return @{schema_version=1;status='attached_read_only';drive_letter='E';disk_unique_id=$Plan.disk_unique_id;
            partition_guid=$Plan.partition_guid;cloud_volume_id=$Plan.cloud_volume_id;cloud_persistence_accepted=$false}
    } catch {
        $failure=$_
        try {
            $current=Assert-DevBoxCloudDisk -Plan $Plan
            if ($mounted) {
                if ($current.partition.DriveLetter -ne 'E') { throw 'Rollback refuses changed E mapping.' }
                Remove-PartitionAccessPath -DiskNumber $Plan.disk_number -PartitionNumber $Plan.partition_number -AccessPath 'E:\' -ErrorAction Stop
            }
            if ($flagsChanged) {
                Assert-DevBoxCloudDisk -Plan $Plan | Out-Null
                Set-Disk -Number $Plan.disk_number -IsReadOnly ([bool]$Plan.original_read_only) -ErrorAction Stop
                Set-Disk -Number $Plan.disk_number -IsOffline ([bool]$Plan.original_offline) -ErrorAction Stop
            }
        } catch { throw "Candidate failed and rollback is incomplete: $($_.Exception.Message). Original: $($failure.Exception.Message)" }
        throw $failure
    }
}
