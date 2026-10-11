# common.ps1 - shared DevBox helpers. Dot-source only; never execute directly.
# Phase 46 quality rules live here: strict mode, loud failures, real exit codes,
# Join-Path everywhere, binary GiB math, no env dumps ever.
Set-StrictMode -Version Latest

# canonical binary-GiB constant (a 5.1-safe literal, dot-source spread)
$OneGiB = 1073741824.0

$script:DEVBOX_FAIL_EXIT = 2

function Write-DevBox {
    param(
        [Parameter(Mandatory)][ValidateSet('INFO','WARN','FAIL','OK')][string]$Level,
        [Parameter(Mandatory)][string]$Message
    )
    $stamp = (Get-Date).ToUniversalTime().ToString('o')
    "[$stamp] DEVBOX-$Level $Message" | Write-Output
    if ($Level -eq 'FAIL' -and $env:DEVBOX_CONTROL_PATH) {
        $Message | Out-File -FilePath (Join-Path $env:DEVBOX_CONTROL_PATH 'last-error.txt') -Encoding utf8 -ErrorAction SilentlyContinue
    }
}

function Stop-DevBox {
    param([Parameter(Mandatory)][string]$Message)
    Write-DevBox FAIL $Message
    exit $script:DEVBOX_FAIL_EXIT
}

function ConvertTo-PackedBytes {
    # Binary GiB (Phase 8): 100 GiB means 107374182400 bytes, not 100 decimal GB.
    param([Parameter(Mandatory)][double]$GiB)
    return [math]::Floor($GiB * 1024 * 1024 * 1024)
}

function Test-HasFreeGiB {
    param(
        [Parameter(Mandatory)][string]$DriveRoot,   # e.g. 'D:\'
        [Parameter(Mandatory)][double]$RequiredGiB
    )
    $letter = ($DriveRoot.Substring(0, 2))
    $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$letter'" -ErrorAction SilentlyContinue
    if (-not $d) { return $false }
    return ($d.FreeSpace -ge (ConvertTo-PackedBytes $RequiredGiB))
}

function Write-Step {
    param([Parameter(Mandatory)][string]$Name)
    Write-DevBox INFO "===== $Name ====="
}

function New-DevboxDirectorySafe {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Invoke-DevboxRetry {
    param(
        [Parameter(Mandatory)][scriptblock]$Script,
        [int]$Attempts = 3,
        [int]$DelaySeconds = 5
    )
    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            # Under StrictMode, LASTEXITCODE must be initialized before use:
            # cmdlet-only scripts do not create it. Reset stale prior status.
            # Under PowerShell 7.4+, make native failures terminating even
            # when their output is piped into a successful cmdlet.
            $ErrorActionPreference = 'Stop'
            $PSNativeCommandUseErrorActionPreference = $true
            $LASTEXITCODE = 0
            & $Script
            $scriptSucceeded = $?
            if ($scriptSucceeded -and $LASTEXITCODE -eq 0) { return }
            throw "command failed (native exit: $LASTEXITCODE; PowerShell success: $scriptSucceeded)"
        } catch {
            Write-DevBox WARN "attempt $i/$Attempts failed: $($_.Exception.Message)"
        }
        if ($i -lt $Attempts) { Start-Sleep -Seconds $DelaySeconds }
    }
    Stop-DevBox "all $Attempts attempts exhausted"
}

# Enforce that production restic operations can target ONLY the dedicated
# Lenovo DevBox repository. Test mode is permitted exclusively on disposable
# GitHub CI runners in the runner's own temporary directory.
function Test-DevBoxRepoDestination {
    param([Parameter(Mandatory)][string]$Repo)
    if ($Repo -ceq 'rest:http://100.70.202.110:8000/devbox/') { return $true }
    if ($env:DEVBOX_ISOLATED_TEST -eq '1' -and $env:GITHUB_ACTIONS -eq 'true' -and $env:RUNNER_TEMP) {
        $root = [System.IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\\') + '\\'
        $full = [System.IO.Path]::GetFullPath($Repo)
        return $full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)
    }
    return $false
}

function Test-SecretSet {
    param(
        [AllowEmptyString()][string]$SecretValue,
        [string]$Name = 'secret'
    )
    if ([string]::IsNullOrWhiteSpace($SecretValue)) {
        Stop-DevBox "$Name is empty. Next action: add it under Settings > Environments > devbox > Add secret."
    }
    if ($SecretValue.Length -lt 8) {
        Stop-DevBox "$Name looks too short to be real. Next action: re-check the value in the devbox environment secrets list."
    }
}

function Write-StepSummary {
    # GH step summary. Public-safe fields only (Phase 36/54): no secrets,
    # no environment dumps, no tailnet internals beyond the DevBox node name.
    param([Parameter(Mandatory)][string[]]$Lines)
    if ($env:GITHUB_STEP_SUMMARY) { $Lines | Add-Content -Path $env:GITHUB_STEP_SUMMARY -Encoding utf8 }
}

Write-DevBox INFO "common.ps1 loaded."
