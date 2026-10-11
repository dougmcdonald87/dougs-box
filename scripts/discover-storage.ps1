# discover-storage.ps1 - Phase 8 storage discovery with machine-readable result.
# Probes every fixed writable volume, write/delete-tests candidates meeting the
# binary-GiB threshold, prefers non-system drive then most free, NEVER assumes D:.
param(
    [double]$RequiredGiB = 100.0
)
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'common.ps1')
Write-Step 'discover-storage'

$result = [ordered]@{
    requiredGiB = $RequiredGiB
    probeUtc    = (Get-Date).ToUniversalTime().ToString('o')
    volumes     = @()
    selected    = $null
    verdict     = 'FAIL'
    fastRoot    = $null
}

foreach ($v in (Get-CimInstance Win32_LogicalDisk -Filter 'DriveType = 3')) {
    $root = $v.DeviceID
    $freeGiB  = [math]::Round($v.FreeSpace / $OneGiB, 2)
    $totalGiB = [math]::Round($v.Size / $OneGiB, 2)
    $isSystem = ($root -like 'C:*')

    $writable = $false
    if ($v.FreeSpace -ge (ConvertTo-PackedBytes $RequiredGiB)) {
        # Phase 8: prove writability with a write/delete test, never assume it.
        $probe = Join-Path $root ('.devbox-write-test-' + [guid]::NewGuid().ToString('N'))
        try {
            Set-Content -LiteralPath $probe -Value 'write-test' -Encoding ascii -ErrorAction Stop
            Remove-Item -LiteralPath $probe -Force -ErrorAction Stop
            $writable = $true
        } catch {
            Write-DevBox WARN "volume $root failed write/delete test: $($_.Exception.Message)"
        }
    }

    $result.volumes += [ordered]@{
        root = $root
        totalGiB = $totalGiB
        freeGiB = $freeGiB
        isSystem = $isSystem
        writable = $writable
        qualifies = $writable
    }
}

# Non-system first (stable), most free inside each group.
$candidates = @($result.volumes | Where-Object { $_.qualifies -and -not $_.isSystem } |
    Sort-Object freeGiB -Descending)
if ($candidates.Count -eq 0) {
    $candidates = @($result.volumes | Where-Object { $_.qualifies } | Sort-Object freeGiB -Descending)
}

$outPath = Join-Path (Split-Path $PSScriptRoot) 'storage-probe-result.json'

if ($candidates.Count -gt 0) {
    $result.selected = $candidates[0].root
    $result.verdict  = 'OK'
    $result.fastRoot = $candidates[0].root
    $result | ConvertTo-Json -Depth 4 | Set-Content $outPath -Encoding utf8
    Write-DevBox OK "selected workspace $($result.fastRoot) ($($candidates[0].freeGiB) GiB free)"
    if ($env:GITHUB_OUTPUT) {
        "fastRoot=$($result.fastRoot)" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding ascii
    }
    exit 0
}

$result | ConvertTo-Json -Depth 4 | Set-Content $outPath -Encoding utf8
$probe = ($result.volumes | ForEach-Object { "$($_.root) free $($_.freeGiB) GiB writable $($_.writable)" }) -join '; '
Stop-DevBox "DEVBOX FAILED: NO >=$RequiredGiB GiB WORKSPACE. Probe: $probe"
