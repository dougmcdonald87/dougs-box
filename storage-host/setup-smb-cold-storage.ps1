# setup-smb-cold-storage.ps1 - Phase 25 OPTIONAL helper: cold-data share on the storage host.
# Only when the owner wants cold browsing/hydration outside restic; Tailscale Grant
# TCP 445 is the ONLY exposure. NOT the primary backup transport, ever.
param(
    [string]$ShareName = 'DevBoxCold',
    [string]$SharePath = 'C:\DevBox-Cold'
)
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot '..\scripts\common.ps1')
Write-Step 'setup-smb-cold-storage (optional)'

New-DevboxDirectorySafe $SharePath | Out-Null

# Reclaim previously provisioned share names (idempotent)
Remove-SmbShare -Name $ShareName -Confirm:$false -ErrorAction SilentlyContinue
New-SmbShare -Name $ShareName -Path $SharePath -ChangeAccess 'AuthenticatedUsers' | Out-Null

Grant-SmbShareAccess -Name $ShareName -AccountName 'AuthenticatedUsers' -AccessRight Change -Force | Out-Null

Write-StepSummary @("**SMB share 'DevBoxCold'** created at $SharePath", "**Access**: tailnet-only via Grant TCP 445 (merge security fragment with the SMB lines)")
Write-DevBox OK "cold storage share $ShareName visible only across the tailnet."
