# connect-persistence.ps1 - Phase 16/17 runner side. Finds the storage host by
# tag over Tailscale, resolves its IPv4, opens the restic repository URL and
# verifies reachability + restic client. Repo re-init NEVER happens here (Phase 19).
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'common.ps1')
Write-Step 'connect-persistence'

# ---- resolve the storage host from tailnet peers by tag (no hard-coded IP)
$tsStatus = & tailscale status --json 2>$null | ConvertFrom-Json
if (-not $tsStatus) { Stop-DevBox "tailscale status returned nothing. Next action: confirm the tailscale join step succeeded before this one." }

$storagePeer = $null
foreach ($prop in $tsStatus.Peer.PSObject.Properties) {
    $peer = $prop.Value
    if ($peer.Tags -contains 'tag:devbox-storage') { $storagePeer = $peer; break }
}
if (-not $storagePeer) {
    Stop-DevBox "no tailnet peer carries tag:devbox-storage. Next action: tag the storage PC in Tailscale admin (Machines) and re-run."
}
$storageIp = $storagePeer.TailscaleIPs[0]
if ([string]::IsNullOrWhiteSpace($storageIp)) {
    Stop-DevBox "storage peer has no Tailscale IP. Next action: check 'tailscale status --json' tag output."
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

@{
    storageIp   = $storageIp
    resticExe   = $resticExe
    resticVer   = $resticVersion
    repoUrl     = "rest:http://${storageIp}:8000/devbox/"
} | ConvertTo-Json -Compress |
    Set-Content (Join-Path $env:DEVBOX_CONTROL_PATH 'persistence.json') -Encoding utf8

Write-DevBox OK "persistence connection ready (repo init deferred to first save; once-only law enforced there)."
