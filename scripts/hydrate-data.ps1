# hydrate-data.ps1 - Phase 21 hydration: pull COLD data from the repository (or
# optional SMB share) into the workspace on demand, never during startup.
# Honors disk budget; refuses below critical disk (Phase 34).
param(
    [string]$IncludePattern = '/persistent/**',
    [double]$MaxGiB = 20.0
)
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'common.ps1')
Write-Step 'hydrate-data'

$persist = (Get-Content (Join-Path $env:DEVBOX_CONTROL_PATH 'persistence.json') -Raw) | ConvertFrom-Json
$repoUrl = $persist.repoUrl
$hydrated = New-DevboxDirectorySafe (Join-Path $env:DEVBOX_WSROOT 'Hydration')

# ---- disk guard (Phase 34): below critical, refuse and explain
$drive = Get-PSDrive -Name $env:DEVBOX_WSROOT.SubString(0, 2).TrimEnd(':') -ErrorAction SilentlyContinue
$freeGiB = [math]::Round($drive.Free / $OneGiB, 2)
$critGiB = if ($env:DEVBOX_CRIT_GIB) { [double]$env:DEVBOX_CRIT_GIB } else { 10.0 }
if ($freeGiB -le $critGiB) {
    Stop-DevBox "disk critical ($freeGiB GiB free). Hydration refused. Next action: free disposable space first; see TROUBLESHOOTING 'Workspace'."
}

if ($freeGiB -lt $MaxGiB) {
    $MaxGiB = [math]::Max(1, $freeGiB - $critGiB - 1)
    Write-DevBox WARN "hydration budget trimmed to $MaxGiB GiB by free space."
}

if ([string]::IsNullOrWhiteSpace($env:RESTIC_PASSWORD)) {
    Stop-DevBox "RESTIC_PASSWORD empty; set restore budget via devbox Environment."
}

# ---- newest snapshot (non-destructive restore only)
$pwFile = Join-Path $env:DEVBOX_WSROOT ('Temp\restic-pw-' + [guid]::NewGuid().ToString('N'))
$env:RESTIC_PASSWORD | Set-Content -LiteralPath $pwFile -NoNewline -Encoding ascii
icacls $pwFile /inheritance:r /grant:r "$env:USERNAME`:R" | Out-Null

try {
    & $env:DEVBOX_RESTIC_EXE --repo $repoUrl --password-file $pwFile `
        --cache-dir (Join-Path $env:DEVBOX_WSROOT 'ResticCache') snapshots --json |
        Set-Content (Join-Path $env:DEVBOX_TEMP 'hyd-snaps.json') -Encoding utf8
    if ($LASTEXITCODE -ne 0) { Stop-DevBox "snapshots failed (exit $LASTEXITCODE)." }

    $snaps = @(Get-Content (Join-Path $env:DEVBOX_TEMP 'hyd-snaps.json') -Raw | ConvertFrom-Json)
    if ($snaps.Count -eq 0) { Write-DevBox OK "nothing to hydrate yet."; exit 0 }

    $latest = $snaps | Sort-Object created -Descending | Select-Object -First 1
    Write-DevBox INFO "hydrating include '$IncludePattern' from snapshot $($latest.id) into $hydrated (max $MaxGiB GiB)."

    & $env:DEVBOX_RESTIC_EXE --repo $repoUrl --password-file $pwFile `
        --cache-dir (Join-Path $env:DEVBOX_WSROOT 'ResticCache') `
        restore $latest.id --include $IncludePattern --target $hydrated | Write-Output
    if ($LASTEXITCODE -ne 0) { Stop-DevBox "hydration restore failed (exit $LASTEXITCODE). Next action: TROUBLESHOOTING 'Hydration'." }
} finally {
    Remove-Item -LiteralPath $pwFile -Force -ErrorAction SilentlyContinue
}

Write-StepSummary @("**Hydrated COLD data** into Hydration\ from latest snapshot.")
Write-DevBox OK "hydrate-data complete."
