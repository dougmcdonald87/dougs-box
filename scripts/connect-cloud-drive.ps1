[CmdletBinding()]
param([string]$ConfigPath,[switch]$InspectOnly,[ValidateRange(5,60)][int]$ConnectTimeoutSeconds=30)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'Native Windows E: candidate only.' }
. (Join-Path $PSScriptRoot 'cloud-drive-windows.ps1')

function Get-CloudProtectedDiskIds {
    $all=@(Get-Partition -ErrorAction Stop)
    $ids=@()
    foreach ($letter in @('C','D')) {
        $parts=@($all | Where-Object DriveLetter -EQ $letter)
        if ($parts.Count -ne 1) { throw "Cannot establish protected $letter`: disk identity." }
        $ids+=[string](Get-Disk -Number $parts[0].DiskNumber -ErrorAction Stop).UniqueId
    }
    return @($ids | Select-Object -Unique)
}

if ($InspectOnly) {
    $service=Get-Service MSiSCSI -ErrorAction SilentlyContinue
    $status=if ($service) { [string]$service.Status } else { 'unavailable' }
    $commands=@{}
    foreach ($name in @('Get-Disk','Get-Partition','Get-Volume','Connect-IscsiTarget','Get-IscsiSession','Get-IscsiConnection')) { $commands[$name]=[bool](Get-Command $name -ErrorAction SilentlyContinue) }
    @{schema_version=1;status='inspection_only';disk_mutations=0;drive_letter='E';e_occupied=(Test-DevBoxCloudEOccupied);
      initiator_service=$status;commands=$commands;protected_disk_ids=@(Get-CloudProtectedDiskIds)} | ConvertTo-Json -Depth 5
    exit 0
}
if (-not $ConfigPath) { throw 'ConfigPath is required; no inferred or example targets.' }
$policy=Join-Path $PSScriptRoot 'cloud_drive.py'
$configOutput=(& python $policy validate --config $ConfigPath | Out-String)
if ($LASTEXITCODE -ne 0) { throw 'Cloud config refused before any connection or disk change.' }
$c=$configOutput | ConvertFrom-Json -AsHashtable
if (Test-DevBoxCloudEOccupied) { throw 'E: is occupied; refusing any connection.' }
$protectedIds=@(Get-CloudProtectedDiskIds)
$service=Get-Service MSiSCSI -ErrorAction Stop
if ($service.Status -ne 'Running') { throw 'MSiSCSI is not running; inspect prerequisites before enabling it.' }
$before=@(Get-IscsiSession -ErrorAction Stop)
if (@($before | Where-Object TargetNodeAddress -EQ $c.target_iqn).Count) { throw 'Existing target session is preserved; no reconfiguration.' }
$beforeIds=@($before | ForEach-Object { [string]$_.SessionIdentifier })
$job=$null;$session=$null;$mounted=$false;$inventoryFile=$null
try {
    # The cloud owner must export the candidate read-only before this command;
    # Windows PnP/automount can inspect disks before client-side policy runs.
    # No provider account is created and no credentials are inferred here.
    $job=Connect-IscsiTarget -NodeAddress $c.target_iqn -TargetPortalAddress $c.portal -TargetPortalPortNumber 3260 -IsPersistent $false -IsMultipathEnabled $false -AsJob -ErrorAction Stop
    if (-not (Wait-Job -Job $job -Timeout $ConnectTimeoutSeconds)) { throw 'Connection timed out; late completion is UNKNOWN and must be inspected before retry.' }
    $result=@(Receive-Job -Job $job -ErrorAction Stop)
    if ($result.Count -ne 1 -or -not $result[0].SessionIdentifier -or $result[0].TargetNodeAddress -ne $c.target_iqn -or -not $result[0].IsConnected) { throw 'Connection result has no reliable owned session; outcome UNKNOWN, inspect before retry.' }
    if ([string]$result[0].SessionIdentifier -in $beforeIds) { throw 'Connection result references a preexisting session; refusing ownership.' }
    $session=$result[0]
    $owned=@(Get-IscsiSession -ErrorAction Stop | Where-Object { $_.TargetNodeAddress -eq $c.target_iqn -and [string]$_.SessionIdentifier -eq [string]$session.SessionIdentifier })
    if ($owned.Count -ne 1) { throw 'Owned connection result is absent/ambiguous in fresh inventory; other sessions are never adopted.' }
    $session=$owned[0]
    $connections=@(Get-IscsiConnection -IscsiSession $session -ErrorAction Stop)
    if ($connections.Count -ne 1 -or [string]$connections[0].TargetNodeAddress -ne $c.portal -or $connections[0].TargetPortNumber -ne 3260) { throw 'Session portal identity mismatch.' }
    $disks=@(Get-Disk -iSCSISession $session -ErrorAction Stop)
    $candidates=@()
    foreach ($disk in $disks) {
        $parts=@()
        foreach ($p in @(Get-Partition -DiskNumber $disk.Number -ErrorAction Stop)) {
            $volumes=@($p | Get-Volume -ErrorAction SilentlyContinue)
            $uid='';$fs='';$label=''
            if ($volumes.Count -eq 1) { $uid=[string]$volumes[0].UniqueId;$fs=[string]$volumes[0].FileSystem;$label=[string]$volumes[0].FileSystemLabel }
            $letter=if ($p.DriveLetter) { [string]$p.DriveLetter } else { $null }
            $parts+=@{number=[int]$p.PartitionNumber;guid=[string]$p.Guid;drive_letter=$letter;
                volume_unique_id=$uid;filesystem=$fs;label=$label;access_paths=@($p.AccessPaths | Where-Object { $_ })}
        }
        $candidates+=@{unique_id=[string]$disk.UniqueId;number=[int]$disk.Number;bus_type=[string]$disk.BusType;
            is_boot=[bool]$disk.IsBoot;is_system=[bool]$disk.IsSystem;is_offline=[bool]$disk.IsOffline;is_read_only=[bool]$disk.IsReadOnly;
            target_iqn=[string]$session.TargetNodeAddress;portal=[string]$connections[0].TargetNodeAddress;
            partition_style=[string]$disk.PartitionStyle;partitions=$parts}
    }
    $letters=@(Get-PSDrive | ForEach-Object Name)
    if (Test-DevBoxCloudEOccupied) { $letters+='E' }
    $inventory=@{occupied_letters=$letters;protected_disk_ids=$protectedIds;active_sessions=@($before | ForEach-Object { @{target_iqn=[string]$_.TargetNodeAddress} });candidate_disks=$candidates}
    $inventoryFile=Join-Path ([IO.Path]::GetTempPath()) ('cloud-e-inventory-'+[guid]::NewGuid().ToString('N')+'.json')
    $inventory | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $inventoryFile -Encoding utf8
    $planOutput=(& python $policy plan --config $ConfigPath --inventory $inventoryFile | Out-String)
    if ($LASTEXITCODE -ne 0) { throw 'Cloud candidate inventory refused; no disk flags or letter were changed.' }
    $plan=$planOutput | ConvertFrom-Json -AsHashtable
    $receipt=Mount-DevBoxCloudCandidate -Plan $plan
    $mounted=$true
    $receipt.session_identifier=[string]$session.SessionIdentifier
    $receipt | ConvertTo-Json -Depth 5
} catch {
    $failure=$_
    # Disconnect only the exact new session; never a preexisting target/session.
    if (-not $mounted -and $null -ne $session) {
        if ([string]$session.SessionIdentifier -in $beforeIds) { throw 'Cleanup refuses preexisting session.' }
        Disconnect-IscsiTarget -NodeAddress $c.target_iqn -SessionIdentifier $session.SessionIdentifier -Confirm:$false -ErrorAction Stop | Out-Null
    }
    throw $failure
} finally {
    if ($null -ne $job) {
        if ($job.State -eq 'Running') { Stop-Job -Job $job -ErrorAction SilentlyContinue }
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }
    if ($inventoryFile -and (Test-Path -LiteralPath $inventoryFile)) { Remove-Item -LiteralPath $inventoryFile -ErrorAction SilentlyContinue }
}
