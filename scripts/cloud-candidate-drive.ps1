# Working-drive alias only; verified cloud checkpoints provide cross-run persistence.
Set-StrictMode -Version Latest
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
    & subst E: $owned
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path 'E:\DevBox\Tools\CloudPersistence\candidate-owner.json')) { throw 'E alias creation failed.' }
    $env:DEVBOX_CLOUD_CANDIDATE_ROOT=$owned
    if ($env:GITHUB_ENV) { "DEVBOX_CLOUD_CANDIDATE_ROOT=$owned" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8 }
    return 'E:'
}
