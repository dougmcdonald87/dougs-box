# Real PowerShell regression for DevBox retry helper.
# Runs on GitHub's Linux pwsh; production failure was Windows pwsh.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '..' 'scripts' 'common.ps1')

# Scenario 1: no native program has run. StrictMode must not error on an
# undefined LASTEXITCODE. A cmdlet-only retry must succeed first time.
Remove-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
$script:cleanCalls = 0
Invoke-DevboxRetry -Script {
    $script:cleanCalls++
    Get-Date | Out-Null
} -Attempts 1 -DelaySeconds 0
if ($script:cleanCalls -ne 1) {
    throw 'Regression: successful cmdlet-only operation did not complete in one attempt.'
}
Write-Output 'PASS: fresh session / no native LASTEXITCODE.'

# Scenario 2: a previous, unrelated native process failed. A successful
# PowerShell cmdlet-only operation must NOT inherit its stale exit code.
$global:LASTEXITCODE = 27
$script:staleCalls = 0
Invoke-DevboxRetry -Script {
    $script:staleCalls++
    Get-Date | Out-Null
} -Attempts 1 -DelaySeconds 0
if ($script:staleCalls -ne 1) {
    throw 'Regression: stale native exit status prevented a valid cmdlet retry.'
}
Write-Output 'PASS: stale native exit code does not override cmdlet success.'

# Scenario 3: temporary terminating cmdlet failure must be retried, not
# treated as success. Restored normal Stop-DevBox handling isn't exercised.
$script:transientCalls = 0
Invoke-DevboxRetry -Script {
    $script:transientCalls++
    if ($script:transientCalls -eq 1) { throw 'simulated temporary failure' }
    Get-Date | Out-Null
} -Attempts 2 -DelaySeconds 0
if ($script:transientCalls -ne 2) {
    throw 'Regression: did not retry exactly once after a transient error.'
}
Write-Output 'PASS: transient cmdlet error is retried.'

# Scenario 4: a native nonzero exit must not be called successful.
# Override only the test's Stop-DevBox handler to avoid exiting this CI job.
function Stop-DevBox {
    param([string]$Message)
    throw "EXPECTED_RETRY_EXHAUSTED: $Message"
}
$script:nativeCalls = 0
$expectedFailure = $false
try {
    Invoke-DevboxRetry -Script {
        $script:nativeCalls++
        & pwsh -NoProfile -NonInteractive -Command 'exit 9' | Out-Null
    } -Attempts 2 -DelaySeconds 0
} catch {
    if ($_.Exception.Message -like 'EXPECTED_RETRY_EXHAUSTED:*') {
        $expectedFailure = $true
    } else {
        throw
    }
}
if (-not $expectedFailure -or $script:nativeCalls -ne 2) {
    throw "Regression: nonzero native command was not rejected after two attempts (calls: $script:nativeCalls)."
}
Write-Output 'PASS: nonzero native exit is rejected.'
# All assertions passed. The native-failure regression intentionally ran a
# subprocess returning 9; make the test process explicitly report success.
exit 0
