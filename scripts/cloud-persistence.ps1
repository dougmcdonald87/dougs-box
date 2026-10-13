# Opt-in cloud destination; existing local save/restore verification remains canonical.
param([Parameter(Mandatory)][ValidateSet('Initialize','Connect','Save')][string]$Mode,
      [switch]$First)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'common.ps1')
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:DEVBOX_PERSISTENCE_BACKEND -cne 'github-release') { Stop-DevBox 'Cloud destination must be explicitly selected on a GitHub runner.' }
if (-not $env:DEVBOX_WSROOT -or -not $env:DEVBOX_CONTROL_PATH -or -not $env:RESTIC_PASSWORD) { Stop-DevBox 'Cloud workspace, controls or backup key unavailable.' }
$workspace=[IO.Path]::GetFullPath($env:DEVBOX_WSROOT).TrimEnd('\')
$allowed=$workspace -match '^[DE]:\\DevBox$'
if ($env:DEVBOX_ISOLATED_TEST -eq '1' -and $env:RUNNER_TEMP) {
    $allowed=$workspace.StartsWith([IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)
}
if (-not $allowed) { Stop-DevBox 'Cloud cache must be inside the selected isolated DevBox workspace.' }
$runtime=New-DevboxDirectorySafe (Join-Path $workspace 'Tools\CloudPersistence')
$repo=Join-Path $runtime 'repository'
$archive=Join-Path $runtime 'encrypted-checkpoint.zip'
$metadata=Join-Path $env:DEVBOX_CONTROL_PATH 'persistence.json'
$receipt=Join-Path $env:DEVBOX_CONTROL_PATH 'last-backup.json'
$channel='production'
if ($env:DEVBOX_ISOLATED_TEST -eq '1') { $channel="ci-$env:GITHUB_RUN_ID-$env:GITHUB_RUN_ATTEMPT" }
$guard=$null
$wasInner=$env:DEVBOX_CLOUD_INNER_SAVE
$wasPending=$env:DEVBOX_CLOUD_PENDING_RECEIPT
$transactionReceipt=$null
$stage='lock'
function Write-CloudState {
    param($AcceptedRecord=$null)
    $value=[ordered]@{backend='github-release';repoUrl=$repo;resticExe=$env:DEVBOX_RESTIC_EXE;channel=$channel}
    if ($AcceptedRecord) {
        $value.snapshotId=$AcceptedRecord.snapshot_id
        $value.receiptSnapshotId=$AcceptedRecord.receipt_snapshot_id
        $value.cloudGeneration=$AcceptedRecord.generation
    }
    $value | ConvertTo-Json -Compress | Set-Content -LiteralPath $metadata -Encoding utf8
    if ($env:GITHUB_ENV) {
        "DEVBOX_RESTIC_EXE=$env:DEVBOX_RESTIC_EXE" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
    }
}
function Install-CloudRestic {
    $tools=Join-Path $workspace 'Tools\restic'
    & (Join-Path $PSScriptRoot 'install-restic.ps1') -ToolsRoot $tools
    if ($LASTEXITCODE -ne 0) { throw 'Pinned Restic installation failed.' }
    $env:DEVBOX_RESTIC_EXE=Join-Path $tools 'restic.exe'
}
try {
    # The entire local-save/package/publish/receipt transaction owns one lock.
    $guard=[IO.File]::Open((Join-Path $runtime 'transaction.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    if ($Mode -eq 'Initialize') {
        if (Test-Path -LiteralPath $repo) { throw 'Explicit initialization refuses an existing repository.' }
        Install-CloudRestic
        & $env:DEVBOX_RESTIC_EXE --repo $repo init | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'New isolated encrypted repository failed to initialize.' }
        Write-CloudState
        Write-DevBox OK 'Explicit cloud migration repository initialized; no existing cloud/home backup altered.'
    } elseif ($Mode -eq 'Connect') {
        if (Test-Path -LiteralPath $repo) { throw 'Startup refuses to overwrite an existing local repository.' }
        Install-CloudRestic
        $raw=& python (Join-Path $PSScriptRoot 'cloud_checkpoint.py') fetch --repository $env:GITHUB_REPOSITORY --channel $channel --archive $archive --restic-exe $env:DEVBOX_RESTIC_EXE
        if ($LASTEXITCODE -ne 0) { throw 'No verified cloud generation; refusing empty startup.' }
        $record=($raw | Out-String) | ConvertFrom-Json
        if ($env:DEVBOX_CLOUD_EXPECTED_GENERATION -and $record.generation -cne $env:DEVBOX_CLOUD_EXPECTED_GENERATION) { throw 'Recovered generation differs from expected candidate.' }
        # Bind hashing and extraction to the same deny-write Windows handle.
        $file=[IO.File]::Open($archive,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        try {
            $sha=[Security.Cryptography.SHA256]::Create()
            try { $actual=[Convert]::ToHexString($sha.ComputeHash($file)).ToLowerInvariant() } finally { $sha.Dispose() }
            if ($actual -cne $record.sha256) { throw 'Cloud archive changed before installation.' }
            $file.Position=0
            $zip=[IO.Compression.ZipArchive]::new($file,[IO.Compression.ZipArchiveMode]::Read,$true)
            try {
                New-Item -ItemType Directory -Path $repo | Out-Null
                foreach ($entry in $zip.Entries) {
                    $target=Join-Path $repo $entry.FullName
                    if ($entry.FullName.EndsWith('/')) { New-Item -ItemType Directory -Path $target -Force | Out-Null }
                    else {
                        New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
                        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$target,$false)
                    }
                }
            } finally { $zip.Dispose() }
        } finally { $file.Dispose() }
        & $env:DEVBOX_RESTIC_EXE --repo $repo check --read-data | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Installed encrypted repository failed verification.' }
        Write-CloudState -AcceptedRecord $record
        Write-DevBox OK 'Cloud generation cryptographically checked; existing restore can now import C and workspace state.'
    } else {
        $stage='local-save'
        if (-not (Test-Path -LiteralPath $metadata)) { throw 'Cloud connection metadata missing.' }
        $state=Get-Content -LiteralPath $metadata -Raw | ConvertFrom-Json
        if ($state.backend -cne 'github-release' -or $state.repoUrl -ine $repo -or $state.channel -cne $channel) { throw 'Cloud repository metadata mismatch.' }
        $transactionReceipt=Join-Path $runtime ('pending-'+[guid]::NewGuid().ToString('N')+'.json')
        $env:DEVBOX_CLOUD_PENDING_RECEIPT=$transactionReceipt
        $env:DEVBOX_CLOUD_INNER_SAVE='1'
        $arguments=@('-NoLogo','-NoProfile','-NonInteractive','-File',(Join-Path $PSScriptRoot 'save-state.ps1'))
        if ($First) { $arguments+='-First' }
        & pwsh @arguments
        if ($LASTEXITCODE -ne 0) { throw 'Existing verified local save failed.' }
        $local=Get-Content -LiteralPath $transactionReceipt -Raw | ConvertFrom-Json
        if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
        [IO.Compression.ZipFile]::CreateFromDirectory($repo,$archive)
        $stage='cloud-publication'
        $archiveGuard=[IO.File]::Open($archive,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        try {
            $raw=& python (Join-Path $PSScriptRoot 'cloud_checkpoint.py') publish --repository $env:GITHUB_REPOSITORY --channel $channel --archive $archive --restic-exe $env:DEVBOX_RESTIC_EXE --snapshot-id $local.snapshotId --receipt-id $local.receiptSnapshotId
            $publishExit=$LASTEXITCODE
        } finally { $archiveGuard.Dispose() }
        if ($publishExit -ne 0) { throw 'Cloud publication/readback failed; no successful receipt.' }
        $record=($raw | Out-String) | ConvertFrom-Json
        $stage='commit-receipt'
        if ($record.snapshot_id -cne $local.snapshotId -or $record.receipt_snapshot_id -cne $local.receiptSnapshotId) { throw 'Published snapshot receipt mismatch.' }
        $local | Add-Member -NotePropertyName cloudVerified -NotePropertyValue $true -Force
        $local | Add-Member -NotePropertyName cloudGeneration -NotePropertyValue $record.generation -Force
        $local | Add-Member -NotePropertyName cloudChannel -NotePropertyValue $channel -Force
        $local | ConvertTo-Json -Compress | Set-Content -LiteralPath $transactionReceipt -Encoding utf8
        if (Test-Path -LiteralPath $receipt) { [IO.File]::Replace($transactionReceipt,$receipt,$null) }
        else { [IO.File]::Move($transactionReceipt,$receipt) }
        Write-DevBox OK 'Cloud save published and read back; existing Save/Finish receipt contract satisfied.'
    }
} catch {
    # Static stage and exception type only: never emit raw exception messages.
    $kind=$_.Exception.GetType().Name
    if ($_.Exception.InnerException) { $kind=$_.Exception.InnerException.GetType().Name }
    Write-DevBox WARN ("Cloud failure stage=$stage; type=$kind")
    Write-DevBox WARN 'Cloud operation failed; no cloud success claimed. Previous cloud generations are retained.'
    $global:LASTEXITCODE=2
    exit 2
} finally {
    $env:DEVBOX_CLOUD_INNER_SAVE=$wasInner
    $env:DEVBOX_CLOUD_PENDING_RECEIPT=$wasPending
    if ($transactionReceipt) { Remove-Item -LiteralPath $transactionReceipt -Force -ErrorAction SilentlyContinue }
    if ($guard) { $guard.Dispose() }
}
$global:LASTEXITCODE=0
exit 0
