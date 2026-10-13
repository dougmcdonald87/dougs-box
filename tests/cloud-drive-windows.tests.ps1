$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_ACTIONS -ne 'true' -or -not $env:RUNNER_TEMP) { throw 'Disposable GitHub test runner only; never a live DevBox.' }
if (-not (Test-Path (Join-Path $PSScriptRoot '../scripts/cloud-drive-windows.ps1'))) { throw 'CLOUD E FEATURE NOT IMPLEMENTED: Windows mount helper is missing.' }
. (Join-Path $PSScriptRoot '../scripts/cloud-drive-windows.ps1')
$connector=Join-Path $PSScriptRoot '../scripts/connect-cloud-drive.ps1'
if (-not (Test-Path $connector)) { throw 'CLOUD E CONNECTOR NOT IMPLEMENTED: prerequisite inventory and connection guard missing.' }
& pwsh -NoProfile -File $connector -ConfigPath (Join-Path $PSScriptRoot '../config/cloud-drive.example.json') 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) { throw 'Unconfigured target accepted by actual connector.' }
$inspection=(& pwsh -NoProfile -File $connector -InspectOnly | Out-String) | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $inspection.status -ne 'inspection_only' -or $inspection.disk_mutations -ne 0) { throw 'Prerequisite inventory failed or claimed mutation.' }

function Assert-Refused([scriptblock]$Action,[string]$Pattern) {
    $caught=$false
    try { & $Action | Out-Null } catch { if ($_.Exception.Message -notmatch $Pattern) { throw };$caught=$true }
    if (-not $caught) { throw "Expected refusal: $Pattern" }
}
if (Get-PSDrive -Name E -ErrorAction SilentlyContinue) { throw 'E already occupied on disposable runner; test never takes it over.' }
$dir=Join-Path $env:RUNNER_TEMP ('cloud-e-fixture-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $dir | Out-Null
$file=Join-Path $dir 'owned-test.vhdx'
$dp=Join-Path $dir 'create.txt'
$detach=Join-Path $dir 'detach.txt'
$disk=$null;$partition=$null
try {
    @("create vdisk file=`"$file`" maximum=64 type=expandable", "select vdisk file=`"$file`"",'attach vdisk','exit') | Set-Content -LiteralPath $dp
    & diskpart.exe /s $dp
    if ($LASTEXITCODE -ne 0) { throw 'Disposable disk creation failed.' }
    $image=Get-DiskImage -ImagePath $file -ErrorAction Stop
    $disk=$image | Get-Disk
    if (-not $image.Attached -or $disk.IsBoot -or $disk.IsSystem -or $disk.PartitionStyle -ne 'RAW') { throw 'Fixture identity guard failed.' }
    # These operations exist ONLY in this guarded test, on the exact newly created image.
    $disk | Initialize-Disk -PartitionStyle GPT | Out-Null
    $partition=New-Partition -DiskNumber $disk.Number -UseMaximumSize
    $partition | Format-Volume -FileSystem NTFS -NewFileSystemLabel 'CLOUD_E_CI' -Confirm:$false | Out-Null
    Add-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $partition.PartitionNumber -AccessPath 'E:\'
    @{schema_version=1;cloud_volume_id='ci-disposable-volume';provider_kind='cloud-block'} | ConvertTo-Json | Set-Content -LiteralPath 'E:\.devbox-cloud-volume.json'
    Remove-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $partition.PartitionNumber -AccessPath 'E:\'
    $disk=Get-Disk -Number $disk.Number;$partition=Get-Partition -DiskNumber $disk.Number -PartitionNumber $partition.PartitionNumber
    $volume=$partition | Get-Volume
    $plan=@{schema_version=1;drive_letter='E';disk_number=[int]$disk.Number;partition_number=[int]$partition.PartitionNumber;
        disk_unique_id=[string]$disk.UniqueId;partition_guid=[string]$partition.Guid;volume_unique_id=[string]$volume.UniqueId;
        volume_label='CLOUD_E_CI';cloud_volume_id='ci-disposable-volume';bus_type=[string]$disk.BusType;
        original_read_only=[bool]$disk.IsReadOnly;original_offline=[bool]$disk.IsOffline;set_read_only=$true;bring_online=[bool]$disk.IsOffline}
    $bad=$plan.Clone();$bad.disk_unique_id='wrong'
    Assert-Refused { Mount-DevBoxCloudCandidate -Plan $bad } 'identity'
    if ((Get-Disk -Number $disk.Number).IsReadOnly) { throw 'Wrong identity changed disk flags.' }
    $bad=$plan.Clone();$bad.cloud_volume_id='wrong'
    Assert-Refused { Mount-DevBoxCloudCandidate -Plan $bad } 'marker'
    if (Get-PSDrive -Name E -ErrorAction SilentlyContinue) { throw 'Failed marker left E mounted.' }
    if ((Get-Disk -Number $disk.Number).IsReadOnly) { throw 'Rollback failed to restore readonly flag.' }
    $receipt=Mount-DevBoxCloudCandidate -Plan $plan
    if ($receipt.status -ne 'attached_read_only' -or -not (Get-Disk -Number $disk.Number).IsReadOnly) { throw 'E not truly read-only.' }
    if ((Get-Volume -DriveLetter E).UniqueId -ne $volume.UniqueId) { throw 'Wrong volume attached.' }
    Assert-Refused { Mount-DevBoxCloudCandidate -Plan $plan } 'occupied'
    if (-not (Test-Path 'E:\.devbox-cloud-volume.json')) { throw 'Repeated attach disrupted existing E.' }
    Assert-Refused { Set-Content -LiteralPath 'E:\must-not-write.txt' -Value 'forbidden' -ErrorAction Stop } 'write|denied|protect|access'
    Write-Output 'WINDOWS E READONLY ATTACH, IDENTITY, COLLISION, MARKER AND ROLLBACK: PASS'
    # Only this exact test-owned fixture is made writable for the canary characterization.
    Set-Disk -Number $disk.Number -IsReadOnly $false
    python (Join-Path $PSScriptRoot '../scripts/probe_cloud_drive.py') --root 'E:\' --cloud-volume-id ci-disposable-volume
    if ($LASTEXITCODE -ne 0) { throw 'Fixture canary flush/readback failed.' }
    Write-Output 'WINDOWS DISPOSABLE E DEVICE FLUSH AND LOCAL READBACK: PASS; CLOUD DURABILITY NOT TESTED'
} finally {
    if ($null -ne $disk) {
        $current=Get-Disk -Number $disk.Number -ErrorAction SilentlyContinue
        if ($current -and $current.UniqueId -eq $disk.UniqueId -and -not $current.IsBoot -and -not $current.IsSystem) {
            if ($null -ne $partition) {
                $p=Get-Partition -DiskNumber $disk.Number -PartitionNumber $partition.PartitionNumber -ErrorAction SilentlyContinue
                if ($p -and $p.DriveLetter -eq 'E') { Remove-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $partition.PartitionNumber -AccessPath 'E:\' -ErrorAction Stop }
            }
            @("select vdisk file=`"$file`"",'detach vdisk','exit') | Set-Content -LiteralPath $detach
            & diskpart.exe /s $detach
        }
    }
}
