$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -ne 'true' -or $env:DEVBOX_ISOLATED_TEST -ne '1'){throw 'Disposable CI runner only.'}
if($env:WINDOWS_STATE_INSTALL_IMAGE -eq 'true' -and -not $env:WINDOWS_STATE_MEDIA_URI){throw 'Native image test requires an explicit official media URI.'}
if($env:WINDOWS_STATE_FIXTURE -eq 'true' -and $env:WINDOWS_STATE_INSTALL_IMAGE -ne 'true'){throw 'Native fixture test requires image installation.'}
if($env:WINDOWS_STATE_CHECKPOINT_ROUNDTRIP -eq 'true' -and $env:WINDOWS_STATE_FIXTURE -ne 'true'){throw 'Native checkpoint roundtrip requires real guest fixture.'}
. (Join-Path $PSScriptRoot '../scripts/windows-state-probe.ps1')
& (Join-Path $PSScriptRoot '../scripts/bootstrap.ps1') -CloudCandidate
if(-not $? -or -not (Test-Path 'E:/DevBox/Control/session.json')){throw 'Owned E bootstrap failed'}
$root='E:/DevBox/Tools/WindowsStateProbe/probe-'+$env:GITHUB_RUN_ID+'-'+$env:GITHUB_RUN_ATTEMPT
$name='DevBoxWindowsState-'+$env:GITHUB_RUN_ID+'-'+$env:GITHUB_RUN_ATTEMPT
$owner=$null
try {
    $owner=New-WindowsStateProbe -Root $root -VmName $name
    $id=[guid]::Parse($owner.vmId)
    Start-VM -VM (Get-VM -Id $id -ErrorAction Stop) -ErrorAction Stop
    Start-Sleep -Seconds 3
    $vm=Get-VM -Id $id -ErrorAction Stop
    if($vm.State -ne 'Running'){throw 'Owned empty VM did not start'}
    Write-Output ('NATIVE OWNED EMPTY VM RUNNING: '+$id+' path='+$vm.Path)
    Stop-VM -VM $vm -TurnOff -Force -ErrorAction Stop
    $disk=New-WindowsStateGuestDisk -Root $root -VmName $name
    if($disk.capacityBytes -ne 64GB -or $disk.type -ne 'Dynamic' -or $disk.secureBoot -ne 'On'){throw 'Guest disk native contract mismatch'}
    $hash=(Get-FileHash -LiteralPath $disk.diskPath -Algorithm SHA256).Hash
    try {New-WindowsStateGuestDisk -Root $root -VmName $name;throw 'Existing disk replaced'}
    catch {if($_.Exception.Message -notmatch '^Existing guest disk must not be replaced'){throw}}
    if((Get-FileHash -LiteralPath $disk.diskPath -Algorithm SHA256).Hash -cne $hash){throw 'Refused retry changed existing disk'}
    Write-Output ('NATIVE OWNED DYNAMIC DISK + REFUSED RETRY: '+($disk|ConvertTo-Json -Compress))
    $nativeMount=Mount-VHD -Path $disk.diskPath -PassThru -ErrorAction Stop
    try {
        $nativeDisk=Get-Disk -Number $nativeMount.DiskNumber -ErrorAction Stop
        $nativeVhd=Get-VHD -Path $disk.diskPath -ErrorAction Stop
        Write-Output ('NATIVE EMPTY VHD MAPPING OBSERVATIONS: '+([pscustomobject]@{path=$nativeVhd.Path;diskNumber=$nativeDisk.Number;resolvedDiskNumber=$nativeVhd.DiskNumber;busType=$nativeDisk.BusType.ToString();busTypeObject=$nativeDisk.BusType.GetType().FullName;partitionStyle=$nativeDisk.PartitionStyle.ToString();partitions=$nativeDisk.NumberOfPartitions;isBoot=$nativeDisk.IsBoot;isSystem=$nativeDisk.IsSystem;mounted=$nativeVhd.Attached}|ConvertTo-Json -Compress))
    } finally {Dismount-VHD -Path $disk.diskPath -ErrorAction Stop}
    # Cheap export identity observation before any ISO download or installed guest.
    $vm=Get-VM -Id $id;$priorCheckpointType=$vm.CheckpointType;$identitySnapshot=$null
    try {
        Set-VM -VM $vm -CheckpointType Standard -ErrorAction Stop
        Checkpoint-VM -VM $vm -SnapshotName 'OwnedEmptyIdentityProbe' -ErrorAction Stop
        $identitySnapshot=Get-VMSnapshot -VM $vm -Name 'OwnedEmptyIdentityProbe' -ErrorAction Stop
        $identityExport=Join-Path $root 'empty-checkpoint-identity'
        New-Item -ItemType Directory -Path $identityExport | Out-Null
        Export-VMSnapshot -VMSnapshot $identitySnapshot -Path $identityExport -ErrorAction Stop | Out-Null
        $configs=@(Get-ChildItem -LiteralPath $identityExport -Recurse -File -Filter '*.vmcx')
        if($configs.Count -ne 1){throw 'Empty checkpoint export configuration ambiguous'}
        $configurationId=[guid]::Parse($configs[0].BaseName)
        Write-Output ('NATIVE EMPTY CHECKPOINT CONFIGURATION FILENAME: '+([pscustomobject]@{sourceVmId=$id.ToString();checkpointId=$identitySnapshot.Id.ToString();configurationFile=$configs[0].Name;configurationId=$configurationId.ToString();evidence='filename-only; actual same-ID import requires source unregistered'}|ConvertTo-Json -Compress))
    } finally {
        if($identitySnapshot){Remove-VMSnapshot -VMSnapshot $identitySnapshot -Confirm:$false -ErrorAction Stop}
        Set-VM -VM (Get-VM -Id $id) -CheckpointType $priorCheckpointType -ErrorAction Stop
    }
    $postCheckpointPath=(Get-VMHardDiskDrive -VM (Get-VM -Id $id))[0].Path
    $postCheckpointDisk=Get-VHD -Path $postCheckpointPath -ErrorAction Stop
    Write-Output ('NATIVE EMPTY POST-CHECKPOINT DISK OBSERVATIONS: '+([pscustomobject]@{attachedPath=$postCheckpointPath;type=$postCheckpointDisk.VhdType.ToString();parent=$postCheckpointDisk.ParentPath;originalFileExists=(Test-Path -LiteralPath $disk.diskPath)}|ConvertTo-Json -Compress))
    # Actual empty same-ID import after positively owned source unregister.
    $ownedEmpty=Get-VM -Id $id -ErrorAction Stop
    if($ownedEmpty.Name -cne $name -or $ownedEmpty.State -ne 'Off' -or -not (Test-WindowsStateProbeVmPath -Root $root -VmName $name -VmPath $ownedEmpty.Path)){throw 'Empty import source owner mismatch'}
    Remove-VM -VM $ownedEmpty -Force -ErrorAction Stop
    $emptyDisks=Join-Path $root 'empty-import-disks';$emptySnapshots=Join-Path $root 'empty-import-snapshots'
    $emptySourceDisks=Split-Path (Get-ChildItem -LiteralPath $identityExport -Recurse -File -Filter '*.vhdx'|Select-Object -First 1).FullName -Parent
    $emptyReport=Compare-VM -Path $configs[0].FullName -Copy -VhdSourcePath $emptySourceDisks -VirtualMachinePath (Join-Path $root $name) -VhdDestinationPath $emptyDisks -SnapshotFilePath $emptySnapshots -ErrorAction Stop
    if($emptyReport.VM.Id -ne $id -or $emptyReport.VM.Name -cne $name -or @($emptyReport.Incompatibilities|Where-Object {$_}).Count){throw 'Empty exported embedded VM identity/compatibility mismatch'}
    $emptyImported=Import-VM -CompatibilityReport $emptyReport -ErrorAction Stop
    if($emptyImported.Id -ne $id -or -not (Test-WindowsStateProbeVmPath -Root $root -VmName $name -VmPath $emptyImported.Path)){throw 'Actual empty import VM ID/path changed'}
    Write-Output ('NATIVE EMPTY ACTUAL SAME-ID COPY IMPORT: '+([pscustomobject]@{sourceVmId=$id.ToString();configurationFilenameId=$configurationId.ToString();parsedVmId=$emptyReport.VM.Id.ToString();importedVmId=$emptyImported.Id.ToString();vmPath=$emptyImported.Path}|ConvertTo-Json -Compress))
    # This subprobe is still RAW/empty (no Windows image). Preserve its old canonical
    # file and copy the verified standalone RAW export to the installer contract path.
    $attached=@(Get-VMHardDiskDrive -VM $emptyImported)
    if($attached.Count -ne 1){throw 'Empty imported disk count mismatch'}
    $rawSource=[IO.Path]::GetFullPath($attached[0].Path)
    if(-not $rawSource.StartsWith([IO.Path]::GetFullPath($emptyDisks)+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Empty imported attachment outside owned import directory'}
    $rawDisk=Get-VHD -Path $rawSource -ErrorAction Stop
    if($rawDisk.VhdType -ne 'Dynamic' -or $rawDisk.Size -ne 64GB -or $rawDisk.ParentPath){throw 'Empty imported RAW disk must be standalone dynamic64GiB'}
    Remove-VMHardDiskDrive -VMHardDiskDrive $attached[0] -ErrorAction Stop
    if(Test-Path -LiteralPath $disk.diskPath){
        $preservedRaw=Join-Path $root 'pre-identity-original.vhdx'
        if(Test-Path -LiteralPath $preservedRaw){throw 'Existing raw preservation file refused'}
        Move-Item -LiteralPath $disk.diskPath -Destination $preservedRaw -ErrorAction Stop
    }
    Copy-Item -LiteralPath $rawSource -Destination $disk.diskPath -ErrorAction Stop
    if((Get-FileHash -LiteralPath $rawSource -Algorithm SHA256).Hash -cne (Get-FileHash -LiteralPath $disk.diskPath -Algorithm SHA256).Hash){throw 'Canonical RAW disk copy hash mismatch'}
    Add-VMHardDiskDrive -VM $emptyImported -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 0 -Path $disk.diskPath -ErrorAction Stop
    Set-VM -VM $emptyImported -CheckpointType $priorCheckpointType -ErrorAction Stop
    if($env:WINDOWS_STATE_MEDIA_URI){
        . (Join-Path $PSScriptRoot '../scripts/windows-home-media.ps1')
        $media=Get-WindowsHomeMedia -Root $root -VmName $name -Uri $env:WINDOWS_STATE_MEDIA_URI -Sha256 $env:WINDOWS_STATE_MEDIA_SHA256
        Write-Output ('NATIVE ISO HASH + BYTES VERIFIED: '+($media|ConvertTo-Json -Compress))
        $image=Mount-DiskImage -ImagePath $media.path -PassThru -ErrorAction Stop
        try {
            $volume=$image | Get-Volume -ErrorAction Stop
            if(@($volume).Count -ne 1 -or -not $volume.DriveLetter){throw 'Installer volume ambiguous'}
            $wim=([string]$volume.DriveLetter)+':\sources\install.wim'
            if(-not (Test-Path -LiteralPath $wim)){throw 'Expected official install.wim missing'}
            $homeImages=@(Get-WindowsImage -ImagePath $wim -ErrorAction Stop | Where-Object {$_.ImageName -ceq 'Windows 10 Home'})
            if($homeImages.Count -ne 1){throw 'Windows 10 Home image ambiguous or missing'}
            $detail=Get-WindowsImage -ImagePath $wim -Index $homeImages[0].ImageIndex -ErrorAction Stop
            if($detail.EditionId -cne 'Core'){throw 'Selected Windows image is not Home/Core'}
            Write-Output ('NATIVE WINDOWS10 HOME MEDIA VERIFIED: '+([pscustomobject]@{sha256=$media.sha256;bytes=$media.bytes;index=$detail.ImageIndex;name=$detail.ImageName;edition=$detail.EditionId;version=[string]$detail.Version;imageBytes=$detail.ImageSize}|ConvertTo-Json -Compress))
        } finally {Dismount-DiskImage -ImagePath $media.path -ErrorAction Stop | Out-Null}
        if($env:WINDOWS_STATE_INSTALL_IMAGE -eq 'true'){
            $guestCredential=$null
            if($env:WINDOWS_STATE_FIXTURE -eq 'true'){
                $secret='Fixture!1'+[Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(24))
                Write-Host ('::add-mask::'+$secret)
                $guestCredential=[pscredential]::new('DevBoxFixture',(ConvertTo-SecureString $secret -AsPlainText -Force))
            }
            $receipt=Install-WindowsStateHomeImage -Root $root -VmName $name -Sha256 $env:WINDOWS_STATE_MEDIA_SHA256 -GuestCredential $guestCredential
            Write-Output ('NATIVE HOME IMAGE APPLIED: '+($receipt|ConvertTo-Json -Compress))
            Start-VM -VM (Get-VM -Id $id -ErrorAction Stop) -ErrorAction Stop
            $deadline=[DateTime]::UtcNow.AddMinutes(5);$heartbeat=$null
            do {
                Start-Sleep -Seconds 5
                $heartbeat=Get-VMIntegrationService -VM (Get-VM -Id $id -ErrorAction Stop) -Name Heartbeat -ErrorAction Stop
            } while($heartbeat.PrimaryStatusDescription -ne 'OK' -and [DateTime]::UtcNow -lt $deadline)
            if($heartbeat.PrimaryStatusDescription -ne 'OK'){throw 'Applied Home guest did not report a healthy OS heartbeat'}
            Write-Output ('NATIVE APPLIED WINDOWS10 DISK HEARTBEAT: '+$heartbeat.PrimaryStatusDescription+'; first-run setup and program fixture remain pending')
            if($guestCredential){
                . (Join-Path $PSScriptRoot '../scripts/windows-state-fixture.ps1')
                $session=$null;$sessionDeadline=[DateTime]::UtcNow.AddMinutes(5)
                do {
                    try {$session=New-PSSession -VMId $id -Credential $guestCredential -ErrorAction Stop}
                    catch {Start-Sleep -Seconds 10}
                } while(-not $session -and [DateTime]::UtcNow -lt $sessionDeadline)
                if(-not $session){throw 'Guest fixture PowerShell Direct setup did not become ready'}
                try {
                    Assert-WindowsStateGuestSession -GuestSession $session -VmId $id
                    & (Join-Path $PSScriptRoot 'windows-state-guest.acceptance.ps1') -GuestSession $session -VmId $id -ExpectMissing
                    $installer=Join-Path $root 'python-3.12.10-amd64.exe'
                    Invoke-WebRequest -Uri 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe' -OutFile $installer -ErrorAction Stop
                    Install-WindowsStateFixture -GuestSession $session -VmId $id -InstallerPath $installer | Out-Null
                    $baseline=& (Join-Path $PSScriptRoot 'windows-state-guest.acceptance.ps1') -GuestSession $session -VmId $id
                    Write-Output ('NATIVE REAL GUEST FIXTURE BASELINE: '+($baseline|Select-Object machineName,machineGuid,programPath,programVersion,documentSha256,preferences,windowsHideFileExt|ConvertTo-Json -Compress))
                } finally {Remove-PSSession $session}
                Stop-VM -VM (Get-VM -Id $id -ErrorAction Stop) -ErrorAction Stop
                $offDeadline=[DateTime]::UtcNow.AddMinutes(2)
                while((Get-VM -Id $id).State -ne 'Off' -and [DateTime]::UtcNow -lt $offDeadline){Start-Sleep -Seconds 5}
                if((Get-VM -Id $id).State -ne 'Off'){throw 'Guest fixture clean shutdown failed'}
                Start-VM -VM (Get-VM -Id $id) -ErrorAction Stop
                $session=$null;$sessionDeadline=[DateTime]::UtcNow.AddMinutes(5)
                do {
                    try {$session=New-PSSession -VMId $id -Credential $guestCredential -ErrorAction Stop}
                    catch {Start-Sleep -Seconds 10}
                } while(-not $session -and [DateTime]::UtcNow -lt $sessionDeadline)
                if(-not $session){throw 'Guest fixture second boot PowerShell Direct unavailable'}
                try {
                    $second=& (Join-Path $PSScriptRoot 'windows-state-guest.acceptance.ps1') -GuestSession $session -VmId $id
                    foreach($property in @('machineName','machineGuid','programPath','programVersion','documentSha256','windowsHideFileExt')){
                        if($baseline.$property -cne $second.$property){throw ('Guest second boot fixture changed: '+$property)}
                    }
                    Write-Output 'NATIVE PROGRAM + DOCUMENT + APPLICATION/HKCU SETTINGS + IDENTITY SECOND BOOT: PASS'
                } finally {Remove-PSSession $session}
            }
            if($env:WINDOWS_STATE_CHECKPOINT_ROUNDTRIP -eq 'true'){
                . (Join-Path $PSScriptRoot '../scripts/windows-state-checkpoint.ps1')
                function Open-CheckpointFixtureSession {
                    $session=$null;$deadline=[DateTime]::UtcNow.AddMinutes(5)
                    do {
                        try {$session=New-PSSession -VMId $id -Credential $guestCredential -ErrorAction Stop}
                        catch {Start-Sleep -Seconds 10}
                    } while(-not $session -and [DateTime]::UtcNow -lt $deadline)
                    if(-not $session){throw 'Checkpoint fixture guest session unavailable'}
                    Assert-WindowsStateGuestSession -GuestSession $session -VmId $id
                    $session
                }
                function Assert-CheckpointFixtureEqual($actual,$expected){
                    foreach($property in @('machineName','machineGuid','programPath','programVersion','documentSha256','windowsHideFileExt')){
                        if($actual.$property -cne $expected.$property){throw ('Restored checkpoint fixture mismatch: '+$property)}
                    }
                    if($actual.preferences.theme -cne $expected.preferences.theme -or $actual.preferences.volume -ne $expected.preferences.volume){throw 'Restored checkpoint application preferences mismatch'}
                }
                $saved=Export-WindowsStateCheckpoint -Root $root -VmId $id -Mode save
                Write-Output ('NATIVE RUNNING PRODUCTION SAVE EXPORTED: '+($saved|ConvertTo-Json -Compress))
                # Change the source after Save: importing Save must recover the prior values.
                $session=Open-CheckpointFixtureSession
                try {
                    Invoke-Command -Session $session -ErrorAction Stop -ScriptBlock {
                        $encoding=[Text.UTF8Encoding]::new($false)
                        [IO.File]::WriteAllText((Join-Path $env:USERPROFILE 'Documents\DevBoxFixture.txt'),"DevBox post-save document fixture v2`n",$encoding)
                        [IO.File]::WriteAllText((Join-Path $env:APPDATA 'DevBoxFixture\preferences.json'),'{"theme":"light","volume":84}',$encoding)
                        Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name HideFileExt -Value 1 -ErrorAction Stop
                    }
                    $finishBaseline=Get-WindowsStateFixture -GuestSession $session -VmId $id
                    if($finishBaseline.documentSha256 -ceq $baseline.documentSha256 -or $finishBaseline.preferences.volume -eq $baseline.preferences.volume){throw 'Post-Save source mutation did not distinguish checkpoint generations'}
                    Write-Output ('NATIVE POST-SAVE SOURCE FIXTURE: '+($finishBaseline|Select-Object machineName,machineGuid,programPath,programVersion,documentSha256,preferences,windowsHideFileExt|ConvertTo-Json -Compress))
                } finally {Remove-PSSession $session}
                $finished=Export-WindowsStateCheckpoint -Root $root -VmId $id -Mode finish
                Write-Output ('NATIVE CLEAN FINISH EXPORTED: '+($finished|ConvertTo-Json -Compress))
                # Hash/configuration checks before unregistering the only owned source.
                foreach($receipt in @($saved,$finished)){
                    $verifyPath=Join-Path (Split-Path $receipt.manifestPath -Parent) 'native-preimport-verification.json'
                    @{vm_id=$id.ToString();supported_versions=@(Get-VMHostSupportedVersion|ForEach-Object {$_.Version.ToString()})}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $verifyPath -Encoding utf8
                    try {
                        & python (Join-Path $PSScriptRoot '../scripts/windows_state_manifest.py') verify --root $receipt.exportPath --metadata $verifyPath --manifest $receipt.manifestPath | ForEach-Object {Write-Host $_}
                        if($LASTEXITCODE -ne 0){throw 'Native pre-import verification failed; source registration preserved'}
                    } finally {Remove-Item -LiteralPath $verifyPath -Force}
                }
                $owned=Get-WindowsStateCheckpointOwner -Root $root -VmId $id
                if($owned.vm.State -ne 'Off'){throw 'Owned source must be off before deliberate test unregister'}
                Remove-VM -VM $owned.vm -Force -ErrorAction Stop
                foreach($case in @([pscustomobject]@{receipt=$saved;expected=$baseline;label='restored-save'},[pscustomobject]@{receipt=$finished;expected=$finishBaseline;label='restored-finish'})){
                    $imported=Import-WindowsStateCheckpoint -Root $root -VmId $id -ExportPath $case.receipt.exportPath -ManifestPath $case.receipt.manifestPath -DestinationLabel $case.label
                    Start-VM -VM $imported -ErrorAction Stop
                    $session=Open-CheckpointFixtureSession
                    try {$actual=Get-WindowsStateFixture -GuestSession $session -VmId $id;Assert-CheckpointFixtureEqual $actual $case.expected}
                    finally {Remove-PSSession $session}
                    Write-Output ('NATIVE '+$case.label.ToUpperInvariant()+' SAME VM ID + PROGRAM + DOCUMENT + APPLICATION/HKCU + MACHINE ID: PASS')
                    Stop-VM -VM (Get-VM -Id $id) -ErrorAction Stop
                    $deadline=[DateTime]::UtcNow.AddMinutes(2)
                    while((Get-VM -Id $id).State -ne 'Off' -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Seconds 5}
                    if((Get-VM -Id $id).State -ne 'Off'){throw 'Restored checkpoint clean shutdown failed'}
                    if($case.label -eq 'restored-save'){
                        $owned=Get-WindowsStateCheckpointOwner -Root $root -VmId $id
                        Remove-VM -VM $owned.vm -Force -ErrorAction Stop
                    }
                }
            } else {
                Stop-VM -VM (Get-VM -Id $id -ErrorAction Stop) -ErrorAction Stop
                if($guestCredential){
                    $offDeadline=[DateTime]::UtcNow.AddMinutes(2)
                    while((Get-VM -Id $id).State -ne 'Off' -and [DateTime]::UtcNow -lt $offDeadline){Start-Sleep -Seconds 5}
                    if((Get-VM -Id $id).State -ne 'Off'){throw 'Capacity measurement requires clean guest shutdown'}
                    . (Join-Path $PSScriptRoot '../scripts/windows-state-capacity.ps1')
                    $capacity=Measure-WindowsStateExportCapacity -Root $root -VmName $name
                    Write-Output ('NATIVE WHOLE GUEST ENCRYPTED CAPACITY: '+($capacity|ConvertTo-Json -Compress))
                    if(-not $capacity.fitsExistingTransport){throw ('Whole guest falsifies existing 8GiB transport: '+$capacity.archiveBytes+' archive bytes')}
                }
            }
        }
    }
} finally {
    if($owner){Remove-WindowsStateProbe -Root $root -VmName $name}
}
if(@(Get-VM -ErrorAction Stop | Where-Object {$_.Id -eq $id}).Count){throw 'Owned VM cleanup failed'}
Write-Output 'NATIVE OWNERSHIP + VM START + DISK + CLEANUP: PASS; optional OS/fixture evidence is reported separately above.'
