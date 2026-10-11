# Install an official pinned restic for an ephemeral GitHub runner only.
param([Parameter(Mandatory)][string]$ToolsRoot)
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'common.ps1')
Write-Step 'install-restic'

$resticVersion = '0.19.1'
$expectedZipSha256 = 'da948ad707ed690426473aaba2046cd61f8f90f6f0e7dab6be0d5796531de67d'
$root = New-DevboxDirectorySafe $ToolsRoot
$exe = Join-Path $root 'restic.exe'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    $zip = Join-Path $root "restic_$($resticVersion)_windows_amd64.zip"
    $unpack = New-DevboxDirectorySafe (Join-Path $root 'unpacked')
    Invoke-DevboxRetry -Script {
        Invoke-WebRequest -Uri "https://github.com/restic/restic/releases/download/v$resticVersion/restic_$($resticVersion)_windows_amd64.zip" -OutFile $zip -ErrorAction Stop
        $actualHash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $expectedZipSha256) { throw 'Official restic ZIP digest mismatch; installation refused.' }
        Expand-Archive -LiteralPath $zip -DestinationPath $unpack -Force -ErrorAction Stop
        $versionedExe = Get-ChildItem -LiteralPath $unpack -Recurse -File |
            Where-Object { $_.Name -eq "restic_$($resticVersion)_windows_amd64.exe" } |
            Select-Object -First 1
        if (-not $versionedExe) { throw 'The release archive did not contain the expected versioned executable.' }
        Copy-Item -LiteralPath $versionedExe.FullName -Destination $exe -Force -ErrorAction Stop
    } -Attempts 3
}
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { Stop-DevBox 'restic.exe is missing after extraction.' }
$versionLine = & $exe version
if ($LASTEXITCODE -ne 0 -or $versionLine -notmatch "restic $resticVersion") {
    Stop-DevBox "restic executable could not verify required version $resticVersion."
}
Write-DevBox OK "Verified restic $resticVersion at $exe (source ZIP digest pinned)."
