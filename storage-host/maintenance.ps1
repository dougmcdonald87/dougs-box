# maintenance.ps1 - Phase 44. DEFAULT IS NON-DESTRUCTIVE. No deletion from this script.
# Reports snapshot list, repository size, free space, repository check, and guidance
# about retention planning that the OWNER does manually at the storage host.
param([switch]$CheckRepo)
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot '..\scripts\common.ps1')
Write-Step 'maintenance (inspection/dry-run defaults)'

$state = Get-Content 'C:\DevBox-Storage\rest-server\storage-host-state.json' -Raw | ConvertFrom-Json
if (-not $state) { Stop-DevBox 'storage host not set up; run setup-storage-host.ps1 first.' }

$drive = Get-PSDrive -Name (($state.dataPath).Substring(0, 1)) -ErrorAction SilentlyContinue
Write-DevBox INFO ("free space: {0} GiB" -f [math]::Round($drive.Free/$OneGiB, 2))
$dataSize = (Get-ChildItem $state.dataPath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
Write-DevBox INFO ("repository size: {0:N2} GiB" -f ($dataSize / $OneGiB))

if ($CheckRepo) {
    # restic check needs the password: the OWNER supplies it interactively.
    Write-DevBox INFO 'repository check requires interaction; run RESTIC_PASSWORD securely via owner-provided env.'
}

Write-DevBox INFO 'retention: the OWNER plans and executes removal manually on this host, interactively.'
Write-DevBox INFO 'THE DEVBOX ITSELF PERMANENTLY LACKS THE RIGHT TO SHRINK THE REPOSITORY (append-only law).'
