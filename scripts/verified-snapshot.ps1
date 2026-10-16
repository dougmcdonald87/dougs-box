# verified-snapshot.ps1 — choose only snapshots with a durable post-proof
# receipt. The receipt is its OWN encrypted Restic snapshot, so it needs no
# mutation/deletion of existing snapshot metadata on an append-only server.
Set-StrictMode -Version Latest

function Test-DevBoxSnapshotHasTag {
    param([Parameter(Mandatory)][object]$Snapshot,
          [Parameter(Mandatory)][string]$Tag)
    $prop = $Snapshot.PSObject.Properties['tags']
    return ($null -ne $prop -and @($prop.Value) -contains $Tag)
}

function Select-DevBoxVerifiedSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResticExe,
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][object[]]$Snapshots,
        [Parameter(Mandatory)][string]$TempRoot,
        [string]$ExpectedReceiptId='',
        [string]$ExpectedSnapshotId=''
    )
    $tag = 'devbox-verified-receipt-v1'
    $receipts = @($Snapshots | Where-Object { Test-DevBoxSnapshotHasTag -Snapshot $_ -Tag $tag } |
        Sort-Object { [DateTime]::Parse([string]$_.time) } -Descending)
    if ($ExpectedReceiptId) {
        $receipts=@($receipts | Where-Object { [string]$_.id -ceq $ExpectedReceiptId })
        if ($receipts.Count -ne 1 -or $ExpectedSnapshotId -cnotmatch '^[0-9a-f]{64}$') { throw 'Accepted cloud snapshot identities missing.' }
    }
    if ($receipts.Count -eq 0) {
        # The single known-good pre-receipt backup is grounded in job #14's
        # restored canary log, not inferred merely from a snapshot listing.
        # Do not silently select an arbitrary newer unverified snapshot.
        $knownGood = '95d29cdb465a966ab247c52a642953f0eb0c52d1a3ace91d6111a80ffe29bfbc'
        $legacy = @($Snapshots | Where-Object { [string]$_.id -eq $knownGood })
        if ($legacy.Count -ne 1) {
            throw 'No verified receipt found, and known verified legacy snapshot is absent. Automatic restore refused.'
        }
        Write-Output 'LEGACY VERIFIED BACKUP: selecting exact snapshot proven by run 14 canary log.' | Out-Host
        return $legacy[0]
    }
    $receipt = $receipts[0]
    $stage = Join-Path $TempRoot ('receipt-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    try {
        & $ResticExe --repo $Repo restore ([string]$receipt.id) --target $stage 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Verified-receipt snapshot could not be restored.' }
        $files = @(Get-ChildItem -LiteralPath $stage -Recurse -File -Filter 'DEVBOX-VERIFIED-RECEIPT.json' -ErrorAction Stop)
        if ($files.Count -ne 1) { throw 'Verified receipt is missing or ambiguous.' }
        $proof = Get-Content -LiteralPath $files[0].FullName -Raw | ConvertFrom-Json -ErrorAction Stop
        if ($ExpectedSnapshotId -and [string]$proof.snapshotId -cne $ExpectedSnapshotId) { throw 'Cloud manifest and encrypted receipt disagree.' }
        if ($proof.version -ne 1 -or
            [string]$proof.snapshotId -cnotmatch '^[0-9a-f]{64}$' -or
            [string]$proof.canaryHash -cnotmatch '^[0-9A-Fa-f]{64}$') {
            throw 'Verified receipt has malformed proof fields.'
        }
        $verified = @($Snapshots | Where-Object {
            [string]$_.id -eq [string]$proof.snapshotId -and
            (Test-DevBoxSnapshotHasTag -Snapshot $_ -Tag 'devbox-auto')
        })
        if ($verified.Count -ne 1) {
            throw 'Receipt points to a missing or non-DevBox snapshot. Restore refused.'
        }
        return $verified[0]
    } finally {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}
