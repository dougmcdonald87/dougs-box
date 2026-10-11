# Install OpenCode v2 Windows x64 using its official @opencode/cli npm package.
# Only touches the disposable GitHub runner Tools directory. No WSL required.
param(
    [string]$ToolsRoot = $(if ($env:DEVBOX_WSROOT) { Join-Path $env:DEVBOX_WSROOT 'Tools' } else { 'C:\Temp\DevBox-Tools' })
)
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'common.ps1')
Write-Step 'install-opencode'

# Pin the exact v2 release verified by independent Windows smoke tests.
$version = '2.0.24'
$dir = New-DevboxDirectorySafe (Join-Path $ToolsRoot 'OpenCode')
$exe = Join-Path $dir 'opencode.exe'

if (Test-Path -LiteralPath $exe -PathType Leaf) {
    $existing = & $exe --version 2>$null | Out-String
    if ($LASTEXITCODE -eq 0 -and $existing.Trim() -eq "opencode v$version") {
        Write-DevBox OK "OpenCode $version already installed at $exe."
        exit 0
    }
}

$npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
if (-not $npm) { Stop-DevBox 'Node/npm.cmd missing on disposable Windows runner.' }
Invoke-DevboxRetry -Script {
    & $npm.Source install --prefix $dir --no-audit --no-fund "@opencode/cli@$version" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "npm CLI installation failed (exit $LASTEXITCODE)." }
} -Attempts 3

# npm's official postinstall resolves the right platform native package.
# Copy native executable into the shared Tools directory used by RDP account.
$native = Get-ChildItem -LiteralPath (Join-Path $dir 'node_modules') -Filter 'opencode.exe' -Recurse -File -ErrorAction Stop |
    Select-Object -First 1
if (-not $native) { Stop-DevBox 'Official v2 npm package did not provide a Windows opencode.exe.' }
Copy-Item -LiteralPath $native.FullName -Destination $exe -Force -ErrorAction Stop
$actualVersion = (& $exe --version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $actualVersion -ne "opencode v$version") {
    Stop-DevBox "OpenCode v2 version verification failed: expected $version, got $actualVersion."
}
"opencode-version=v$version" | Set-Content (Join-Path $dir 'version.txt') -Encoding ascii
$cfg = Join-Path $env:USERPROFILE '.config\opencode'
New-DevboxDirectorySafe $cfg | Out-Null
$machinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
if ($machinePath -notlike "*$dir*") {
    [Environment]::SetEnvironmentVariable('Path', "$machinePath;$dir", 'Machine')
}
$version | Out-File -FilePath (Join-Path $env:DEVBOX_CONTROL_PATH 'opencode-version.txt') -Encoding utf8
Write-DevBox OK "Official OpenCode v$version installed at $exe; PATH configured on temporary runner."
exit 0
