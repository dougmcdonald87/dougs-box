# install-desktop-controls.ps1 — create safe buttons on THIS ephemeral runner only.
# A shortcut writes a local request. Only the GitHub job can run the restic save.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($env:DEVBOX_WSROOT)) {
    throw 'DEVBOX_WSROOT is required for desktop control installation.'
}
$control = Join-Path $env:DEVBOX_WSROOT 'Control'
if (-not (Test-Path -LiteralPath (Join-Path $control 'session.json') -PathType Leaf)) {
    throw 'DevBox session.json missing. Refuse to create nonworking desktop shortcuts.'
}
New-Item -ItemType Directory -Path (Join-Path $control 'Commands') -Force | Out-Null

$destinationDir = Join-Path $env:DEVBOX_WSROOT 'Tools\DevBoxControls'
New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
$client = Join-Path $destinationDir 'request-control.ps1'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'request-control.ps1') -Destination $client -Force

# Public Desktop is merged into every interactive Windows user's desktop.
# Save controls here on EVERY startup, before restore or backup begins.
$desktop = [Environment]::GetFolderPath('CommonDesktopDirectory')
if ([string]::IsNullOrWhiteSpace($desktop) -or -not (Test-Path -LiteralPath $desktop -PathType Container)) {
    throw 'Public desktop folder missing: cannot install safe controls.'
}
$powerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $powerShell -PathType Leaf)) {
    throw 'Windows PowerShell missing: cannot install safe controls.'
}
$shell = New-Object -ComObject WScript.Shell
foreach ($entry in @(
    @{ Name = 'Save DevBox State Now'; Action = 'save'; Description = 'Verified Lenovo backup; keep DevBox running' },
    @{ Name = 'Finish DevBox Safely'; Action = 'stop'; Description = 'Verified Lenovo backup BEFORE ending GitHub session' }
)) {
    $shortcutPath = Join-Path $desktop ($entry.Name + '.lnk')
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $powerShell
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$client`" -Action $($entry.Action)"
    $shortcut.WorkingDirectory = Join-Path $env:DEVBOX_WSROOT 'Workspace'
    $shortcut.Description = $entry.Description
    $shortcut.Save()
    if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) {
        throw "Shortcut creation not verified: $shortcutPath"
    }
    Write-Output "Installed desktop control: $shortcutPath"
}
# Validate the shortcuts against their actual targets, not merely whether
# Windows created two .lnk files. This is still not a visual RDP test.
foreach ($action in @('Save DevBox State Now', 'Finish DevBox Safely')) {
    $path = Join-Path $desktop ($action + '.lnk')
    $link = $shell.CreateShortcut($path)
    if (-not (Test-Path -LiteralPath $link.TargetPath -PathType Leaf) -or
        -not ($link.Arguments -match 'request-control\\.ps1' -and $link.Arguments -match 'Action (save|stop)') -or
        -not (Test-Path -LiteralPath $client -PathType Leaf)) {
        throw "Desktop control link is not actionable: $action"
    }
}
Write-Output 'Both Public Desktop controls exist and point to a present request client. RDP visibility still requires checking.'
