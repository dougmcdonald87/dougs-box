$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_ACTIONS -ne 'true' -or -not $env:RUNNER_TEMP) { throw 'Disposable GitHub runner only.' }
if (Get-PSDrive -Name E -ErrorAction SilentlyContinue) { throw 'Requires unoccupied test E; no takeover.' }
$connector=Join-Path $PSScriptRoot '../scripts/connect-cloud-drive.ps1'
$cfg=@{schema_version=1;drive_letter='E';portal='100.100.1.2';target_iqn='iqn.2026-10.devbox:cloud-test';disk_unique_id='fixture';
 partition_guid='{11111111-1111-1111-1111-111111111111}';volume_unique_id='\\?\Volume{22222222-2222-2222-2222-222222222222}\';volume_label='FIXTURE';cloud_volume_id='fixture'}
$configPath=Join-Path $env:RUNNER_TEMP ('cloud-session-test-'+[guid]::NewGuid().ToString('N')+'.json')
$cfg | ConvertTo-Json | Set-Content -LiteralPath $configPath
$global:CloudTestTarget=$cfg.target_iqn
$global:CloudTestSessionsCalls=0
$global:CloudTestCase='both'
$global:CloudTestDisconnected=@()
function global:Get-Service { param([string]$Name) if ($Name -ne 'MSiSCSI') { throw 'Unexpected service query.' };[pscustomobject]@{Status='Running'} }
function global:Connect-IscsiTarget {
 param($NodeAddress,$TargetPortalAddress,$TargetPortalPortNumber,$IsPersistent,$IsMultipathEnabled,[switch]$AsJob)
 if ($NodeAddress -ne $global:CloudTestTarget -or $TargetPortalAddress -ne '100.100.1.2' -or -not $AsJob) { throw 'Unexpected connect arguments.' }
 [pscustomobject]@{State='Completed'}
}
function global:Wait-Job { param($Job,$Timeout) return $Job }
function global:Receive-Job { param($Job) [pscustomobject]@{SessionIdentifier='owned-A';TargetNodeAddress=$global:CloudTestTarget;IsConnected=$true} }
function global:Remove-Job { param($Job,[switch]$Force) }
function global:Get-IscsiSession {
 $global:CloudTestSessionsCalls++
 if ($global:CloudTestSessionsCalls -eq 1) { return }
 if ($global:CloudTestCase -eq 'both') { [pscustomobject]@{SessionIdentifier='owned-A';TargetNodeAddress=$global:CloudTestTarget;IsConnected=$true} }
 [pscustomobject]@{SessionIdentifier='other-B';TargetNodeAddress=$global:CloudTestTarget;IsConnected=$true}
}
function global:Get-IscsiConnection { param($IscsiSession) [pscustomobject]@{TargetNodeAddress='100.100.1.99';TargetPortNumber=3260} }
function global:Disconnect-IscsiTarget {
 param($NodeAddress,$SessionIdentifier,[switch]$Confirm)
 $global:CloudTestDisconnected+= [string]$SessionIdentifier
}
$failures=@()
try {
 foreach ($case in @('both','only-other')) {
   $global:CloudTestCase=$case;$global:CloudTestSessionsCalls=0;$global:CloudTestDisconnected=@();$refused=$false
   try { & $connector -ConfigPath $configPath | Out-Null } catch { $refused=$true }
   if (-not $refused) { throw 'Wrong/absent owned session was accepted.' }
   if (($global:CloudTestDisconnected -join ',') -ne 'owned-A') { $failures+= "Cleanup must target own result A, never B: case=$case observed=$($global:CloudTestDisconnected -join ',')" }
 }
 if ($failures.Count) { throw ($failures -join '; ') }
 Write-Output 'CLOUD CONNECTION OWNED-SESSION CONCURRENCY BOUNDARY: PASS (CONTROLLED API RESPONSES, NO REAL TARGET)'
} finally {
 foreach ($name in @('Get-Service','Connect-IscsiTarget','Wait-Job','Receive-Job','Remove-Job','Get-IscsiSession','Get-IscsiConnection','Disconnect-IscsiTarget')) { Remove-Item ('Function:\global:'+ $name) }
 Remove-Item -LiteralPath $configPath
}
