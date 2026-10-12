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

function Assert-OpenCodeGlobalCommand {
    param([Parameter(Mandatory)][string]$Executable,
          [Parameter(Mandatory)][string]$Directory,
          [Parameter(Mandatory)][string]$ExpectedVersion)
    # Machine PATH is inherited by fresh RDP logons. This register-and-probe
    # runs even when the executable was already installed.
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $entries = @($machinePath -split ';' | Where-Object { $_.Trim() })
    if (-not @($entries | Where-Object {
        $_.TrimEnd([char]92) -ieq $Directory.TrimEnd([char]92)
    }).Count) {
        [Environment]::SetEnvironmentVariable('Path', "$Directory;$machinePath", 'Machine')
    }
    # Current process and its child cmd/pwsh do not inherit registry updates
    # automatically. Explicitly update this process without shortening PATH.
    $env:Path = "$Directory;$env:Path"
    $original = Get-Location
    try {
        Set-Location -LiteralPath $env:WINDIR
        $resolved = (Get-Command opencode.exe -CommandType Application -ErrorAction Stop).Source
        if (-not [string]::Equals([IO.Path]::GetFullPath($resolved),
                                  [IO.Path]::GetFullPath($Executable),
                                  [StringComparison]::OrdinalIgnoreCase)) {
            throw "OpenCode global command resolves to an unexpected executable."
        }
        $reported = (& opencode.exe --version | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $reported -ne "opencode v$ExpectedVersion") {
            throw "OpenCode global CLI version probe failed outside the D: workspace."
        }
        $cmdProbe = (& cmd.exe /d /c 'cd /d %SystemRoot% && where opencode.exe && opencode.exe --version' | Out-String)
        if ($LASTEXITCODE -ne 0 -or $cmdProbe -notmatch [regex]::Escape("opencode v$ExpectedVersion")) {
            throw "CMD global CLI probe failed from the Windows directory."
        }
    } finally {
        Set-Location -LiteralPath $original.Path
    }
    Write-DevBox OK "Global opencode command resolves correctly outside the workspace in PowerShell and CMD."
}

if (Test-Path -LiteralPath $exe -PathType Leaf) {
    $existing = & $exe --version 2>$null | Out-String
    if ($LASTEXITCODE -eq 0 -and $existing.Trim() -eq "opencode v$version") {
        Assert-OpenCodeGlobalCommand -Executable $exe -Directory $dir -ExpectedVersion $version
        $version | Set-Content -LiteralPath (Join-Path $env:DEVBOX_CONTROL_PATH 'opencode-version.txt') -Encoding utf8
        Write-DevBox OK "OpenCode $version already installed and callable globally."
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
Assert-OpenCodeGlobalCommand -Executable $exe -Directory $dir -ExpectedVersion $version
$version | Out-File -FilePath (Join-Path $env:DEVBOX_CONTROL_PATH 'opencode-version.txt') -Encoding utf8
Write-DevBox OK "Official OpenCode v$version installed and global CLI verified."
exit 0
