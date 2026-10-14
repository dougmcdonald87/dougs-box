# Real small-file crypto integration only; this is not Windows/VM recovery evidence.
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:DEVBOX_ISOLATED_TEST -cne '1' -or -not $env:RUNNER_TEMP){throw 'Disposable CI fixture only.'}
. (Join-Path $PSScriptRoot '../scripts/windows-state-roundtrip.ps1')
$root=Join-Path $env:RUNNER_TEMP ('windows-state-package-'+[guid]::NewGuid().ToString('N'))
if(Test-Path -LiteralPath $root){throw 'Occupied package fixture refused.'}
New-Item -ItemType Directory -Path $root | Out-Null
$previous=$env:RESTIC_PASSWORD
try {
    $env:RESTIC_PASSWORD=[Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
    Write-Host ('::add-mask::'+$env:RESTIC_PASSWORD)
    $tools=Join-Path $root 'tools';$repo=Join-Path $root 'repo';$data=Join-Path $root 'data';$readback=Join-Path $root 'readback';$receipts=Join-Path $root 'receipts'
    & (Join-Path $PSScriptRoot '../scripts/install-restic.ps1') -ToolsRoot $tools | ForEach-Object {Write-Host $_}
    $restic=Join-Path $tools 'restic.exe'
    New-Item -ItemType Directory -Path $data,$receipts | Out-Null
    $manifest=Join-Path $data 'manifest.json'
    [IO.File]::WriteAllText($manifest,'{"fixture":"small crypto test only"}',[Text.UTF8Encoding]::new($false))
    $expected=(Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash
    & $restic --repo $repo init | ForEach-Object {Write-Host $_}
    if($LASTEXITCODE -ne 0){throw 'Fixture repository initialization failed.'}
    $snapshot=Invoke-WindowsStateResticBackup -Restic $restic -Repository $repo -Path $data -Tag 'devbox-auto'
    & $restic --repo $repo check --read-data | ForEach-Object {Write-Host $_}
    if($LASTEXITCODE -ne 0){throw 'Fixture encrypted data check failed.'}
    & $restic --repo $repo restore $snapshot --target $readback --include '**/manifest.json' | ForEach-Object {Write-Host $_}
    if($LASTEXITCODE -ne 0){throw 'Fixture canary restore failed.'}
    $files=@(Get-ChildItem -LiteralPath $readback -Recurse -File -Filter 'manifest.json')
    if($files.Count -ne 1 -or (Get-FileHash -LiteralPath $files[0].FullName -Algorithm SHA256).Hash -cne $expected){throw 'Fixture canary content mismatch.'}
    $receipt=Join-Path $receipts 'DEVBOX-VERIFIED-RECEIPT.json'
    @{version=1;snapshotId=$snapshot;canaryHash=$expected}|ConvertTo-Json|Set-Content -LiteralPath $receipt -Encoding utf8
    $receiptId=Invoke-WindowsStateResticBackup -Restic $restic -Repository $repo -Path $receipt -Tag 'devbox-verified-receipt-v1'
    $archive=Join-Path $root 'encrypted.zip'
    [IO.Compression.ZipFile]::CreateFromDirectory($repo,$archive,[IO.Compression.CompressionLevel]::NoCompression,$false)
    & python -c "import sys;sys.path.insert(0,sys.argv[1]);from cloud_checkpoint import crypto_verify;assert crypto_verify(sys.argv[2],sys.argv[3],{'snapshot_id':sys.argv[4],'receipt_snapshot_id':sys.argv[5]});print('REAL SMALL-FILE ENCRYPTED PACKAGE + CANARY + DURABLE RECEIPT CRYPTO VERIFY: PASS')" (Join-Path $PSScriptRoot '../scripts') $archive $restic $snapshot $receiptId | ForEach-Object {Write-Host $_}
    if($LASTEXITCODE -ne 0){throw 'Actual package/receipt cryptographic verifier refused fixture.'}
} finally {$env:RESTIC_PASSWORD=$previous}
