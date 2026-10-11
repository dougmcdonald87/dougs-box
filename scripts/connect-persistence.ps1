# connect-persistence.ps1 - Phase 16/17 runner side. Finds the storage host by
# tag over Tailscale, resolves its IPv4, opens the restic repository URL and
# verifies reachability + restic client. Repo re-init NEVER happens here (Phase 19).
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'common.ps1')
Write-Step 'connect-persistence'

# ---- resolve existing, USER-OWNED Lenovo without changing its tag/identity.
# The storage IP is an explicit input; other devices keep their current Tailscale
# policies, servers, file shares, and RustDesk configuration untouched.
$storageIp = $env:DEVBOX_STORAGE_TAILSCALE_IP
if ([string]::IsNullOrWhiteSpace($storageIp)) {
    Stop-DevBox "DEVBOX_STORAGE_TAILSCALE_IP unset. Configure the value for the existing storage computer. No tailnet device needs retagging."
}
$parsedIp = $null
if (-not ([System.Net.IPAddress]::TryParse($storageIp, [ref]$parsedIp)) -or
    $parsedIp.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork -or
    -not $storageIp.StartsWith('100.')) {
    Stop-DevBox "DEVBOX_STORAGE_TAILSCALE_IP must be a valid existing tailnet IPv4 address."
}

$tsStatus = & tailscale status --json 2>$null | ConvertFrom-Json
if (-not $tsStatus) {
    Stop-DevBox "tailscale status returned nothing. Confirm the DevBox join succeeded."
}
$storagePeer = $null
foreach ($prop in $tsStatus.Peer.PSObject.Properties) {
    $peer = $prop.Value
    if ($peer.TailscaleIPs -contains $storageIp) {
        $storagePeer = $peer
        break
    }
}
if (-not $storagePeer) {
    Stop-DevBox "The existing storage computer ($storageIp) is not visible as a Tailscale peer. No existing device will be retagged or changed."
}

# ---- reachability proof (Phase 16 step 11 mirrored from the client side)
$tcp = New-Object System.Net.Sockets.TcpClient
try {
    $tcp.Connect($storageIp, 8000) | Out-Null
} finally { $tcp.Dispose() }
Write-DevBox OK "rest-server reachable at ${storageIp}:8000"

# ---- official restic binary, pinned current stable; provenance-checkable
#      Download once into the shared Tools dir; sha256 recorded for the log.
$resticRoot = New-DevboxDirectorySafe (Join-Path $env:DEVBOX_WSROOT 'Tools\restic')
$resticExe = Join-Path $resticRoot 'restic.exe'
$resticVersion = '0.18.4'   # candidate version; Phase 1 live research duty on first real run
if (-not (Test-Path $resticExe)) {
    $zip = Join-Path $resticRoot 'restic.zip'
    Invoke-DevboxRetry -Script {
        Invoke-WebRequest -Uri "https://github.com/restic/restic/releases/download/v$resticVersion/restic_${resticVersion}_windows_amd64.zip" -OutFile $zip
        Expand-Archive -LiteralPath $zip -DestinationPath $resticRoot -Force
    } -Attempts 3
}
if (-not (Test-Path $resticExe)) { Stop-DevBox "restic.exe missing after download. Next action: confirm asset name on restic releases." }
& $resticExe version | Out-Null
if ($LASTEXITCODE -ne 0) { Stop-DevBox "restic binary fails to run. Next action: see TROUBLESHOOTING 'restic'." }

# ---- state for the rest of the session (NO password in any file here)
$env:RESTIC_REPOSITORY_URL_FACTOR = $storageIp
$env:DEVBOX_STORAGE_IP = $storageIp
$env:DEVBOX_RESTIC_EXE = $resticExe

# Actions steps are isolated processes; preserve the binary location for
# restore/save/health steps. No secrets are written to GITHUB_ENV.
if ($env:GITHUB_ENV) {
    "DEVBOX_RESTIC_EXE=$resticExe" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
}

@{
    storageIp   = $storageIp
    resticExe   = $resticExe
    resticVer   = $resticVersion
    repoUrl     = "rest:http://${storageIp}:8000/devbox/"
} | ConvertTo-Json -Compress |
    Set-Content (Join-Path $env:DEVBOX_CONTROL_PATH 'persistence.json') -Encoding utf8

Write-DevBox OK "persistence connection ready (repo init deferred to first save; once-only law enforced there)."
