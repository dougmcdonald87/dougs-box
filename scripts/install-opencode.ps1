# install-opencode.ps1 - Phase 28. Current OpenCode v2, standalone Windows x64 binary.
# Shared tools path so the Actions account and the RDP account see the same install.
# No WSL. Sharing disabled by default. Version recorded for the session log.
param(
    [string]$ToolsRoot = $(if ($env:DEVBOX_WSROOT) { Join-Path $env:DEVBOX_WSROOT 'Tools' } else { 'C:\Temp\DevBox-Tools' })
)
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'common.ps1')
Write-Step 'install-opencode'

$dir = New-DevboxDirectorySafe (Join-Path $ToolsRoot 'OpenCode')
# 1) Reuse if a working binary is already in the shared path (idempotency).
$existing = Get-ChildItem -LiteralPath $dir -Filter 'opencode.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($existing) {
    & $existing.FullName --version 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-DevBox OK "OpenCode already present at $($existing.FullName)"
        exit 0
    }
}

# 2) Ask the official project for the current Windows x64 asset (Phase 1 law:
#    real research beats a hard-coded download that rots). The release API is
#    public; both URLs below resolve the LATEST v2 Windows binary.
$api = 'https://api.github.com/repos/sst/opencode/releases/latest'
Invoke-DevboxRetry -Script {
    # GitHub-hosted runner IPs can exhaust the anonymous GitHub API quota.
    # Use this workflow's ephemeral, read-only GitHub token when available.
    $headers = @{
        Accept = 'application/vnd.github+json'
        'User-Agent' = 'DevBox-OpenCode-Installer'
        'X-GitHub-Api-Version' = '2022-11-28'
    }
    if (-not [string]::IsNullOrWhiteSpace($env:GH_TOKEN)) {
        $headers.Authorization = 'Bearer ' + $env:GH_TOKEN
    }
    $rel = Invoke-RestMethod -Uri $api -Headers $headers -ErrorAction Stop
    $asset = $rel.assets | Where-Object { $_.name -match 'windows.*x64' -and $_.name -match '\.zip$' } | Select-Object -First 1
    if (-not $asset) { throw "no windows x64 zip in latest release" }
    "opencode-version=$($rel.tag_name)" | Set-Content (Join-Path $dir 'version.txt') -Encoding ascii
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile (Join-Path $dir 'opencode.zip')
    Expand-Archive -LiteralPath (Join-Path $dir 'opencode.zip') -DestinationPath $dir -Force
    Remove-Item -LiteralPath (Join-Path $dir 'opencode.zip') -Force -ErrorAction SilentlyContinue
} -Attempts 3

# 3) Validate from this context (liveness; the RDP-account check is health-check's job).
$opencodeExe = (Get-ChildItem -LiteralPath $dir -Filter 'opencode.exe' -Recurse | Select-Object -First 1).FullName
if (-not $opencodeExe) { Stop-DevBox "OpenCode zip contained no opencode.exe. Next action: check asset name changed; update matcher in this script." }
& $opencodeExe --version 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Stop-DevBox "opencode --version failed (exit $LASTEXITCODE). Next action: see docs/TROUBLESHOOTING.md 'OpenCode'." }

# 4) Config: share OFF by default (Phase 28), config dir exists before first run.
$cfg = Join-Path $env:USERPROFILE '.config\opencode'
New-DevboxDirectorySafe $cfg | Out-Null

# 5) PATH machine-scope addition so any account session can resolve it
$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
if ($machinePath -notlike "*$dir*") {
    [Environment]::SetEnvironmentVariable('Path', "$machinePath;$dir", 'Machine')
}
$version = (Get-Content (Join-Path $dir 'version.txt') -ErrorAction SilentlyContinue)
Write-DevBox OK "OpenCode $version installed at $dir; sharing disabled default; PATH updated."

$version | Out-File -FilePath (Join-Path $env:DEVBOX_CONTROL_PATH 'opencode-version.txt') -Encoding utf8
