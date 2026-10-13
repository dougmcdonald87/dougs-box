# No secrets or desktop: prove candidate drive visibility in an independent logon.
$ErrorActionPreference='Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or -not $env:RUNNER_TEMP) { throw 'CI only.' }
. (Join-Path $PSScriptRoot '..\scripts\cloud-candidate-drive.ps1')
$env:DEVBOX_ISOLATED_TEST='1'
$null=Initialize-DevBoxCloudCandidateDrive -PhysicalRoot $env:RUNNER_TEMP -RequiredGiB 0.01
$name='dbx'+[guid]::NewGuid().ToString('N').Substring(0,12)
$password=ConvertTo-SecureString ('Dbx!9aA'+[guid]::NewGuid().ToString('N')) -AsPlainText -Force
$account=New-LocalUser -Name $name -Password $password -AccountNeverExpires -PasswordNeverExpires
$probe=Join-Path $env:RUNNER_TEMP ('logon-probe-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $probe -Force | Out-Null
try {
    # Give this disposable account access only to owned fixture/probe directories.
    & icacls $probe /grant "*$($account.SID.Value):(OI)(CI)M" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Probe ACL setup failed.' }
    & icacls $env:DEVBOX_CLOUD_CANDIDATE_ROOT /grant "*$($account.SID.Value):(OI)(CI)RX" /T | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Candidate fixture ACL setup failed.' }
    $script=Join-Path $probe 'probe.ps1';$result=Join-Path $probe 'visible.txt'
    @'
$ErrorActionPreference='Stop'
$visible=[bool](Get-PSDrive -Name E -PSProvider FileSystem -ErrorAction SilentlyContinue)
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'visible.txt'),$visible.ToString())
exit 0
'@ | Set-Content -LiteralPath $script -Encoding utf8
    $credential=[pscredential]::new("$env:COMPUTERNAME\$name",$password)
    $exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $child=Start-Process -FilePath $exe -Credential $credential -LoadUserProfile -WorkingDirectory $probe -ArgumentList "-NoLogo -NoProfile -NonInteractive -File `"$script`"" -Wait -PassThru
    if ($child.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $result)) { throw 'Independent logon probe did not execute.' }
    if ([IO.File]::ReadAllText($result) -cne 'True') { throw 'Candidate E is invisible in an independent Windows logon.' }
    Write-Host 'CANDIDATE LOGON ATTACK PASS: E remains visible in an independent Windows logon, with no source account changed.'
} finally {
    Remove-LocalUser -Name $name -ErrorAction SilentlyContinue
    $password=$null;$credential=$null
}
$global:LASTEXITCODE=0
exit 0
