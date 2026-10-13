# Disposable feasibility test only. Never called by production startup.
param(
    [Parameter(Mandatory)][ValidateSet('Capture','Restore')][string]$Mode,
    [Parameter(Mandatory)][string]$Archive,
    [string]$ExpectedSha256
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_ACTIONS -ne 'true' -or -not $env:RUNNER_TEMP) { throw 'Disposable GitHub CI only.' }
$id = "$($env:GITHUB_RUN_ID)-$($env:GITHUB_RUN_ATTEMPT)"
if ($id -notmatch '^\d+-\d+$') { throw 'Invalid fixture identity.' }
$machineId = [string](Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction Stop).UUID
if ($machineId -notmatch '^[a-fA-F0-9-]{36}$' -or $machineId -eq '00000000-0000-0000-0000-000000000000') { throw 'Missing native VM identity.' }
$profile = Join-Path $env:LOCALAPPDATA "DevBoxPersistenceProbe\$id"
if ([IO.Path]::GetPathRoot($profile) -ine 'C:\') { throw 'This test requires actual C: AppData.' }
$key = "HKCU:\Software\DevBoxPersistenceProbe\$id"
$tempRoot = [IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\') + '\'
$Archive = [IO.Path]::GetFullPath($Archive)
if (-not $Archive.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'Archive must stay inside RUNNER_TEMP.' }
$stage = Join-Path $env:RUNNER_TEMP ("c-restore-stage-" + [guid]::NewGuid().ToString('N'))
$files = @('settings.json','history.db','cache.bin','registry.json')
if (Test-Path -LiteralPath $profile) { throw 'Existing fixture profile: refusing overwrite.' }
if (Test-Path -LiteralPath $key) { throw 'Existing fixture registry key: refusing overwrite.' }
function Assert-Equal($actual,$expected,[string]$message) {
    if ($actual -cne $expected) { throw $message }
}
$sqlite = @'
import sqlite3,sys
path,mode=sys.argv[1:]
with sqlite3.connect(path) as db:
    if mode == 'create':
        db.execute('CREATE TABLE sessions (id TEXT PRIMARY KEY, body TEXT)')
        db.execute('INSERT INTO sessions VALUES (?,?)', ('probe-session', 'saved developer work'))
    else:
        assert db.execute('SELECT id,body FROM sessions').fetchall() == [('probe-session','saved developer work')]
'@
try {
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    if ($Mode -eq 'Capture') {
        if (Test-Path -LiteralPath $Archive) { throw 'Existing snapshot: refusing overwrite.' }
        New-Item -ItemType Directory -Path $profile -Force | Out-Null
        '{"theme":"dark","workspace":"developer-project","saved":true}' | Set-Content -LiteralPath (Join-Path $profile 'settings.json') -Encoding utf8
        & python -c $sqlite (Join-Path $profile 'history.db') create
        if ($LASTEXITCODE -ne 0) { throw 'Fixture SQLite creation failed.' }
        [IO.File]::WriteAllBytes((Join-Path $profile 'cache.bin'),[byte[]](0..255))
        New-Item -Path $key -Force | Out-Null
        New-ItemProperty -Path $key -Name 'Workspace' -Value 'developer-project' -PropertyType String -Force | Out-Null
        $registry = [pscustomobject]@{name='Workspace';kind='String';value=(Get-ItemPropertyValue -LiteralPath $key -Name 'Workspace')}
        $registry | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stage 'registry.json') -Encoding utf8
        foreach ($name in @('settings.json','history.db','cache.bin')) {
            Copy-Item -LiteralPath (Join-Path $profile $name) -Destination (Join-Path $stage $name)
        }
        $manifest = [ordered]@{schema=1;fixture_id=$id;source_host=$env:COMPUTERNAME;source_machine_id=$machineId;source_job=$env:GITHUB_JOB;files=@()}
        foreach ($name in $files) {
            $manifest.files += [ordered]@{name=$name;sha256=(Get-FileHash -LiteralPath (Join-Path $stage $name) -Algorithm SHA256).Hash.ToLowerInvariant()}
        }
        $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $stage 'manifest.json') -Encoding utf8
        Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $Archive
        $digest = (Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash.ToLowerInvariant()
        "sha256=$digest" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
        Write-Host "CAPTURE: C AppData settings, closed SQLite, cache and owned HKCU value; snapshot SHA256 $digest"
    } else {
        if ($ExpectedSha256 -notmatch '^[a-f0-9]{64}$') { throw 'Expected cloud snapshot digest required.' }
        Assert-Equal (Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash.ToLowerInvariant() $ExpectedSha256 'Cloud archive checksum mismatch; no restore performed.'
        Expand-Archive -LiteralPath $Archive -DestinationPath $stage
        $manifest = Get-Content -LiteralPath (Join-Path $stage 'manifest.json') -Raw | ConvertFrom-Json
        Assert-Equal $manifest.schema 1 'Wrong manifest schema.'
        Assert-Equal $manifest.fixture_id $id 'Snapshot belongs to a different test.'
        if ($manifest.source_job -eq $env:GITHUB_JOB) { throw 'Restore must use a separate CI job.' }
        if ($manifest.source_machine_id -eq $machineId) { throw 'Restore must use a fresh Windows VM.' }
        Write-Host "Distinct native VM identities verified: capture $($manifest.source_machine_id), restore $machineId"
        if (@($manifest.files).Count -ne $files.Count) { throw 'Incomplete snapshot.' }
        foreach ($name in $files) {
            $entry = @($manifest.files | Where-Object { $_.name -ceq $name })
            if ($entry.Count -ne 1) { throw 'Missing or duplicate snapshot entry.' }
            Assert-Equal (Get-FileHash -LiteralPath (Join-Path $stage $name) -Algorithm SHA256).Hash.ToLowerInvariant() $entry[0].sha256 'Snapshot file integrity failed.'
        }
        $registry = Get-Content -LiteralPath (Join-Path $stage 'registry.json') -Raw | ConvertFrom-Json
        Assert-Equal $registry.name 'Workspace' 'Unexpected registry value.'
        Assert-Equal $registry.kind 'String' 'Unexpected registry type.'
        Assert-Equal $registry.value 'developer-project' 'Unexpected registry content.'
        New-Item -ItemType Directory -Path $profile -Force | Out-Null
        foreach ($name in @('settings.json','history.db','cache.bin')) {
            Copy-Item -LiteralPath (Join-Path $stage $name) -Destination (Join-Path $profile $name)
        }
        New-Item -Path $key -Force | Out-Null
        New-ItemProperty -Path $key -Name $registry.name -Value $registry.value -PropertyType String -Force | Out-Null
        $settings = Get-Content -LiteralPath (Join-Path $profile 'settings.json') -Raw | ConvertFrom-Json
        Assert-Equal $settings.theme 'dark' 'Settings not restored.'
        Assert-Equal $settings.workspace 'developer-project' 'Workspace not restored.'
        & python -c $sqlite (Join-Path $profile 'history.db') verify
        if ($LASTEXITCODE -ne 0) { throw 'SQLite state not restored.' }
        Assert-Equal (Get-ItemPropertyValue -LiteralPath $key -Name 'Workspace') 'developer-project' 'Registry state not restored.'
        Assert-Equal ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $profile 'cache.bin')))) ([Convert]::ToBase64String([byte[]](0..255))) 'Cache state not restored.'
        Write-Host 'RESTORE PASS: fresh Windows C AppData/settings/SQLite/cache and native HKCU registry; GitHub cloud transport only.'
        Write-Host 'LIMIT: synthetic fixture, no real application, no production integration, no durable storage or sudden-stop guarantee.'
    }
} finally {
    if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key -Recurse -Force }
    if (Test-Path -LiteralPath $profile) { Remove-Item -LiteralPath $profile -Recurse -Force }
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
