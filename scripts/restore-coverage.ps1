# restore-coverage.ps1 — compare restored working data against saved manifest.
# No source file names, secrets, or contents printed to public Actions logs.
Set-StrictMode -Version Latest

function Assert-DevBoxRestoreCoverage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ResticExe,
          [Parameter(Mandatory)][string]$Repo,
          [Parameter(Mandatory)][string]$SnapshotId,
          [Parameter(Mandatory)][string]$WorkspaceRoot)
    $lines = @(& $ResticExe --repo $Repo ls --json $SnapshotId 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'Restic restore metadata could not be listed.' }
    $expected = @{ Projects=0; Workspace=0; PersistentData=0 }
    $observedNodes = 0
    foreach ($line in $lines) {
        $obj = $null
        try { $obj = ([string]$line) | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        if ([string]$obj.type -ne 'file') { continue }
        $observedNodes++
        $p = ([string]$obj.path).Replace('\\','/').ToLowerInvariant()
        foreach ($name in @('Projects','Workspace','PersistentData')) {
            if ($p -match ('(^|/)devbox/' + $name.ToLowerInvariant() + '/')) {
                $expected[$name]++
            }
        }
    }
    if ($observedNodes -eq 0) { throw 'Snapshot file manifest is empty; restored project content cannot be verified.' }
    $actual = @{}
    foreach ($name in @('Projects','Workspace','PersistentData')) {
        $path = Join-Path $WorkspaceRoot $name
        $actual[$name] = if (Test-Path -LiteralPath $path -PathType Container) {
            @(Get-ChildItem -LiteralPath $path -Recurse -File -Force -ErrorAction Stop).Count
        } else { 0 }
        Write-Output "RESTORED COVERAGE $name expected=$($expected[$name]) on-disk=$($actual[$name])" | Out-Host
        if ($expected[$name] -gt 0 -and $actual[$name] -eq 0) {
            throw "Snapshot contains $name files but the restored $name directory is empty."
        }
    }
    if ($expected.Projects -eq 0) {
        Write-Output 'RESTORED COVERAGE WARNING: selected snapshot contains no DevBox Projects files; it cannot recover missing historical project data.' | Out-Host
    }
    if ($expected.PersistentData -eq 0) {
        Write-Output 'RESTORED COVERAGE WARNING: selected snapshot contains no DevBox PersistentData files.' | Out-Host
    }
    $record = [ordered]@{
        utc=[DateTime]::UtcNow.ToString('o')
        snapshotId=$SnapshotId
        savedFileCounts=$expected
        restoredFileCounts=$actual
    } | ConvertTo-Json -Depth 5
    $report = Join-Path $WorkspaceRoot 'Logs\restore-coverage.json'
    $reportDir = Split-Path $report -Parent
    if (-not (Test-Path -LiteralPath $reportDir)) {
        New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    }
    Set-Content -LiteralPath $report -Value $record -Encoding utf8
}
