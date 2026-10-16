# remove-storage-host.ps1 - full local teardown (owner-initiated only).
# Stops the task, unregisters it, deletes install dir; data dir kept unless -DeleteData flag,
# because wiping a backup repository from thin air is the most dangerous command possible.
param([switch]$DeleteData)
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot '..\scripts\common.ps1')

Stop-ScheduledTask -TaskName 'DevBox-RestServer' -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName 'DevBox-RestServer' -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item 'C:\DevBox-Storage\rest-server' -Recurse -Force -ErrorAction SilentlyContinue

if ($DeleteData) {
    Stop-DevBox 'DELIBERATE OFF-RAMP: passing -DeleteData destroys the entire backup history.' `
    ' The owner must do this MANUALLY (interactive) after explicit review of what is inside the data directory.' 
}
Write-DevBox OK 'rest-server removed; boot task deregistered; data preserved unless owner handled the delete separately by hand.'
