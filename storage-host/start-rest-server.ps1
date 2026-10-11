# start-rest-server.ps1 - run the boot task right now (owner convenience).
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '..\scripts\common.ps1')
Start-ScheduledTask -TaskName 'DevBox-RestServer' -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
Write-DevBox OK "rest-server task started; verify with check-storage-host.ps1."
