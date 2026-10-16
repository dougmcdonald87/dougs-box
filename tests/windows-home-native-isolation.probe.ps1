# Manual-only disposable Windows runner test: no guest VM, no backup secrets, no Desktop Commander.
# Expected read-denial marker: PILOT_RESTRICTED_IDENTITY_SENTINEL_DENIAL_OK=true
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or
   $env:GITHUB_REF -cne 'refs/heads/pilot/windows-home-connection-20261015' -or
   $env:GITHUB_REPOSITORY -cne 'dougmcdonald87/dougs-box' -or
   $env:DEVBOX_ISOLATED_TEST -cne '1' -or
   $env:GITHUB_RUN_ID -cnotmatch '^[1-9][0-9]*$'){throw 'Isolated manual probe only.'}
$script=Join-Path $env:GITHUB_WORKSPACE 'scripts/windows-home-restricted-agent.ps1'
$originalWorkspace=$env:GITHUB_WORKSPACE
$root=Join-Path $env:RUNNER_TEMP ('pilot-native-denial-'+$env:GITHUB_RUN_ID)
$guest=Join-Path $root 'guest'
$workspace=Join-Path $root 'workspace'
$control=Join-Path $env:ProgramData ('WindowsHomePilot\'+$env:GITHUB_RUN_ID)
if(Test-Path -LiteralPath $root){throw 'Probe root already exists.'}
if(Test-Path -LiteralPath $control){throw 'Probe must not replace a real control session.'}
function Restrict-SyntheticPath([string]$Path){
 $acl=Get-Acl -LiteralPath $Path -ErrorAction Stop
 $acl.SetAccessRuleProtection($true,$false)
 foreach($sid in @([Security.Principal.WindowsIdentity]::GetCurrent().User.Value,'S-1-5-18','S-1-5-32-544')){
  $principal=[Security.Principal.SecurityIdentifier]::new($sid)
  $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($principal,'FullControl','ContainerInherit,ObjectInherit','None','Allow'))
 }
 Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
}
try {
 New-Item -Path $guest -ItemType Directory -Force -ErrorAction Stop|Out-Null
 New-Item -Path (Join-Path $workspace 'scripts') -ItemType Directory -Force -ErrorAction Stop|Out-Null
 New-Item -Path $control -ItemType Directory -ErrorAction Stop|Out-Null
 Set-Content -LiteralPath (Join-Path $guest 'probe-owner.json') -Value '{"synthetic":true}' -ErrorAction Stop
 Set-Content -LiteralPath (Join-Path $workspace 'scripts/windows-state-operator.ps1') -Value '# synthetic fixture only' -ErrorAction Stop
 [ordered]@{schema=1;runId=$env:GITHUB_RUN_ID;root=$guest;deadlineMs=[DateTimeOffset]::UtcNow.AddMinutes(8).ToUnixTimeMilliseconds()}|
  ConvertTo-Json -Compress|Set-Content -LiteralPath (Join-Path $control 'session.json') -ErrorAction Stop
 foreach($path in @($guest,$workspace,$control, (Join-Path $guest 'probe-owner.json'),
  (Join-Path $workspace 'scripts'), (Join-Path $workspace 'scripts/windows-state-operator.ps1'),
  (Join-Path $control 'session.json'))){Restrict-SyntheticPath -Path $path}
 $env:GITHUB_WORKSPACE=$workspace
 & $script -ControlDir $control -GuestRoot $guest -WorkspaceRoot $workspace
 if($LASTEXITCODE -ne 0){throw 'Actual Windows token denial test exited unsuccessfully.'}
 Write-Output 'PILOT_NATIVE_SYNTHETIC_DENIAL_PASSED=true'
} finally {
 $env:GITHUB_WORKSPACE=$originalWorkspace
 foreach($p in @($control,$root)){
  if(Test-Path -LiteralPath $p){Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop}
 }
}
