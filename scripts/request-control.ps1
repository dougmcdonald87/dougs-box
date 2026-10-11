# request-control.ps1 — invoked by a shortcut in the interactive RDP session.
# Never holds backup passwords and never terminates Windows or GitHub directly.
param([Parameter(Mandatory)][ValidateSet('save','stop')][string]$Action)
$ErrorActionPreference = 'Stop'

function End-Interactive([int]$Code) {
    if (-not $env:DEVBOX_CONTROL_NONINTERACTIVE) {
        [void](Read-Host 'Press Enter to close this window')
    }
    exit $Code
}
try {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $controlPath = Join-Path $root 'Control'
    if (-not (Test-Path -LiteralPath (Join-Path $controlPath 'session.json') -PathType Leaf)) {
        throw 'This DevBox session has not started. Do not use GitHub Cancel to save work.'
    }
    $commands = Join-Path $controlPath 'Commands'
    if (-not (Test-Path -LiteralPath $commands -PathType Container)) {
        throw 'The DevBox command receiver is not ready.'
    }
    $nonce = [guid]::NewGuid().ToString('N')
    $request = Join-Path $commands "$Action-$nonce.request"
    $temp = Join-Path $commands "$Action-$nonce.tmp"
    $response = Join-Path $commands "$Action-$nonce.result.json"

    if ($Action -eq 'stop') {
        Write-Host 'Requesting a VERIFIED backup, then a clean DevBox shutdown.'
        Write-Host 'If the backup fails, DevBox must remain running.'
    } else {
        Write-Host 'Requesting an immediate verified backup to dedicated Lenovo storage.'
    }
    Set-Content -LiteralPath $temp -Value "Requested $Action at $([DateTime]::UtcNow.ToString('o'))" -Encoding utf8
    Move-Item -LiteralPath $temp -Destination $request -ErrorAction Stop

    $deadline = [DateTime]::UtcNow.AddMinutes(5)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath $response -PathType Leaf) {
            $result = Get-Content -LiteralPath $response -Raw | ConvertFrom-Json -ErrorAction Stop
            if ([string]$result.id -ne $nonce -or [string]$result.action -ne $Action) {
                throw 'Command result ID does not match request.'
            }
            if ($result.success -eq $true -and -not [string]::IsNullOrWhiteSpace([string]$result.snapshotId)) {
                Write-Host "SUCCESS: Verified restic snapshot $($result.snapshotId)"
                if ($Action -eq 'stop') {
                    Write-Host 'DevBox is shutting down. Your Remote Desktop connection will disconnect.'
                } else {
                    Write-Host 'DevBox remains running.'
                }
                End-Interactive 0
            }
            Write-Host "FAILED: $($result.detail)"
            Write-Host 'Do NOT cancel the GitHub run; the previous snapshot may be all that is safe.'
            End-Interactive 2
        }
        Start-Sleep -Seconds 3
    }
    Write-Host 'NO CONFIRMATION within five minutes. Do not assume backup succeeded.'
    Write-Host 'Inspect the active GitHub run and last-backup.json before stopping.'
    End-Interactive 2
} catch {
    Write-Host "DEVBOX CONTROL ERROR: $($_.Exception.Message)"
    End-Interactive 2
}
