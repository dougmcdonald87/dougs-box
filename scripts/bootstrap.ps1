# bootstrap.ps1 - Phase 9 workspace structure + Phase 27 tool inventory.
# Installs nothing yet. Creates the workspace tree on the volume that
# qualifies (same rules as discover-storage) and records which tools the
# runner image already provides so later steps reuse instead of reinstall.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'common.ps1')

Write-Step 'bootstrap'

# ---- config if the owner filled one (filled copy is gitignored)
$cfgPath = Join-Path $PSScriptRoot '..\config\devbox.json'
$cfg = if (Test-Path $cfgPath) { Get-Content $cfgPath -Raw | ConvertFrom-Json } else { $null }

$requireFreeGiB     = if ($cfg -and $cfg.require_free_gib)         { [double]$cfg.require_free_gib } else { 100.0 }
$backupIntervalMin  = if ($cfg -and $cfg.backup_interval_minutes)  { [int]$cfg.backup_interval_minutes } else { 10 }
$autoRestoreMaxGiB  = if ($cfg -and $cfg.auto_restore_max_gib)     { [double]$cfg.auto_restore_max_gib } else { 3.0 }
$readyTargetMinutes = if ($cfg -and $cfg.ready_target_minutes)     { [int]$cfg.ready_target_minutes } else { 320 }
$jobTimeout         = if ($cfg -and $cfg.job_timeout_minutes)      { [int]$cfg.job_timeout_minutes } else { 350 }
$jobHardLimit       = if ($cfg -and $cfg.job_hard_limit_minutes)   { [int]$cfg.job_hard_limit_minutes } else { 360 }
$warnGiB            = if ($cfg -and $cfg.disk_warning_free_gib)    { [double]$cfg.disk_warning_free_gib } else { 25.0 }
$critGiB            = if ($cfg -and $cfg.disk_critical_free_gib)   { [double]$cfg.disk_critical_free_gib } else { 10.0 }

if ($jobTimeout -ge $jobHardLimit) {
    Stop-DevBox "config error: job_timeout_minutes ($jobTimeout) must stay below the GitHub hard limit ($jobHardLimit)."
}

# ---- select fast root: >= requireFreeGiB free, prefer NON-system drive, then most free
# Stable two-pass sort: first freeSpace descending, then stable sort by 'is C:' so
# non-system drives come first while free-space order is preserved inside each group.
$volumes = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType = 3' |
    Where-Object { Test-HasFreeGiB -DriveRoot $_.DeviceID -RequiredGiB $requireFreeGiB } |
    Sort-Object FreeSpace -Descending)
$volumes = @($volumes | Sort-Object -Property @{Expression = { [int]($_.DeviceID -like 'C*') } })

if ($volumes.Count -eq 0) {
    $probe = (Get-CimInstance Win32_LogicalDisk -Filter 'DriveType = 3') |
        ForEach-Object { "$($_.DeviceID)$([math]::Round($_.FreeSpace/1GB,1))GiB" }
    Stop-DevBox "DEVBOX FAILED: NO >=$requireFreeGiB GiB WORKSPACE. Probed volumes: $($probe -join ', '). " +
        "Next action: enable ALLOW_NETWORK_WORKSPACE_FALLBACK=true in config with a >=${requireFreeGiB} GiB " +
        "share on the storage host, or accept no session today."
}

$fastRoot = $volumes[0].DeviceID
Write-DevBox OK "fast workspace root: $fastRoot ($requireFreeGiB+ GiB free verified)"

# ---- Phase 9 structure
$wsRoot = Join-Path $fastRoot 'DevBox'
$subs = @('Projects','Workspace','PersistentData','Builds','Downloads','Tools','Temp','ResticCache','Logs','Control','Hydration')
foreach ($s in $subs) { New-DevboxDirectorySafe (Join-Path $wsRoot $s) | Out-Null }

$env:DEVBOX_FAST_ROOT     = $fastRoot
$env:DEVBOX_WSROOT        = $wsRoot
$env:DEVBOX_CONTROL_PATH  = (Join-Path $wsRoot 'Control')
$env:DEVBOX_LOGS_PATH     = (Join-Path $wsRoot 'Logs')
$env:DEVBOX_REQUIRE_GIB   = "$requireFreeGiB"
$env:DEVBOX_BACKUP_MIN    = "$backupIntervalMin"
$env:DEVBOX_RESTORE_MAXGB = "$autoRestoreMaxGiB"
$env:DEVBOX_READY_MIN     = "$readyTargetMinutes"
$env:DEVBOX_WARN_GIB      = "$warnGiB"
$env:DEVBOX_CRIT_GIB      = "$critGiB"
$env:DEVBOX_TEMP         = (Join-Path $wsRoot 'Temp')

# GitHub Actions executes each shell step in a new process. Persist the
# workspace environment for the next steps instead of relying on local $env.
if ($env:GITHUB_ENV) {
    foreach ($key in @(
        'DEVBOX_FAST_ROOT', 'DEVBOX_WSROOT', 'DEVBOX_CONTROL_PATH',
        'DEVBOX_LOGS_PATH', 'DEVBOX_REQUIRE_GIB', 'DEVBOX_BACKUP_MIN',
        'DEVBOX_RESTORE_MAXGB', 'DEVBOX_READY_MIN', 'DEVBOX_WARN_GIB',
        'DEVBOX_CRIT_GIB', 'DEVBOX_TEMP'
    )) {
        "$key=$([Environment]::GetEnvironmentVariable($key, 'Process'))" |
            Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
    }
}

# ---- knobs for session-manager / health-check (NO secrets in this file)
[ordered]@{
    fastRoot            = $fastRoot
    workspaceRoot       = $wsRoot
    requireFreeGiB      = $requireFreeGiB
    backupIntervalMin   = $backupIntervalMin
    autoRestoreMaxGiB   = $autoRestoreMaxGiB
    readyTargetMinutes  = $readyTargetMinutes
    jobTimeoutMinutes   = $jobTimeout
    jobHardLimitMinutes = $jobHardLimit
    diskWarnFreeGiB     = $warnGiB
    diskCritFreeGiB     = $critGiB
    startedUtc          = (Get-Date).ToUniversalTime().ToString('o')
} | ConvertTo-Json -Depth 3 |
    Set-Content (Join-Path $env:DEVBOX_CONTROL_PATH 'session.json') -Encoding utf8

# ---- Phase 27: tool inventory (reuse image software, do not reinstall)
$tools = @{}
foreach ($t in 'git','python','node','npm','cmake','gh','pwsh') {
    $c = Get-Command $t -ErrorAction SilentlyContinue
    if ($c) { $tools[$t] = $c.Source }
}
$tools | ConvertTo-Json -Compress |
    Set-Content (Join-Path $env:DEVBOX_CONTROL_PATH 'tool-inventory.json') -Encoding utf8
foreach ($k in $tools.Keys) { Write-DevBox INFO "inventory: $k -> $($tools[$k])" }

Write-StepSummary @(
    "**DevBox workspace**: $wsRoot",
    "**Backup cadence**: every $backupIntervalMin min; auto-restore cap ${autoRestoreMaxGiB} GiB",
    "**Job**: $jobTimeout min timeout vs $jobHardLimit hard limit"
)
Write-DevBox OK "bootstrap complete."
