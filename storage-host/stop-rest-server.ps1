# stop-rest-server.ps1 - stop the listener process (task stays registered for next boot).
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '..\scripts\common.ps1')
Stop-ScheduledTask -TaskName 'DevBox-RestServer' -ErrorAction SilentlyContinue
Write-DevBox OK "rest-server stopped (boot task remains registered)."
