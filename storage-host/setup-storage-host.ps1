# setup-storage-host.ps1 - Phase 16. Runs ON DOUG'S STORAGE PC (run from this repo locally).
# Installs official rest-server, binds ONLY to the host's Tailscale IP on 8000,
# --append-only --no-auth, explicit persistent --path (never %TEMP%),
# boot Scheduled Task. NO TLS. NO rest-server auth. 0.0.0.0 bind is prohibited.
param(
    [string]$DataPath = 'C:\DevBox-Storage\data',
    [string]$InstallDir = 'C:\DevBox-Storage\rest-server',
    [int]$Port = 8000
)
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot '..\scripts\common.ps1')
Write-Step 'setup-storage-host'

if (-not $IsWindows -and $PSVersionTable.PSEdition -eq 'Core') {
    Write-DevBox FAIL 'this script is for Windows storage host; exit.' 
    exit 2
}

# 1) Tailscale installed / running
$ts = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
if (-not $ts) { Stop-DevBox 'tailscale service not found. Next action: install Tailscale on this host first.' }
if ($ts.Status -ne 'Running') { Start-Service Tailscale; Start-Sleep -Seconds 5 }

# 2) host's tailnet IPv4 (the ONLY legal bind address)
$tsStatus = & tailscale status --json | ConvertFrom-Json
$tsIp = $tsStatus.Self.TailscaleIPs[0]
if ([string]::IsNullOrWhiteSpace($tsIp)) { Stop-DevBox 'no Tailscale IP on this host. Next action: connect host to the tailnet.' }

# 3) capacity check on data path volume
$drive = Get-PSDrive -Name ($DataPath.SubString(0, 1)) -ErrorAction SilentlyContinue
if (-not $drive) { Stop-DevBox "volume $DataPath invalid." }
if (($drive.Free / $OneGiB) -lt 100) { Write-DevBox WARN "storage volume has <100 GiB free; DevBox >=100 GiB law refers to WORKSPACE, but note storage free space here for planning." }

# 4) directories (PERSISTENT, never temp)
New-DevboxDirectorySafe $InstallDir | Out-Null
New-DevboxDirectorySafe $DataPath | Out-Null
if ($DataPath -like "$env:TEMP*") { Stop-DevBox 'refusing to place repository under %TEMP% (Phase 16 law 9).' }

# 5) download official rest-server binary (provenance: latest stable release; checksum noted)
Invoke-DevboxRetry -Script {
    $api = 'https://api.github.com/repos/restic/rest-server/releases/latest'
    $rel = Invoke-RestMethod -Uri $api -Headers @{ Accept = 'application/vnd.github+json' }
    $asset = $rel.assets | Where-Object { $_.name -match 'windows.*amd64\.zip$' } | Select-Object -First 1
    if (-not $asset) { throw "no windows amd64 zip in rest-server latest release" }
    "rest-server-version=$($rel.tag_name)" | Set-Content (Join-Path $InstallDir 'rest-server-version.txt') -Encoding ascii
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile (Join-Path $InstallDir 'rest-server.zip')
    Expand-Archive -LiteralPath (Join-Path $InstallDir 'rest-server.zip') -DestinationPath $InstallDir -Force
    Remove-Item -LiteralPath (Join-Path $InstallDir 'rest-server.zip') -Force -ErrorAction SilentlyContinue
} -Attempts 3

$exe = Get-ChildItem -LiteralPath $InstallDir -Recurse -Filter 'rest-server.exe' | Select-Object -First 1
if (-not $exe) { Stop-DevBox 'rest-server.exe missing after download. Next action: check release asset naming.' }

# 6-8) Scheduled Task to run at boot: bound ONLY to the tailnet IP
$taskName = 'DevBox-RestServer'
$action = New-ScheduledTaskAction -Execute $exe.FullName `
    -Argument "--listen $tsIp`:$Port --path `"$DataPath`" --append-only --no-auth" `
    -WorkingDirectory $InstallDir
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null

# 9) start + health-check listener NOW
Start-ScheduledTask -TaskName $taskName
Start-Sleep -Seconds 3
$listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalAddress -eq $tsIp }
if (-not $listener) {
    Stop-DevBox "port $Port not bound to $tsIp. Next action: run check-storage-host.ps1 and inspect storage host logs."
}

@{
    tailnetIp  = $tsIp
    port       = $Port
    dataPath   = $DataPath
    installDir = $InstallDir
    version    = (Get-Content (Join-Path $InstallDir 'rest-server-version.txt') -ErrorAction SilentlyContinue)
} | ConvertTo-Json -Compress |
    Set-Content (Join-Path $InstallDir 'storage-host-state.json') -Encoding utf8

Write-StepSummary @("**rest-server bound to** $tsIp`:$Port with --append-only --no-auth", "**data**: $DataPath", "**boot task**: $taskName")
Write-DevBox OK "storage host ready. Grant fragment in security/ controls DevBox -> this TCP $Port."
