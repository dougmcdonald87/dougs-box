# Pilot-only graphical console prerequisite. Real disposable Windows runner
# proved RSAT-Hyper-V-Tools can be re-applied without a reboot when vmconnect.exe
# is missing even though Get-WindowsFeature says Installed (run 38820107023).
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

if($env:GITHUB_ACTIONS -cne 'true' -or
   $env:DEVBOX_ISOLATED_TEST -cne '1' -or
   $env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or
   $env:GITHUB_REF -cne 'refs/heads/pilot/windows-home-connection-20261015' -or
   $env:GITHUB_REPOSITORY -cne 'dougmcdonald87/dougs-box'){
 throw 'Only manually dispatched isolated Windows Home pilot may install VM console tools.'
}
$vmconnect=Join-Path $env:WINDIR 'System32\vmconnect.exe'
$present=(Test-Path -LiteralPath $vmconnect -PathType Leaf)
Write-Output ('PILOT_VMCONNECT_PRESENT_BEFORE='+$present)
if(-not $present){
 $feature=Get-WindowsFeature -Name 'RSAT-Hyper-V-Tools' -ErrorAction Stop
 if(-not $feature){throw 'Windows runner does not offer Hyper-V GUI management tools.'}
 Write-Output ('PILOT_HYPERV_MANAGEMENT_BEFORE='+$feature.InstallState)
 # Real 2026-10-15 Windows runner reported Installed while vmconnect.exe was
 # absent: re-applying this management-tools-only feature supplied the binary.
 # Do not add the Hyper-V host role, force a reboot, or download binaries.
 $result=Install-WindowsFeature -Name 'RSAT-Hyper-V-Tools' -ErrorAction Stop
 Write-Output ('PILOT_GUI_TOOLS_INSTALL_SUCCESS='+$result.Success)
 Write-Output ('PILOT_GUI_TOOLS_RESTART_NEEDED='+$result.RestartNeeded)
 if(-not $result.Success -or $result.RestartNeeded -eq 'Yes'){
   throw 'Hyper-V GUI tools failed or require a reboot; refuse 10 GiB guest restore.'
 }
}
if(-not(Test-Path -LiteralPath $vmconnect -PathType Leaf)){
 throw 'Hyper-V console executable still missing; refuse costly guest restore.'
}
$binary=Get-Item -LiteralPath $vmconnect -ErrorAction Stop
if(-not $binary.VersionInfo.FileVersion){throw 'VMConnect version metadata unavailable.'}
Write-Output ('PILOT_VMCONNECT_VERSION='+$binary.VersionInfo.FileVersion)
Write-Output 'PILOT_VMCONNECT_READY=true'
