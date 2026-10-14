# Real control client with virtual clock: late results, failure and wrong nonce.
$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('DevBox-Wait-' + [guid]::NewGuid().ToString('N'))
try {
    foreach ($case in @('success','failure','wrong-id')) {
        $ws = Join-Path $root $case
        $scripts = Join-Path $ws 'Tools/DevBoxControls'
        $commands = Join-Path $ws 'Control/Commands'
        New-Item -ItemType Directory -Path $scripts,$commands -Force | Out-Null
        '{}' | Set-Content (Join-Path $ws 'Control/session.json')
        $source = Get-Content (Join-Path $PSScriptRoot '../scripts/request-control.ps1') -Raw
        # Only replace time reads in this temporary test copy; production is unchanged.
        $source = $source.Replace('[DateTime]::UtcNow', '(Get-TestUtcNow)')
        $header = @'
$script:clock = [DateTime]::Parse('2026-10-14T00:00:00Z').ToUniversalTime()
$script:initial = $script:clock
function Get-TestUtcNow { return $script:clock }
function Start-Sleep {
    param([int]$Seconds)
    $script:clock = $script:clock.AddSeconds($Seconds)
    if (($script:clock - $script:initial).TotalSeconds -ge 306) {
        $request = Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '../../Control/Commands') -Filter '*.request' | Select-Object -First 1
        if ($request) {
            $id = $request.BaseName.Substring(5)
            if ($env:WAIT_TEST_CASE -eq 'wrong-id') { $id = 'incorrect' }
            @{id=$id;action='stop';success=($env:WAIT_TEST_CASE -ne 'failure');snapshotId='verified-after-six-minutes';detail='simulated backup failure'} |
                ConvertTo-Json | Set-Content ($request.FullName.Replace('.request','.result.json'))
        }
    }
}
'@
        # Keep param first; mock functions are inserted before normal body.
        $source = $source.Replace("$([char]36)ErrorActionPreference = 'Stop'", $header + "`n$([char]36)ErrorActionPreference = 'Stop'")
        $scriptPath = Join-Path $scripts 'request-control.ps1'
        $source | Set-Content $scriptPath
        $env:DEVBOX_CONTROL_NONINTERACTIVE = '1'
        $env:WAIT_TEST_CASE = $case
        $output = & (Get-Command pwsh).Source -NoProfile -File $scriptPath -Action stop 2>&1
        $code = $LASTEXITCODE
        $expected = if ($case -eq 'success') { 0 } else { 2 }
        if ($code -ne $expected) { throw "Late result $case expected exit $expected got $code : $output" }
        if ($case -eq 'success' -and "$output" -notmatch 'verified-after-six-minutes') { throw 'Missing late verified snapshot' }
        Write-Output "LATE RESULT $case : PASS"
    }
} finally {
    Remove-Item Env:WAIT_TEST_CASE -ErrorAction SilentlyContinue
    Remove-Item Env:DEVBOX_CONTROL_NONINTERACTIVE -ErrorAction SilentlyContinue
    Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
}
