$ErrorActionPreference='Stop'
function Measure-WindowsStateExportCapacity {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$VmName)
    . (Join-Path $PSScriptRoot 'windows-state-probe.ps1')
    $facts=@{FreeBytes=100GB;AvailableMemoryBytes=12GB;HyperVReady=$true;ExistingVm=$false;RootOccupied=$false}
    $policy=Test-WindowsStateProbePolicy -Root $Root -VmName $VmName -Facts $facts
    if(-not $policy.eligible){throw $policy.reason}
    $marker=Get-Content -LiteralPath (Join-Path $Root 'probe-owner.json') -Raw -ErrorAction Stop | ConvertFrom-Json
    if($marker.schema -ne 1 -or $marker.root -cne $policy.root -or $marker.name -cne $VmName -or $marker.status -cne 'created'){throw 'Capacity export ownership marker mismatch.'}
    if(-not $IsWindows){throw 'Capacity export requires native Windows PowerShell 7.'}
    $ancestor=$Root
    while($ancestor){
        $item=Get-Item -LiteralPath $ancestor -ErrorAction Stop
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Capacity export reparse ancestry refused.'}
        $ancestor=if($item.Parent){$item.Parent.FullName}else{$null}
    }
    $vm=Get-VM -Id ([guid]::Parse($marker.vmId)) -ErrorAction Stop
    if($vm.Name -cne $VmName -or $vm.State -ne 'Off' -or -not (Test-WindowsStateProbeVmPath -Root $Root -VmName $VmName -VmPath $vm.Path)){throw 'Capacity export VM identity/off state mismatch.'}
    $drives=@(Get-VMHardDiskDrive -VM $vm -ErrorAction Stop)
    $expected=[IO.Path]::GetFullPath((Join-Path $Root 'windows-home.vhdx'))
    if($drives.Count -ne 1 -or [IO.Path]::GetFullPath($drives[0].Path) -ine $expected){throw 'Capacity export requires exactly the owned guest disk.'}
    $vhd=Get-VHD -Path $expected -ErrorAction Stop
    if($vhd.VhdType -ne 'Dynamic' -or $vhd.Size -ne 64GB -or $vhd.ParentPath -or $vhd.Attached){throw 'Capacity export disk must be standalone and detached.'}
    $export=Join-Path $Root 'capacity-export';$repo=Join-Path $Root 'capacity-restic';$archive=Join-Path $Root 'capacity-encrypted.zip';$tools=Join-Path $Root 'capacity-tools'
    foreach($path in @($export,$repo,$archive,$tools)){if(Test-Path -LiteralPath $path){throw 'Capacity measurement refuses existing output.'}}
    if((Get-PSDrive E).Free -lt ($vhd.FileSize*2+16GB)){throw 'Capacity export/packing free-space headroom insufficient.'}
    New-Item -ItemType Directory -Path $export | Out-Null
    Export-VM -VM $vm -Path $export -ErrorAction Stop
    $files=@(Get-ChildItem -LiteralPath $export -File -Recurse)
    if(-not ($files | Where-Object {$_.Extension -eq '.vhdx'}) -or -not ($files | Where-Object {$_.Extension -eq '.vmcx'})){throw 'Whole guest export disk/configuration missing.'}
    foreach($file in $files){if($file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Export reparse file refused.'}}
    & (Join-Path $PSScriptRoot 'install-restic.ps1') -ToolsRoot $tools | Out-Null
    $restic=Join-Path $tools 'restic.exe'
    if(-not (Test-Path -LiteralPath $restic)){throw 'Pinned capacity Restic unavailable.'}
    $previousPassword=$env:RESTIC_PASSWORD
    try {
        $password=[Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
        Write-Host ('::add-mask::'+$password)
        $env:RESTIC_PASSWORD=$password
        & $restic --repo $repo init | ForEach-Object {Write-Host $_}
        if($LASTEXITCODE -ne 0){throw 'Capacity encrypted repository initialization failed.'}
        $raw=& $restic --repo $repo backup $export --compression max --json
        if($LASTEXITCODE -ne 0){throw 'Whole guest encrypted backup failed.'}
        $summary=@($raw | ForEach-Object {$_ | ConvertFrom-Json} | Where-Object {$_.message_type -eq 'summary'})
        if($summary.Count -ne 1 -or -not $summary[0].snapshot_id){throw 'Whole guest backup snapshot receipt missing.'}
        & $restic --repo $repo check --read-data | ForEach-Object {Write-Host $_}
        if($LASTEXITCODE -ne 0){throw 'Whole guest encrypted data check failed.'}
        [IO.Compression.ZipFile]::CreateFromDirectory($repo,$archive,[IO.Compression.CompressionLevel]::NoCompression,$false)
        $bytes=(Get-Item -LiteralPath $archive).Length
        $repositoryBytes=(Get-ChildItem -LiteralPath $repo -File -Recurse | Measure-Object -Property Length -Sum).Sum
        $fits=$bytes -le 8GB -and $repositoryBytes -le 8GB
        if($fits){
            & python -c "import sys;sys.path.insert(0,sys.argv[1]);from cloud_checkpoint import archive_check;archive_check(sys.argv[2]);print('EXISTING 8GiB ARCHIVE STRUCTURE GUARD: PASS')" $PSScriptRoot $archive
            if($LASTEXITCODE -ne 0){throw 'Existing bounded archive verifier refused whole guest repository.'}
        }
        [pscustomobject]@{vmId=$vm.Id.ToString();exportBytes=($files|Measure-Object Length -Sum).Sum;encryptedRepositoryBytes=$repositoryBytes;archiveBytes=$bytes;maxBytes=8GB;fitsExistingTransport=$fits;snapshotId=$summary[0].snapshot_id;wholeExport=$true;published=$false}
    } finally {$env:RESTIC_PASSWORD=$previousPassword}
}
