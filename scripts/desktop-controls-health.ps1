# desktop-controls-health.ps1 — real shortcut target checks and repair.
# Public Desktop is merged into RDP users' desktops; never call remote APIs.
Set-StrictMode -Version Latest

function Test-DevBoxDesktopControls {
    $desktop = [Environment]::GetFolderPath('CommonDesktopDirectory')
    $client = Join-Path $env:DEVBOX_WSROOT 'Tools\DevBoxControls\request-control.ps1'
    if (-not $desktop -or -not (Test-Path -LiteralPath $desktop -PathType Container) -or
        -not (Test-Path -LiteralPath $client -PathType Leaf)) {
        return $false
    }
    try {
        $shell = New-Object -ComObject WScript.Shell
        foreach ($entry in @(
            @{ Name='Save DevBox State Now'; Action='save' },
            @{ Name='Finish DevBox Safely'; Action='stop' }
        )) {
            $shortcutPath = Join-Path $desktop ($entry.Name + '.lnk')
            if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) { return $false }
            $link = $shell.CreateShortcut($shortcutPath)
            if (-not (Test-Path -LiteralPath $link.TargetPath -PathType Leaf) -or
                $link.Arguments -notlike '*request-control.ps1*' -or
                $link.Arguments -notlike "*-Action $($entry.Action)*" -or
                -not [string]::Equals($link.WorkingDirectory,
                  (Join-Path $env:DEVBOX_WSROOT 'Workspace'),
                  [StringComparison]::OrdinalIgnoreCase)) {
                return $false
            }
        }
        return $true
    } catch {
        return $false
    }
}

function Repair-DevBoxDesktopControls {
    param([Parameter(Mandatory)][string]$ScriptsRoot)
    if (Test-DevBoxDesktopControls) { return $true }
    try {
        & (Join-Path $ScriptsRoot 'install-desktop-controls.ps1') | Out-Host
        return (Test-DevBoxDesktopControls)
    } catch {
        Write-Warning 'Save/Finish Desktop controls could not be repaired; do not claim buttons available.'
        return $false
    }
}
