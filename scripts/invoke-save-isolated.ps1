# invoke-save-isolated.ps1 — isolate Restic verification failures from RDP lifetime.
# Child PowerShell retains current runner environment/secrets, never exports them.
Set-StrictMode -Version Latest

function Invoke-DevBoxBackupIsolated {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SaveScript)

    if (-not (Test-Path -LiteralPath $SaveScript -PathType Leaf)) {
        Write-Warning 'Verified backup script missing; request rejected.'
        return $false
    }
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwsh) { $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue }
    if (-not $pwsh) {
        Write-Warning 'PowerShell 7 binary missing; request rejected.'
        return $false
    }
    try {
        # A terminating JSON parse error or "exit" inside save-state.ps1
        # must end ONLY this child process, not the Actions session manager.
        # Out-Host preserves log output without contaminating the Boolean result.
        & $pwsh.Source -NoLogo -NoProfile -NonInteractive -File $SaveScript 2>&1 |
            Out-Host
        $code = $LASTEXITCODE
        # The nonzero code belongs to the CHILD, not the session manager.
        # The Boolean is the only success/failure result of this wrapper.
        $global:LASTEXITCODE = 0
    } catch {
        $global:LASTEXITCODE = 0
        # Never leak credentials, file contents, or provider stack traces.
        Write-Warning 'Backup child process raised an exception; no verified success.'
        return $false
    }
    if ($code -ne 0) {
        Write-Warning "Backup child process returned exit $code; no verified success."
        return $false
    }
    return $true
}
