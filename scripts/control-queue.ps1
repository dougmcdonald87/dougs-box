# control-queue.ps1 — process local, allowlisted RDP desktop commands.
# This is dot-sourced by session-manager. No network endpoint or credentials.
Set-StrictMode -Version Latest

function Invoke-DevBoxControlRequests {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ControlPath,
        [Parameter(Mandatory)][scriptblock]$VerifiedSave
    )

    $commandsDir = Join-Path $ControlPath 'Commands'
    if (-not (Test-Path -LiteralPath $commandsDir -PathType Container)) {
        return $false
    }
    $pending = @(Get-ChildItem -LiteralPath $commandsDir -File -Filter '*.request' |
        Sort-Object @{Expression = { if ($_.Name -like 'stop-*') { 0 } else { 1 } }}, Name)

    foreach ($file in $pending) {
        if ($file.Name -cnotmatch '^(save|stop)-([0-9a-f]{32})\.request$') {
            # Refuse unknown command names. Never interpret file contents as code.
            continue
        }
        $action = $Matches[1]
        $nonce = $Matches[2]
        $metadataFile = Join-Path $ControlPath 'last-backup.json'
        $before = ''
        if (Test-Path -LiteralPath $metadataFile -PathType Leaf) {
            $before = Get-Content -LiteralPath $metadataFile -Raw
        }
        $saveReturned = $false
        $reason = ''
        try {
            # This callback invokes the same verified restic backup as the timer.
            $values = @(& $VerifiedSave $action)
            $saveReturned = ($values.Count -gt 0 -and $values[-1] -eq $true)
        } catch {
            $reason = "Backup threw an exception: $($_.Exception.Message)"
        }

        $after = ''
        $snapshotId = ''
        if (Test-Path -LiteralPath $metadataFile -PathType Leaf) {
            $after = Get-Content -LiteralPath $metadataFile -Raw
        }
        if ($saveReturned -and $after -ne $before -and -not [string]::IsNullOrWhiteSpace($after)) {
            try {
                $data = $after | ConvertFrom-Json -ErrorAction Stop
                if (-not [string]::IsNullOrWhiteSpace([string]$data.snapshotId) -and
                    -not [string]::IsNullOrWhiteSpace([string]$data.utc)) {
                    $snapshotId = [string]$data.snapshotId
                }
            } catch {
                $reason = 'Verified snapshot metadata was malformed.'
            }
        }

        $ok = -not [string]::IsNullOrWhiteSpace($snapshotId)
        if (-not $ok -and -not $reason) {
            $reason = 'No NEW verified snapshot metadata. DevBox remains running.'
        }

        $responseFile = Join-Path $commandsDir "$action-$nonce.result.json"
        $tmpFile = Join-Path $commandsDir "$action-$nonce.result.tmp"
        [ordered]@{
            action     = $action
            id         = $nonce
            success    = $ok
            snapshotId = $snapshotId
            detail     = $(if ($ok) { 'Verified backup completed.' } else { $reason })
            utc        = [DateTime]::UtcNow.ToString('o')
        } | ConvertTo-Json -Compress | Set-Content -LiteralPath $tmpFile -Encoding utf8 -ErrorAction Stop
        Move-Item -LiteralPath $tmpFile -Destination $responseFile -ErrorAction Stop
        Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop

        if ($action -eq 'stop' -and $ok) {
            # Only now may the manager return/exit; never stop on a failed save.
            return $true
        }
    }
    return $false
}
