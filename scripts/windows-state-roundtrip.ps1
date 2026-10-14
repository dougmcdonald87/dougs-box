$ErrorActionPreference='Stop'
function Assert-WindowsStateRoundtripContext {
    if($env:GITHUB_ACTIONS -cne 'true' -or $env:DEVBOX_ISOLATED_TEST -cne '1' -or $env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or $env:GITHUB_REPOSITORY -cnotmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or [string]::IsNullOrWhiteSpace($env:RESTIC_PASSWORD) -or [string]::IsNullOrWhiteSpace($env:GH_TOKEN)){
        throw 'Only an isolated authenticated manual fixture transfer is allowed.'
    }
}
function Get-WindowsStatePortableFixtureCredential {
    param([Parameter(Mandatory)][guid]$VmId)
    Assert-WindowsStateRoundtripContext
    if($VmId -eq [guid]::Empty){throw 'Portable fixture VM identity required.'}
    $key=[Text.Encoding]::UTF8.GetBytes($env:RESTIC_PASSWORD)
    $hmac=[Security.Cryptography.HMACSHA256]::new($key)
    try {
        $message=[Text.Encoding]::UTF8.GetBytes('DevBoxWindowsStateFixture-v1|'+$VmId.ToString('D').ToLowerInvariant())
        $secret='Fixture!1'+[Convert]::ToHexString($hmac.ComputeHash($message))
        Write-Host ('::add-mask::'+$secret)
        [pscredential]::new('DevBoxFixture',(ConvertTo-SecureString $secret -AsPlainText -Force))
    } finally {$hmac.Dispose();[Array]::Clear($key,0,$key.Length)}
}

function Invoke-WindowsStateResticBackup {
    param([string]$Restic,[string]$Repository,[string]$Path,[string]$Tag)
    $lines=& $Restic --repo $Repository --json backup --compression max --tag $Tag $Path
    if($LASTEXITCODE -ne 0){throw 'Whole Windows encrypted snapshot failed.'}
    $summary=@($lines|ForEach-Object {$_|ConvertFrom-Json}|Where-Object {$_.message_type -eq 'summary'})
    if($summary.Count -ne 1 -or $summary[0].snapshot_id -cnotmatch '^[0-9a-f]{64}$'){throw 'Encrypted snapshot receipt unavailable.'}
    [string]$summary[0].snapshot_id
}

