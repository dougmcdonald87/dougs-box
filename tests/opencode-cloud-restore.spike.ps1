# CI feasibility fixture only: real OpenCode runtime, disposable created session.
param([Parameter(Mandatory)][ValidateSet('Capture','Restore')][string]$Mode,
      [Parameter(Mandatory)][string]$Archive,[string]$ExpectedSha256)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_ACTIONS -ne 'true' -or -not $env:RUNNER_TEMP) { throw 'Disposable CI only.' }
$id = "$env:GITHUB_RUN_ID-$env:GITHUB_RUN_ATTEMPT"
if ($id -notmatch '^\d+-\d+$') { throw 'Invalid test identity.' }
$Archive = [IO.Path]::GetFullPath($Archive)
$temp = [IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\') + '\'
if (-not $Archive.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)) { throw 'Archive outside test temporary root.' }
$machine = [string](Get-CimInstance Win32_ComputerSystemProduct).UUID
$project = Join-Path $env:USERPROFILE "Documents\DevBoxCloudProbe-$id"
$env:DEVBOX_WSROOT = "C:\DevBoxCloudProbeTools-$id"
$env:DEVBOX_CONTROL_PATH = Join-Path $env:DEVBOX_WSROOT 'Control'
New-Item -ItemType Directory -Path $env:DEVBOX_CONTROL_PATH -Force | Out-Null
./scripts/install-opencode.ps1 -ToolsRoot (Join-Path $env:DEVBOX_WSROOT 'Tools')
$exe = Join-Path $env:DEVBOX_WSROOT 'Tools\OpenCode\opencode.exe'
$db = (& $exe debug paths db | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or -not [IO.Path]::IsPathFullyQualified($db) -or
    -not $db.StartsWith($env:USERPROFILE + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected actual OpenCode DB location.' }
if ([IO.Path]::GetPathRoot($db) -ine 'C:\') { throw 'Actual app state must live on C.' }
$config = Join-Path $env:USERPROFILE '.config\opencode\opencode.json'
$stage = Join-Path $env:RUNNER_TEMP ('opencode-state-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage | Out-Null
New-Item -ItemType Directory -Path $project -Force | Out-Null
$process = $null
$old = Get-Location
function Start-ProbeServer {
    $stdout = Join-Path $env:RUNNER_TEMP "opencode-$Mode.stdout.log"
    $stderr = Join-Path $env:RUNNER_TEMP "opencode-$Mode.stderr.log"
    $script:process = Start-Process -FilePath $exe -ArgumentList @('serve','--hostname','127.0.0.1','--port','4097') -WorkingDirectory $project -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(60)
    do {
        $script:process.Refresh()
        if ($script:process.HasExited) {
            Get-Content -LiteralPath $stderr -Tail 15
            throw 'Owned OpenCode server exited before readiness.'
        }
        try {
            $response = Invoke-RestMethod -Uri 'http://127.0.0.1:4097/api/session' -TimeoutSec 2
            return
        } catch { Start-Sleep -Milliseconds 500 }
    } while ([DateTime]::UtcNow -lt $deadline)
    Get-Content -LiteralPath $stderr -Tail 15
    throw 'OpenCode loopback server readiness timed out.'
}
try {
    Set-Location -LiteralPath $project
    if ($Mode -eq 'Capture') {
        if (Test-Path -LiteralPath $Archive) { throw 'Refusing snapshot overwrite.' }
        '{"permission":{"bash":"ask"}}' | Set-Content -LiteralPath $config -Encoding utf8
        'Developer project marker that must survive cloud recovery.' | Set-Content -LiteralPath (Join-Path $project 'README.md') -Encoding utf8
        Start-ProbeServer
        $created = Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:4097/api/session' -ContentType 'application/json' -Body '{"title":"GitHub cloud recovery probe"}' -TimeoutSec 15
        $sessionId = [string]$created.data.id
        if ($sessionId -notmatch '^ses_') { throw 'Real app did not return a created session ID.' }
        $found = Invoke-RestMethod -Uri "http://127.0.0.1:4097/api/session/$sessionId" -TimeoutSec 15
        if ($found.data.title -cne 'GitHub cloud recovery probe') { throw 'Created session was not readable.' }
        # Existing verified SQLite online-backup helper, while real app is alive.
        & python (Join-Path $PSScriptRoot '..\scripts\snapshot-opencode-db.py') $db (Join-Path $stage 'opencode.db')
        if ($LASTEXITCODE -ne 0) { throw 'Real OpenCode online snapshot failed.' }
        Copy-Item -LiteralPath $config -Destination (Join-Path $stage 'opencode.json')
        Copy-Item -LiteralPath (Join-Path $project 'README.md') -Destination (Join-Path $stage 'README.md')
        $manifest = @{schema=1;fixture_id=$id;machine=$machine;session_id=$sessionId;title='GitHub cloud recovery probe';files=@()}
        foreach ($name in @('opencode.db','opencode.json','README.md')) {
            $manifest.files += @{name=$name;sha256=(Get-FileHash -LiteralPath (Join-Path $stage $name)).Hash}
        }
        $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $stage 'manifest.json') -Encoding utf8
        Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $Archive
        $hash = (Get-FileHash -LiteralPath $Archive).Hash.ToLowerInvariant()
        "sha256=$hash" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
        Write-Host 'ACTUAL OPENCODE CAPTURE: native C runtime/config/project and app-created session; SQLite captured while server alive.'
    } else {
        if ($ExpectedSha256 -notmatch '^[a-f0-9]{64}$' -or (Get-FileHash -LiteralPath $Archive).Hash.ToLowerInvariant() -cne $ExpectedSha256) { throw 'Cloud snapshot checksum mismatch.' }
        Expand-Archive -LiteralPath $Archive -DestinationPath $stage
        $manifest = Get-Content -LiteralPath (Join-Path $stage 'manifest.json') -Raw | ConvertFrom-Json
        if ($manifest.schema -ne 1 -or $manifest.fixture_id -cne $id -or $manifest.machine -eq $machine) { throw 'Invalid snapshot or same VM.' }
        foreach ($name in @('opencode.db','opencode.json','README.md')) {
            $entry = @($manifest.files | Where-Object { $_.name -ceq $name })
            if ($entry.Count -ne 1 -or (Get-FileHash -LiteralPath (Join-Path $stage $name)).Hash -cne $entry[0].sha256) { throw 'App snapshot file integrity failed.' }
        }
        & python (Join-Path $PSScriptRoot '..\scripts\restore-opencode-db.py') (Join-Path $stage 'opencode.db') $db (Join-Path $env:RUNNER_TEMP 'safe-db-recovery')
        if ($LASTEXITCODE -ne 0) { throw 'Existing safe restore helper refused app database.' }
        Copy-Item -LiteralPath (Join-Path $stage 'opencode.json') -Destination $config -Force
        Copy-Item -LiteralPath (Join-Path $stage 'README.md') -Destination (Join-Path $project 'README.md') -Force
        Start-ProbeServer
        $found = Invoke-RestMethod -Uri "http://127.0.0.1:4097/api/session/$($manifest.session_id)" -TimeoutSec 15
        if ($found.data.title -cne $manifest.title) { throw 'Real OpenCode cannot read recovered session.' }
        $listed = (& $exe session list --format json | Out-String)
        if ($LASTEXITCODE -ne 0 -or $listed -notmatch [regex]::Escape($manifest.session_id)) { throw 'Real CLI cannot list recovered session.' }
        if ((Get-Content -LiteralPath $config -Raw | ConvertFrom-Json).permission.bash -cne 'ask') { throw 'App configuration not recovered.' }
        Write-Host 'ACTUAL OPENCODE CLOUD RESTORE PASS: existing native safe restore, real API reads created session and CLI lists it on fresh C.'
        Write-Host 'LIMIT: isolated app-created test session; not Doug live conversation history, no model call, no production cutover.'
    }
} finally {
    if ($process -and -not $process.HasExited) { Stop-Process -Id $process.Id -Force; $process.WaitForExit(10000) | Out-Null }
    Set-Location -LiteralPath $old.Path
    Remove-Item -LiteralPath $stage -Recurse -Force
}
