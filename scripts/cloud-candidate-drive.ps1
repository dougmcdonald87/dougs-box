# Working-drive alias only; verified cloud checkpoints provide cross-run persistence.
param([string]$GlobalAliasTarget='')
Set-StrictMode -Version Latest
if ($GlobalAliasTarget) {
    # Only the owned on-demand LocalSystem task may enter this path. Windows
    # places its DOS mapping in the global namespace, visible to desktop logons.
    $runtime=$null;$ok=$false
    try {
        if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne 'S-1-5-18') { throw 'Global mapping requires LocalSystem.' }
        $root=[IO.Path]::GetFullPath($GlobalAliasTarget)
        $runtime=Join-Path $root 'DevBox\Tools\CloudPersistence'
        $owner=Get-Content -LiteralPath (Join-Path $runtime 'candidate-owner.json') -Raw | ConvertFrom-Json
        if ($owner.root -ine $root -or [string]$owner.runId -notmatch '^\d+$' -or [string]$owner.attempt -notmatch '^\d+$' -or
            [IO.Path]::GetFileName($root) -cne ('.devbox-cloud-candidate-'+$owner.runId+'-'+$owner.attempt) -or (Test-Path 'E:\')) {
            throw 'Unowned target or occupied global E; no mapping changed.'
        }
        & subst E: $root
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path 'E:\DevBox\Tools\CloudPersistence\candidate-owner.json')) { throw 'Global E mapping failed.' }
        $ok=$true
    } catch { $ok=$false }
    if ($runtime) {
        $pending=Join-Path $runtime 'alias-result.tmp'
        [ordered]@{success=$ok} | ConvertTo-Json -Compress | Set-Content -LiteralPath $pending -Encoding utf8
        [IO.File]::Move($pending,(Join-Path $runtime 'alias-result.json'))
    }
    if ($ok) { exit 0 }
    exit 2
}
function Initialize-DevBoxCloudCandidateDrive {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PhysicalRoot,[double]$RequiredGiB=100.0)
    if ($env:GITHUB_ACTIONS -ne 'true' -or $env:GITHUB_RUN_ID -notmatch '^\d+$' -or $env:GITHUB_RUN_ATTEMPT -notmatch '^\d+$') { throw 'Candidate requires an identified GitHub runner.' }
    if (Test-Path 'E:\') { throw 'E is occupied; candidate refuses to modify it.' }
    if ($RequiredGiB -le 0 -or $RequiredGiB -gt 1000) { throw 'Invalid candidate capacity threshold.' }
    if ($PhysicalRoot -match '^[A-Za-z]:$') { $PhysicalRoot+='\' }
    $root=[IO.Path]::GetFullPath($PhysicalRoot)
    $item=Get-Item -LiteralPath $root -ErrorAction Stop
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Backing root must be an existing ordinary directory.' }
    $volume=[IO.DriveInfo]::new([IO.Path]::GetPathRoot($root))
    if ($volume.AvailableFreeSpace -lt [math]::Floor($RequiredGiB*1GB)) { throw 'Backing volume lacks required free space.' }
    $owned=Join-Path $root ('.devbox-cloud-candidate-'+$env:GITHUB_RUN_ID+'-'+$env:GITHUB_RUN_ATTEMPT)
    if (Test-Path -LiteralPath $owned) { throw 'Backing directory already exists; no overwrite permitted.' }
    $runtime=Join-Path $owned 'DevBox\Tools\CloudPersistence'
    New-Item -ItemType Directory -Path $runtime -Force -ErrorAction Stop | Out-Null
    [ordered]@{runId=$env:GITHUB_RUN_ID;attempt=$env:GITHUB_RUN_ATTEMPT;root=$owned} | ConvertTo-Json -Compress |
        Set-Content -LiteralPath (Join-Path $runtime 'candidate-owner.json') -Encoding utf8 -ErrorAction Stop
    $taskName='DevBoxCloudCandidate-'+$env:GITHUB_RUN_ID+'-'+$env:GITHUB_RUN_ATTEMPT
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) { throw 'Owned candidate task name already exists; no overwrite permitted.' }
    $registered=$false
    try {
        $exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $file=Join-Path $PSScriptRoot 'cloud-candidate-drive.ps1'
        $action=New-ScheduledTaskAction -Execute $exe -Argument "-NoLogo -NoProfile -NonInteractive -File `"$file`" -GlobalAliasTarget `"$owned`""
        $principal=New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        $settings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::FromMinutes(1))
        Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -ErrorAction Stop | Out-Null
        $registered=$true
        Start-ScheduledTask -TaskName $taskName -ErrorAction Stop
        $result=Join-Path $runtime 'alias-result.json'
        $deadline=[DateTime]::UtcNow.AddSeconds(30)
        while (-not (Test-Path -LiteralPath $result) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 200 }
        if (-not (Test-Path -LiteralPath $result) -or -not (Get-Content -LiteralPath $result -Raw | ConvertFrom-Json).success -or
            -not (Test-Path 'E:\DevBox\Tools\CloudPersistence\candidate-owner.json')) { throw 'Global E creation was not acknowledged; no candidate readiness.' }
    } finally {
        if ($registered) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop }
    }
    $env:DEVBOX_CLOUD_CANDIDATE_ROOT=$owned
    if ($env:GITHUB_ENV) { "DEVBOX_CLOUD_CANDIDATE_ROOT=$owned" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8 }
    return 'E:'
}