function Publish-WindowsStateRoundtrip {
    param([string]$Root,[guid]$VmId,[AllowNull()][object]$Checkpoint,[AllowNull()][object]$Baseline)
    if($Root -cnotmatch '^E:/DevBox/Tools/WindowsStateProbe/probe-[0-9]+-[0-9]+$'){throw 'Only an exact owned E probe directory is allowed.'}
    Assert-WindowsStateRoundtripContext
    . (Join-Path $PSScriptRoot 'windows-state-checkpoint.ps1')
    $owner=Get-WindowsStateCheckpointOwner -Root $Root -VmId $VmId
    if($owner.vm.State -ne 'Off' -or -not $Checkpoint -or $Checkpoint.mode -cne 'finish' -or $Checkpoint.vmId -cne $VmId.ToString() -or -not $Checkpoint.exportVerified -or $Checkpoint.published){throw 'Only a verified owned clean Finish export can be published.'}
    $manifest=Assert-WindowsStateOwnedPath -Root $Root -Path $Checkpoint.manifestPath
    $payload=Assert-WindowsStateOwnedPath -Root $Root -Path $Checkpoint.exportPath
    $directory=Split-Path $manifest -Parent
    if((Split-Path $directory -Leaf) -cne $Checkpoint.generation -or (Split-Path $payload -Parent) -ine $directory){throw 'Transfer checkpoint generation mismatch.'}
    $proof=Join-Path $directory 'transfer-preflight.json'
    if(Test-Path -LiteralPath $proof){throw 'Transfer preflight must be new.'}
    @{vm_id=$VmId.ToString();supported_versions=@(Get-VMHostSupportedVersion|ForEach-Object {$_.Version.ToString()})}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $proof -Encoding utf8
    try {
        & python (Join-Path $PSScriptRoot 'windows_state_manifest.py') verify --root $payload --metadata $proof --manifest $manifest | ForEach-Object {Write-Host $_}
        if($LASTEXITCODE -ne 0){throw 'Transfer refused unverified whole VM files.'}
    } finally {Remove-Item -LiteralPath $proof -Force}
    $channel='ci-'+$env:GITHUB_RUN_ID+'-'+$env:GITHUB_RUN_ATTEMPT
    if($Root -cne ('E:/DevBox/Tools/WindowsStateProbe/probe-'+$env:GITHUB_RUN_ID+'-'+$env:GITHUB_RUN_ATTEMPT)){throw 'Publisher must own the current CI run channel.'}
    $manifestHash=(Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash.ToLowerInvariant()
    $transfer=Join-Path $directory 'WINDOWS-STATE-TRANSFER.json'
    if(Test-Path -LiteralPath $transfer){throw 'Transfer metadata must be new.'}
    $systemProduct=Get-CimInstance Win32_ComputerSystemProduct -ErrorAction Stop
    $outerId=([guid]$systemProduct.UUID).ToString()
    if([guid]$outerId -eq [guid]::Empty -or $env:GITHUB_SHA -cnotmatch '^[0-9a-f]{40}$'){throw 'Producer host/revision identity unavailable.'}
    [ordered]@{schema=1;producer_run=$env:GITHUB_RUN_ID;producer_attempt=$env:GITHUB_RUN_ATTEMPT;producer_host=$outerId;source_sha=$env:GITHUB_SHA;vm_id=$VmId.ToString();vm_name=$owner.name;root=$Root;generation=$Checkpoint.generation;manifest_sha256=$manifestHash;baseline=($Baseline|Select-Object machineName,machineGuid,programPath,programVersion,documentSha256,preferences,windowsHideFileExt)}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $transfer -Encoding utf8
    $repo=Join-Path $Root 'transfer-restic';$tools=Join-Path $Root 'transfer-tools';$archive=Join-Path $Root 'transfer-encrypted.zip';$check=Join-Path $Root 'transfer-readback';$receipts=Join-Path $Root 'transfer-receipt'
    foreach($path in @($repo,$tools,$archive,$check,$receipts)){if(Test-Path -LiteralPath $path){throw 'Transfer must not replace an existing output.'}}
    $bytes=(Get-ChildItem -LiteralPath $directory -File -Recurse|Measure-Object Length -Sum).Sum
    if((Get-PSDrive E).Free -lt ($bytes+16GB)){throw 'Encrypted package free space insufficient.'}
    & (Join-Path $PSScriptRoot 'install-restic.ps1') -ToolsRoot $tools | Out-Null
    $restic=Join-Path $tools 'restic.exe'
    & $restic --repo $repo init | ForEach-Object {Write-Host $_}
    if($LASTEXITCODE -ne 0){throw 'Isolated transfer repository initialization failed.'}
    $snapshot=Invoke-WindowsStateResticBackup -Restic $restic -Repository $repo -Path $directory -Tag 'devbox-auto'
    & $restic --repo $repo check --read-data | ForEach-Object {Write-Host $_}
    if($LASTEXITCODE -ne 0){throw 'Whole Windows encrypted data check failed.'}
    & $restic --repo $repo restore $snapshot --target $check --include '**/manifest.json' | ForEach-Object {Write-Host $_}
    if($LASTEXITCODE -ne 0){throw 'Encrypted package canary restore failed.'}
    $canaries=@(Get-ChildItem -LiteralPath $check -Recurse -File -Filter 'manifest.json')
    if($canaries.Count -ne 1 -or (Get-FileHash -LiteralPath $canaries[0].FullName -Algorithm SHA256).Hash.ToLowerInvariant() -cne $manifestHash){throw 'Restored whole VM manifest canary mismatch.'}
    New-Item -ItemType Directory -Path $receipts | Out-Null
    $receiptPath=Join-Path $receipts 'DEVBOX-VERIFIED-RECEIPT.json'
    @{version=1;snapshotId=$snapshot;canaryHash=$manifestHash}|ConvertTo-Json|Set-Content -LiteralPath $receiptPath -Encoding utf8
    $receiptId=Invoke-WindowsStateResticBackup -Restic $restic -Repository $repo -Path $receiptPath -Tag 'devbox-verified-receipt-v1'
    [IO.Compression.ZipFile]::CreateFromDirectory($repo,$archive,[IO.Compression.CompressionLevel]::NoCompression,$false)
    $archiveBytes=(Get-Item -LiteralPath $archive).Length
    if($archiveBytes -gt 8GB -or (Get-ChildItem -LiteralPath $repo -File -Recurse|Measure-Object Length -Sum).Sum -gt 8GB){throw 'Whole Windows encrypted package exceeds existing8GiB transport.'}
    $raw=& python (Join-Path $PSScriptRoot 'cloud_checkpoint.py') publish --repository $env:GITHUB_REPOSITORY --channel $channel --archive $archive --restic-exe $restic --snapshot-id $snapshot --receipt-id $receiptId
    if($LASTEXITCODE -ne 0){throw 'Encrypted whole Windows publication/readback failed; no accepted Finish receipt.'}
    $accepted=($raw -join "`n")|ConvertFrom-Json
    if($accepted.snapshot_id -cne $snapshot -or $accepted.receipt_snapshot_id -cne $receiptId){throw 'Published transfer snapshot identity mismatch.'}
    [pscustomobject]@{generation=$accepted.generation;vmId=$VmId.ToString();producerHost=$outerId;archiveBytes=$archiveBytes;snapshotId=$snapshot;published=$true;freshHostRestored=$false}
}

function Restore-WindowsStateRoundtrip {
    param([Parameter(Mandatory)][string]$ExpectedGeneration)
    if($ExpectedGeneration -cnotmatch '^devbox-checkpoint-v1-ci-([1-9][0-9]*)-([1-9][0-9]*)-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{32}$'){throw 'Only an exact isolated CI generation can be restored.'}
    $producerRun=$Matches[1];$producerAttempt=$Matches[2]
    Assert-WindowsStateRoundtripContext
    if($producerRun -ceq $env:GITHUB_RUN_ID){throw 'Consumer must be an independent run.'}
    $raw=& gh api ('repos/'+$env:GITHUB_REPOSITORY+'/actions/runs/'+$producerRun)
    if($LASTEXITCODE -ne 0){throw 'Producer completion cannot be verified.'}
    $producer=($raw -join "`n")|ConvertFrom-Json
    if($producer.status -cne 'completed' -or $producer.conclusion -cne 'success' -or [string]$producer.run_attempt -cne $producerAttempt -or $producer.event -cne 'workflow_dispatch' -or $producer.path -cne '.github/workflows/windows-state-probe-validate.yml' -or $producer.head_sha -cne $env:GITHUB_SHA){throw 'Producer must have completed successfully on the exact consumer revision.'}
    . (Join-Path $PSScriptRoot 'windows-state-checkpoint.ps1')
    . (Join-Path $PSScriptRoot 'windows-state-fixture.ps1')
    & (Join-Path $PSScriptRoot 'bootstrap.ps1') -CloudCandidate
    if(-not $?){throw 'Isolated E bootstrap failed.'}
    $work='E:/DevBox/Tools/WindowsStateProbe/probe-'+$env:GITHUB_RUN_ID+'-'+$env:GITHUB_RUN_ATTEMPT
    $policy=Test-WindowsStateProbeHost -Root $work -VmName ('DevBoxWindowsState-'+$env:GITHUB_RUN_ID+'-'+$env:GITHUB_RUN_ATTEMPT)
    if(-not $policy.eligible){throw $policy.reason}
    New-Item -ItemType Directory -Path $work | Out-Null
    $tools=Join-Path $work 'tools';$archive=Join-Path $work 'recovered-encrypted.zip';$repo=Join-Path $work 'restic';$restored=Join-Path $work 'restored'
    & (Join-Path $PSScriptRoot 'install-restic.ps1') -ToolsRoot $tools | Out-Null
    $restic=Join-Path $tools 'restic.exe'
    $raw=& python (Join-Path $PSScriptRoot 'windows_state_transfer.py') fetch --generation $ExpectedGeneration --archive $archive --restic-exe $restic
    if($LASTEXITCODE -ne 0){throw 'Exact encrypted recovery refused; no VM created.'}
    $accepted=($raw -join "`n")|ConvertFrom-Json
    [IO.Compression.ZipFile]::ExtractToDirectory($archive,$repo)
    & $restic --repo $repo restore $accepted.snapshot_id --target $restored | ForEach-Object {Write-Host $_}
    if($LASTEXITCODE -ne 0){throw 'Whole guest files restore failed; no VM created.'}
    $records=@(Get-ChildItem -LiteralPath $restored -Recurse -File -Filter 'WINDOWS-STATE-TRANSFER.json')
    if($records.Count -ne 1){throw 'Whole guest transfer record missing/ambiguous.'}
    $systemProduct=Get-CimInstance Win32_ComputerSystemProduct -ErrorAction Stop
    $outerId=([guid]$systemProduct.UUID).ToString()
    $raw=& python (Join-Path $PSScriptRoot 'windows_state_transfer.py') verify-record --generation $ExpectedGeneration --record $records[0].FullName --host $outerId --run $env:GITHUB_RUN_ID
    if($LASTEXITCODE -ne 0){throw 'Fresh-host/source/fixture identity verification refused.'}
    $record=($raw -join "`n")|ConvertFrom-Json
    if($record.source_sha -cne $env:GITHUB_SHA){throw 'Encrypted producer revision mismatch.'}
    $originalDirectory=Split-Path $records[0].FullName -Parent
    if((Split-Path $originalDirectory -Leaf) -cne $record.generation){throw 'Recovered checkpoint generation path mismatch.'}
    $manifest=Join-Path $originalDirectory 'manifest.json'
    if((Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash.ToLowerInvariant() -cne $record.manifest_sha256){throw 'Recovered checkpoint manifest canary mismatch.'}
    $root=$record.root;$name=$record.vm_name;$id=[guid]$record.vm_id
    $policy=Test-WindowsStateProbeHost -Root $root -VmName $name
    if(-not $policy.eligible){throw $policy.reason}
    if(Get-VM -Id $id -ErrorAction SilentlyContinue){throw 'Existing VM identity must not be replaced.'}
    New-Item -ItemType Directory -Path (Join-Path $root 'checkpoints') -Force | Out-Null
    $directory=Join-Path $root ('checkpoints/'+$record.generation)
    Move-Item -LiteralPath $originalDirectory -Destination $directory -ErrorAction Stop
    @{schema=1;root=$root;name=$name;vmId=$id.ToString();status='created'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'probe-owner.json') -Encoding utf8
    try {
        $vm=Import-WindowsStateCheckpoint -Root $root -VmId $id -ExportPath (Join-Path $directory 'payload') -ManifestPath (Join-Path $directory 'manifest.json')
        Start-VM -VM $vm -ErrorAction Stop
        $credential=Get-WindowsStatePortableFixtureCredential -VmId $id
        $session=$null;$deadline=[DateTime]::UtcNow.AddMinutes(5)
        do {try{$session=New-PSSession -VMId $id -Credential $credential -ErrorAction Stop}catch{Start-Sleep -Seconds 10}}while(-not $session -and [DateTime]::UtcNow -lt $deadline)
        if(-not $session){throw 'Fresh Windows boot/guest authentication did not become ready.'}
        try {
            $actual=Get-WindowsStateFixture -GuestSession $session -VmId $id
            foreach($property in @('machineName','machineGuid','programPath','programVersion','documentSha256','windowsHideFileExt')){if($actual.$property -cne $record.baseline.$property){throw ('Fresh-host fixture mismatch: '+$property)}}
            if($actual.preferences.theme -cne $record.baseline.preferences.theme -or $actual.preferences.volume -ne $record.baseline.preferences.volume){throw 'Fresh-host application preferences mismatch.'}
        } finally {Remove-PSSession $session}
        [pscustomobject]@{generation=$ExpectedGeneration;vmId=$id.ToString();producerHost=$record.producer_host;consumerHost=$outerId;sourceRun=$record.producer_run;consumerRun=$env:GITHUB_RUN_ID;boot=$true;program=$actual.programVersion;documentSha256=$actual.documentSha256;preferences=$actual.preferences;windowsHideFileExt=$actual.windowsHideFileExt;machineGuid=$actual.machineGuid;freshHostRestored=$true}
    } finally {
        if(Get-VM -Id $id -ErrorAction SilentlyContinue){Remove-WindowsStateProbe -Root $root -VmName $name}
    }
}
