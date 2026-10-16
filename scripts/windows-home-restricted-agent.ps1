# Windows 10 Home pilot only. Fail closed before any third-party terminal launch.
# Probe uses a disposable account and synthetic read-denial conditions; no remote agent is launched by this script.
[CmdletBinding()]
param(
    [switch]$ChildProbe,
    [switch]$LaunchAgent,
    [string]$ControlDir,
    [string]$GuestRoot
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($ChildProbe) {
    # Executed with an independent, non-admin local Windows logon token.
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $admins = [Security.Principal.WindowsBuiltInRole]::Administrator
    $hyperV = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-578')
    $privilegeDenied = -not $principal.IsInRole($admins) -and -not $principal.IsInRole($hyperV)
    $secretKeys = @('GH_TOKEN','GITHUB_TOKEN','RESTIC_PASSWORD','RESTIC_REST_PASSWORD',
                    'DEVBOX_RDP_PASSWORD','PILOT_RDP_PASSWORD','ACTIONS_ID_TOKEN_REQUEST_TOKEN')
    $envClean = $true
    foreach ($key in $secretKeys) {
        if (-not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($key,'Process'))) {
            $envClean = $false
        }
    }
    # Read the actual scoped privileged operator receipt with this exact Windows token.
    # A missing file, non-access-denial error or non-existent guest root is not proof.
    $controllDenied = $false
    $controlFile = Join-Path $ControlDir 'session.json'
    try {
        $handle = [IO.File]::Open($controlFile,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $handle.Dispose()
    } catch [System.UnauthorizedAccessException] {
        $controllDenied = $true
    }
    $guestDenied = $false
    try {
        # Materialise enumeration: merely testing existence does not test effective ACLs.
        $entries = [IO.Directory]::EnumerateFileSystemEntries($GuestRoot)
        foreach ($entry in $entries) { break }
    } catch [System.UnauthorizedAccessException] {
        $guestDenied = $true
    }
    [pscustomobject]@{
        sid=$identity.User.Value
        controllDenied=$controllDenied
        guestDenied=$guestDenied
        privilegeDenied=$privilegeDenied
        envClean=$envClean
    } | ConvertTo-Json -Compress
    exit 0
}

# No fallback to the legacy DevBox or operator-only workflow.
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or
    $env:GITHUB_REF -cne 'refs/heads/pilot/windows-home-connection-20261015' -or
    $env:GITHUB_REPOSITORY -cne 'dougmcdonald87/dougs-box' -or
    $env:DEVBOX_ISOLATED_TEST -cne '1' -or
    $env:GITHUB_RUN_ID -cnotmatch '^[1-9][0-9]*$') {
    throw 'Restricted terminal is permitted only in the exact isolated manual pilot.'
}
$expectedDir = Join-Path $env:ProgramData ('WindowsHomePilot\' + $env:GITHUB_RUN_ID)
if ([IO.Path]::GetFullPath($ControlDir).TrimEnd('\') -ine
    [IO.Path]::GetFullPath($expectedDir).TrimEnd('\')) {
    throw 'Restricted terminal control directory mismatch.'
}
$sessionFile = Join-Path $expectedDir 'session.json'
if (-not (Test-Path -LiteralPath $sessionFile -PathType Leaf)) { throw 'Protected session does not exist.' }
$session = Get-Content -LiteralPath $sessionFile -Raw | ConvertFrom-Json
if ($session.schema -ne 1 -or $session.runId -cne $env:GITHUB_RUN_ID -or
    $session.deadlineMs -le [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() -or
    [string]::IsNullOrWhiteSpace($session.root) -or
    $GuestRoot -cne [string]$session.root) {
    throw 'Missing, expired or mismatched guest state.'
}
if (-not (Test-Path -LiteralPath $GuestRoot -PathType Container)) { throw 'Guest root unavailable.' }
# Account name is unique within one short-lived runner, not a persistent credential.
$name = 'PilotDC' + $env:GITHUB_RUN_ID.Substring([Math]::Max(0,$env:GITHUB_RUN_ID.Length-8))
if (Get-LocalUser -Name $name -ErrorAction SilentlyContinue) { throw 'Restricted account already exists.' }
$chars = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(48))
$password = ConvertTo-SecureString ('Ab!9' + $chars) -AsPlainText -Force
$accountCreated = $false
try {
    $account = New-LocalUser -Name $name -Password $password -AccountNeverExpires -PasswordNeverExpires -ErrorAction Stop
    $accountCreated = $true
    if ($account.Enabled -ne $true) { throw 'New restricted account is disabled.' }
    foreach ($groupSid in @('S-1-5-32-544','S-1-5-32-578','S-1-5-32-555')) {
        $group = Get-LocalGroup -SID ([Security.Principal.SecurityIdentifier]::new($groupSid)) -ErrorAction SilentlyContinue
        if ($group) {
            $members = @(Get-LocalGroupMember -Group $group.Name -ErrorAction Stop)
            if (@($members | Where-Object { $_.SID.Value -eq $account.SID.Value }).Count -gt 0) {
                throw 'Restricted account belongs to a privileged or RDP group.'
            }
        }
    }
    $exe = (Get-Command pwsh.exe -ErrorAction Stop).Source
    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $exe
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UserName = $name
    $psi.Domain = '.'
    $psi.Password = $password
    $psi.LoadUserProfile = $true
    $psi.WorkingDirectory = $env:RUNNER_TEMP
    $psi.Environment.Clear()
    foreach ($key in @('SystemRoot','WINDIR','COMSPEC','PATH','PATHEXT','TEMP','TMP')) {
        $value = [Environment]::GetEnvironmentVariable($key,'Process')
        if (-not [string]::IsNullOrWhiteSpace($value)) { $psi.Environment[$key] = $value }
    }
    foreach ($arg in @('-NoProfile','-NonInteractive','-File',$PSCommandPath,'-ChildProbe',
                     '-ControlDir',$ControlDir,'-GuestRoot',$GuestRoot)) { [void]$psi.ArgumentList.Add($arg) }
    $process = [Diagnostics.Process]::Start($psi)
    if (-not $process.WaitForExit(30000)) {
        $process.Kill($true)
        throw 'Restricted token probe timed out.'
    }
    $output = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    if ($process.ExitCode -ne 0) { throw 'Restricted token probe failed without permission proof.' }
    $rows = @($output.Trim() | ConvertFrom-Json -ErrorAction Stop)
    if ($rows.Count -ne 1 -or $rows[0].sid -cne $account.SID.Value -or
        $rows[0].controllDenied -ne $true -or $rows[0].guestDenied -ne $true -or
        $rows[0].privilegeDenied -ne $true -or $rows[0].envClean -ne $true) {
        throw 'Restricted user can reach privileged data or identity is unverified.'
    }
    Write-Output 'PILOT_RESTRICTED_IDENTITY_SENTINEL_DENIAL_OK=true'
    if ($LaunchAgent) {
        # The third-party process runs under the SAME restricted token as the probe.
        $psi.FileName = Join-Path $env:WINDIR 'System32\cmd.exe'
        $psi.ArgumentList.Clear()
        foreach ($arg in @('/d','/s','/c',
            'npx --yes @wonderwhy-er/desktop-commander@0.2.52 remote --no-persist-session')) {
            [void]$psi.ArgumentList.Add($arg)
        }
        $profileDir = Join-Path $env:SystemDrive ('Users\'+$name)
        $psi.Environment['USERPROFILE'] = $profileDir
        $psi.Environment['HOME'] = $profileDir
        $psi.Environment['APPDATA'] = Join-Path $profileDir 'AppData\Roaming'
        $psi.Environment['LOCALAPPDATA'] = Join-Path $profileDir 'AppData\Local'
        $psi.Environment['TEMP'] = Join-Path $profileDir 'AppData\Local\Temp'
        $psi.Environment['TMP'] = $psi.Environment['TEMP']
        $agent = [Diagnostics.Process]::Start($psi)
        try {
            $stdout = $agent.StandardOutput.ReadLineAsync()
            $stderrStream = $agent.StandardError.ReadLineAsync()
            while (-not $agent.HasExited) {
                if ($stdout.IsCompleted) {
                    $line = $stdout.GetAwaiter().GetResult()
                    if ($null -ne $line) { [Console]::Out.WriteLine($line) }
                    $stdout = $agent.StandardOutput.ReadLineAsync()
                }
                if ($stderrStream.IsCompleted) {
                    $line = $stderrStream.GetAwaiter().GetResult()
                    if ($null -ne $line) { [Console]::Out.WriteLine($line) }
                    $stderrStream = $agent.StandardError.ReadLineAsync()
                }
                Start-Sleep -Milliseconds 100
            }
            throw 'Restricted Desktop Commander terminated before verified Finish.'
        } finally {
            if (-not $agent.HasExited) { $agent.Kill($true) }
            $agent.Dispose()
        }
    }
} finally {
    if ($accountCreated) { Remove-LocalUser -Name $name -ErrorAction Stop }
    $password.Dispose()
}
